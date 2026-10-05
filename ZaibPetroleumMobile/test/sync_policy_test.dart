import 'package:flutter_test/flutter_test.dart';
import 'package:zaib_petroleum_mobile/services/sync_policy.dart';

void main() {
  group('SyncPolicy.shouldApplyRemote', () {
    test('protects SyncDirty pending edits', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: true,
          hasLocalTombstone: false,
          localUpdatedAt: '2026-01-01T00:00:00.000Z',
          remoteUpdatedAt: '2026-12-01T00:00:00.000Z',
          localDeviceId: 'a',
          remoteDeviceId: 'b',
          remoteDeleted: false,
        ),
        isFalse,
      );
    });

    test('tombstone blocks live resurrection', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: true,
          localUpdatedAt: null,
          remoteUpdatedAt: '2026-12-01T00:00:00.000Z',
          localDeviceId: null,
          remoteDeviceId: 'b',
          remoteDeleted: false,
        ),
        isFalse,
      );
    });

    test('tombstone allows matching remote delete', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: true,
          localUpdatedAt: null,
          remoteUpdatedAt: '2026-12-01T00:00:00.000Z',
          localDeviceId: null,
          remoteDeviceId: 'b',
          remoteDeleted: true,
        ),
        isTrue,
      );
    });

    test('equal timestamps prefer remote delete', () {
      const ts = '2026-06-01T12:00:00.000Z';
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: false,
          localUpdatedAt: ts,
          remoteUpdatedAt: ts,
          localDeviceId: 'z',
          remoteDeviceId: 'a',
          remoteDeleted: true,
        ),
        isTrue,
      );
    });

    test('equal timestamps use device_id tie-break', () {
      const ts = '2026-06-01T12:00:00.000Z';
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: false,
          localUpdatedAt: ts,
          remoteUpdatedAt: ts,
          localDeviceId: 'device-b',
          remoteDeviceId: 'device-a',
          remoteDeleted: false,
        ),
        isFalse,
      );
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: false,
          localUpdatedAt: ts,
          remoteUpdatedAt: ts,
          localDeviceId: 'device-a',
          remoteDeviceId: 'device-b',
          remoteDeleted: false,
        ),
        isTrue,
      );
    });
  });

  group('SyncPolicy.shouldMarkClean', () {
    test('acks only exact uploaded version', () {
      const v = '2026-06-01T12:00:00.000Z';
      expect(
        SyncPolicy.shouldMarkClean(
          currentUpdatedAt: v,
          uploadedUpdatedAt: v,
          stillDirtyExpected: false,
        ),
        isTrue,
      );
      expect(
        SyncPolicy.shouldMarkClean(
          currentUpdatedAt: '2026-06-01T12:00:01.000Z',
          uploadedUpdatedAt: v,
          stillDirtyExpected: false,
        ),
        isFalse,
      );
    });
  });

  group('SyncPolicy.uploadAckMatches', () {
    test('rejects when server kept newer revision', () {
      expect(
        SyncPolicy.uploadAckMatches(
          uploadedUpdatedAt: '2026-01-01T00:00:00.000Z',
          returnedUpdatedAt: '2026-02-01T00:00:00.000Z',
          uploadedDeviceId: 'd1',
          returnedDeviceId: 'd2',
        ),
        isFalse,
      );
    });

    test('accepts matching updated_at and device', () {
      const v = '2026-01-01T00:00:00.000Z';
      expect(
        SyncPolicy.uploadAckMatches(
          uploadedUpdatedAt: v,
          returnedUpdatedAt: v,
          uploadedDeviceId: 'd1',
          returnedDeviceId: 'd1',
        ),
        isTrue,
      );
    });
  });
}
