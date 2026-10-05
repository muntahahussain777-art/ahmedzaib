import 'dart:async';

import 'package:uuid/uuid.dart';

/// Local SQLite sync metadata helpers (no UI).
class SyncMeta {
  static const uuid = Uuid();

  /// Set by SyncService.init — any form save/update kicks global push/pull.
  static void Function()? onLocalChange;

  static final StreamController<void> _dataApplied =
      StreamController<void>.broadcast();

  /// Fired after remote rows were applied locally (pull/flush). UI lists soft-reload.
  static Stream<void> get onDataApplied => _dataApplied.stream;

  static String newId() => uuid.v4();

  static String nowIso() => DateTime.now().toUtc().toIso8601String();

  /// Stable delete operation request id (immutable across retries).
  static String tombstoneRequestId(String cloudTable, String syncId, String deletedAt) =>
      uuid.v5(Namespace.url.value, '$cloudTable|$syncId|$deletedAt|del');

  static int? asServerRev(Object? v) {
    if (v == null) return null;
    int? i;
    if (v is int) {
      i = v;
    } else if (v is num) {
      i = v.toInt();
    } else {
      i = int.tryParse(v.toString());
    }
    if (i == null || i <= 0) return null;
    return i;
  }

  static void stampNew(Map<String, Object?> map) {
    map['SyncId'] ??= newId();
    map['UpdatedAt'] = nowIso();
    map['SyncDirty'] = 1;
    map['DeletedAt'] = null;
    // Notify AFTER caller finishes insert (markChanged) — save pe sync race na ho
  }

  static void stampUpdate(Map<String, Object?> map) {
    map['SyncId'] ??= newId();
    map['UpdatedAt'] = nowIso();
    map['SyncDirty'] = 1;
  }

  static void stampFromRemote(Map<String, Object?> map, {required String syncId, required String updatedAt}) {
    map['SyncId'] = syncId;
    map['UpdatedAt'] = updatedAt;
    map['SyncDirty'] = 0;
  }

  static void markChanged() => onLocalChange?.call();

  static void notifyDataApplied() {
    if (!_dataApplied.isClosed) _dataApplied.add(null);
  }
}
