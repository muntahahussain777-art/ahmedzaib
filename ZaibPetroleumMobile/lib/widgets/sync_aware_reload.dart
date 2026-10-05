import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/sync_meta.dart';

/// Soft refresh after sync without clearing search/focus/unsaved forms.
mixin SyncAwareReload<T extends StatefulWidget> on State<T> {
  StreamSubscription<void>? _syncSub;
  int _loadGen = 0;

  /// Soft reload (no blocking spinner when possible).
  Future<void> reloadAfterSync();

  @override
  void initState() {
    super.initState();
    _syncSub = SyncMeta.onDataApplied.listen((_) {
      if (!mounted) return;
      unawaited(_safeReload());
    });
  }

  Future<void> _safeReload() async {
    final gen = ++_loadGen;
    await reloadAfterSync();
    if (!mounted || gen != _loadGen) return;
  }

  /// Bump generation so older async searches cannot replace newer results.
  int bumpLoadGeneration() => ++_loadGen;

  int get loadGeneration => _loadGen;

  bool isLoadCurrent(int gen) => gen == _loadGen;

  @override
  void dispose() {
    _syncSub?.cancel();
    _syncSub = null;
    super.dispose();
  }
}
