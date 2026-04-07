part of '../session_engine.dart';

class PermissionCenter {
  PermissionCenter(this._db, this._events);

  final AppDatabase _db;
  final LocalEventBus _events;
  final Map<String, Completer<PermissionReply>> _pending = {};
  final Map<String, String> _pendingSessionIds = {};

  Future<void> ask({
    required WorkspaceInfo workspace,
    required PermissionRequest request,
    List<PermissionRule> rules = const [],
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final savedRules = await _db.listToolPermissions(workspace.id);
    final mergedRules = [...rules, ...savedRules];
    var needsAsk = false;
    for (final pattern in request.patterns) {
      final action = _evaluateRule(request.permission, pattern, mergedRules);
      if (action == PermissionAction.deny) {
        throw Exception('Permission denied for ${request.permission} $pattern');
      }
      if (action == PermissionAction.ask) {
        needsAsk = true;
      }
    }
    if (!needsAsk) return;
    final completer = Completer<PermissionReply>();
    _pending[request.id] = completer;
    _pendingSessionIds[request.id] = request.sessionId;
    await _db.savePermissionRequest(request);
    _events.emit(ServerEvent(
      type: 'permission.asked',
      properties: request.toJson(),
      directory: workspace.treeUri,
    ));
    final PermissionReply reply;
    try {
      reply = cancelToken != null
          ? await cancelToken.guard(completer.future)
          : await completer.future;
    } finally {
      _pending.remove(request.id);
      _pendingSessionIds.remove(request.id);
    }
    await _db.deletePermissionRequest(request.id);
    _events.emit(ServerEvent(
      type: 'permission.replied',
      properties: {
        'sessionID': request.sessionId,
        'requestID': request.id,
        'reply': reply.name,
      },
      directory: workspace.treeUri,
    ));
    if (reply == PermissionReply.reject) {
      throw Exception('Permission rejected by user');
    }
    if (reply == PermissionReply.always) {
      for (final pattern in request.always) {
        await _db.saveToolPermission(
          workspace.id,
          PermissionRule(
            permission: request.permission,
            pattern: pattern,
            action: PermissionAction.allow,
          ),
        );
      }
    }
  }

  Future<void> reply(String requestId, PermissionReply reply) async {
    final completer = _pending.remove(requestId);
    _pendingSessionIds.remove(requestId);
    completer?.complete(reply);
  }

  void cancelSession(String sessionId) {
    final toCancel = _pendingSessionIds.entries
        .where((e) => e.value == sessionId)
        .map((e) => e.key)
        .toList();
    for (final id in toCancel) {
      _pending.remove(id);
      _pendingSessionIds.remove(id);
    }
  }

  PermissionAction _evaluateRule(
    String permission,
    String pattern,
    List<PermissionRule> rules,
  ) {
    PermissionAction result = PermissionAction.ask;
    for (final rule in rules) {
      if (!_match(rule.permission, permission)) continue;
      if (!_match(rule.pattern, pattern)) continue;
      result = rule.action;
    }
    return result;
  }

  bool _match(String pattern, String input) {
    if (pattern == '*' || pattern == input) return true;
    final escaped = RegExp.escape(pattern)
        .replaceAll(r'\*\*', '.*')
        .replaceAll(r'\*', '[^/]*')
        .replaceAll(r'\?', '.');
    return RegExp('^$escaped\$').hasMatch(input);
  }
}
