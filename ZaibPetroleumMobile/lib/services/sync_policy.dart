/// Pure sync decision helpers (unit-testable; no I/O / secrets).
///
/// Conflict rule (documented):
/// - Pending local SyncDirty / SyncTombstone always protect until upload ack.
/// - Upload ack succeeds only when returned (updated_at, device_id) matches the
///   exact payload that was sent (mid-upload edits must not be marked clean).
/// - Upload conflict (server kept another revision): preserve rejected local
///   payload for review; fetch server; if local UpdatedAt still equals the
///   rejected upload version, adopt server and clear dirty; if user edited
///   mid-upload, keep dirty and stage server for later.
/// - Soft-deleted SyncIds never resurrect from an ordinary newer live upsert;
///   restore requires an intentional restore path (not a normal update).
/// - Pull cursor is (updated_at, sync_id). Unresolved (dirty/parent-missing)
///   remotes are staged before the cursor advances past them.
/// - Late-arriving offline rows with older updated_at than the checkpoint are NOT
///   returned by timestamp/keyset pull. Clients must push dirty rows/tombstones
///   first (push-before-pull); peers pull only rows after the watermark.
class SyncPolicy {
  SyncPolicy._();

  /// PostgREST filter for rows at/after the composite cursor.
  /// Empty [syncId] → inclusive gte on updated_at (bootstrap). Otherwise strict
  /// keyset: (updated_at, sync_id) > (updatedAt, syncId).
  static String keysetFilter({required String updatedAt, required String syncId}) {
    if (syncId.isEmpty) return 'updated_at=gte.$updatedAt';
    return 'or=(and(updated_at.eq.$updatedAt,sync_id.gt.$syncId),updated_at.gt.$updatedAt)';
  }

  /// Page exhaustion from raw server page length — never from a client-filtered subset.
  static bool serverPageHasMore({required int rawPageLength, required int pageSize}) =>
      rawPageLength >= pageSize;

