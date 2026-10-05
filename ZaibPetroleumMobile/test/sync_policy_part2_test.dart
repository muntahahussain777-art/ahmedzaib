import 'package:flutter_test/flutter_test.dart';
import 'package:zaib_petroleum_mobile/services/sync_policy.dart';

void main() {
  group('UploadAck', () {
    test('empty ack is failure not success', () {
      expect(
        SyncPolicy.classifyUploadAck(
          httpOk: true,
          responseBody: '[]',
          uploadedUpdatedAt: '2026-01-01T00:00:00.000Z',
          returnedUpdatedAt: null,
          uploadedDeviceId: 'a',
          returnedDeviceId: null,
          parseError: false,
        ),
        UploadAck.failure,
      );
    });

    test('matching revision is accepted', () {
      expect(
        SyncPolicy.classifyUploadAck(
          httpOk: true,
          responseBody: '[{"x":1}]',
          uploadedUpdatedAt: '2026-01-01T00:00:00.000Z',
          returnedUpdatedAt: '2026-01-01T00:00:00.000Z',
          uploadedDeviceId: 'a',
          returnedDeviceId: 'a',
          parseError: false,
        ),
        UploadAck.accepted,
      );
    });

    test('server kept other revision is conflict', () {
      expect(
        SyncPolicy.classifyUploadAck(
          httpOk: true,
          responseBody: '[{"x":1}]',
          uploadedUpdatedAt: '2026-01-01T00:00:00.000Z',
          returnedUpdatedAt: '2026-01-01T01:00:00.000Z',
          uploadedDeviceId: 'a',
          returnedDeviceId: 'b',
          parseError: false,
        ),
        UploadAck.conflict,
      );
    });
  });

  group('rejected upload reconcile', () {
    test('exact version adopts server', () {
      expect(
        SyncPolicy.reconcileRejectedUpload(
          localUpdatedAtNow: '2026-01-01T00:00:00.000Z',
          rejectedUploadedUpdatedAt: '2026-01-01T00:00:00.000Z',
        ),
        ConflictReconcile.adoptServerClearDirty,
      );
    });

    test('mid-upload edit keeps dirty', () {
      expect(
        SyncPolicy.reconcileRejectedUpload(
          localUpdatedAtNow: '2026-01-01T01:00:00.000Z',
          rejectedUploadedUpdatedAt: '2026-01-01T00:00:00.000Z',
        ),
        ConflictReconcile.keepLocalDirtyStageServer,
      );
    });
  });

  group('remote apply + tombstone', () {
    test('tombstone never applies live row', () {
      expect(
        SyncPolicy.classifyRemoteApply(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: true,
          localUpdatedAt: null,
          remoteUpdatedAt: '2026-10-01T00:00:00.000Z',
          localDeviceId: null,
          remoteDeviceId: 'pc',
          remoteDeleted: false,
        ),
        RemoteApplyDecision.skipStage,
      );
    });

    test('dirty stages newer remote', () {
      expect(
        SyncPolicy.classifyRemoteApply(
          rowExists: true,
          syncDirty: true,
          hasLocalTombstone: false,
          localUpdatedAt: '2026-01-01T00:00:00.000Z',
          remoteUpdatedAt: '2026-02-01T00:00:00.000Z',
          localDeviceId: 'm',
          remoteDeviceId: 'pc',
          remoteDeleted: false,
        ),
        RemoteApplyDecision.skipStage,
      );
    });

    test('equal timestamp delete wins', () {
      expect(
        SyncPolicy.shouldApplyRemote(
          rowExists: true,
          syncDirty: false,
          hasLocalTombstone: false,
          localUpdatedAt: '2026-01-01T00:00:00.000Z',
          remoteUpdatedAt: '2026-01-01T00:00:00.000Z',
          localDeviceId: 'm',
          remoteDeviceId: 'pc',
          remoteDeleted: true,
        ),
        isTrue,
      );
    });
  });

  group('composite cursor', () {
    test('encode/decode roundtrip', () {
      final c = SyncPolicy.encodeCursor('2026-01-01T00:00:00.000Z', 'abc');
      final d = SyncPolicy.decodeCursor(c);
      expect(d.$1, '2026-01-01T00:00:00.000Z');
      expect(d.$2, 'abc');
    });

    test('equal timestamp later sync_id is after cursor', () {
      expect(
        SyncPolicy.cursorLessOrEqual(
          '2026-01-01T00:00:00.000Z',
          'b',
          '2026-01-01T00:00:00.000Z',
          'a',
        ),
        isFalse,
      );
    });
  });

  group('mark clean exact version', () {
    test('mid upload edit not cleaned', () {
      expect(
        SyncPolicy.shouldMarkClean(
          currentUpdatedAt: '2026-01-01T01:00:00.000Z',
          uploadedUpdatedAt: '2026-01-01T00:00:00.000Z',
          stillDirtyExpected: false,
        ),
        isFalse,
      );
    });
  });
}
