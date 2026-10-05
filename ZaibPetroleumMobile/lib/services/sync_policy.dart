/// Pure sync decision helpers (unit-testable; no I/O / secrets).
class SyncPolicy {
  SyncPolicy._();

  static DateTime parseTs(dynamic v) {
    if (v == null) return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return DateTime.tryParse(v.toString())?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Remote soft-delete / live-row apply decision.
  /// Pending local edits and deletion tombstones always win until uploaded.
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
    if (hasLocalTombstone) {
      // Keep tombstone until push ack; never resurrect from stale live row.
      return remoteDeleted;
    }
    if (syncDirty) return false;

    if (!rowExists) return true;

    final local = parseTs(localUpdatedAt);
    final remote = parseTs(remoteUpdatedAt);
    final cmp = remote.compareTo(local);
    if (cmp > 0) return true;
    if (cmp < 0) return false;

    // Equal timestamps: delete wins; else higher device_id wins (deterministic).
    if (remoteDeleted) return true;
    final ld = localDeviceId ?? '';
    final rd = remoteDeviceId ?? '';
    return rd.compareTo(ld) >= 0;
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

  /// Upload won on server when returned revision/timestamp matches what we sent.
  static bool uploadAckMatches({
    required String? uploadedUpdatedAt,
    required String? returnedUpdatedAt,
    required String? uploadedDeviceId,
    required String? returnedDeviceId,
  }) {
    if (uploadedUpdatedAt == null || returnedUpdatedAt == null) return false;
    if (!parseTs(uploadedUpdatedAt).isAtSameMomentAs(parseTs(returnedUpdatedAt))) {
      return false;
    }
    final ud = uploadedDeviceId ?? '';
    final rd = returnedDeviceId ?? '';
    if (ud.isEmpty || rd.isEmpty) return true;
    return ud == rd;
  }
}
