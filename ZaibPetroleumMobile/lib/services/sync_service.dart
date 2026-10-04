import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import 'supabase_config.dart';
import 'sync_meta.dart';

/// Silent offline-first sync: Mobile ↔ Supabase (zaibservice) ↔ other devices/PC.
/// Dedup key = sync_id (UUID). Last-write-wins on updated_at.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _prefsLastPull = 'zaib_sync_last_pull';
  static const _prefsDeviceId = 'zaib_sync_device_id';

  bool _running = false;
  bool _initialized = false;
  bool _queued = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _periodic;
  Timer? _dirtyDebounce;

  static const _syncTimeout = Duration(seconds: 45);
  static const _httpTimeout = Duration(seconds: 12);

  SupabaseClient get _client => Supabase.instance.client;

  /// public.zaib_* tables (same as WinForms)
  PostgrestQueryBuilder _table(String name) => _client.from(name);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // Same anon JWT WinForms uses (PC→cloud already works)
      anonKey: SupabaseConfig.anonKey,
    );
    await _ensureDeviceId();
    // Form save → silent sync (debounced, never blocks UI)
    SyncMeta.onLocalChange = () {
      _dirtyDebounce?.cancel();
      _dirtyDebounce = Timer(const Duration(seconds: 2), () {
        unawaited(syncNow());
      });
    };
    // Force full cloud→local on next sync (fix stale lastPull)
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsLastPull);
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

  Future<String> _ensureDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_prefsDeviceId, id);
    }
    return id;
  }

  /// Never blocks UI. Offline pe skip; online pe timeout ke sath pull/push.
  Future<void> syncNow() async {
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      await _runSyncPass().timeout(_syncTimeout, onTimeout: () {});
    } catch (_) {
      // Silent — offline / transient errors must not break UI.
    } finally {
      _running = false;
      if (_queued) {
        _queued = false;
        unawaited(syncNow());
      }
    }
  }

  Future<void> _runSyncPass() async {
    // Empty list = unknown (not offline). Only skip when clearly none.
    final net = await Connectivity().checkConnectivity();
    final clearlyOffline =
        net.isNotEmpty && net.every((r) => r == ConnectivityResult.none);
    if (clearlyOffline) return;

    try {
      await AppDatabase.instance.ensureSyncColumnsAndBackfill();
    } catch (_) {}

    final deviceId = await _ensureDeviceId();

    // IMPORTANT: pull FIRST so WinForms→Supabase→Mobile always works
    // even when mobile push has errors.
    try {
      await _pullAll();
    } catch (_) {}

    try {
      await _pushAll(deviceId);
      await _pushTombstones(deviceId);
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

  Future<void> _markClean(Database db, String table, String pkCol, Object pk, String syncId) async {
    await db.update(
      table,
      {'SyncDirty': 0, 'SyncId': syncId},
      where: '$pkCol = ?',
      whereArgs: [pk],
    );
  }

  Future<String?> _syncIdOf(Database db, String table, String pkCol, Object? pk) async {
    if (pk == null) return null;
    final rows = await db.query(table, columns: ['SyncId'], where: '$pkCol = ?', whereArgs: [pk], limit: 1);
    if (rows.isEmpty) return null;
    final s = rows.first['SyncId']?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  Future<void> _upsert(String table, Map<String, dynamic> row) async {
    await _table(table).upsert(row, onConflict: 'sync_id').timeout(_httpTimeout);
  }

  /// Full table fetch (paginated). WinForms data must always land on mobile.
  Future<List<Map<String, dynamic>>> _fetchAll(String table) async {
    final all = <Map<String, dynamic>>[];
    const page = 1000;
    var from = 0;
    while (true) {
      final raw = await _table(table)
          .select()
          .range(from, from + page - 1)
          .timeout(_httpTimeout);
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final row in raw) {
          if (row is Map) list.add(Map<String, dynamic>.from(row));
        }
      }
      all.addAll(list);
      if (list.length < page) break;
      from += page;
    }
    return all;
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

  Future<void> _pushCustomers(Database db, String deviceId) async {
    final rows = await db.query('AddCustomer', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      await _upsert('zaib_customers', {
        'sync_id': syncId,
        'local_id': r['id'],
        'name': r['Name'] ?? '',
        'mobile': r['Mobile'] ?? '',
        'date_text': r['Date'] ?? '',
        'updated_at': r['UpdatedAt'] ?? SyncMeta.nowIso(),
        'deleted_at': null,
        'device_id': deviceId,
      });
      await _markClean(db, 'AddCustomer', 'id', r['id']!, syncId);
    }
  }

  Future<void> _pushDealers(Database db, String deviceId) async {
    final rows = await db.query('AddDealer', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      await _upsert('zaib_dealers', {
        'sync_id': syncId,
        'local_id': r['Did'],
        'dealer_name': r['DealerName'] ?? '',
        'dd_amount': r['DDAmount'] ?? 0,
        'd_amount': r['DAmount'] ?? 0,
        'date_text': r['Date'] ?? '',
        'updated_at': r['UpdatedAt'] ?? SyncMeta.nowIso(),
        'deleted_at': null,
        'device_id': deviceId,
      });
      await _markClean(db, 'AddDealer', 'Did', r['Did']!, syncId);
    }
  }

  Future<void> _pushPetrol(Database db, String deviceId) async {
    final rows = await db.query('PetrolAdd', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final custSync = await _syncIdOf(db, 'AddCustomer', 'id', r['CustomerId']);
      String customerName = '';
      if (r['CustomerId'] != null) {
        final c = await db.query('AddCustomer', columns: ['Name'], where: 'id = ?', whereArgs: [r['CustomerId']], limit: 1);
        if (c.isNotEmpty) customerName = c.first['Name']?.toString() ?? '';
      }
      await _upsert('zaib_petrol_entries', {
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
        'updated_at': r['UpdatedAt'] ?? SyncMeta.nowIso(),
        'deleted_at': null,
        'device_id': deviceId,
      });
      await _markClean(db, 'PetrolAdd', 'pid', r['pid']!, syncId);
    }
  }

  Future<void> _pushPayouts(Database db, String deviceId) async {
    final rows = await db.query('DieselLedgerCredit', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final dSync = await _syncIdOf(db, 'AddDealer', 'Did', r['Did']);
      String dealerName = '';
      if (r['Did'] != null) {
        final d = await db.query('AddDealer', columns: ['DealerName'], where: 'Did = ?', whereArgs: [r['Did']], limit: 1);
        if (d.isNotEmpty) dealerName = d.first['DealerName']?.toString() ?? '';
      }
      await _upsert('zaib_dealer_payouts', {
        'sync_id': syncId,
        'local_id': r['LedgerID'],
        'dealer_sync_id': dSync,
        'dealer_name': dealerName,
        'amount_given': r['AmounGiven'] ?? 0,
        'date_text': r['Date'] ?? '',
        'note': r['Note'] ?? '',
        'updated_at': r['UpdatedAt'] ?? SyncMeta.nowIso(),
        'deleted_at': null,
        'device_id': deviceId,
      });
      await _markClean(db, 'DieselLedgerCredit', 'LedgerID', r['LedgerID']!, syncId);
    }
  }

  Future<void> _pushPurchases(Database db, String deviceId) async {
    final rows = await db.query('AddStock', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final dSync = await _syncIdOf(db, 'AddDealer', 'Did', r['DealerId']);
      String dealerName = '';
      if (r['DealerId'] != null) {
        final d = await db.query('AddDealer', columns: ['DealerName'], where: 'Did = ?', whereArgs: [r['DealerId']], limit: 1);
        if (d.isNotEmpty) dealerName = d.first['DealerName']?.toString() ?? '';
      }
      await _upsert('zaib_dealer_purchases', {
        'sync_id': syncId,
        'local_id': r['Sid'],
        'dealer_sync_id': dSync,
        'dealer_name': dealerName,
        'vehicle': r['Vehicle'] ?? '',
        'rate': r['Rate'] ?? 0,
        'add_diesel': r['AddDisel'] ?? 0,
        'date_text': r['Date'] ?? '',
        'note': r['Note'] ?? '',
        'updated_at': r['UpdatedAt'] ?? SyncMeta.nowIso(),
        'deleted_at': null,
        'device_id': deviceId,
      });
      await _markClean(db, 'AddStock', 'Sid', r['Sid']!, syncId);
    }
  }

  Future<void> _pushDirect(Database db, String deviceId) async {
    final rows = await db.query('DieselLedgerDebit', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final dSync = await _syncIdOf(db, 'AddDealer', 'Did', r['Did']);
      String dealerName = '';
      if (r['Did'] != null) {
        final d = await db.query('AddDealer', columns: ['DealerName'], where: 'Did = ?', whereArgs: [r['Did']], limit: 1);
        if (d.isNotEmpty) dealerName = d.first['DealerName']?.toString() ?? '';
      }
      await _upsert('zaib_dealer_direct', {
        'sync_id': syncId,
        'local_id': r['LedgerID'],
        'dealer_sync_id': dSync,
        'dealer_name': dealerName,
        'amount_given': r['AmounGiven'] ?? 0,
        'date_text': r['Date'] ?? '',
        'note': r['Note'] ?? '',
        'updated_at': r['UpdatedAt'] ?? SyncMeta.nowIso(),
        'deleted_at': null,
        'device_id': deviceId,
      });
      await _markClean(db, 'DieselLedgerDebit', 'LedgerID', r['LedgerID']!, syncId);
    }
  }

  Future<void> _pushStock(Database db, String deviceId) async {
    final rows = await db.query('StockDiesel', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      final dSync = await _syncIdOf(db, 'AddDealer', 'Did', r['SDid']);
      String dealerName = '';
      if (r['SDid'] != null) {
        final d = await db.query('AddDealer', columns: ['DealerName'], where: 'Did = ?', whereArgs: [r['SDid']], limit: 1);
        if (d.isNotEmpty) dealerName = d.first['DealerName']?.toString() ?? '';
      }
      await _upsert('zaib_stock_diesel', {
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
        'updated_at': r['UpdatedAt'] ?? SyncMeta.nowIso(),
        'deleted_at': null,
        'device_id': deviceId,
      });
      await _markClean(db, 'StockDiesel', 'SID', r['SID']!, syncId);
    }
  }

  Future<void> _pushBank(Database db, String deviceId) async {
    final rows = await db.query('BankTransactions', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
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
      await _upsert('zaib_bank_transactions', {
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
        'updated_at': r['UpdatedAt'] ?? SyncMeta.nowIso(),
        'deleted_at': null,
        'device_id': deviceId,
      });
      await _markClean(db, 'BankTransactions', 'Id', r['Id']!, syncId);
    }
  }

  Future<void> _pushExpenses(Database db, String deviceId) async {
    final rows = await db.query('Expensetable', where: 'IFNULL(SyncDirty,1) = 1');
    for (final r in rows) {
      final syncId = (r['SyncId']?.toString().isNotEmpty == true) ? r['SyncId'].toString() : SyncMeta.newId();
      await _upsert('zaib_expenses', {
        'sync_id': syncId,
        'local_id': r['sid'],
        'name': r['Name'] ?? '',
        'category': r['Category'] ?? '',
        'amount': r['Amount'] ?? 0,
        'e_date': r['EDate'] ?? '',
        'note': r['Note'] ?? '',
        'updated_at': r['UpdatedAt'] ?? SyncMeta.nowIso(),
        'deleted_at': null,
        'device_id': deviceId,
      });
      await _markClean(db, 'Expensetable', 'sid', r['sid']!, syncId);
    }
  }

  Future<void> _pushTombstones(String deviceId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('SyncTombstone');
    for (final r in rows) {
      final table = r['CloudTable']?.toString() ?? '';
      final syncId = r['SyncId']?.toString() ?? '';
      if (table.isEmpty || syncId.isEmpty) continue;
      try {
        await _table(table).upsert({
          'sync_id': syncId,
          'updated_at': r['DeletedAt'] ?? SyncMeta.nowIso(),
          'deleted_at': r['DeletedAt'] ?? SyncMeta.nowIso(),
          'device_id': deviceId,
        }, onConflict: 'sync_id').timeout(_httpTimeout);
        await db.delete('SyncTombstone', where: 'SyncId = ?', whereArgs: [syncId]);
      } catch (_) {}
    }
  }

  Future<void> _pullAll() async {
    // Full pull — no since filter (PC entries always appear on mobile).
    // Each table isolated so one failure cannot block the rest.
    Future<void> safe(Future<void> Function() fn) async {
      try {
        await fn();
      } catch (_) {}
    }

    await safe(_pullCustomers);
    await safe(_pullDealers);
    await safe(_pullPetrol);
    await safe(_pullPayouts);
    await safe(_pullPurchases);
    await safe(_pullDirect);
    await safe(_pullStock);
    await safe(_pullBank);
    await safe(_pullExpenses);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLastPull, SyncMeta.nowIso());
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

  DateTime _parseTs(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return DateTime.tryParse(v.toString())?.toUtc() ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  Future<bool> _shouldApply(Database db, String table, String syncId, String remoteUpdated) async {
    final rows = await db.query(table, columns: ['UpdatedAt', 'SyncDirty'], where: 'SyncId = ?', whereArgs: [syncId], limit: 1);
    if (rows.isEmpty) return true;
    final dirty = rows.first['SyncDirty'];
    final dirtyInt = dirty is int ? dirty : int.tryParse('$dirty') ?? 0;
    if (dirtyInt == 1) {
      final local = _parseTs(rows.first['UpdatedAt']);
      final remote = _parseTs(remoteUpdated);
      return remote.isAfter(local);
    }
    final local = _parseTs(rows.first['UpdatedAt']);
    final remote = _parseTs(remoteUpdated);
    return !remote.isBefore(local);
  }

  Future<int?> _localIdBySync(Database db, String table, String pkCol, String? syncId) async {
    if (syncId == null || syncId.isEmpty) return null;
    final rows = await db.query(table, columns: [pkCol], where: 'SyncId = ?', whereArgs: [syncId], limit: 1);
    if (rows.isEmpty) return null;
    final v = rows.first[pkCol];
    if (v is int) return v;
    return int.tryParse('$v');
  }

  Future<void> _pullCustomers() async {
    final list = await _fetchAll('zaib_customers');
    final db = await AppDatabase.instance.database;
    for (final r in list) {
      final syncId = r['sync_id']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
      if (_isDeleted(r['deleted_at'])) {
        await db.delete('AddCustomer', where: 'SyncId = ?', whereArgs: [syncId]);
        continue;
      }
      if (!await _shouldApply(db, 'AddCustomer', syncId, updated)) continue;
      await _upsertLocal(db, 'AddCustomer', syncId, {
        'Name': _asStr(r['name']),
        'Mobile': _asStr(r['mobile']),
        'Date': _asStr(r['date_text']),
        'SyncId': syncId,
        'UpdatedAt': updated,
        'SyncDirty': 0,
      });
    }
  }

  Future<void> _pullDealers() async {
    final list = await _fetchAll('zaib_dealers');
    final db = await AppDatabase.instance.database;
    for (final r in list) {
      final syncId = r['sync_id']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
      if (_isDeleted(r['deleted_at'])) {
        await db.delete('AddDealer', where: 'SyncId = ?', whereArgs: [syncId]);
        continue;
      }
      if (!await _shouldApply(db, 'AddDealer', syncId, updated)) continue;
      await _upsertLocal(db, 'AddDealer', syncId, {
        'DealerName': _asStr(r['dealer_name']),
        'DDAmount': _asDouble(r['dd_amount']),
        'DAmount': _asDouble(r['d_amount']),
        'Date': _asStr(r['date_text']),
        'SyncId': syncId,
        'UpdatedAt': updated,
        'SyncDirty': 0,
      });
    }
  }

  Future<void> _pullPetrol() async {
    final list = await _fetchAll('zaib_petrol_entries');
    final db = await AppDatabase.instance.database;
    for (final r in list) {
      final syncId = r['sync_id']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
      if (_isDeleted(r['deleted_at'])) {
        await db.delete('PetrolAdd', where: 'SyncId = ?', whereArgs: [syncId]);
        continue;
      }
      if (!await _shouldApply(db, 'PetrolAdd', syncId, updated)) continue;
      final custId = await _localIdBySync(db, 'AddCustomer', 'id', r['customer_sync_id']?.toString());
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
    }
  }

  Future<void> _pullPayouts() async {
    final list = await _fetchAll('zaib_dealer_payouts');
    final db = await AppDatabase.instance.database;
    for (final r in list) {
      final syncId = r['sync_id']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
      if (_isDeleted(r['deleted_at'])) {
        await db.delete('DieselLedgerCredit', where: 'SyncId = ?', whereArgs: [syncId]);
        continue;
      }
      if (!await _shouldApply(db, 'DieselLedgerCredit', syncId, updated)) continue;
      final did = await _localIdBySync(db, 'AddDealer', 'Did', r['dealer_sync_id']?.toString());
      await _upsertLocal(db, 'DieselLedgerCredit', syncId, {
        'Did': did,
        'Date': _asStr(r['date_text']),
        'AmounGiven': _asDouble(r['amount_given']),
        'Note': _asStr(r['note']),
        'SyncId': syncId,
        'UpdatedAt': updated,
        'SyncDirty': 0,
      });
    }
  }

  Future<void> _pullPurchases() async {
    final list = await _fetchAll('zaib_dealer_purchases');
    final db = await AppDatabase.instance.database;
    for (final r in list) {
      final syncId = r['sync_id']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
      if (_isDeleted(r['deleted_at'])) {
        await db.delete('AddStock', where: 'SyncId = ?', whereArgs: [syncId]);
        continue;
      }
      if (!await _shouldApply(db, 'AddStock', syncId, updated)) continue;
      final did = await _localIdBySync(db, 'AddDealer', 'Did', r['dealer_sync_id']?.toString());
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
    }
  }

  Future<void> _pullDirect() async {
    final list = await _fetchAll('zaib_dealer_direct');
    final db = await AppDatabase.instance.database;
    for (final r in list) {
      final syncId = r['sync_id']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
      if (_isDeleted(r['deleted_at'])) {
        await db.delete('DieselLedgerDebit', where: 'SyncId = ?', whereArgs: [syncId]);
        continue;
      }
      if (!await _shouldApply(db, 'DieselLedgerDebit', syncId, updated)) continue;
      final did = await _localIdBySync(db, 'AddDealer', 'Did', r['dealer_sync_id']?.toString());
      await _upsertLocal(db, 'DieselLedgerDebit', syncId, {
        'Did': did,
        'Date': _asStr(r['date_text']),
        'AmounGiven': _asDouble(r['amount_given']),
        'Note': _asStr(r['note']),
        'SyncId': syncId,
        'UpdatedAt': updated,
        'SyncDirty': 0,
      });
    }
  }

  Future<void> _pullStock() async {
    final list = await _fetchAll('zaib_stock_diesel');
    final db = await AppDatabase.instance.database;
    for (final r in list) {
      final syncId = r['sync_id']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
      if (_isDeleted(r['deleted_at'])) {
        await db.delete('StockDiesel', where: 'SyncId = ?', whereArgs: [syncId]);
        continue;
      }
      if (!await _shouldApply(db, 'StockDiesel', syncId, updated)) continue;
      final did = await _localIdBySync(db, 'AddDealer', 'Did', r['dealer_sync_id']?.toString());
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
    }
  }

  Future<void> _pullBank() async {
    final list = await _fetchAll('zaib_bank_transactions');
    final db = await AppDatabase.instance.database;
    for (final r in list) {
      final syncId = r['sync_id']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
      if (_isDeleted(r['deleted_at'])) {
        await db.delete('BankTransactions', where: 'SyncId = ?', whereArgs: [syncId]);
        continue;
      }
      if (!await _shouldApply(db, 'BankTransactions', syncId, updated)) continue;
      final cid = await _localIdBySync(db, 'AddCustomer', 'id', r['customer_sync_id']?.toString());
      final did = await _localIdBySync(db, 'AddDealer', 'Did', r['dealer_sync_id']?.toString());
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
    }
  }

  Future<void> _pullExpenses() async {
    final list = await _fetchAll('zaib_expenses');
    final db = await AppDatabase.instance.database;
    for (final r in list) {
      final syncId = r['sync_id']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      final updated = r['updated_at']?.toString() ?? SyncMeta.nowIso();
      if (_isDeleted(r['deleted_at'])) {
        await db.delete('Expensetable', where: 'SyncId = ?', whereArgs: [syncId]);
        continue;
      }
      if (!await _shouldApply(db, 'Expensetable', syncId, updated)) continue;
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
    }
  }
}
