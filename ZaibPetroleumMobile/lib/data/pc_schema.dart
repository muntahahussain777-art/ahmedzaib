import 'package:sqflite/sqflite.dart';

/// Exact PC-compatible SQLite schema (DiselPetrolPump.db tables).
class PcSchema {
  static Future<void> createAll(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS AddCustomer (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT,
        Mobile TEXT,
        Date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS PetrolAdd (
        pid INTEGER PRIMARY KEY AUTOINCREMENT,
        Date TEXT,
        ReceiptNo TEXT,
        vehicle TEXT,
        Litter REAL,
        Rate REAL,
        Advance REAL,
        Amount REAL,
        Credit REAL,
        Balance REAL,
        Note TEXT,
        CustomerId INTEGER,
        Processed INTEGER DEFAULT 0,
        IsInitialEntry INTEGER DEFAULT 1,
        TotalBalance REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS AddDealer (
        Did INTEGER PRIMARY KEY AUTOINCREMENT,
        DealerName TEXT,
        DDAmount REAL DEFAULT 0,
        DAmount REAL DEFAULT 0,
        Date TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS DieselLedgerCredit (
        LedgerID INTEGER PRIMARY KEY AUTOINCREMENT,
        Did INTEGER,
        Date TEXT,
        AmounGiven REAL,
        Note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS AddStock (
        Sid INTEGER PRIMARY KEY AUTOINCREMENT,
        Vehicle TEXT,
        Rate REAL,
        SellDisel REAL,
        Stock REAL,
        Date TEXT,
        AddDisel REAL,
        DealerId INTEGER,
        Note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS DieselLedgerDebit (
        LedgerID INTEGER PRIMARY KEY AUTOINCREMENT,
        Did INTEGER,
        Date TEXT,
        AmounGiven REAL,
        Note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS StockDiesel (
        SID INTEGER PRIMARY KEY AUTOINCREMENT,
        SDid INTEGER,
        Date TEXT,
        Vehicle TEXT,
        Litter REAL,
        Rate REAL,
        Credit REAL,
        Debit REAL,
        Note TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS BankTransactions (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        TransactionDate TEXT,
        TransactionType TEXT,
        CustomerId INTEGER,
        DealerId INTEGER,
        Deposit REAL,
        Withdrawal REAL,
        Amount REAL,
        Note TEXT,
        BankName TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS Expensetable (
        sid INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT,
        Category TEXT,
        Amount REAL,
        EDate TEXT,
        Note TEXT
      )
    ''');
  }

  static Future<void> ensure(Database db) async {
    await createAll(db);
    await _ensureColumn(db, 'BankTransactions', 'BankName', 'TEXT');
    await _ensureColumn(db, 'PetrolAdd', 'IsInitialEntry', 'INTEGER DEFAULT 1');
    await _ensureColumn(db, 'PetrolAdd', 'Processed', 'INTEGER DEFAULT 0');
    await _ensureColumn(db, 'PetrolAdd', 'TotalBalance', 'REAL');
    await _ensureColumn(db, 'AddStock', 'Note', 'TEXT');
    await _ensureColumn(db, 'AddStock', 'DealerId', 'INTEGER');
    await _ensureColumn(db, 'AddStock', 'AddDisel', 'REAL');

    // Cloud sync metadata (Supabase zaibservice) — UI unchanged
    const syncTables = [
      'AddCustomer',
      'PetrolAdd',
      'AddDealer',
      'DieselLedgerCredit',
      'AddStock',
      'DieselLedgerDebit',
      'StockDiesel',
      'BankTransactions',
      'Expensetable',
    ];
    for (final t in syncTables) {
      await _ensureColumn(db, t, 'SyncId', 'TEXT');
      await _ensureColumn(db, t, 'UpdatedAt', 'TEXT');
      await _ensureColumn(db, t, 'SyncDirty', 'INTEGER DEFAULT 1');
      try {
        await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS uq_${t}_SyncId ON $t(SyncId) WHERE SyncId IS NOT NULL AND SyncId <> \'\'',
        );
      } catch (_) {
        // Duplicate SyncId pe index fail — sync phir bhi chale
      }
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS SyncTombstone (
        SyncId TEXT PRIMARY KEY,
        CloudTable TEXT NOT NULL,
        DeletedAt TEXT NOT NULL
      )
    ''');

    // Local-only Bul Mal (sync/pull nahi — PC cloud se alag)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS BulMalOwner (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        Name TEXT NOT NULL,
        Date TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS BulMalEntry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        OwnerId INTEGER NOT NULL,
        Date TEXT,
        Type TEXT,
        Amount REAL DEFAULT 0,
        Note TEXT
      )
    ''');
  }

  static Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String typeSql,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((r) => (r['name']?.toString() ?? '') == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $typeSql');
    }
  }
}
