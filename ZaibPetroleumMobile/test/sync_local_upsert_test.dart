import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zaib_petroleum_mobile/services/sync_local_upsert.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SyncLocalUpsert.upsertBySyncId', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(
        inMemoryDatabasePath,
        version: 1,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE AddCustomer (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              Name TEXT,
              SyncId TEXT UNIQUE,
              UpdatedAt TEXT,
              SyncDirty INTEGER DEFAULT 0
            )
          ''');
        },
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('recovers from unique SyncId race via update', () async {
      const syncId = 'race-id';
      await db.insert('AddCustomer', {
        'Name': 'First',
        'SyncId': syncId,
        'UpdatedAt': '2026-01-01T00:00:00.000Z',
        'SyncDirty': 0,
      });
      await SyncLocalUpsert.upsertBySyncId(db, 'AddCustomer', syncId, {
        'Name': 'Second',
        'SyncId': syncId,
        'UpdatedAt': '2026-01-02T00:00:00.000Z',
        'SyncDirty': 0,
      });
      final rows = await db.query('AddCustomer', where: 'SyncId = ?', whereArgs: [syncId]);
      expect(rows.length, 1);
      expect(rows.first['Name'], 'Second');
    });

    test('insert then upsert same SyncId updates row', () async {
      const syncId = 'cust-a';
      await SyncLocalUpsert.upsertBySyncId(db, 'AddCustomer', syncId, {
        'Name': 'A',
        'SyncId': syncId,
        'UpdatedAt': '2026-01-01T00:00:00.000Z',
        'SyncDirty': 0,
      });
      await SyncLocalUpsert.upsertBySyncId(db, 'AddCustomer', syncId, {
        'Name': 'B',
        'SyncId': syncId,
        'UpdatedAt': '2026-01-02T00:00:00.000Z',
        'SyncDirty': 0,
      });
      final rows = await db.query('AddCustomer', where: 'SyncId = ?', whereArgs: [syncId]);
      expect(rows.length, 1);
      expect(rows.first['Name'], 'B');
    });
  });
}
