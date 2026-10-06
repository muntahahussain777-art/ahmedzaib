import 'package:flutter_test/flutter_test.dart';
import 'package:zaib_petroleum_mobile/services/sync_policy.dart';

void main() {
  group('SyncPolicy.shouldRemoveStagedRemote', () {
    test('retains staging when blocked for retry', () {
      expect(SyncPolicy.shouldRemoveStagedRemote(RemoteApplyResult.stagedForRetry), isFalse);
    });

    test('drops staging after successful apply', () {
      expect(SyncPolicy.shouldRemoveStagedRemote(RemoteApplyResult.applied), isTrue);
    });

    test('drops staging when safely already handled', () {
      expect(SyncPolicy.shouldRemoveStagedRemote(RemoteApplyResult.safelyAlreadyHandled), isTrue);
    });
  });
}
