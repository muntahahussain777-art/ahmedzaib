import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../services/sync_meta.dart';
import 'pc_schema.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const dbFileName = 'DiselPetrolPump.db';

  Database? _db;
  String? _dbPath;

  Future<String> get databasePath async {
    if (_dbPath != null) return _dbPath!;
    final dir = await getDatabasesPath();
    _dbPath = join(dir, dbFileName);
    return _dbPath!;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = await databasePath;
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async => PcSchema.createAll(db),
    );
    await PcSchema.ensure(db);
    return db;
  }

  Future<void> closeDb() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  /// Replace mobile DB with a PC backup `.db` file.
  Future<void> restoreFromFile(String sourcePath) async {
    final src = File(sourcePath);
    if (!await src.exists()) {
      throw Exception('Backup file nahi mili.');
    }

    await closeDb();
    final destPath = await databasePath;
    final dest = File(destPath);
    if (await dest.exists()) {
      await dest.delete();
    }
    await src.copy(destPath);
    _db = await _open();
  }

  /// Copy current DB to Documents as timestamped backup.
  Future<String> createBackupCopy() async {
    await database; // ensure open/flushed
    await closeDb();
    final srcPath = await databasePath;
    final docs = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '')
        .replaceAll('-', '');
    final destPath = join(docs.path, 'DiselPetrolPump_backup_$stamp.db');
    await File(srcPath).copy(destPath);
    _db = await _open();
    return destPath;
  }

  Future<Map<String, int>> countMainTables() async {
    final db = await database;
    Future<int> c(String table) async =>
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ?? 0;

    return {
      'AddCustomer': await c('AddCustomer'),
      'PetrolAdd': await c('PetrolAdd'),
      'AddDealer': await c('AddDealer'),
      'DieselLedgerCredit': await c('DieselLedgerCredit'),
      'AddStock': await c('AddStock'),
      'DieselLedgerDebit': await c('DieselLedgerDebit'),
      'StockDiesel': await c('StockDiesel'),
      'BankTransactions': await c('BankTransactions'),
      'Expensetable': await c('Expensetable'),
    };
  }

  /// Backfill SyncId for old rows so cloud upsert never duplicates.
  bool _syncBackfillDone = false;

  Future<void> ensureSyncColumnsAndBackfill() async {
    final db = await database;
    await PcSchema.ensure(db);
    // Har sync pe full table scan UI save ko lock karta tha — ek dafa kaafi
    if (_syncBackfillDone) return;
    const tables = <(String, String)>[
      ('AddCustomer', 'id'),
      ('PetrolAdd', 'pid'),
      ('AddDealer', 'Did'),
      ('DieselLedgerCredit', 'LedgerID'),
      ('AddStock', 'Sid'),
      ('DieselLedgerDebit', 'LedgerID'),
      ('StockDiesel', 'SID'),
      ('BankTransactions', 'Id'),
      ('Expensetable', 'sid'),
    ];
    for (final t in tables) {
      final rows = await db.query(t.$1, columns: [t.$2, 'SyncId'], where: 'SyncId IS NULL OR SyncId = \'\'');
      for (final r in rows) {
        await db.update(
          t.$1,
          {'SyncId': SyncMeta.newId(), 'UpdatedAt': SyncMeta.nowIso(), 'SyncDirty': 1},
          where: '${t.$2} = ?',
          whereArgs: [r[t.$2]],
        );
      }
    }
    _syncBackfillDone = true;
  }

  Future<void> _tombstone(String cloudTable, String? syncId) async {
    if (syncId == null || syncId.isEmpty) return;
    final db = await database;
    await db.insert(
      'SyncTombstone',
      {'SyncId': syncId, 'CloudTable': cloudTable, 'DeletedAt': SyncMeta.nowIso()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    SyncMeta.markChanged();
  }

  Future<String?> _readSyncId(String table, String pkCol, Object id) async {
    final db = await database;
    final rows = await db.query(table, columns: ['SyncId'], where: '$pkCol = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['SyncId']?.toString();
  }

  Future<int> _insertAndNotify(String table, Map<String, Object?> map) async {
    final db = await database;
    SyncMeta.stampNew(map);
    final id = await db.insert(table, map);
    SyncMeta.markChanged();
    return id;
  }

  Future<int> _updateAndNotify(String table, Map<String, Object?> map, String where, List<Object?> args) async {
    final db = await database;
    SyncMeta.stampUpdate(map);
    final n = await db.update(table, map, where: where, whereArgs: args);
    SyncMeta.markChanged();
    return n;
  }

  // ---------- Customers (AddCustomer) ----------
  Future<int> insertCustomer(Customer c) async {
    final map = c.toMap()..remove('id');
    return _insertAndNotify('AddCustomer', map);
  }

  Future<int> updateCustomer(Customer c) async {
    final map = c.toMap()..remove('id');
    final existing = await _readSyncId('AddCustomer', 'id', c.id!);
    if (existing != null && existing.isNotEmpty) map['SyncId'] = existing;
    return _updateAndNotify('AddCustomer', map, 'id = ?', [c.id]);
  }

  Future<int> deleteCustomer(int id) async {
    final db = await database;
    final used = (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM PetrolAdd WHERE CustomerId = ?', [id])) ?? 0) +
        (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM BankTransactions WHERE CustomerId = ?', [id])) ?? 0);
    if (used > 0) throw Exception('Ye customer use ho raha hai — delete nahi ho sakta.');
    await _tombstone('zaib_customers', await _readSyncId('AddCustomer', 'id', id));
    return db.delete('AddCustomer', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Customer>> getCustomers({String query = ''}) async {
    final db = await database;
    final q = query.trim();
    final rows = q.isEmpty
        ? await db.query('AddCustomer', orderBy: 'id DESC')
        : await db.query('AddCustomer', where: 'Name LIKE ? OR Mobile LIKE ?', whereArgs: ['%$q%', '%$q%'], orderBy: 'id DESC');
    return rows.map(Customer.fromMap).toList();
  }

  Future<CustomerLedgerSummary> getCustomerLedgerSummary(int customerId) async {
    final db = await database;
    final inRow = await db.rawQuery(
      'SELECT IFNULL(SUM(IFNULL(Amount,0) + IFNULL(Advance,0)),0) AS t FROM PetrolAdd WHERE CustomerId = ?',
      [customerId],
    );
    final creditRow = await db.rawQuery(
      'SELECT IFNULL(SUM(IFNULL(Credit,0)),0) AS t FROM PetrolAdd WHERE CustomerId = ?',
      [customerId],
    );
    final totalAmount = asDouble(inRow.first['t']);
    final totalCredit = asDouble(creditRow.first['t']);
    return CustomerLedgerSummary(
      totalAmount: totalAmount,
      totalCredit: totalCredit,
      balance: totalAmount - totalCredit,
    );
  }

  /// Exact name only (haji ≠ haji nazar).
  Future<Customer?> findCustomerByExactName(String name) async {
    final q = name.trim();
    if (q.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'AddCustomer',
      where: 'lower(trim(IFNULL(Name,\'\'))) = lower(?)',
      whereArgs: [q],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Customer.fromMap(rows.first);
  }

  Future<CustomerLedgerSummary?> getCustomerLedgerByExactName(String name) async {
    final c = await findCustomerByExactName(name);
    if (c?.id == null) return null;
    return getCustomerLedgerSummary(c!.id!);
  }

  Future<Dealer?> findDealerByExactName(String name) async {
    final q = name.trim();
    if (q.isEmpty) return null;
    final db = await database;
    final rows = await db.query(
      'AddDealer',
      where: 'lower(trim(IFNULL(DealerName,\'\'))) = lower(?)',
      whereArgs: [q],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Dealer.fromMap(rows.first);
  }

  Future<DealerLedgerSummary?> getDealerLedgerByExactName(String name) async {
    final d = await findDealerByExactName(name);
    if (d?.id == null) return null;
    return getDealerLedgerSummary(d!.id!);
  }

  Future<double> getCustomerRemaining(int customerId) async {
    final s = await getCustomerLedgerSummary(customerId);
    return s.balance;
  }

  Future<DealerLedgerSummary> getDealerLedgerSummary(int dealerId) async {
    final d = await getDealerById(dealerId);
    if (d == null) {
      return const DealerLedgerSummary(ddAmount: 0, dAmount: 0, balance: 0);
    }
    return DealerLedgerSummary(
      ddAmount: d.ddAmount,
      dAmount: d.dAmount,
      balance: d.creditBalance,
    );
  }

  Future<Dealer?> getDealerById(int id) async {
    final db = await database;
    final rows = await db.query('AddDealer', where: 'Did = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Dealer.fromMap(rows.first);
  }

  // ---------- Diesel Sales (PetrolAdd IsInitialEntry=1) ----------
  Future<int> insertSale(DieselSale s) async {
    final map = s.toMap()..remove('pid');
    return _insertAndNotify('PetrolAdd', map);
  }

  Future<int> updateSale(DieselSale s) async {
    final map = s.toMap()..remove('pid');
    final existing = await _readSyncId('PetrolAdd', 'pid', s.id!);
    if (existing != null && existing.isNotEmpty) map['SyncId'] = existing;
    return _updateAndNotify('PetrolAdd', map, 'pid = ?', [s.id]);
  }

  Future<int> deleteSale(int id) async {
    final db = await database;
    await _tombstone('zaib_petrol_entries', await _readSyncId('PetrolAdd', 'pid', id));
    return db.delete('PetrolAdd', where: 'pid = ?', whereArgs: [id]);
  }

  Future<List<DieselSale>> getSales({String query = '', String? from, String? to}) async {
    final db = await database;
    final q = query.trim();
    final args = <Object?>[];
    final buf = StringBuffer('''
      SELECT s.*, c.Name AS customer_name
      FROM PetrolAdd s
      LEFT JOIN AddCustomer c ON c.id = s.CustomerId
      WHERE IFNULL(s.IsInitialEntry, 1) = 1
    ''');
    if (q.isNotEmpty) {
      buf.write(' AND (c.Name LIKE ? OR IFNULL(s.vehicle,\'\') LIKE ? OR IFNULL(s.ReceiptNo,\'\') LIKE ?)');
      args.addAll(['%$q%', '%$q%', '%$q%']);
    }
    if (from != null && from.isNotEmpty) {
      buf.write(' AND date(s.Date) >= date(?)');
      args.add(from);
    }
    if (to != null && to.isNotEmpty) {
      buf.write(' AND date(s.Date) <= date(?)');
      args.add(to);
    }
    buf.write(' ORDER BY s.pid DESC');
    final rows = await db.rawQuery(buf.toString(), args.isEmpty ? null : args);
    return rows.map(DieselSale.fromMap).toList();
  }

  // ---------- Credit Customer (PetrolAdd IsInitialEntry=0) ----------
  Future<int> insertCredit(CreditCustomerEntry e) async {
    final map = e.toMap()..remove('pid');
    return _insertAndNotify('PetrolAdd', map);
  }

  Future<int> updateCredit(CreditCustomerEntry e) async {
    final map = e.toMap()..remove('pid');
    final existing = await _readSyncId('PetrolAdd', 'pid', e.id!);
    if (existing != null && existing.isNotEmpty) map['SyncId'] = existing;
    return _updateAndNotify('PetrolAdd', map, 'pid = ?', [e.id]);
  }

  Future<int> deleteCredit(int id) async {
    final db = await database;
    await _tombstone('zaib_petrol_entries', await _readSyncId('PetrolAdd', 'pid', id));
    return db.delete('PetrolAdd', where: 'pid = ? AND IFNULL(IsInitialEntry,0) = 0', whereArgs: [id]);
  }

  Future<List<CreditCustomerEntry>> getCredits({String query = ''}) async {
    final db = await database;
    final q = query.trim();
    final rows = await db.rawQuery('''
      SELECT e.*, c.Name AS customer_name
      FROM PetrolAdd e
      LEFT JOIN AddCustomer c ON c.id = e.CustomerId
      WHERE IFNULL(e.IsInitialEntry, 1) = 0
      ${q.isEmpty ? '' : 'AND (c.Name LIKE ? OR IFNULL(e.ReceiptNo,\'\') LIKE ?)'}
      ORDER BY e.pid DESC
    ''', q.isEmpty ? null : ['%$q%', '%$q%']);
    return rows.map(CreditCustomerEntry.fromMap).toList();
  }

  // ---------- Dealers (AddDealer) ----------
  Future<int> insertDealer(Dealer d) async {
    final map = d.toMap()..remove('Did');
    return _insertAndNotify('AddDealer', map);
  }

  Future<int> updateDealer(Dealer d) async {
    final map = d.toMap()..remove('Did');
    final existing = await _readSyncId('AddDealer', 'Did', d.id!);
    if (existing != null && existing.isNotEmpty) map['SyncId'] = existing;
    return _updateAndNotify('AddDealer', map, 'Did = ?', [d.id]);
  }

  Future<int> deleteDealer(int id) async {
    final db = await database;
    final used = (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM DieselLedgerCredit WHERE Did = ?', [id])) ?? 0) +
        (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM DieselLedgerDebit WHERE Did = ?', [id])) ?? 0) +
        (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM AddStock WHERE DealerId = ?', [id])) ?? 0) +
        (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM StockDiesel WHERE SDid = ?', [id])) ?? 0) +
        (Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM BankTransactions WHERE DealerId = ?', [id])) ?? 0);
    if (used > 0) throw Exception('Ye dealer use ho raha hai — delete nahi ho sakta.');
    await _tombstone('zaib_dealers', await _readSyncId('AddDealer', 'Did', id));
    return db.delete('AddDealer', where: 'Did = ?', whereArgs: [id]);
  }

  Future<List<Dealer>> getDealers({String query = ''}) async {
    final db = await database;
    final q = query.trim();
    final rows = q.isEmpty
        ? await db.query('AddDealer', orderBy: 'Did DESC')
        : await db.query('AddDealer', where: 'DealerName LIKE ?', whereArgs: ['%$q%'], orderBy: 'Did DESC');
    return rows.map(Dealer.fromMap).toList();
  }

  /// WinForms jaisa: Stock forms pe dealer "Stock" fixed.
  Future<Dealer> ensureStockDealer() async {
    final existing = await findDealerByExactName('Stock');
    if (existing != null) return existing;

    final db = await database;
    await db.rawUpdate('''
      UPDATE AddDealer SET DealerName = 'Stock', UpdatedAt = ?, SyncDirty = 1
      WHERE lower(trim(IFNULL(DealerName,''))) IN ('stock','stok','stcok','sotck','stocks')
        AND trim(IFNULL(DealerName,'')) <> 'Stock'
    ''', [SyncMeta.nowIso()]);
    SyncMeta.markChanged();

    final fixed = await findDealerByExactName('Stock');
    if (fixed != null) return fixed;

    final map = <String, Object?>{
      'DealerName': 'Stock',
      'DDAmount': 0,
      'DAmount': 0,
      'Date': DateTime.now().toIso8601String().substring(0, 10),
    };
    final id = await _insertAndNotify('AddDealer', map);
    return Dealer(id: id, name: 'Stock', ddAmount: 0, dAmount: 0, date: map['Date'] as String);
  }

  Future<void> _adjustDAmount(int dealerId, double delta) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE AddDealer SET DAmount = IFNULL(DAmount,0) + ?, UpdatedAt = ?, SyncDirty = 1 WHERE Did = ?',
      [delta, SyncMeta.nowIso(), dealerId],
    );
    SyncMeta.markChanged();
  }

  Future<void> _adjustDdAmount(int dealerId, double delta) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE AddDealer SET DDAmount = IFNULL(DDAmount,0) + ?, UpdatedAt = ?, SyncDirty = 1 WHERE Did = ?',
      [delta, SyncMeta.nowIso(), dealerId],
    );
    SyncMeta.markChanged();
  }

  // ---------- Dealer Payout (DieselLedgerCredit) ----------
  Future<int> insertPayout(DealerPayout p) async {
    final map = p.toMap()..remove('LedgerID');
    final id = await _insertAndNotify('DieselLedgerCredit', map);
    await _adjustDAmount(p.dealerId, p.amountGiven);
    return id;
  }

  Future<int> updatePayout(DealerPayout oldP, DealerPayout p) async {
    await _adjustDAmount(oldP.dealerId, -oldP.amountGiven);
    await _adjustDAmount(p.dealerId, p.amountGiven);
    final map = p.toMap()..remove('LedgerID');
    final existing = await _readSyncId('DieselLedgerCredit', 'LedgerID', p.id!);
    if (existing != null && existing.isNotEmpty) map['SyncId'] = existing;
    return _updateAndNotify('DieselLedgerCredit', map, 'LedgerID = ?', [p.id]);
  }

  Future<int> deletePayout(DealerPayout p) async {
    final db = await database;
    await _adjustDAmount(p.dealerId, -p.amountGiven);
    await _tombstone('zaib_dealer_payouts', await _readSyncId('DieselLedgerCredit', 'LedgerID', p.id!));
    return db.delete('DieselLedgerCredit', where: 'LedgerID = ?', whereArgs: [p.id]);
  }

  Future<List<DealerPayout>> getPayouts({String query = ''}) async {
    final db = await database;
    final q = query.trim();
    final rows = await db.rawQuery('''
      SELECT p.*, d.DealerName AS dealer_name
      FROM DieselLedgerCredit p
      LEFT JOIN AddDealer d ON d.Did = p.Did
      ${q.isEmpty ? '' : 'WHERE d.DealerName LIKE ?'}
      ORDER BY p.LedgerID DESC
    ''', q.isEmpty ? null : ['%$q%']);
    return rows.map(DealerPayout.fromMap).toList();
  }

  // ---------- DealerAmount (AddStock) ----------
  Future<int> insertDealerAmount(DealerAmountEntry e) async {
    final map = e.toMap()..remove('Sid');
    final id = await _insertAndNotify('AddStock', map);
    await _adjustDdAmount(e.dealerId, e.amount);
    return id;
  }

  Future<int> updateDealerAmount(DealerAmountEntry oldE, DealerAmountEntry e) async {
    await _adjustDdAmount(oldE.dealerId, -oldE.amount);
    await _adjustDdAmount(e.dealerId, e.amount);
    final map = e.toMap()..remove('Sid');
    final existing = await _readSyncId('AddStock', 'Sid', e.id!);
    if (existing != null && existing.isNotEmpty) map['SyncId'] = existing;
    return _updateAndNotify('AddStock', map, 'Sid = ?', [e.id]);
  }

  Future<int> deleteDealerAmount(DealerAmountEntry e) async {
    final db = await database;
    await _adjustDdAmount(e.dealerId, -e.amount);
    await _tombstone('zaib_dealer_purchases', await _readSyncId('AddStock', 'Sid', e.id!));
    return db.delete('AddStock', where: 'Sid = ?', whereArgs: [e.id]);
  }

  Future<List<DealerAmountEntry>> getDealerAmounts({String query = '', String? from, String? to}) async {
    final db = await database;
    final q = query.trim();
    final args = <Object?>[];
    final buf = StringBuffer('''
      SELECT a.*, d.DealerName AS dealer_name
      FROM AddStock a
      LEFT JOIN AddDealer d ON d.Did = a.DealerId
      WHERE 1=1
    ''');
    if (q.isNotEmpty) {
      buf.write(' AND (d.DealerName LIKE ? OR IFNULL(a.Vehicle,\'\') LIKE ?)');
      args.addAll(['%$q%', '%$q%']);
    }
    if (from != null && from.isNotEmpty) {
      buf.write(' AND date(a.Date) >= date(?)');
      args.add(from);
    }
    if (to != null && to.isNotEmpty) {
      buf.write(' AND date(a.Date) <= date(?)');
      args.add(to);
    }
    buf.write(' ORDER BY a.Sid DESC');
    final rows = await db.rawQuery(buf.toString(), args.isEmpty ? null : args);
    return rows.map(DealerAmountEntry.fromMap).toList();
  }

  // ---------- Direct Dealer Amount (DieselLedgerDebit) ----------
  Future<int> insertDirect(DirectDealerAmount e) async {
    final map = e.toMap()..remove('LedgerID');
    final id = await _insertAndNotify('DieselLedgerDebit', map);
    await _adjustDdAmount(e.dealerId, e.amountGiven);
    return id;
  }

  Future<int> updateDirect(DirectDealerAmount oldE, DirectDealerAmount e) async {
    await _adjustDdAmount(oldE.dealerId, -oldE.amountGiven);
    await _adjustDdAmount(e.dealerId, e.amountGiven);
    final map = e.toMap()..remove('LedgerID');
    final existing = await _readSyncId('DieselLedgerDebit', 'LedgerID', e.id!);
    if (existing != null && existing.isNotEmpty) map['SyncId'] = existing;
    return _updateAndNotify('DieselLedgerDebit', map, 'LedgerID = ?', [e.id]);
  }

  Future<int> deleteDirect(DirectDealerAmount e) async {
    final db = await database;
    await _adjustDdAmount(e.dealerId, -e.amountGiven);
    await _tombstone('zaib_dealer_direct', await _readSyncId('DieselLedgerDebit', 'LedgerID', e.id!));
    return db.delete('DieselLedgerDebit', where: 'LedgerID = ?', whereArgs: [e.id]);
  }

  Future<List<DirectDealerAmount>> getDirects({String query = ''}) async {
    final db = await database;
    final q = query.trim();
    final rows = await db.rawQuery('''
      SELECT a.*, d.DealerName AS dealer_name
      FROM DieselLedgerDebit a
      LEFT JOIN AddDealer d ON d.Did = a.Did
      ${q.isEmpty ? '' : 'WHERE d.DealerName LIKE ?'}
      ORDER BY a.LedgerID DESC
    ''', q.isEmpty ? null : ['%$q%']);
    return rows.map(DirectDealerAmount.fromMap).toList();
  }

  // ---------- StockDiesel ----------
  Future<int> insertStock(StockDieselEntry e) async {
    final map = e.toMap()..remove('SID');
    return _insertAndNotify('StockDiesel', map);
  }

  Future<int> updateStock(StockDieselEntry e) async {
    final map = e.toMap()..remove('SID');
    final existing = await _readSyncId('StockDiesel', 'SID', e.id!);
    if (existing != null && existing.isNotEmpty) map['SyncId'] = existing;
    return _updateAndNotify('StockDiesel', map, 'SID = ?', [e.id]);
  }

  Future<int> deleteStock(int id) async {
    final db = await database;
    await _tombstone('zaib_stock_diesel', await _readSyncId('StockDiesel', 'SID', id));
    return db.delete('StockDiesel', where: 'SID = ?', whereArgs: [id]);
  }

  Future<List<StockDieselEntry>> getStocks({String query = ''}) async {
    final db = await database;
    final q = query.trim();
    final rows = await db.rawQuery('''
      SELECT s.*, d.DealerName AS dealer_name
      FROM StockDiesel s
      LEFT JOIN AddDealer d ON d.Did = s.SDid
      ${q.isEmpty ? '' : 'WHERE d.DealerName LIKE ? OR IFNULL(s.Vehicle,\'\') LIKE ?'}
      ORDER BY s.SID DESC
    ''', q.isEmpty ? null : ['%$q%', '%$q%']);
    return rows.map(StockDieselEntry.fromMap).toList();
  }

  // ---------- BankTransactions ----------
  Future<int> insertBank(BankTransaction t) async {
    final map = t.toMap()..remove('Id');
    return _insertAndNotify('BankTransactions', map);
  }

  Future<int> updateBank(BankTransaction t) async {
    final map = t.toMap()..remove('Id');
    final existing = await _readSyncId('BankTransactions', 'Id', t.id!);
    if (existing != null && existing.isNotEmpty) map['SyncId'] = existing;
    return _updateAndNotify('BankTransactions', map, 'Id = ?', [t.id]);
  }

  Future<int> deleteBank(int id) async {
    final db = await database;
    await _tombstone('zaib_bank_transactions', await _readSyncId('BankTransactions', 'Id', id));
    return db.delete('BankTransactions', where: 'Id = ?', whereArgs: [id]);
  }

  Future<List<BankTransaction>> getBanks({String query = ''}) async {
    final db = await database;
    final q = query.trim();
    final rows = await db.rawQuery('''
      SELECT b.*,
             c.Name AS customer_name,
             d.DealerName AS dealer_name
      FROM BankTransactions b
      LEFT JOIN AddCustomer c ON c.id = b.CustomerId
      LEFT JOIN AddDealer d ON d.Did = b.DealerId
      ${q.isEmpty ? '' : 'WHERE IFNULL(b.BankName,\'\') LIKE ? OR IFNULL(c.Name,\'\') LIKE ? OR IFNULL(d.DealerName,\'\') LIKE ?'}
      ORDER BY b.Id DESC
    ''', q.isEmpty ? null : ['%$q%', '%$q%', '%$q%']);
    return rows.map(BankTransaction.fromMap).toList();
  }

  Future<double> getBankBalance(String bankName) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT IFNULL(SUM(Amount),0) AS t FROM BankTransactions WHERE BankName = ?',
      [bankName],
    );
    return asDouble(rows.first['t']);
  }

  String _dateFilterSql(String column, {int? year, int? month, String? from, String? to}) {
    final parts = <String>[];
    if (year != null) parts.add("substr($column,1,4) = '${year.toString().padLeft(4, '0')}'");
    if (month != null) parts.add("substr($column,6,2) = '${month.toString().padLeft(2, '0')}'");
    if (from != null && from.isNotEmpty) parts.add("date($column) >= date('$from')");
    if (to != null && to.isNotEmpty) parts.add("date($column) <= date('$to')");
    if (parts.isEmpty) return '';
    return ' AND ${parts.join(' AND ')}';
  }

  Future<CustomerLedgerSummary> getGlobalCustomerLedger({int? year, int? month, String? from, String? to}) async {
    final db = await database;
    final filter = _dateFilterSql('Date', year: year, month: month, from: from, to: to);
    final inRow = await db.rawQuery(
      'SELECT IFNULL(SUM(IFNULL(Amount,0) + IFNULL(Advance,0)),0) AS t FROM PetrolAdd WHERE 1=1$filter',
    );
    final creditRow = await db.rawQuery(
      'SELECT IFNULL(SUM(IFNULL(Credit,0)),0) AS t FROM PetrolAdd WHERE 1=1$filter',
    );
    final totalAmount = asDouble(inRow.first['t']);
    final totalCredit = asDouble(creditRow.first['t']);
    return CustomerLedgerSummary(
      totalAmount: totalAmount,
      totalCredit: totalCredit,
      balance: totalAmount - totalCredit,
    );
  }

  Future<DealerLedgerSummary> getGlobalDealerLedger() async {
    final db = await database;
    final row = await db.rawQuery(
      'SELECT IFNULL(SUM(IFNULL(DDAmount,0)),0) AS dd, IFNULL(SUM(IFNULL(DAmount,0)),0) AS d FROM AddDealer',
    );
    final dd = asDouble(row.first['dd']);
    final d = asDouble(row.first['d']);
    return DealerLedgerSummary(ddAmount: dd, dAmount: d, balance: dd - d);
  }

  Future<DashboardStats> getDashboardStats({int? year, int? month}) async {
    final db = await database;
    final filter = _dateFilterSql('Date', year: year, month: month);
    final saleLitter = asDouble((await db.rawQuery(
      'SELECT IFNULL(SUM(IFNULL(Litter,0)),0) AS t FROM PetrolAdd WHERE IFNULL(IsInitialEntry,1)=1$filter',
    )).first['t']);
    final purchaseLitter = asDouble((await db.rawQuery(
      'SELECT IFNULL(SUM(IFNULL(AddDisel,0)),0) AS t FROM AddStock WHERE 1=1$filter',
    )).first['t']);
    final saleAmount = asDouble((await db.rawQuery(
      'SELECT IFNULL(SUM(IFNULL(Amount,0)+IFNULL(Advance,0)),0) AS t FROM PetrolAdd WHERE IFNULL(IsInitialEntry,1)=1$filter',
    )).first['t']);
    final purchaseAmount = asDouble((await db.rawQuery(
      'SELECT IFNULL(SUM(IFNULL(AddDisel,0)*IFNULL(Rate,0)),0) AS t FROM AddStock WHERE 1=1$filter',
    )).first['t']);
    final customer = await getGlobalCustomerLedger(year: year, month: month);
    final dealer = await getGlobalDealerLedger();
    return DashboardStats(
      customer: customer,
      dealer: dealer,
      saleLitter: saleLitter,
      purchaseLitter: purchaseLitter,
      saleAmount: saleAmount,
      purchaseAmount: purchaseAmount,
    );
  }

  Future<List<DieselSale>> searchDieselReport({
    String query = '',
    String? name,
    String? vehicle,
    String? from,
    String? to,
  }) async {
    final db = await database;
    final nameQ = (name ?? '').trim();
    final vehQ = (vehicle ?? '').trim();
    final legacy = query.trim();
    final args = <Object?>[];
    final buf = StringBuffer('''
      SELECT s.*, c.Name AS customer_name
      FROM PetrolAdd s
      LEFT JOIN AddCustomer c ON c.id = s.CustomerId
      WHERE 1=1
    ''');

    // Name exact only (haji ≠ haji nazar). Vehicle exact only.
    if (nameQ.isNotEmpty || vehQ.isNotEmpty) {
      if (nameQ.isNotEmpty) {
        buf.write(' AND lower(trim(IFNULL(c.Name,\'\'))) = lower(?)');
        args.add(nameQ);
      }
      if (vehQ.isNotEmpty) {
        buf.write(' AND lower(trim(IFNULL(s.vehicle,\'\'))) = lower(?)');
        args.add(vehQ);
      }
    } else if (legacy.isNotEmpty) {
      // Single box: pehle exact name, warna exact vehicle — mix nahi
      final nameHit = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM AddCustomer WHERE lower(trim(IFNULL(Name,\'\'))) = lower(?)',
            [legacy],
          )) ??
          0;
      if (nameHit > 0) {
        buf.write(' AND lower(trim(IFNULL(c.Name,\'\'))) = lower(?)');
        args.add(legacy);
      } else {
        buf.write(' AND lower(trim(IFNULL(s.vehicle,\'\'))) = lower(?)');
        args.add(legacy);
      }
    }

    if (from != null && from.isNotEmpty) {
      buf.write(' AND date(s.Date) >= date(?)');
      args.add(from);
    }
    if (to != null && to.isNotEmpty) {
      buf.write(' AND date(s.Date) <= date(?)');
      args.add(to);
    }
    buf.write(' ORDER BY s.Date ASC, s.pid ASC');
    final rows = await db.rawQuery(buf.toString(), args);
    return rows.map(DieselSale.fromMap).toList();
  }

  Future<List<DealerGroupReportRow>> searchDealerGroupReport({
    String query = '',
    String? name,
    String? vehicle,
    String? from,
    String? to,
  }) async {
    final db = await database;
    final nameQ = (name ?? '').trim();
    final vehQ = (vehicle ?? '').trim();
    final legacy = query.trim();
    final args = <Object?>[];
    final buf = StringBuffer('''
      SELECT
        d.Did AS dealer_id,
        d.DealerName AS dealer_name,
        IFNULL(d.DDAmount,0) AS dd_amount,
        IFNULL(d.DAmount,0) AS d_amount,
        (IFNULL(d.DDAmount,0) - IFNULL(d.DAmount,0)) AS balance,
        s.Date AS stock_date,
        IFNULL(s.Vehicle,'') AS vehicle,
        IFNULL(s.AddDisel,0) AS litter,
        IFNULL(s.Rate,0) AS rate,
        (IFNULL(s.AddDisel,0) * IFNULL(s.Rate,0)) AS amount,
        IFNULL(s.Note,'') AS note
      FROM AddDealer d
      LEFT JOIN AddStock s ON s.DealerId = d.Did
      WHERE 1=1
    ''');

    if (nameQ.isNotEmpty || vehQ.isNotEmpty) {
      if (nameQ.isNotEmpty) {
        buf.write(' AND lower(trim(IFNULL(d.DealerName,\'\'))) = lower(?)');
        args.add(nameQ);
      }
      if (vehQ.isNotEmpty) {
        buf.write(' AND s.Sid IS NOT NULL AND lower(trim(IFNULL(s.Vehicle,\'\'))) = lower(?)');
        args.add(vehQ);
      }
    } else if (legacy.isNotEmpty) {
      final nameHit = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM AddDealer WHERE lower(trim(IFNULL(DealerName,\'\'))) = lower(?)',
            [legacy],
          )) ??
          0;
      if (nameHit > 0) {
        buf.write(' AND lower(trim(IFNULL(d.DealerName,\'\'))) = lower(?)');
        args.add(legacy);
      } else {
        buf.write(' AND s.Sid IS NOT NULL AND lower(trim(IFNULL(s.Vehicle,\'\'))) = lower(?)');
        args.add(legacy);
      }
    }

    if (from != null && from.isNotEmpty) {
      buf.write(' AND (s.Date IS NULL OR date(s.Date) >= date(?))');
      args.add(from);
    }
    if (to != null && to.isNotEmpty) {
      buf.write(' AND (s.Date IS NULL OR date(s.Date) <= date(?))');
      args.add(to);
    }
    buf.write(' ORDER BY d.DealerName, s.Date, s.Sid');
    final rows = await db.rawQuery(buf.toString(), args);
    return rows.map(DealerGroupReportRow.fromMap).toList();
  }

  Future<List<StockDieselEntry>> searchStockReport({
    String query = '',
    String? name,
    String? vehicle,
    String? from,
    String? to,
  }) async {
    final db = await database;
    final nameQ = (name ?? '').trim();
    final vehQ = (vehicle ?? '').trim();
    final legacy = query.trim();
    final args = <Object?>[];
    final buf = StringBuffer('''
      SELECT s.*, d.DealerName AS dealer_name
      FROM StockDiesel s
      LEFT JOIN AddDealer d ON d.Did = s.SDid
      WHERE 1=1
    ''');

    if (nameQ.isNotEmpty || vehQ.isNotEmpty) {
      if (nameQ.isNotEmpty) {
        buf.write(' AND lower(trim(IFNULL(d.DealerName,\'\'))) = lower(?)');
        args.add(nameQ);
      }
      if (vehQ.isNotEmpty) {
        buf.write(' AND lower(trim(IFNULL(s.Vehicle,\'\'))) = lower(?)');
        args.add(vehQ);
      }
    } else if (legacy.isNotEmpty) {
      final nameHit = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM AddDealer WHERE lower(trim(IFNULL(DealerName,\'\'))) = lower(?)',
            [legacy],
          )) ??
          0;
      if (nameHit > 0) {
        buf.write(' AND lower(trim(IFNULL(d.DealerName,\'\'))) = lower(?)');
        args.add(legacy);
      } else {
        buf.write(' AND lower(trim(IFNULL(s.Vehicle,\'\'))) = lower(?)');
        args.add(legacy);
      }
    }

    if (from != null && from.isNotEmpty) {
      buf.write(' AND date(s.Date) >= date(?)');
      args.add(from);
    }
    if (to != null && to.isNotEmpty) {
      buf.write(' AND date(s.Date) <= date(?)');
      args.add(to);
    }
    buf.write(' ORDER BY s.Date ASC, s.SID ASC');
    final rows = await db.rawQuery(buf.toString(), args);
    return rows.map(StockDieselEntry.fromMap).toList();
  }

  // ---------- Owner read-only ledgers (no edit) ----------

  Future<List<String>> distinctCustomerVehicles({String? customerName}) async {
    final db = await database;
    final nameQ = (customerName ?? '').trim();
    if (nameQ.isEmpty) {
      final rows = await db.rawQuery(
        "SELECT DISTINCT trim(IFNULL(vehicle,'')) AS v FROM PetrolAdd WHERE IFNULL(trim(vehicle),'') <> '' ORDER BY v COLLATE NOCASE",
      );
      return rows.map((r) => r['v']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT trim(IFNULL(s.vehicle,'')) AS v
      FROM PetrolAdd s
      LEFT JOIN AddCustomer c ON c.id = s.CustomerId
      WHERE lower(trim(IFNULL(c.Name,''))) = lower(?)
        AND IFNULL(trim(s.vehicle),'') <> ''
      ORDER BY v COLLATE NOCASE
      ''',
      [nameQ],
    );
    return rows.map((r) => r['v']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }

  Future<List<String>> distinctDealerVehicles({String? dealerName}) async {
    final db = await database;
    final nameQ = (dealerName ?? '').trim();
    if (nameQ.isEmpty) {
      final rows = await db.rawQuery(
        "SELECT DISTINCT trim(IFNULL(Vehicle,'')) AS v FROM AddStock WHERE IFNULL(trim(Vehicle),'') <> '' ORDER BY v COLLATE NOCASE",
      );
      return rows.map((r) => r['v']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT trim(IFNULL(s.Vehicle,'')) AS v
      FROM AddStock s
      LEFT JOIN AddDealer d ON d.Did = s.DealerId
      WHERE lower(trim(IFNULL(d.DealerName,''))) = lower(?)
        AND IFNULL(trim(s.Vehicle),'') <> ''
      ORDER BY v COLLATE NOCASE
      ''',
      [nameQ],
    );
    return rows.map((r) => r['v']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }

  /// Owner customer ledger: amount jama, credit minus → running balance.
  Future<List<OwnerLedgerLine>> ownerCustomerLedger({
    String? name,
    String? vehicle,
    String? from,
    String? to,
  }) async {
    final sales = await searchDieselReport(name: name, vehicle: vehicle, from: from, to: to);
    var run = 0.0;
    final out = <OwnerLedgerLine>[];
    for (final e in sales) {
      final lineAmt = (e.litter == 0 && e.rate == 0) ? e.amount : (e.litter * e.rate + e.advance);
      run += lineAmt;
      run -= e.credit;
      out.add(
        OwnerLedgerLine(
          partyName: e.customerName,
          date: e.date,
          vehicle: e.vehicle,
          note: e.note,
          litter: e.litter,
          rate: e.rate,
          amount: lineAmt,
          credit: e.credit,
          runningBalance: run,
        ),
      );
    }
    return out;
  }

  /// Owner dealer ledger: purchase/direct amount jama, payout credit minus.
  Future<List<OwnerLedgerLine>> ownerDealerLedger({
    String? name,
    String? vehicle,
    String? from,
    String? to,
  }) async {
    final db = await database;
    final nameQ = (name ?? '').trim();
    final vehQ = (vehicle ?? '').trim();
    final nameFilter = nameQ.isEmpty ? '' : ' AND lower(trim(IFNULL(d.DealerName,\'\'))) = lower(?)';

    final stockArgs = <Object?>[];
    if (nameQ.isNotEmpty) stockArgs.add(nameQ);
    if (vehQ.isNotEmpty) stockArgs.add(vehQ);
    if (from != null && from.isNotEmpty) stockArgs.add(from);
    if (to != null && to.isNotEmpty) stockArgs.add(to);

    final stockSql = '''
      SELECT d.DealerName AS party, s.Date AS dt, IFNULL(s.Vehicle,'') AS veh,
             IFNULL(s.Note,'') AS note, IFNULL(s.AddDisel,0) AS litter, IFNULL(s.Rate,0) AS rate,
             (IFNULL(s.AddDisel,0)*IFNULL(s.Rate,0)) AS amount, 0.0 AS credit, s.Sid AS ord
      FROM AddStock s
      LEFT JOIN AddDealer d ON d.Did = s.DealerId
      WHERE 1=1
      $nameFilter
      ${vehQ.isEmpty ? '' : ' AND lower(trim(IFNULL(s.Vehicle,\'\'))) = lower(?)'}
      ${from != null && from.isNotEmpty ? ' AND date(s.Date) >= date(?)' : ''}
      ${to != null && to.isNotEmpty ? ' AND date(s.Date) <= date(?)' : ''}
    ''';

    final debitArgs = <Object?>[];
    if (nameQ.isNotEmpty) debitArgs.add(nameQ);
    if (from != null && from.isNotEmpty) debitArgs.add(from);
    if (to != null && to.isNotEmpty) debitArgs.add(to);
    final debitSql = '''
      SELECT d.DealerName AS party, a.Date AS dt, '' AS veh,
             IFNULL(a.Note,'') AS note, 0.0 AS litter, 0.0 AS rate,
             IFNULL(a.AmounGiven,0) AS amount, 0.0 AS credit, a.LedgerID AS ord
      FROM DieselLedgerDebit a
      LEFT JOIN AddDealer d ON d.Did = a.Did
      WHERE 1=1
      $nameFilter
      ${vehQ.isNotEmpty ? ' AND 0' : ''}
      ${from != null && from.isNotEmpty ? ' AND date(a.Date) >= date(?)' : ''}
      ${to != null && to.isNotEmpty ? ' AND date(a.Date) <= date(?)' : ''}
    ''';

    final creditArgs = <Object?>[];
    if (nameQ.isNotEmpty) creditArgs.add(nameQ);
    if (from != null && from.isNotEmpty) creditArgs.add(from);
    if (to != null && to.isNotEmpty) creditArgs.add(to);
    final creditSql = '''
      SELECT d.DealerName AS party, p.Date AS dt, '' AS veh,
             IFNULL(p.Note,'') AS note, 0.0 AS litter, 0.0 AS rate,
             0.0 AS amount, IFNULL(p.AmounGiven,0) AS credit, p.LedgerID AS ord
      FROM DieselLedgerCredit p
      LEFT JOIN AddDealer d ON d.Did = p.Did
      WHERE 1=1
      $nameFilter
      ${vehQ.isNotEmpty ? ' AND 0' : ''}
      ${from != null && from.isNotEmpty ? ' AND date(p.Date) >= date(?)' : ''}
      ${to != null && to.isNotEmpty ? ' AND date(p.Date) <= date(?)' : ''}
    ''';

    List<Map<String, Object?>> stockRows = const [];
    List<Map<String, Object?>> debitRows = const [];
    List<Map<String, Object?>> creditRows = const [];
    try {
      stockRows = await db.rawQuery(stockSql, stockArgs);
    } catch (_) {}
    try {
      debitRows = await db.rawQuery(debitSql, debitArgs);
    } catch (_) {}
    try {
      creditRows = await db.rawQuery(creditSql, creditArgs);
    } catch (_) {}

    final merged = <Map<String, Object?>>[
      ...stockRows,
      ...debitRows,
      ...creditRows,
    ];
    merged.sort((a, b) {
      final da = a['dt']?.toString() ?? '';
      final dbDate = b['dt']?.toString() ?? '';
      final c = da.compareTo(dbDate);
      if (c != 0) return c;
      return (asInt(a['ord']) ?? 0).compareTo(asInt(b['ord']) ?? 0);
    });

    var run = 0.0;
    final out = <OwnerLedgerLine>[];
    for (final r in merged) {
      final amt = asDouble(r['amount']);
      final cred = asDouble(r['credit']);
      run += amt;
      run -= cred;
      out.add(
        OwnerLedgerLine(
          partyName: r['party']?.toString() ?? '',
          date: r['dt']?.toString() ?? '',
          vehicle: r['veh']?.toString() ?? '',
          note: r['note']?.toString() ?? '',
          litter: asDouble(r['litter']),
          rate: asDouble(r['rate']),
          amount: amt,
          credit: cred,
          runningBalance: run,
        ),
      );
    }
    return out;
  }

  // ---------- Bul Mal (local-only — sync/pull nahi) ----------

  Future<int> insertBulMalOwner(BulMalOwner o) async {
    final db = await database;
    return db.insert('BulMalOwner', {
      'Name': o.name.trim(),
      'Date': o.date,
    });
  }

  Future<int> updateBulMalOwner(BulMalOwner o) async {
    final db = await database;
    return db.update(
      'BulMalOwner',
      {'Name': o.name.trim(), 'Date': o.date},
      where: 'id = ?',
      whereArgs: [o.id],
    );
  }

  Future<int> deleteBulMalOwner(int id) async {
    final db = await database;
    final used = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM BulMalEntry WHERE OwnerId = ?', [id]),
        ) ??
        0;
    if (used > 0) throw Exception('Is owner ki entries hain — pehle entries delete karein');
    return db.delete('BulMalOwner', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<BulMalOwner>> getBulMalOwners({String query = ''}) async {
    final db = await database;
    final q = query.trim();
    final rows = await db.rawQuery(
      '''
      SELECT * FROM BulMalOwner
      WHERE (? = '' OR lower(Name) LIKE '%' || lower(?) || '%')
      ORDER BY Name COLLATE NOCASE
      ''',
      [q, q],
    );
    return rows.map(BulMalOwner.fromMap).toList();
  }

  Future<BulMalOwner?> findBulMalOwnerByExactName(String name) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT * FROM BulMalOwner WHERE lower(trim(Name)) = lower(?) LIMIT 1',
      [name.trim()],
    );
    if (rows.isEmpty) return null;
    return BulMalOwner.fromMap(rows.first);
  }

  Future<int> insertBulMalEntry(BulMalEntry e) async {
    final db = await database;
    return db.insert('BulMalEntry', e.toMap()..remove('id'));
  }

  Future<int> updateBulMalEntry(BulMalEntry e) async {
    final db = await database;
    final map = e.toMap()..remove('id');
    return db.update('BulMalEntry', map, where: 'id = ?', whereArgs: [e.id]);
  }

  Future<int> deleteBulMalEntry(int id) async {
    final db = await database;
    return db.delete('BulMalEntry', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<BulMalEntry>> getBulMalEntries({
    String query = '',
    int? ownerId,
    String? from,
    String? to,
  }) async {
    final db = await database;
    final q = query.trim();
    final args = <Object?>[];
    final buf = StringBuffer('''
      SELECT e.*, o.Name AS owner_name
      FROM BulMalEntry e
      LEFT JOIN BulMalOwner o ON o.id = e.OwnerId
      WHERE 1=1
    ''');
    if (ownerId != null) {
      buf.write(' AND e.OwnerId = ?');
      args.add(ownerId);
    } else if (q.isNotEmpty) {
      buf.write(' AND (lower(IFNULL(o.Name,\'\')) LIKE \'%\' || lower(?) || \'%\' OR lower(IFNULL(e.Note,\'\')) LIKE \'%\' || lower(?) || \'%\')');
      args.add(q);
      args.add(q);
    }
    if (from != null && from.isNotEmpty) {
      buf.write(' AND date(e.Date) >= date(?)');
      args.add(from);
    }
    if (to != null && to.isNotEmpty) {
      buf.write(' AND date(e.Date) <= date(?)');
      args.add(to);
    }
    buf.write(' ORDER BY date(e.Date) DESC, e.id DESC');
    final rows = await db.rawQuery(buf.toString(), args);
    return rows.map(BulMalEntry.fromMap).toList();
  }

  Future<BulMalSummary> getBulMalSummary({int? ownerId, String? from, String? to}) async {
    final db = await database;
    final args = <Object?>[];
    final filter = StringBuffer(' WHERE 1=1');
    if (ownerId != null) {
      filter.write(' AND OwnerId = ?');
      args.add(ownerId);
    }
    if (from != null && from.isNotEmpty) {
      filter.write(' AND date(Date) >= date(?)');
      args.add(from);
    }
    if (to != null && to.isNotEmpty) {
      filter.write(' AND date(Date) <= date(?)');
      args.add(to);
    }
    final inAmt = asDouble((await db.rawQuery(
      "SELECT IFNULL(SUM(IFNULL(Amount,0)),0) AS t FROM BulMalEntry$filter AND lower(IFNULL(Type,'')) = 'in'",
      args,
    ))
        .first['t']);
    final outAmt = asDouble((await db.rawQuery(
      "SELECT IFNULL(SUM(IFNULL(Amount,0)),0) AS t FROM BulMalEntry$filter AND lower(IFNULL(Type,'')) = 'out'",
      args,
    ))
        .first['t']);
    return BulMalSummary(totalIn: inAmt, totalOut: outAmt, balance: inAmt - outAmt);
  }
}
