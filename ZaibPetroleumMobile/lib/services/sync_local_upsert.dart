import 'package:sqflite/sqflite.dart';

/// Local upsert-by-SyncId (shared with tests; used by [SyncService]).
class SyncLocalUpsert {
  SyncLocalUpsert._();

  static bool isUniqueConflict(DatabaseException e) {
    final m = e.toString().toLowerCase();
    return m.contains('unique') || m.contains('constraint') || m.contains('2067');
  }

  static Future<void> upsertBySyncId(
    DatabaseExecutor db,
    String table,
    String syncId,
    Map<String, Object?> map,
  ) async {
    final existing = await db.query(table, columns: ['rowid'], where: 'SyncId = ?', whereArgs: [syncId], limit: 1);
    if (existing.isEmpty) {
      try {
        final id = await db.insert(table, map);
        if (id <= 0) throw StateError('insert $table returned 0');
      } on DatabaseException catch (e) {
        if (!isUniqueConflict(e)) rethrow;
        final n = await db.update(table, map, where: 'SyncId = ?', whereArgs: [syncId]);
        if (n <= 0) throw StateError('unique conflict but update 0 rows $table $syncId');
      }
    } else {
      final n = await db.update(table, map, where: 'SyncId = ?', whereArgs: [syncId]);
      if (n <= 0) throw StateError('update 0 rows $table $syncId');
    }
  }
}
