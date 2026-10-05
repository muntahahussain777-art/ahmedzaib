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

  group('decodeChangeCursor bootstrap', () {
    test('legacy timestamp cursor signals bootstrap', () {
      expect(SyncPolicy.decodeChangeCursor('2026-01-01T00:00:00.000Z|abc'), -1);
    });

    test('encoded change cursor roundtrip', () {
      expect(SyncPolicy.decodeChangeCursor(SyncPolicy.encodeChangeCursor(42)), 42);
    });
  });
}
