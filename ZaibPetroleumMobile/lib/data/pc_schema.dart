import 'dart:io';

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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS DealertoDealer (
        LedgerID INTEGER PRIMARY KEY AUTOINCREMENT,
        Date TEXT,
        FirstDealer INTEGER,
        SecondDealer INTEGER,
        AmounGiven REAL,
        Note TEXT,
        id INTEGER,
        Did INTEGER
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
      'DealertoDealer',
    ];
    for (final t in syncTables) {
      await _ensureColumn(db, t, 'SyncId', 'TEXT');
      await _ensureColumn(db, t, 'UpdatedAt', 'TEXT');
      await _ensureColumn(db, t, 'SyncDirty', 'INTEGER DEFAULT 1');
      await _ensureColumn(db, t, 'ServerRev', 'INTEGER');
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
        DeletedAt TEXT NOT NULL,
        ExpectedServerRev INTEGER,
        RequestId TEXT
      )
    ''');
    await _ensureColumn(db, 'SyncTombstone', 'ExpectedServerRev', 'INTEGER');
    await _ensureColumn(db, 'SyncTombstone', 'RequestId', 'TEXT');
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SyncRejectedUpload (
        Id INTEGER PRIMARY KEY AUTOINCREMENT,
        At TEXT NOT NULL,
        CloudTable TEXT NOT NULL,
        SyncId TEXT NOT NULL,
        LocalUpdatedAt TEXT,
        PayloadJson TEXT NOT NULL,
        ServerPayloadJson TEXT,
        Outcome TEXT NOT NULL
      )
    ''');
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
        DeletedAt TEXT
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
      if (table == 'SyncTombstone' &&
          (column == 'ExpectedServerRev' || column == 'RequestId')) {
        await _tryBackupBeforeMigration(db);
      }
      await db.execute('ALTER TABLE $table ADD COLUMN $column $typeSql');
    }
  }

  /// Copy live DB + WAL/SHM before additive SyncTombstone migration.
  static Future<void> _tryBackupBeforeMigration(Database db) async {
    try {
      final path = db.path;
      if (path.isEmpty) return;
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('.', '')
          .replaceAll('-', '');
      final dest = '$path.pre_tombstone_rev_$stamp.bak';
      await File(path).copy(dest);
      for (final suffix in ['-wal', '-shm']) {
        final side = File('$path$suffix');
        if (await side.exists()) {
          await side.copy('$dest$suffix');
        }
      }
    } catch (_) {
      // Never block open on backup failure.
    }
  }
}
