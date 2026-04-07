part of '../session_engine.dart';

class QuestionCenter {
  QuestionCenter(this._db, this._events);

  final AppDatabase _db;
  final LocalEventBus _events;
  final Map<String, Completer<List<List<String>>>> _pending = {};
  final Map<String, String> _pendingSessionIds = {};

  Future<List<List<String>>> ask({
    required WorkspaceInfo workspace,
    required QuestionRequest request,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final completer = Completer<List<List<String>>>();
    _pending[request.id] = completer;
    _pendingSessionIds[request.id] = request.sessionId;
    await _db.saveQuestionRequest(request);
    _events.emit(ServerEvent(
      type: 'question.asked',
      properties: request.toJson(),
      directory: workspace.treeUri,
    ));
    final List<List<String>> answers;
    try {
      answers = cancelToken != null
          ? await cancelToken.guard(completer.future)
          : await completer.future;
    } finally {
      _pending.remove(request.id);
      _pendingSessionIds.remove(request.id);
    }
    await _db.deleteQuestionRequest(request.id);
    _events.emit(ServerEvent(
      type: 'question.replied',
      properties: {
        'sessionID': request.sessionId,
        'requestID': request.id,
        'answers': answers,
      },
      directory: workspace.treeUri,
    ));
    return answers;
  }

  Future<void> reply(String requestId, List<List<String>> answers) async {
    final completer = _pending.remove(requestId);
    _pendingSessionIds.remove(requestId);
    completer?.complete(answers);
  }

  Future<void> reject(String requestId) async {
    final completer = _pending.remove(requestId);
    _pendingSessionIds.remove(requestId);
    completer?.complete(const []);
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
}