  static DateTime parseTs(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return DateTime.tryParse(v.toString())?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Outcome of a remote upsert acknowledgement.
  static UploadAck classifyUploadAck({
    required bool httpOk,
    required String? responseBody,
    required String? uploadedUpdatedAt,
    required String? returnedUpdatedAt,
    required String? uploadedDeviceId,
    required String? returnedDeviceId,
    required bool parseError,
  }) {
    if (!httpOk) return UploadAck.failure;
    if (parseError) return UploadAck.failure;
    // Empty / missing representation is NOT success — caller must verify or fail.
    if (responseBody == null || responseBody.trim().isEmpty || responseBody.trim() == '[]') {
      return UploadAck.failure;
    }
    if (uploadedUpdatedAt == null || uploadedUpdatedAt.isEmpty) return UploadAck.failure;
    if (returnedUpdatedAt == null || returnedUpdatedAt.isEmpty) return UploadAck.failure;

    final sameTs = parseTs(uploadedUpdatedAt).isAtSameMomentAs(parseTs(returnedUpdatedAt));
    final ud = uploadedDeviceId ?? '';
    final rd = returnedDeviceId ?? '';
    final sameDev = ud.isEmpty || rd.isEmpty || ud == rd;

    if (sameTs && sameDev) return UploadAck.accepted;
    // Same timestamp+device already accepted; identical retry after accept is duplicate.
    if (sameTs && ud.isNotEmpty && ud == rd) return UploadAck.duplicate;
    return UploadAck.conflict;
  }

  /// Whether a returned row matches the exact uploaded revision.
  static bool uploadAckMatches({
    required String? uploadedUpdatedAt,
    required String? returnedUpdatedAt,
    required String? uploadedDeviceId,
    required String? returnedDeviceId,
  }) {
    return classifyUploadAck(
          httpOk: true,
          responseBody: '[{}]',
          uploadedUpdatedAt: uploadedUpdatedAt,
          returnedUpdatedAt: returnedUpdatedAt,
          uploadedDeviceId: uploadedDeviceId,
          returnedDeviceId: returnedDeviceId,
          parseError: false,
        ) ==
        UploadAck.accepted;
  }

  /// Only acknowledge the exact version that was uploaded.
  static bool shouldMarkClean({
    required String? currentUpdatedAt,
    required String? uploadedUpdatedAt,
    required bool stillDirtyExpected,
  }) {
    if (stillDirtyExpected) {
      // Caller already verified SyncDirty / mid-edit via UpdatedAt mismatch.
    }
    if (uploadedUpdatedAt == null || uploadedUpdatedAt.isEmpty) return false;
    if (currentUpdatedAt == null || currentUpdatedAt.isEmpty) return false;
    return parseTs(currentUpdatedAt).isAtSameMomentAs(parseTs(uploadedUpdatedAt));
  }

  /// Remote soft-delete / live-row apply decision.
  static bool shouldApplyRemote({
    required bool rowExists,
    required bool syncDirty,
    required bool hasLocalTombstone,
    required String? localUpdatedAt,
    required String? remoteUpdatedAt,
    required String? localDeviceId,
    required String? remoteDeviceId,
    required bool remoteDeleted,
  }) {
    return classifyRemoteApply(
          rowExists: rowExists,
          syncDirty: syncDirty,
          hasLocalTombstone: hasLocalTombstone,
          localUpdatedAt: localUpdatedAt,
          remoteUpdatedAt: remoteUpdatedAt,
          localDeviceId: localDeviceId,
          remoteDeviceId: remoteDeviceId,
          remoteDeleted: remoteDeleted,
        ) ==
        RemoteApplyDecision.apply;
  }

  static RemoteApplyDecision classifyRemoteApply({
    required bool rowExists,
    required bool syncDirty,
    required bool hasLocalTombstone,
    required String? localUpdatedAt,
    required String? remoteUpdatedAt,
    required String? localDeviceId,
    required String? remoteDeviceId,
    required bool remoteDeleted,
  }) {
    if (hasLocalTombstone) {
      // Keep tombstone until push ack; never resurrect from live row.
      return remoteDeleted ? RemoteApplyDecision.apply : RemoteApplyDecision.skipStage;
    }
    if (syncDirty) return RemoteApplyDecision.skipStage;

    if (!rowExists) return RemoteApplyDecision.apply;

    final local = parseTs(localUpdatedAt);
    final remote = parseTs(remoteUpdatedAt);
    final cmp = remote.compareTo(local);
    if (cmp > 0) return RemoteApplyDecision.apply;
    if (cmp < 0) return RemoteApplyDecision.skipDone;

    // Equal timestamps: delete wins; else higher device_id wins (deterministic).
    if (remoteDeleted) return RemoteApplyDecision.apply;
    final ld = localDeviceId ?? '';
    final rd = remoteDeviceId ?? '';
    return rd.compareTo(ld) >= 0 ? RemoteApplyDecision.apply : RemoteApplyDecision.skipDone;
  }

  /// After upload conflict: adopt server only if local still at rejected revision.
  static ConflictReconcile reconcileRejectedUpload({
    required String? localUpdatedAtNow,
    required String? rejectedUploadedUpdatedAt,
  }) {
    if (rejectedUploadedUpdatedAt == null || rejectedUploadedUpdatedAt.isEmpty) {
      return ConflictReconcile.keepLocalDirtyStageServer;
    }
    if (localUpdatedAtNow == null || localUpdatedAtNow.isEmpty) {
      return ConflictReconcile.keepLocalDirtyStageServer;
    }
    if (parseTs(localUpdatedAtNow).isAtSameMomentAs(parseTs(rejectedUploadedUpdatedAt))) {
      return ConflictReconcile.adoptServerClearDirty;
    }
    return ConflictReconcile.keepLocalDirtyStageServer;
  }

  /// Composite pull cursor: updated_at + sync_id (timestamp alone is insufficient).
  static String encodeCursor(String? updatedAt, String? syncId) {
    final u = (updatedAt == null || updatedAt.isEmpty) ? '1970-01-01T00:00:00.000Z' : updatedAt;
    final s = syncId ?? '';
    return '$u|$s';
  }

  static (String updatedAt, String syncId) decodeCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) {
      return ('1970-01-01T00:00:00.000Z', '');
    }
    final i = cursor.indexOf('|');
    if (i < 0) return (cursor, '');
    return (cursor.substring(0, i), cursor.substring(i + 1));
  }

  /// Contiguous watermark for a gapless transactional publication counter.
  /// Under Part 6, revisions are allocated via a locked counter in the same
  /// transaction as the feed row — permanent IDENTITY gaps do not occur.
  /// Contiguous advance remains a defensive stall if a page is incomplete.
  static int advanceContiguousWatermark({
    required int cursor,
    required Iterable<int> seenIds,
  }) {
    final sorted = seenIds.where((id) => id > cursor).toSet().toList()..sort();
    var next = cursor;
    for (final id in sorted) {
      if (id == next + 1) {
        next = id;
      } else if (id > next + 1) {
        break;
      }
    }
    return next;
  }

  /// Protocol v2 cursor for zaib_sync_feed.rev (transactional publication).
  static const int changeFeedProtocolVersion = 2;

  static String encodeChangeCursor(int rev, {int protocol = changeFeedProtocolVersion}) {
    if (protocol >= 2) return 'chg_v2:$rev';
    return 'chg:$rev';
  }

  /// Decoded publication cursor. [-1] means "needs v2 repair bootstrap"
  /// (legacy timestamp, legacy chg: MAX-bootstrap, or unknown).
  static int decodeChangeCursor(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    if (raw.startsWith('chg_v2:')) {
      return int.tryParse(raw.substring(7)) ?? 0;
    }
    // Legacy v1 MAX-bootstrapped or timestamp cursors must re-reconcile from 0.
    return -1;
  }

  /// True when a full server page produced no watermark progress (stop pass).
  static bool changeFeedNoProgress({
    required int cursorBefore,
    required int cursorAfter,
    required int rawPageLength,
    required int pageSize,
  }) {
    if (cursorAfter > cursorBefore) return false;
    return rawPageLength >= pageSize || rawPageLength > 0;
  }

  /// Whether composite pull cursor (updatedAt, syncId) is at or before (at2, id2).
  static bool cursorLessOrEqual(String at1, String id1, String at2, String id2) {
    final cmp = parseTs(at1).compareTo(parseTs(at2));
    if (cmp < 0) return true;
    if (cmp > 0) return false;
    return id1.compareTo(id2) <= 0;
  }

  /// Staged remote rows are dropped after apply or when safely skipped.
  static bool shouldRemoveStagedRemote(RemoteApplyResult result) =>
      result == RemoteApplyResult.applied || result == RemoteApplyResult.safelyAlreadyHandled;
}

enum UploadAck { accepted, duplicate, conflict, failure }

enum RemoteApplyDecision {
  /// Apply remote row now.
  apply,
  /// Do not apply; keep staged (pending local dirty/tombstone/parent).
  skipStage,
  /// Do not apply; safe to forget (older / lost tie-break).
  skipDone,
}

/// Explicit outcome of a remote apply attempt (staging lifecycle).
enum RemoteApplyResult {
  /// Row/balances/markers committed successfully.
  applied,
  /// Older/duplicate remote; safe to drop staging and advance.
  safelyAlreadyHandled,
  /// Blocked (missing parent / pending local); staging must be retained.
  stagedForRetry,
}

enum ConflictReconcile {
  adoptServerClearDirty,
  keepLocalDirtyStageServer,
}
