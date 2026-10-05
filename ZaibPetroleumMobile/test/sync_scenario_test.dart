import 'package:flutter_test/flutter_test.dart';
import 'package:zaib_petroleum_mobile/services/sync_policy.dart';

/// Part 3 scenario matrix (pure policy — no network / no secrets).
void main() {
  const t1 = '2026-06-01T10:00:00.000Z';
  const t2 = '2026-06-01T11:00:00.000Z';
  const tEq = '2026-06-01T12:00:00.000Z';

  group('insert/update before first sync', () {
    test('local dirty always wins over remote until clean', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: true,
          hasLocalTombstone: false,
          localUpdatedAt: t1,
          remoteUpdatedAt: t2,
          localDeviceId: 'mobile',
          remoteDeviceId: 'pc',
          remoteDeleted: false,
        ),
        isFalse,
      );
    });
  });

  group('insert/delete before first sync', () {
    test('local tombstone blocks live remote row', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: false,
          syncDirty: false,
          hasLocalTombstone: true,
          localUpdatedAt: null,
          remoteUpdatedAt: t2,
          localDeviceId: null,
          remoteDeviceId: 'pc',
          remoteDeleted: false,
        ),
        isFalse,
      );
    });

    test('local tombstone accepts remote soft-delete', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: false,
          syncDirty: false,
          hasLocalTombstone: true,
          localUpdatedAt: null,
          remoteUpdatedAt: t2,
          localDeviceId: null,
          remoteDeviceId: 'pc',
          remoteDeleted: true,
        ),
        isTrue,
      );
    });
  });

  group('offline deletion then reconnect', () {
    test('pending tombstone survives equal-timestamp live overwrite', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: true,
          localUpdatedAt: tEq,
          remoteUpdatedAt: tEq,
          localDeviceId: 'mobile',
          remoteDeviceId: 'zzzz',
          remoteDeleted: false,
        ),
        isFalse,
      );
    });
  });

  group('editing during upload', () {
    test('mark-clean rejected when UpdatedAt changed mid-upload', () {
      expect(
        SyncPolicy.shouldMarkClean(
          currentUpdatedAt: t2,
          uploadedUpdatedAt: t1,
          stillDirtyExpected: false,
        ),
        isFalse,
      );
    });

    test('mark-clean accepted only for exact uploaded version', () {
      expect(
        SyncPolicy.shouldMarkClean(
          currentUpdatedAt: t1,
          uploadedUpdatedAt: t1,
          stillDirtyExpected: false,
        ),
        isTrue,
      );
    });
  });

  group('concurrent update/update and update/delete', () {
    test('newer remote update wins when local clean', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: false,
          localUpdatedAt: t1,
          remoteUpdatedAt: t2,
          localDeviceId: 'a',
          remoteDeviceId: 'b',
          remoteDeleted: false,
        ),
        isTrue,
      );
    });

    test('equal timestamp: remote delete wins over live', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: false,
          localUpdatedAt: tEq,
          remoteUpdatedAt: tEq,
          localDeviceId: 'zzz',
          remoteDeviceId: 'aaa',
          remoteDeleted: true,
        ),
        isTrue,
      );
    });

    test('upload ack fails when server kept other device revision', () {
      expect(
        SyncPolicy.uploadAckMatches(
          uploadedUpdatedAt: t1,
          returnedUpdatedAt: t1,
          uploadedDeviceId: 'mobile',
          returnedDeviceId: 'pc',
        ),
        isFalse,
      );
    });
  });

  group('idempotent retries', () {
    test('matching ack is idempotent success', () {
      expect(
        SyncPolicy.uploadAckMatches(
          uploadedUpdatedAt: t1,
          returnedUpdatedAt: t1,
          uploadedDeviceId: 'd1',
          returnedDeviceId: 'd1',
        ),
        isTrue,
      );
    });
  });

  group('late-arriving / stale remote', () {
    test('older remote does not apply when local clean', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: false,
          localUpdatedAt: t2,
          remoteUpdatedAt: t1,
          localDeviceId: 'a',
          remoteDeviceId: 'b',
          remoteDeleted: false,
        ),
        isFalse,
      );
    });
  });
}
