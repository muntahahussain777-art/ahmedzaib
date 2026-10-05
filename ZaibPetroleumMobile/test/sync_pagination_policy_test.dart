import 'package:flutter_test/flutter_test.dart';
import 'package:zaib_petroleum_mobile/services/sync_policy.dart';

void main() {
  group('keyset pagination policy', () {
    test('bootstrap filter uses inclusive gte', () {
      expect(
        SyncPolicy.keysetFilter(updatedAt: '2026-01-01T00:00:00.000Z', syncId: ''),
        'updated_at=gte.2026-01-01T00:00:00.000Z',
      );
    });

    test('composite filter is strict after (updated_at, sync_id)', () {
      const at = '2026-01-01T00:00:00.000Z';
      const id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      expect(
        SyncPolicy.keysetFilter(updatedAt: at, syncId: id),
        'or=(and(updated_at.eq.$at,sync_id.gt.$id),updated_at.gt.$at)',
      );
    });

    test('page exhaustion uses raw server length not filtered length', () {
      // Simulates: server returned 500 rows; after local filter only 0 kept.
      // Old bug stopped here; correct policy still asks for more.
      expect(SyncPolicy.serverPageHasMore(rawPageLength: 500, pageSize: 500), isTrue);
      expect(SyncPolicy.serverPageHasMore(rawPageLength: 499, pageSize: 500), isFalse);
      expect(SyncPolicy.serverPageHasMore(rawPageLength: 0, pageSize: 500), isFalse);
    });

    test('equal timestamps still progress via sync_id keyset', () {
      const at = '2026-06-01T12:00:00.000Z';
      final a = SyncPolicy.keysetFilter(updatedAt: at, syncId: 'aaa');
      final b = SyncPolicy.keysetFilter(updatedAt: at, syncId: 'zzz');
      expect(a.contains('sync_id.gt.aaa'), isTrue);
      expect(b.contains('sync_id.gt.zzz'), isTrue);
      expect(a, isNot(equals(b)));
    });
  });
}
