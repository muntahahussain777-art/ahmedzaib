import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import 'supabase_config.dart';
import 'sync_meta.dart';
import 'sync_policy.dart';

/// Silent offline-first sync: Mobile ↔ Supabase ↔ WinForms.
/// Serialized pass; dependency-safe push; version-ack mark-clean; pull protects dirty/tombstones.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _prefsLastPullPrefix = 'zaib_sync_last_pull_';
  static const _prefsDeviceId = 'zaib_sync_device_id';

  bool _running = false;
  bool _initialized = false;
  bool _queued = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _periodic;
  Timer? _dirtyDebounce;

  static const _httpTimeout = Duration(seconds: 12);
  static const _pageSize = 500;

  SupabaseClient get _client => Supabase.instance.client;

  PostgrestQueryBuilder _table(String name) => _client.from(name);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    await _ensureDeviceId();
    await _ensureSyncAuxTables();
    SyncMeta.onLocalChange = () {
      _dirtyDebounce?.cancel();
      _dirtyDebounce = Timer(const Duration(seconds: 2), () {
        unawaited(syncNow());
      });
    };
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.isEmpty || results.any((r) => r != ConnectivityResult.none);
      if (online) unawaited(syncNow());
    });
    _periodic = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(syncNow());
    });
    unawaited(syncNow());
  }

  void dispose() {
    _connSub?.cancel();
    _periodic?.cancel();
    _dirtyDebounce?.cancel();
  }

  Future<void> _ensureSyncAuxTables() async {
    final db = await AppDatabase.instance.database;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SyncFailLog (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        At TEXT NOT NULL,
        Scope TEXT NOT NULL,
        SyncId TEXT,
        Message TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SyncStagedRemote (
        SyncId TEXT NOT NULL,
        CloudTable TEXT NOT NULL,
        PayloadJson TEXT NOT NULL,
        UpdatedAt TEXT NOT NULL,
        PRIMARY KEY (CloudTable, SyncId)
      )
    ''');
  }

  Future<String> _ensureDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_prefsDeviceId, id);
    }
    return id;
  }

  /// One serialized sync pass. Timeouts on HTTP only — never clear the lock early.
  Future<void> syncNow() async {
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      await _runSyncPass();
    } catch (e) {
      await _logFail('syncNow', null, e);
    } finally {
      _running = false;
      if (_queued) {
        _queued = false;
        unawaited(syncNow());
      }
    }
  }

  Future<void> _runSyncPass() async {
    final net = await Connectivity().checkConnectivity();
    final clearlyOffline =
        net.isNotEmpty && net.every((r) => r == ConnectivityResult.none);
    if (clearlyOffline) return;

    try {
      await AppDatabase.instance.ensureSyncColumnsAndBackfill();
    } catch (_) {}
    await _ensureSyncAuxTables();

    final deviceId = await _ensureDeviceId();

    // Tombstones + dirty first (parents→children), then protected pull.
    // Not a naive order swap: pull still cannot overwrite pending/tombstones.
    try {
      await _pushTombstones(deviceId);
      await _pushAll(deviceId);
    } catch (e) {
      await _logFail('push', null, e);
    }

    try {
      await _pullAll();
      await _flushStaged();
    } catch (e) {
      await _logFail('pull', null, e);
    }
  }

  Future<void> _logFail(String scope, String? syncId, Object error) async {
    try {
      final db = await AppDatabase.instance.database;
      final msg = error.toString();
      final safe = msg
          .replaceAll(RegExp(r'eyJ[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'), '[redacted-jwt]')
          .replaceAll(RegExp(r'Bearer\s+\S+', caseSensitive: false), 'Bearer [redacted]');
      await db.insert('SyncFailLog', {
        'At': SyncMeta.nowIso(),
        'Scope': scope,
        'SyncId': syncId,
        'Message': safe.length > 500 ? safe.substring(0, 500) : safe,
      });
    } catch (_) {}
  }

  Future<void> _pushAll(String deviceId) async {
    final db = await AppDatabase.instance.database;
    await _pushCustomers(db, deviceId);
    await _pushDealers(db, deviceId);
    await _pushPetrol(db, deviceId);
    await _pushPayouts(db, deviceId);
    await _pushPurchases(db, deviceId);
    await _pushDirect(db, deviceId);
    await _pushStock(db, deviceId);
    await _pushBank(db, deviceId);
    await _pushExpenses(db, deviceId);
  }

  /// Acknowledge only the exact uploaded local version (preserve mid-upload edits).
  Future<void> _markCleanIfVersion(
    Database db,
    String table,
    String pkCol,
    Object pk,
    String syncId,
    String uploadedUpdatedAt,
  ) async {
    final rows = await db.query(
      table,
      columns: ['UpdatedAt'],
      where: '$pkCol = ?',
      whereArgs: [pk],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final current = rows.first['UpdatedAt']?.toString();
    if (!SyncPolicy.shouldMarkClean(
      currentUpdatedAt: current,
      uploadedUpdatedAt: uploadedUpdatedAt,
      stillDirtyExpected: false,
    )) {
      return;
    }
    await db.update(
      table,
      {'SyncDirty': 0, 'SyncId': syncId},
      where: '$pkCol = ? AND UpdatedAt = ?',
      whereArgs: [pk, uploadedUpdatedAt],
    );
  }

  Future<String?> _syncIdOf(Database db, String table, String pkCol, Object? pk) async {
    if (pk == null) return null;
    final rows = await db.query(table, columns: ['SyncId'], where: '$pkCol = ?', whereArgs: [pk], limit: 1);
    if (rows.isEmpty) return null;
    final s = rows.first['SyncId']?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  Future<bool> _parentReady(Database db, String table, String pkCol, Object? pk) async {
    if (pk == null) return true;
    final rows = await db.query(
      table,
      columns: ['SyncId', 'SyncDirty'],
      where: '$pkCol = ?',
      whereArgs: [pk],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final syncId = rows.first['SyncId']?.toString();
    if (syncId == null || syncId.isEmpty) return false;
    final dirty = rows.first['SyncDirty'];
    final dirtyInt = dirty is int ? dirty : int.tryParse('$dirty') ?? 0;
    // Parent must already be clean (uploaded) so child FK sync_id is stable on server.
    return dirtyInt == 0;
  }

  Future<bool> _upsertAck(String table, Map<String, dynamic> row) async {
    final uploadedAt = row['updated_at']?.toString();
    final uploadedDevice = row['device_id']?.toString();
    final raw = await _table(table)
        .upsert(row, onConflict: 'sync_id')
        .select('sync_id, updated_at, device_id, deleted_at')
        .timeout(_httpTimeout);
    if (raw.isEmpty) {
      // Server may omit representation; treat as soft ack of idempotent upsert.
      return true;
    }
    final returned = Map<String, dynamic>.from(raw.first);
    return SyncPolicy.uploadAckMatches(
      uploadedUpdatedAt: uploadedAt,
      returnedUpdatedAt: returned['updated_at']?.toString(),
      uploadedDeviceId: uploadedDevice,
      returnedDeviceId: returned['device_id']?.toString(),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchPage(
    String table, {
    required String since,
    required int from,
  }) async {
    final raw = await _table(table)
        .select()
        .gt('updated_at', since)
        .order('updated_at', ascending: true)
        .order('sync_id', ascending: true)
        .range(from, from + _pageSize - 1)
        .timeout(_httpTimeout);
    return raw.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<String> _checkpoint(String cloudTable) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefsLastPullPrefix$cloudTable') ?? '1970-01-01T00:00:00.000Z';
  }

  Future<void> _saveCheckpoint(String cloudTable, String updatedAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefsLastPullPrefix$cloudTable', updatedAt);
  }

  Future<void> _upsertLocal(
    Database db,
    String table,
    String syncId,
    Map<String, Object?> map,
  ) async {
    final existing = await db.query(table, columns: ['rowid'], where: 'SyncId = ?', whereArgs: [syncId], limit: 1);
    if (existing.isEmpty) {
      try {
        await db.insert(table, map);
      } catch (_) {
        await db.update(table, map, where: 'SyncId = ?', whereArgs: [syncId]);
      }
    } else {
      await db.update(table, map, where: 'SyncId = ?', whereArgs: [syncId]);
    }
  }

  Future<bool> _hasTombstone(Database db, String syncId) async {
    final rows = await db.query('SyncTombstone', columns: ['SyncId'], where: 'SyncId = ?', whereArgs: [syncId], limit: 1);
    return rows.isNotEmpty;
  }

  /// Remote soft-delete → local delete without leaving SyncTombstone (no push loop).
  Future<void> _applyRemoteDelete(Database db, String table, String syncId) async {
    if (await _hasTombstone(db, syncId)) {
      // Local delete pending upload — keep tombstone; do not clear until push ack.
      return;
    }
    final rows = await db.query(table, columns: ['SyncDirty'], where: 'SyncId = ?', whereArgs: [syncId], limit: 1);
    if (rows.isNotEmpty) {
      final dirty = rows.first['SyncDirty'];
      final dirtyInt = dirty is int ? dirty : int.tryParse('$dirty') ?? 0;
      if (dirtyInt == 1) return;
    }
    await db.delete(table, where: 'SyncId = ?', whereArgs: [syncId]);
    await db.delete('SyncTombstone', where: 'SyncId = ?', whereArgs: [syncId]);
  }

  Future<bool> _shouldApply(
    Database db,
    String table,
    String syncId,
    String remoteUpdated, {
    required bool remoteDeleted,
    String? remoteDeviceId,
  }) async {
    if (await _hasTombstone(db, syncId)) {
      return SyncPolicy.shouldApplyRemote(
        rowExists: true,
        syncDirty: false,
        hasLocalTombstone: true,
        localUpdatedAt: null,
        remoteUpdatedAt: remoteUpdated,
        localDeviceId: null,
        remoteDeviceId: remoteDeviceId,
        remoteDeleted: remoteDeleted,
      );
    }
    final rows = await db.query(
      table,
      columns: ['UpdatedAt', 'SyncDirty'],
      where: 'SyncId = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return SyncPolicy.shouldApplyRemote(
        rowExists: false,
        syncDirty: false,
        hasLocalTombstone: false,
        localUpdatedAt: null,
        remoteUpdatedAt: remoteUpdated,
        localDeviceId: null,
        remoteDeviceId: remoteDeviceId,
        remoteDeleted: remoteDeleted,
      );
    }
    final dirty = rows.first['SyncDirty'];
    final dirtyInt = dirty is int ? dirty : int.tryParse('$dirty') ?? 0;
    return SyncPolicy.shouldApplyRemote(
      rowExists: true,
      syncDirty: dirtyInt == 1,
      hasLocalTombstone: false,
      localUpdatedAt: rows.first['UpdatedAt']?.toString(),
      remoteUpdatedAt: remoteUpdated,
      localDeviceId: await _ensureDeviceId(),
      remoteDeviceId: remoteDeviceId,
      remoteDeleted: remoteDeleted,
    );
  }

  Future<void> _stageRemote(String cloudTable, Map<String, dynamic> row) async {
    final db = await AppDatabase.instance.database;
    final syncId = row['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) return;
    await db.insert(
      'SyncStagedRemote',
      {
        'SyncId': syncId,
        'CloudTable': cloudTable,
        'PayloadJson': jsonEncode(row),
        'UpdatedAt': row['updated_at']?.toString() ?? SyncMeta.nowIso(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _pushCustomers(Database db, String deviceId) async {
    final rows = await db.query('AddCustomer', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final updatedAt = (r['UpdatedAt']?.toString().isNotEmpty == true) ? r['UpdatedAt'].toString() : SyncMeta.nowIso();
      try {
        final ok = await _upsertAck('zaib_customers', {
          'sync_id': syncId,
          'local_id': r['id'],
          'name': r['Name'] ?? '',
          'mobile': r['Mobile'] ?? '',
          'date_text': r['Date'] ?? '',
          'updated_at': updatedAt,
          'deleted_at': null,
          'device_id': deviceId,
        });
        if (ok) await _markCleanIfVersion(db, 'AddCustomer', 'id', r['id']!, syncId, updatedAt);
      } catch (e) {
        await _logFail('push:zaib_customers', syncId, e);
      }
    }
  }

  Future<void> _pushDealers(Database db, String deviceId) async {
    final rows = await db.query('AddDealer', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final updatedAt = (r['UpdatedAt']?.toString().isNotEmpty == true) ? r['UpdatedAt'].toString() : SyncMeta.nowIso();
      try {
        final ok = await _upsertAck('zaib_dealers', {
          'sync_id': syncId,
          'local_id': r['Did'],
          'dealer_name': r['DealerName'] ?? '',
          'dd_amount': r['DDAmount'] ?? 0,
          'd_amount': r['DAmount'] ?? 0,
          'date_text': r['Date'] ?? '',
          'updated_at': updatedAt,
          'deleted_at': null,
          'device_id': deviceId,
        });
        if (ok) await _markCleanIfVersion(db, 'AddDealer', 'Did', r['Did']!, syncId, updatedAt);
      } catch (e) {
        await _logFail('push:zaib_dealers', syncId, e);
      }
    }
  }

  Future<void> _pushPetrol(Database db, String deviceId) async {
    final rows = await db.query('PetrolAdd', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      if (!await _parentReady(db, 'AddCustomer', 'id', r['CustomerId'])) continue;
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final updatedAt = (r['UpdatedAt']?.toString().isNotEmpty == true) ? r['UpdatedAt'].toString() : SyncMeta.nowIso();
      final custSync = await _syncIdOf(db, 'AddCustomer', 'id', r['CustomerId']);
      String customerName = '';
      if (r['CustomerId'] != null) {
        final c = await db.query('AddCustomer', columns: ['Name'], where: 'id = ?', whereArgs: [r['CustomerId']], limit: 1);
        if (c.isNotEmpty) customerName = c.first['Name']?.toString() ?? '';
      }
      try {
        final ok = await _upsertAck('zaib_petrol_entries', {
          'sync_id': syncId,
          'local_id': r['pid'],
          'customer_sync_id': custSync,
          'customer_name': customerName,
          'date_text': r['Date'] ?? '',
          'receipt_no': r['ReceiptNo'] ?? '',
          'vehicle': r['vehicle'] ?? '',
          'litter': r['Litter'] ?? 0,
          'rate': r['Rate'] ?? 0,
          'advance': r['Advance'] ?? 0,
          'amount': r['Amount'] ?? 0,
          'credit': r['Credit'] ?? 0,
          'balance': r['Balance'] ?? 0,
          'note': r['Note'] ?? '',
          'is_initial_entry': r['IsInitialEntry'] ?? 1,
          'processed': r['Processed'] ?? 0,
          'updated_at': updatedAt,
          'deleted_at': null,
          'device_id': deviceId,
        });
        if (ok) await _markCleanIfVersion(db, 'PetrolAdd', 'pid', r['pid']!, syncId, updatedAt);
      } catch (e) {
        await _logFail('push:zaib_petrol_entries', syncId, e);
      }
    }
  }

  Future<void> _pushPayouts(Database db, String deviceId) async {
    final rows = await db.query('DieselLedgerCredit', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      if (!await _parentReady(db, 'AddDealer', 'Did', r['Did'])) continue;
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final updatedAt = (r['UpdatedAt']?.toString().isNotEmpty == true) ? r['UpdatedAt'].toString() : SyncMeta.nowIso();
      final dSync = await _syncIdOf(db, 'AddDealer', 'Did', r['Did']);
      String dealerName = '';
      if (r['Did'] != null) {
        final d = await db.query('AddDealer', columns: ['DealerName'], where: 'Did = ?', whereArgs: [r['Did']], limit: 1);
        if (d.isNotEmpty) dealerName = d.first['DealerName']?.toString() ?? '';
      }
      try {
        final ok = await _upsertAck('zaib_dealer_payouts', {
          'sync_id': syncId,
          'local_id': r['LedgerID'],
          'dealer_sync_id': dSync,
          'dealer_name': dealerName,
          'amount_given': r['AmounGiven'] ?? 0,
          'date_text': r['Date'] ?? '',
          'note': r['Note'] ?? '',
          'updated_at': updatedAt,
          'deleted_at': null,
          'device_id': deviceId,
        });
        if (ok) await _markCleanIfVersion(db, 'DieselLedgerCredit', 'LedgerID', r['LedgerID']!, syncId, updatedAt);
      } catch (e) {
        await _logFail('push:zaib_dealer_payouts', syncId, e);
      }
    }
  }

  Future<void> _pushPurchases(Database db, String deviceId) async {
    final rows = await db.query('AddStock', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      if (!await _parentReady(db, 'AddDealer', 'Did', r['DealerId'])) continue;
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final updatedAt = (r['UpdatedAt']?.toString().isNotEmpty == true) ? r['UpdatedAt'].toString() : SyncMeta.nowIso();
      final dSync = await _syncIdOf(db, 'AddDealer', 'Did', r['DealerId']);
      String dealerName = '';
      if (r['DealerId'] != null) {
        final d = await db.query('AddDealer', columns: ['DealerName'], where: 'Did = ?', whereArgs: [r['DealerId']], limit: 1);
        if (d.isNotEmpty) dealerName = d.first['DealerName']?.toString() ?? '';
      }
      try {
        final ok = await _upsertAck('zaib_dealer_purchases', {
          'sync_id': syncId,
          'local_id': r['Sid'],
          'dealer_sync_id': dSync,
          'dealer_name': dealerName,
          'vehicle': r['Vehicle'] ?? '',
          'rate': r['Rate'] ?? 0,
          'add_diesel': r['AddDisel'] ?? 0,
          'date_text': r['Date'] ?? '',
          'note': r['Note'] ?? '',
          'updated_at': updatedAt,
          'deleted_at': null,
          'device_id': deviceId,
        });
        if (ok) await _markCleanIfVersion(db, 'AddStock', 'Sid', r['Sid']!, syncId, updatedAt);
      } catch (e) {
        await _logFail('push:zaib_dealer_purchases', syncId, e);
      }
    }
  }

  Future<void> _pushDirect(Database db, String deviceId) async {
    final rows = await db.query('DieselLedgerDebit', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      if (!await _parentReady(db, 'AddDealer', 'Did', r['Did'])) continue;
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final updatedAt = (r['UpdatedAt']?.toString().isNotEmpty == true) ? r['UpdatedAt'].toString() : SyncMeta.nowIso();
      final dSync = await _syncIdOf(db, 'AddDealer', 'Did', r['Did']);
      String dealerName = '';
      if (r['Did'] != null) {
        final d = await db.query('AddDealer', columns: ['DealerName'], where: 'Did = ?', whereArgs: [r['Did']], limit: 1);
        if (d.isNotEmpty) dealerName = d.first['DealerName']?.toString() ?? '';
      }
      try {
        final ok = await _upsertAck('zaib_dealer_direct', {
          'sync_id': syncId,
          'local_id': r['LedgerID'],
          'dealer_sync_id': dSync,
          'dealer_name': dealerName,
          'amount_given': r['AmounGiven'] ?? 0,
          'date_text': r['Date'] ?? '',
          'note': r['Note'] ?? '',
          'updated_at': updatedAt,
          'deleted_at': null,
          'device_id': deviceId,
        });
        if (ok) await _markCleanIfVersion(db, 'DieselLedgerDebit', 'LedgerID', r['LedgerID']!, syncId, updatedAt);
      } catch (e) {
        await _logFail('push:zaib_dealer_direct', syncId, e);
      }
    }
  }

  Future<void> _pushStock(Database db, String deviceId) async {
    final rows = await db.query('StockDiesel', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      if (!await _parentReady(db, 'AddDealer', 'Did', r['SDid'])) continue;
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final updatedAt = (r['UpdatedAt']?.toString().isNotEmpty == true) ? r['UpdatedAt'].toString() : SyncMeta.nowIso();
      final dSync = await _syncIdOf(db, 'AddDealer', 'Did', r['SDid']);
      String dealerName = '';
      if (r['SDid'] != null) {
        final d = await db.query('AddDealer', columns: ['DealerName'], where: 'Did = ?', whereArgs: [r['SDid']], limit: 1);
        if (d.isNotEmpty) dealerName = d.first['DealerName']?.toString() ?? '';
      }
      try {
        final ok = await _upsertAck('zaib_stock_diesel', {
          'sync_id': syncId,
          'local_id': r['SID'],
          'dealer_sync_id': dSync,
          'dealer_name': dealerName,
          'date_text': r['Date'] ?? '',
          'vehicle': r['Vehicle'] ?? '',
          'litter': r['Litter'] ?? 0,
          'rate': r['Rate'] ?? 0,
          'credit': r['Credit'] ?? 0,
          'debit': r['Debit'] ?? 0,
          'note': r['Note'] ?? '',
          'updated_at': updatedAt,
          'deleted_at': null,
          'device_id': deviceId,
        });
        if (ok) await _markCleanIfVersion(db, 'StockDiesel', 'SID', r['SID']!, syncId, updatedAt);
      } catch (e) {
        await _logFail('push:zaib_stock_diesel', syncId, e);
      }
    }
  }

  Future<void> _pushBank(Database db, String deviceId) async {
    final rows = await db.query('BankTransactions', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      if (r['CustomerId'] != null && !await _parentReady(db, 'AddCustomer', 'id', r['CustomerId'])) continue;
      if (r['DealerId'] != null && !await _parentReady(db, 'AddDealer', 'Did', r['DealerId'])) continue;
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final updatedAt = (r['UpdatedAt']?.toString().isNotEmpty == true) ? r['UpdatedAt'].toString() : SyncMeta.nowIso();
      final cSync = await _syncIdOf(db, 'AddCustomer', 'id', r['CustomerId']);
      final dSync = await _syncIdOf(db, 'AddDealer', 'Did', r['DealerId']);
      String customerName = '';
      String dealerName = '';
      if (r['CustomerId'] != null) {
        final c = await db.query('AddCustomer', columns: ['Name'], where: 'id = ?', whereArgs: [r['CustomerId']], limit: 1);
        if (c.isNotEmpty) customerName = c.first['Name']?.toString() ?? '';
      }
      if (r['DealerId'] != null) {
        final d = await db.query('AddDealer', columns: ['DealerName'], where: 'Did = ?', whereArgs: [r['DealerId']], limit: 1);
        if (d.isNotEmpty) dealerName = d.first['DealerName']?.toString() ?? '';
      }
      try {
        final ok = await _upsertAck('zaib_bank_transactions', {
          'sync_id': syncId,
          'local_id': r['Id'],
          'transaction_date': r['TransactionDate'] ?? '',
          'transaction_type': r['TransactionType'] ?? '',
          'customer_sync_id': cSync,
          'customer_name': customerName,
          'dealer_sync_id': dSync,
          'dealer_name': dealerName,
          'amount': r['Amount'] ?? 0,
          'note': r['Note'] ?? '',
          'bank_name': r['BankName'] ?? '',
          'updated_at': updatedAt,
          'deleted_at': null,
          'device_id': deviceId,
        });
        if (ok) await _markCleanIfVersion(db, 'BankTransactions', 'Id', r['Id']!, syncId, updatedAt);
      } catch (e) {
        await _logFail('push:zaib_bank_transactions', syncId, e);
      }
    }
  }

  Future<void> _pushExpenses(Database db, String deviceId) async {
    final rows = await db.query('Expensetable', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final updatedAt = (r['UpdatedAt']?.toString().isNotEmpty == true) ? r['UpdatedAt'].toString() : SyncMeta.nowIso();
      try {
        final ok = await _upsertAck('zaib_expenses', {
          'sync_id': syncId,
          'local_id': r['sid'],
          'name': r['Name'] ?? '',
          'category': r['Category'] ?? '',
          'amount': r['Amount'] ?? 0,
          'e_date': r['EDate'] ?? '',
          'note': r['Note'] ?? '',
          'updated_at': updatedAt,
          'deleted_at': null,
          'device_id': deviceId,
        });
        if (ok) await _markCleanIfVersion(db, 'Expensetable', 'sid', r['sid']!, syncId, updatedAt);
      } catch (e) {
        await _logFail('push:zaib_expenses', syncId, e);
      }
    }
  }

  Future<void> _pushTombstones(String deviceId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('SyncTombstone');
    for (final r in rows) {
      final table = r['CloudTable']?.toString() ?? '';
      final syncId = r['SyncId']?.toString() ?? '';
      if (table.isEmpty || syncId.isEmpty) continue;
      final deletedAt = r['DeletedAt']?.toString() ?? SyncMeta.nowIso();
      try {
        final ok = await _upsertAck(table, {
          'sync_id': syncId,
          'updated_at': deletedAt,
          'deleted_at': deletedAt,
          'device_id': deviceId,
        });
        if (ok) {
          await db.delete('SyncTombstone', where: 'SyncId = ?', whereArgs: [syncId]);
        }
      } catch (e) {
        await _logFail('push:tombstone:$table', syncId, e);
      }
    }
  }

  Future<void> _pullAll() async {
    Future<void> safe(Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        await _logFail('pull', null, e);
      }
    }

    // Parents before children.
    await safe(() => _pullTable('zaib_customers', _applyCustomer));
    await safe(() => _pullTable('zaib_dealers', _applyDealer));
    await safe(() => _pullTable('zaib_petrol_entries', _applyPetrol));
    await safe(() => _pullTable('zaib_dealer_payouts', _applyPayout));
    await safe(() => _pullTable('zaib_dealer_purchases', _applyPurchase));
    await safe(() => _pullTable('zaib_dealer_direct', _applyDirect));
    await safe(() => _pullTable('zaib_stock_diesel', _applyStock));
    await safe(() => _pullTable('zaib_bank_transactions', _applyBank));
    await safe(() => _pullTable('zaib_expenses', _applyExpense));
  }

  Future<void> _pullTable(
    String cloudTable,
    Future<bool> Function(Database db, Map<String, dynamic> r) apply,
  ) async {
    final db = await AppDatabase.instance.database;
    var since = await _checkpoint(cloudTable);
    var from = 0;
    String? appliedMax = since;

    while (true) {
      final page = await _fetchPage(cloudTable, since: since, from: from);
      if (page.isEmpty) break;
      for (final r in page) {
        final updated = r['updated_at']?.toString() ?? '';
        final ok = await apply(db, r);
        if (ok && updated.isNotEmpty) {
          if (appliedMax == null || SyncPolicy.parseTs(updated).isAfter(SyncPolicy.parseTs(appliedMax))) {
            appliedMax = updated;
          }
        }
      }
      // Checkpoint only successfully applied watermark (interrupted download safe).
      if (appliedMax != null && appliedMax != since) {
        await _saveCheckpoint(cloudTable, appliedMax);
      }
      if (page.length < _pageSize) break;
      from += _pageSize;
    }
  }

  Future<void> _flushStaged() async {
    final db = await AppDatabase.instance.database;
    final staged = await db.query('SyncStagedRemote', orderBy: 'UpdatedAt ASC');
    for (final s in staged) {
      final cloud = s['CloudTable']?.toString() ?? '';
      final json = s['PayloadJson']?.toString() ?? '';
      if (cloud.isEmpty || json.isEmpty) continue;
      try {
        final row = Map<String, dynamic>.from(jsonDecode(json) as Map);
        bool ok = false;
        switch (cloud) {
          case 'zaib_petrol_entries':
            ok = await _applyPetrol(db, row);
            break;
          case 'zaib_dealer_payouts':
            ok = await _applyPayout(db, row);
            break;
          case 'zaib_dealer_purchases':
            ok = await _applyPurchase(db, row);
            break;
          case 'zaib_dealer_direct':
            ok = await _applyDirect(db, row);
            break;
          case 'zaib_stock_diesel':
            ok = await _applyStock(db, row);
            break;
          case 'zaib_bank_transactions':
            ok = await _applyBank(db, row);
            break;
          default:
            ok = true;
        }
        if (ok) {
          await db.delete(
            'SyncStagedRemote',
            where: 'CloudTable = ? AND SyncId = ?',
            whereArgs: [cloud, s['SyncId']],
          );
        }
      } catch (e) {
        await _logFail('flush:$cloud', s['SyncId']?.toString(), e);
      }
    }
  }

  int _asInt(dynamic v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is bool) return v ? 1 : 0;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? fallback;
  }

  double _asDouble(dynamic v, [double fallback = 0]) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  String _asStr(dynamic v) => v?.toString() ?? '';

  bool _isDeleted(dynamic v) {
    if (v == null) return false;
    final s = v.toString().trim();
    return s.isNotEmpty && s.toLowerCase() != 'null';
  }

  Future<int?> _localIdBySync(Database db, String table, String pkCol, String? syncId) async {
    if (syncId == null || syncId.isEmpty) return null;
    final rows = await db.query(table, columns: [pkCol], where: 'SyncId = ?', whereArgs: [syncId], limit: 1);
    if (rows.isEmpty) return null;
    final v = rows.first[pkCol];
    if (v is int) return v;
    return int.tryParse('$v');
  }

  Future<bool> _dealerHasPendingChildren(Database db, int? did) async {
    if (did == null) return false;
    Future<bool> dirty(String table, String col) async {
      final rows = await db.query(
        table,
        columns: ['rowid'],
        where: '$col = ? AND IFNULL(SyncDirty,1) = 1',
        whereArgs: [did],
        limit: 1,
      );
      return rows.isNotEmpty;
    }

    return await dirty('DieselLedgerCredit', 'Did') ||
        await dirty('DieselLedgerDebit', 'Did') ||
        await dirty('AddStock', 'DealerId') ||
        await dirty('StockDiesel', 'SDid');
  }

  Future<bool> _applyCustomer(Database db, Map<String, dynamic> r) async {
    final syncId = r['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) return true;
    final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
    final deleted = _isDeleted(r['deleted_at']);
    final device = r['device_id']?.toString();
    if (!await _shouldApply(db, 'AddCustomer', syncId, updated, remoteDeleted: deleted, remoteDeviceId: device)) {
      return true; // intentionally skipped counts as handled for checkpoint
    }
    if (deleted) {
      await _applyRemoteDelete(db, 'AddCustomer', syncId);
      return true;
    }
    await _upsertLocal(db, 'AddCustomer', syncId, {
      'Name': _asStr(r['name']),
      'Mobile': _asStr(r['mobile']),
      'Date': _asStr(r['date_text']),
      'SyncId': syncId,
      'UpdatedAt': updated,
      'SyncDirty': 0,
    });
    return true;
  }

  Future<bool> _applyDealer(Database db, Map<String, dynamic> r) async {
    final syncId = r['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) return true;
    final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
    final deleted = _isDeleted(r['deleted_at']);
    final device = r['device_id']?.toString();
    if (!await _shouldApply(db, 'AddDealer', syncId, updated, remoteDeleted: deleted, remoteDeviceId: device)) {
      return true;
    }
    if (deleted) {
      await _applyRemoteDelete(db, 'AddDealer', syncId);
      return true;
    }
    final existing = await db.query('AddDealer', columns: ['Did', 'SyncDirty'], where: 'SyncId = ?', whereArgs: [syncId], limit: 1);
    if (existing.isNotEmpty) {
      final did = existing.first['Did'];
      final didInt = did is int ? did : int.tryParse('$did');
      if (await _dealerHasPendingChildren(db, didInt)) {
        // Preserve accounting formulas: do not overwrite aggregate balances while children pending.
        await _upsertLocal(db, 'AddDealer', syncId, {
          'DealerName': _asStr(r['dealer_name']),
          'Date': _asStr(r['date_text']),
          'SyncId': syncId,
          'UpdatedAt': updated,
          'SyncDirty': 0,
        });
        return true;
      }
    }
    await _upsertLocal(db, 'AddDealer', syncId, {
      'DealerName': _asStr(r['dealer_name']),
      'DDAmount': _asDouble(r['dd_amount']),
      'DAmount': _asDouble(r['d_amount']),
      'Date': _asStr(r['date_text']),
      'SyncId': syncId,
      'UpdatedAt': updated,
      'SyncDirty': 0,
    });
    return true;
  }

  Future<bool> _applyPetrol(Database db, Map<String, dynamic> r) async {
    final syncId = r['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) return true;
    final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
    final deleted = _isDeleted(r['deleted_at']);
    final device = r['device_id']?.toString();
    if (!await _shouldApply(db, 'PetrolAdd', syncId, updated, remoteDeleted: deleted, remoteDeviceId: device)) {
      return true;
    }
    if (deleted) {
      await _applyRemoteDelete(db, 'PetrolAdd', syncId);
      return true;
    }
    final custSync = r['customer_sync_id']?.toString();
    final custId = await _localIdBySync(db, 'AddCustomer', 'id', custSync);
    if (custSync != null && custSync.isNotEmpty && custId == null) {
      await _stageRemote('zaib_petrol_entries', r);
      return false;
    }
    await _upsertLocal(db, 'PetrolAdd', syncId, {
      'Date': _asStr(r['date_text']),
      'ReceiptNo': _asStr(r['receipt_no']),
      'vehicle': _asStr(r['vehicle']),
      'Litter': _asDouble(r['litter']),
      'Rate': _asDouble(r['rate']),
      'Advance': _asDouble(r['advance']),
      'Amount': _asDouble(r['amount']),
      'Credit': _asDouble(r['credit']),
      'Balance': _asDouble(r['balance']),
      'Note': _asStr(r['note']),
      'CustomerId': custId,
      'Processed': _asInt(r['processed']),
      'IsInitialEntry': _asInt(r['is_initial_entry'], 1),
      'SyncId': syncId,
      'UpdatedAt': updated,
      'SyncDirty': 0,
    });
    return true;
  }

  Future<bool> _applyPayout(Database db, Map<String, dynamic> r) async {
    final syncId = r['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) return true;
    final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
    final deleted = _isDeleted(r['deleted_at']);
    final device = r['device_id']?.toString();
    if (!await _shouldApply(db, 'DieselLedgerCredit', syncId, updated, remoteDeleted: deleted, remoteDeviceId: device)) {
      return true;
    }
    if (deleted) {
      await _applyRemoteDelete(db, 'DieselLedgerCredit', syncId);
      return true;
    }
    final dSync = r['dealer_sync_id']?.toString();
    final did = await _localIdBySync(db, 'AddDealer', 'Did', dSync);
    if (dSync != null && dSync.isNotEmpty && did == null) {
      await _stageRemote('zaib_dealer_payouts', r);
      return false;
    }
    await _upsertLocal(db, 'DieselLedgerCredit', syncId, {
      'Did': did,
      'Date': _asStr(r['date_text']),
      'AmounGiven': _asDouble(r['amount_given']),
      'Note': _asStr(r['note']),
      'SyncId': syncId,
      'UpdatedAt': updated,
      'SyncDirty': 0,
    });
    return true;
  }

  Future<bool> _applyPurchase(Database db, Map<String, dynamic> r) async {
    final syncId = r['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) return true;
    final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
    final deleted = _isDeleted(r['deleted_at']);
    final device = r['device_id']?.toString();
    if (!await _shouldApply(db, 'AddStock', syncId, updated, remoteDeleted: deleted, remoteDeviceId: device)) {
      return true;
    }
    if (deleted) {
      await _applyRemoteDelete(db, 'AddStock', syncId);
      return true;
    }
    final dSync = r['dealer_sync_id']?.toString();
    final did = await _localIdBySync(db, 'AddDealer', 'Did', dSync);
    if (dSync != null && dSync.isNotEmpty && did == null) {
      await _stageRemote('zaib_dealer_purchases', r);
      return false;
    }
    await _upsertLocal(db, 'AddStock', syncId, {
      'Vehicle': _asStr(r['vehicle']),
      'Rate': _asDouble(r['rate']),
      'SellDisel': 0,
      'Stock': 0,
      'Date': _asStr(r['date_text']),
      'AddDisel': _asDouble(r['add_diesel']),
      'DealerId': did,
      'Note': _asStr(r['note']),
      'SyncId': syncId,
      'UpdatedAt': updated,
      'SyncDirty': 0,
    });
    return true;
  }

  Future<bool> _applyDirect(Database db, Map<String, dynamic> r) async {
    final syncId = r['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) return true;
    final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
    final deleted = _isDeleted(r['deleted_at']);
    final device = r['device_id']?.toString();
    if (!await _shouldApply(db, 'DieselLedgerDebit', syncId, updated, remoteDeleted: deleted, remoteDeviceId: device)) {
      return true;
    }
    if (deleted) {
      await _applyRemoteDelete(db, 'DieselLedgerDebit', syncId);
      return true;
    }
    final dSync = r['dealer_sync_id']?.toString();
    final did = await _localIdBySync(db, 'AddDealer', 'Did', dSync);
    if (dSync != null && dSync.isNotEmpty && did == null) {
      await _stageRemote('zaib_dealer_direct', r);
      return false;
    }
    await _upsertLocal(db, 'DieselLedgerDebit', syncId, {
      'Did': did,
      'Date': _asStr(r['date_text']),
      'AmounGiven': _asDouble(r['amount_given']),
      'Note': _asStr(r['note']),
      'SyncId': syncId,
      'UpdatedAt': updated,
      'SyncDirty': 0,
    });
    return true;
  }

  Future<bool> _applyStock(Database db, Map<String, dynamic> r) async {
    final syncId = r['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) return true;
    final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
    final deleted = _isDeleted(r['deleted_at']);
    final device = r['device_id']?.toString();
    if (!await _shouldApply(db, 'StockDiesel', syncId, updated, remoteDeleted: deleted, remoteDeviceId: device)) {
      return true;
    }
    if (deleted) {
      await _applyRemoteDelete(db, 'StockDiesel', syncId);
      return true;
    }
    final dSync = r['dealer_sync_id']?.toString();
    final did = await _localIdBySync(db, 'AddDealer', 'Did', dSync);
    if (dSync != null && dSync.isNotEmpty && did == null) {
      await _stageRemote('zaib_stock_diesel', r);
      return false;
    }
    await _upsertLocal(db, 'StockDiesel', syncId, {
      'SDid': did,
      'Date': _asStr(r['date_text']),
      'Vehicle': _asStr(r['vehicle']),
      'Litter': _asDouble(r['litter']),
      'Rate': _asDouble(r['rate']),
      'Credit': _asDouble(r['credit']),
      'Debit': _asDouble(r['debit']),
      'Note': _asStr(r['note']),
      'SyncId': syncId,
      'UpdatedAt': updated,
      'SyncDirty': 0,
    });
    return true;
  }

  Future<bool> _applyBank(Database db, Map<String, dynamic> r) async {
    final syncId = r['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) return true;
    final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
    final deleted = _isDeleted(r['deleted_at']);
    final device = r['device_id']?.toString();
    if (!await _shouldApply(db, 'BankTransactions', syncId, updated, remoteDeleted: deleted, remoteDeviceId: device)) {
      return true;
    }
    if (deleted) {
      await _applyRemoteDelete(db, 'BankTransactions', syncId);
      return true;
    }
    final cSync = r['customer_sync_id']?.toString();
    final dSync = r['dealer_sync_id']?.toString();
    final cid = await _localIdBySync(db, 'AddCustomer', 'id', cSync);
    final did = await _localIdBySync(db, 'AddDealer', 'Did', dSync);
    if ((cSync != null && cSync.isNotEmpty && cid == null) ||
        (dSync != null && dSync.isNotEmpty && did == null)) {
      await _stageRemote('zaib_bank_transactions', r);
      return false;
    }
    await _upsertLocal(db, 'BankTransactions', syncId, {
      'TransactionDate': _asStr(r['transaction_date']),
      'TransactionType': _asStr(r['transaction_type']),
      'CustomerId': cid,
      'DealerId': did,
      'Amount': _asDouble(r['amount']),
      'Note': _asStr(r['note']),
      'BankName': _asStr(r['bank_name']),
      'SyncId': syncId,
      'UpdatedAt': updated,
      'SyncDirty': 0,
    });
    return true;
  }

  Future<bool> _applyExpense(Database db, Map<String, dynamic> r) async {
    final syncId = r['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) return true;
    final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
    final deleted = _isDeleted(r['deleted_at']);
    final device = r['device_id']?.toString();
    if (!await _shouldApply(db, 'Expensetable', syncId, updated, remoteDeleted: deleted, remoteDeviceId: device)) {
      return true;
    }
    if (deleted) {
      await _applyRemoteDelete(db, 'Expensetable', syncId);
      return true;
    }
    await _upsertLocal(db, 'Expensetable', syncId, {
      'Name': _asStr(r['name']),
      'Category': _asStr(r['category']),
      'Amount': _asDouble(r['amount']),
      'EDate': _asStr(r['e_date']),
      'Note': _asStr(r['note']),
      'SyncId': syncId,
      'UpdatedAt': updated,
      'SyncDirty': 0,
    });
    return true;
  }
}
