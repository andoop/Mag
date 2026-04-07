// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'app_controller.dart';

extension AppControllerEvents on AppController {
  /// 终止/错误等只带 sessionID 的事件：directory 与 workspace 略有不一致时仍应更新 isBusy，否则点停止后界面一直转圈。
  bool _sessionLifecycleEventForCurrentSession(ServerEvent event) {
    if (event.type != 'session.status' && event.type != 'session.error') {
      return false;
    }
    return _isCurrentSession(event.properties['sessionID'] as String?);
  }

  bool _matchesWorkspace(ServerEvent event) {
    final workspace = state.workspace;
    if (workspace == null) return true;
    if (event.directory == null) return true;
    final d = event.directory!;
    final w = workspace.treeUri;
    if (d == w) return true;
    // file: URI 可能因编码或尾部斜杠不一致，避免 SSE 全部被丢弃导致界面一直 busy、无回复
    try {
      final ud = Uri.parse(d);
      final uw = Uri.parse(w);
      if (ud.scheme == 'file' && uw.scheme == 'file') {
        var pd = ud.path;
        var pw = uw.path;
        if (pd.endsWith('/')) pd = pd.substring(0, pd.length - 1);
        if (pw.endsWith('/')) pw = pw.substring(0, pw.length - 1);
        if (pd == pw) return true;
      }
    } catch (_) {}
    return false;
  }

  void _queuePartDelta(JsonMap payload) {
    final sid = payload['sessionID'] as String?;
    if (!_isCurrentSession(sid)) {
      return;
    }
    final partId = payload['partID'] as String?;
    if (partId == null || partId.isEmpty) {
      state =
          state.copyWith(messages: _applyPartDelta(state.messages, payload));
      notifyListeners();
      return;
    }
    final existing = _pendingPartDeltas[partId];
    if (existing == null) {
      _pendingPartDeltas[partId] = payload;
    } else {
      final merged = Map<String, dynamic>.from(existing);
      final existingDelta =
          Map<String, dynamic>.from(existing['delta'] as Map? ?? const {});
      final nextDelta =
          Map<String, dynamic>.from(payload['delta'] as Map? ?? const {});
      merged['delta'] = _mergeDelta(existingDelta, nextDelta);
      _pendingPartDeltas[partId] = merged;
    }
    _partDeltaFlushTimer ??= Timer(
      Duration(milliseconds: _adaptiveFlushIntervalMs()),
      _flushPendingPartDeltas,
    );
  }

  int _adaptiveFlushIntervalMs() {
    if (_lastFlushDurationMs > 16) {
      return (AppController._kBaseFlushIntervalMs * 2).clamp(AppController._kBaseFlushIntervalMs, AppController._kMaxFlushIntervalMs);
    }
    return AppController._kBaseFlushIntervalMs;
  }

  void _flushPendingPartDeltas() {
    final pendingCount = _pendingPartDeltas.length;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    _partDeltaFlushTimer?.cancel();
    _partDeltaFlushTimer = null;
    if (_pendingPartDeltas.isEmpty) return;
    var messages = state.messages;
    for (final payload in _pendingPartDeltas.values) {
      final deltaSid = payload['sessionID'] as String?;
      if (!_isCurrentSession(deltaSid)) {
        continue;
      }
      messages = _applyPartDelta(messages, payload);
    }
    _pendingPartDeltas.clear();
    state = state.copyWith(messages: messages);
    notifyListeners();
    _lastFlushDurationMs = DateTime.now().millisecondsSinceEpoch - startedAt;
    // #region agent log
    debugTrace(
      runId: 'delta-flush',
      hypothesisId: 'H5',
      location: 'app_controller.dart:620',
      message: 'delta flush applied',
      data: {
        'pendingCount': pendingCount,
        'messageCount': messages.length,
        'elapsedMs': _lastFlushDurationMs,
      },
    );
    // #endregion
  }
}
