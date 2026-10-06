import 'package:flutter_test/flutter_test.dart';
import 'package:zaib_petroleum_mobile/services/sync_policy.dart';

void main() {
  group('advanceContiguousWatermark', () {
    test('gap at next id stalls watermark', () {
      expect(
        SyncPolicy.advanceContiguousWatermark(cursor: 99, seenIds: [101, 102]),
        99,
      );
    });

    test('filling gap advances through contiguous run', () {
      expect(
        SyncPolicy.advanceContiguousWatermark(cursor: 99, seenIds: [100, 101]),
        101,
      );
      expect(
        SyncPolicy.advanceContiguousWatermark(cursor: 99, seenIds: [100, 101, 102]),
        102,
      );
    });

    test('ignores ids at or below cursor', () {
      expect(
        SyncPolicy.advanceContiguousWatermark(cursor: 50, seenIds: [49, 50, 51]),
        51,
      );
    });
  });

  group('protocol v2 change cursor', () {
    test('legacy chg: signals repair bootstrap', () {
      expect(SyncPolicy.decodeChangeCursor('chg:2284'), -1);
    });

    test('legacy timestamp cursor signals bootstrap', () {
      expect(SyncPolicy.decodeChangeCursor('2026-01-01T00:00:00.000Z|abc'), -1);
    });

    test('chg_v2 roundtrip', () {
      expect(SyncPolicy.decodeChangeCursor(SyncPolicy.encodeChangeCursor(42)), 42);
      expect(SyncPolicy.encodeChangeCursor(0), 'chg_v2:0');
    });
  });

  group('changeFeedNoProgress', () {
    test('full page without advance is no-progress', () {
      expect(
        SyncPolicy.changeFeedNoProgress(
          cursorBefore: 10,
          cursorAfter: 10,
          rawPageLength: 500,
          pageSize: 500,
        ),
        isTrue,
      );
    });

    test('advance clears no-progress', () {
      expect(
        SyncPolicy.changeFeedNoProgress(
          cursorBefore: 10,
          cursorAfter: 20,
          rawPageLength: 500,
          pageSize: 500,
        ),
        isFalse,
      );
    });

    test('empty page is not no-progress', () {
      expect(
        SyncPolicy.changeFeedNoProgress(
          cursorBefore: 10,
          cursorAfter: 10,
          rawPageLength: 0,
          pageSize: 500,
        ),
        isFalse,
      );
    });
  });
}
