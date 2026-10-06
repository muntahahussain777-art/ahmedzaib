import 'package:sqflite/sqflite.dart';

import 'sync_meta.dart';

/// Idempotent dealer DD/D application keyed by source SyncId.
/// Prevents double-adjust on pull/retry and keeps concurrent child effects.
class DealerBalanceApply {
  DealerBalanceApply._();

  static Future<void> ensureTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SyncBalanceApplied (
        SourceSyncId TEXT PRIMARY KEY,
        DealerId INTEGER,
        DealerSyncId TEXT,
        DdDelta REAL NOT NULL DEFAULT 0,
        DDelta REAL NOT NULL DEFAULT 0,
        AppliedAt TEXT NOT NULL
      )
    ''');
        await db.execute('''
      CREATE TABLE IF NOT EXISTS SyncDealerBalanceOp (
        SyncId TEXT PRIMARY KEY,
        DealerSyncId TEXT NOT NULL,
        DdDelta REAL NOT NULL DEFAULT 0,
        DDelta REAL NOT NULL DEFAULT 0,
        SourceKind TEXT NOT NULL DEFAULT 'manual',
        SourceSyncId TEXT,
        DateText TEXT,
        Note TEXT,
        UpdatedAt TEXT NOT NULL,
        SyncDirty INTEGER NOT NULL DEFAULT 1,
        DeletedAt TEXT,
        ServerRev INTEGER
      )
    ''');
    try {
      await db.execute('ALTER TABLE SyncDealerBalanceOp ADD COLUMN ServerRev INTEGER');
    } catch (_) {}
  }

  /// Mark existing local children as already applied (no balance change).
  static Future<void> backfillMarkers(DatabaseExecutor db) async {
    final now = SyncMeta.nowIso();
    await db.execute('''
      INSERT OR IGNORE INTO SyncBalanceApplied(SourceSyncId, DealerId, DealerSyncId, DdDelta, DDelta, AppliedAt)
      SELECT p.SyncId, p.Did, d.SyncId, 0, IFNULL(p.AmounGiven,0), ?
      FROM DieselLedgerCredit p
      LEFT JOIN AddDealer d ON d.Did = p.Did
      WHERE p.SyncId IS NOT NULL AND trim(p.SyncId) <> ''
    ''', [now]);
    await db.execute('''
      INSERT OR IGNORE INTO SyncBalanceApplied(SourceSyncId, DealerId, DealerSyncId, DdDelta, DDelta, AppliedAt)
      SELECT p.SyncId, p.Did, d.SyncId, IFNULL(p.AmounGiven,0), 0, ?
      FROM DieselLedgerDebit p
      LEFT JOIN AddDealer d ON d.Did = p.Did
      WHERE p.SyncId IS NOT NULL AND trim(p.SyncId) <> ''
    ''', [now]);
    await db.execute('''
      INSERT OR IGNORE INTO SyncBalanceApplied(SourceSyncId, DealerId, DealerSyncId, DdDelta, DDelta, AppliedAt)
      SELECT a.SyncId, a.DealerId, d.SyncId,
             IFNULL(a.AddDisel,0) * IFNULL(a.Rate,0), 0, ?
      FROM AddStock a
      LEFT JOIN AddDealer d ON d.Did = a.DealerId
      WHERE a.SyncId IS NOT NULL AND trim(a.SyncId) <> ''
    ''', [now]);
  }

  static Future<Map<String, Object?>?> _applied(DatabaseExecutor db, String sourceSyncId) async {
    final rows = await db.query(
      'SyncBalanceApplied',
      where: 'SourceSyncId = ?',
      whereArgs: [sourceSyncId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(rows.first);
  }

  /// Apply target deltas for [sourceSyncId]. Reverses prior applied effect if present.
  /// [markDealerDirty] false for remote apply (avoid absolute LWW push of aggregates).
  static Future<void> reconcile({
    required DatabaseExecutor db,
    required String sourceSyncId,
    required int? dealerId,
    String? dealerSyncId,
    required double ddDelta,
    required double dDelta,
    bool markDealerDirty = false,
  }) async {
    if (sourceSyncId.isEmpty) return;
    final prev = await _applied(db, sourceSyncId);
    final prevDid = prev == null
        ? null
        : (prev['DealerId'] is int
            ? prev['DealerId'] as int
            : int.tryParse('${prev['DealerId']}'));
    final prevDd = prev == null ? 0.0 : _asDouble(prev['DdDelta']);
    final prevD = prev == null ? 0.0 : _asDouble(prev['DDelta']);

    if (prev != null &&
        prevDid == dealerId &&
        (prevDd - ddDelta).abs() < 0.0000001 &&
        (prevD - dDelta).abs() < 0.0000001) {
      return; // already applied at target
    }

    if (prev != null && prevDid != null && prevDid > 0) {
      await _adjust(db, prevDid, -prevDd, -prevD, markDealerDirty: markDealerDirty);
    }

    if (dealerId != null && dealerId > 0 && (ddDelta != 0 || dDelta != 0)) {
      await _adjust(db, dealerId, ddDelta, dDelta, markDealerDirty: markDealerDirty);
    }

    if (dealerId == null || dealerId <= 0 || (ddDelta == 0 && dDelta == 0)) {
      await db.delete('SyncBalanceApplied', where: 'SourceSyncId = ?', whereArgs: [sourceSyncId]);
      return;
    }

    await db.insert(
      'SyncBalanceApplied',
      {
        'SourceSyncId': sourceSyncId,
        'DealerId': dealerId,
        'DealerSyncId': dealerSyncId,
        'DdDelta': ddDelta,
        'DDelta': dDelta,
        'AppliedAt': SyncMeta.nowIso(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> reverse({
    required DatabaseExecutor db,
    required String sourceSyncId,
    bool markDealerDirty = false,
  }) async {
    if (sourceSyncId.isEmpty) return;
    final prev = await _applied(db, sourceSyncId);
    if (prev == null) return;
    final prevDid = prev['DealerId'] is int
        ? prev['DealerId'] as int
        : int.tryParse('${prev['DealerId']}');
    if (prevDid != null && prevDid > 0) {
      await _adjust(
        db,
        prevDid,
        -_asDouble(prev['DdDelta']),
        -_asDouble(prev['DDelta']),
        markDealerDirty: markDealerDirty,
      );
    }
    await db.delete('SyncBalanceApplied', where: 'SourceSyncId = ?', whereArgs: [sourceSyncId]);
  }

  static Future<void> _adjust(
    DatabaseExecutor db,
    int dealerId,
    double ddDelta,
    double dDelta, {
    required bool markDealerDirty,
  }) async {
    if (dealerId <= 0) return;
    if (ddDelta == 0 && dDelta == 0) return;
    final now = SyncMeta.nowIso();
    if (markDealerDirty) {
      final n = await db.rawUpdate(
        'UPDATE AddDealer SET DDAmount = IFNULL(DDAmount,0) + ?, DAmount = IFNULL(DAmount,0) + ?, UpdatedAt = ?, SyncDirty = 1 WHERE Did = ?',
        [ddDelta, dDelta, now, dealerId],
      );
      if (n <= 0) throw Exception('Dealer balance update fail.');
    } else {
      final n = await db.rawUpdate(
        'UPDATE AddDealer SET DDAmount = IFNULL(DDAmount,0) + ?, DAmount = IFNULL(DAmount,0) + ?, UpdatedAt = ? WHERE Did = ?',
        [ddDelta, dDelta, now, dealerId],
      );
      if (n <= 0) throw Exception('Dealer balance update fail.');
    }
  }

  static Future<String?> dealerSyncId(DatabaseExecutor db, int? did) async {
    if (did == null || did <= 0) return null;
    final rows = await db.query('AddDealer', columns: ['SyncId'], where: 'Did = ?', whereArgs: [did], limit: 1);
    if (rows.isEmpty) return null;
    final s = rows.first['SyncId']?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Queue a cloud-synced balance op (manual dealer edit / closing / etc.).
  /// When [sourceSyncId] is stable (e.g. opening:{dealerSync}), reuses the existing
  /// op SyncId so retries do not invent a second cloud identity.
  static Future<void> enqueueOp({
    required DatabaseExecutor db,
    required String dealerSyncId,
    required double ddDelta,
    required double dDelta,
    String sourceKind = 'manual',
    String? sourceSyncId,
    String? dateText,
    String? note,
    bool alreadyAppliedLocally = true,
    int? dealerId,
  }) async {
    if (dealerSyncId.isEmpty) return;
    if (ddDelta == 0 && dDelta == 0) return;
    final source = (sourceSyncId == null || sourceSyncId.isEmpty) ? null : sourceSyncId;
    String syncId;
    if (source != null) {
      final existing = await db.query(
        'SyncDealerBalanceOp',
        columns: ['SyncId'],
        where: 'SourceSyncId = ? AND DeletedAt IS NULL',
        whereArgs: [source],
        limit: 1,
      );
      if (existing.isNotEmpty && (existing.first['SyncId']?.toString().isNotEmpty ?? false)) {
        syncId = existing.first['SyncId']!.toString();
        await db.update(
          'SyncDealerBalanceOp',
          {
            'DealerSyncId': dealerSyncId,
            'DdDelta': ddDelta,
            'DDelta': dDelta,
            'SourceKind': sourceKind,
            'DateText': dateText,
            'Note': note,
            'UpdatedAt': SyncMeta.nowIso(),
            'SyncDirty': 1,
            'DeletedAt': null,
          },
          where: 'SyncId = ?',
          whereArgs: [syncId],
        );
      } else {
        syncId = SyncMeta.newId();
        await db.insert('SyncDealerBalanceOp', {
          'SyncId': syncId,
          'DealerSyncId': dealerSyncId,
          'DdDelta': ddDelta,
          'DDelta': dDelta,
          'SourceKind': sourceKind,
          'SourceSyncId': source,
          'DateText': dateText,
          'Note': note,
          'UpdatedAt': SyncMeta.nowIso(),
          'SyncDirty': 1,
          'DeletedAt': null,
        });
      }
    } else {
      syncId = SyncMeta.newId();
      await db.insert('SyncDealerBalanceOp', {
        'SyncId': syncId,
        'DealerSyncId': dealerSyncId,
        'DdDelta': ddDelta,
        'DDelta': dDelta,
        'SourceKind': sourceKind,
        'SourceSyncId': syncId,
        'DateText': dateText,
        'Note': note,
        'UpdatedAt': SyncMeta.nowIso(),
        'SyncDirty': 1,
        'DeletedAt': null,
      });
    }
    final appliedKey = source ?? syncId;
    if (alreadyAppliedLocally) {
      int? did = dealerId;
      if (did == null) {
        final didRows = await db.query(
          'AddDealer',
          columns: ['Did'],
          where: 'SyncId = ?',
          whereArgs: [dealerSyncId],
          limit: 1,
        );
        if (didRows.isNotEmpty) {
          final v = didRows.first['Did'];
          did = v is int ? v : int.tryParse('$v');
        }
      }
      await db.insert(
        'SyncBalanceApplied',
        {
          'SourceSyncId': appliedKey,
          'DealerId': did,
          'DealerSyncId': dealerSyncId,
          'DdDelta': ddDelta,
          'DDelta': dDelta,
          'AppliedAt': SyncMeta.nowIso(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      int? did = dealerId;
      if (did == null) {
        final didRows = await db.query(
          'AddDealer',
          columns: ['Did'],
          where: 'SyncId = ?',
          whereArgs: [dealerSyncId],
          limit: 1,
        );
        if (didRows.isNotEmpty) {
          final v = didRows.first['Did'];
          did = v is int ? v : int.tryParse('$v');
        }
      }
      await reconcile(
        db: db,
        sourceSyncId: appliedKey,
        dealerId: did,
        dealerSyncId: dealerSyncId,
        ddDelta: ddDelta,
        dDelta: dDelta,
        markDealerDirty: false,
      );
    }
  }

  static double _asDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
