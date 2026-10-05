import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zaib_petroleum_mobile/services/dealer_balance_apply.dart';

/// Expected child → dealer delta mapping (mirrors AppDatabase._reconcileChildBalance):
/// - Dealer payout (DieselLedgerCredit): ddDelta=0, dDelta=amountGiven → DAmount +=
/// - Dealer purchase (AddStock): ddDelta=entry.amount, dDelta=0 → DDAmount +=
/// - Direct dealer (DieselLedgerDebit): ddDelta=amountGiven, dDelta=0 → DDAmount +=
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE AddDealer (
            Did INTEGER PRIMARY KEY AUTOINCREMENT,
            DDAmount REAL NOT NULL DEFAULT 0,
            DAmount REAL NOT NULL DEFAULT 0,
            UpdatedAt TEXT,
            SyncDirty INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await DealerBalanceApply.ensureTables(database);
      },
    );
    await db.insert('AddDealer', {'Did': 1, 'DDAmount': 100, 'DAmount': 50});
  });

  tearDown(() async {
    await db.close();
  });

  Future<(double dd, double d)> balances(int did) async {
    final row = (await db.query('AddDealer', where: 'Did = ?', whereArgs: [did])).single;
    return (_asDouble(row['DDAmount']), _asDouble(row['DAmount']));
  }

  group('DealerBalanceApply.reconcile idempotency', () {
    test('same target applied twice does not double-adjust', () async {
      const source = 'payout-sync-1';
      await DealerBalanceApply.reconcile(
        db: db,
        sourceSyncId: source,
        dealerId: 1,
        ddDelta: 0,
        dDelta: 25,
      );
      expect(await balances(1), (100.0, 75.0));

      await DealerBalanceApply.reconcile(
        db: db,
        sourceSyncId: source,
        dealerId: 1,
        ddDelta: 0,
        dDelta: 25,
      );
      expect(await balances(1), (100.0, 75.0));

      final markers = await db.query('SyncBalanceApplied', where: 'SourceSyncId = ?', whereArgs: [source]);
      expect(markers.length, 1);
    });

    test('changed target reverses prior effect then applies new deltas', () async {
      const source = 'purchase-sync-1';
      await DealerBalanceApply.reconcile(
        db: db,
        sourceSyncId: source,
        dealerId: 1,
        ddDelta: 300,
        dDelta: 0,
      );
      expect(await balances(1), (400.0, 50.0));

      await DealerBalanceApply.reconcile(
        db: db,
        sourceSyncId: source,
        dealerId: 1,
        ddDelta: 500,
        dDelta: 0,
      );
      expect(await balances(1), (600.0, 50.0));
    });

    test('reverse clears marker and rolls back balance', () async {
      const source = 'direct-sync-1';
      await DealerBalanceApply.reconcile(
        db: db,
        sourceSyncId: source,
        dealerId: 1,
        ddDelta: 40,
        dDelta: 0,
      );
      expect(await balances(1), (140.0, 50.0));

      await DealerBalanceApply.reverse(db: db, sourceSyncId: source);
      expect(await balances(1), (100.0, 50.0));
      final markers = await db.query('SyncBalanceApplied', where: 'SourceSyncId = ?', whereArgs: [source]);
      expect(markers, isEmpty);
    });
  });

  group('dealer balance delta policy (documentation)', () {
    test('payout increases DAmount only', () async {
      await DealerBalanceApply.reconcile(
        db: db,
        sourceSyncId: 'doc-payout',
        dealerId: 1,
        ddDelta: 0,
        dDelta: 10,
      );
      final (dd, d) = await balances(1);
      expect(dd, 100.0);
      expect(d, 60.0);
    });

    test('purchase increases DDAmount only', () async {
      await DealerBalanceApply.reconcile(
        db: db,
        sourceSyncId: 'doc-purchase',
        dealerId: 1,
        ddDelta: 250,
        dDelta: 0,
      );
      final (dd, d) = await balances(1);
      expect(dd, 350.0);
      expect(d, 50.0);
    });

    test('direct amount increases DDAmount only', () async {
      await DealerBalanceApply.reconcile(
        db: db,
        sourceSyncId: 'doc-direct',
        dealerId: 1,
        ddDelta: 80,
        dDelta: 0,
      );
      final (dd, d) = await balances(1);
      expect(dd, 180.0);
      expect(d, 50.0);
    });
  });
}

double _asDouble(Object? v) {
  if (v == null) return 0;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
