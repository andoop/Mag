// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'app_controller.dart';

extension AppControllerState on AppController {
  void _setError(Object error) {
    state = state.copyWith(error: error.toString());
    notifyListeners();
  }

  void _setSessionStatus(String sessionId, SessionRunStatus status) {
    final next = Map<String, SessionRunStatus>.from(state.sessionStatuses);
    if (status.phase == SessionRunPhase.idle) {
      next.remove(sessionId);
    } else {
      next[sessionId] = status;
    }
    state = state.copyWith(sessionStatuses: next);
  }

  void _setSessionError(String sessionId, String message) {
    final next = Map<String, SessionRunStatus>.from(state.sessionStatuses);
    next[sessionId] = SessionRunStatus.error(message);
    state = state.copyWith(
        sessionStatuses: next,
        error: _isCurrentSession(sessionId) ? message : state.error);
  }

  void _removeSessionStatus(String sessionId) {
    final next = Map<String, SessionRunStatus>.from(state.sessionStatuses);
    next.remove(sessionId);
    state = state.copyWith(sessionStatuses: next);
  }

  bool _isCurrentSession(String? sessionId) {
    final current = state.session?.id;
    if (current == null || sessionId == null) return false;
    return current == sessionId;
  }

  List<SessionInfo> _upsertSession(
      List<SessionInfo> sessions, SessionInfo session) {
    final items = [...sessions];
    final index = items.indexWhere((item) => item.id == session.id);
    if (index >= 0) {
      items[index] = session;
    } else {
      items.add(session);
    }
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  List<SessionMessageBundle> _upsertMessage(
    List<SessionMessageBundle> bundles,
    MessageInfo message,
  ) {
    final index = bundles.indexWhere((item) => item.message.id == message.id);
    if (index >= 0) {
      final updated =
          SessionMessageBundle(message: message, parts: bundles[index].parts);
      if (index == bundles.length - 1) {
        final items = List<SessionMessageBundle>.of(bundles);
        items[index] = updated;
        return items;
      }
      final items = [...bundles];
      items[index] = updated;
      items.sort((a, b) => a.message.createdAt.compareTo(b.message.createdAt));
      return items;
    }
    final items = [...bundles];
    items.add(SessionMessageBundle(message: message, parts: const []));
    items.sort((a, b) => a.message.createdAt.compareTo(b.message.createdAt));
    return items;
  }

  List<SessionMessageBundle> _upsertPart(
    List<SessionMessageBundle> bundles,
    MessagePart part,
  ) {
    final index =
        bundles.indexWhere((item) => item.message.id == part.messageId);
    if (index < 0) return bundles;
    final oldParts = bundles[index].parts;
    final partIndex = oldParts.indexWhere((item) => item.id == part.id);
    final List<MessagePart> parts;
    if (partIndex >= 0) {
      parts = List<MessagePart>.of(oldParts);
      parts[partIndex] = part;
    } else {
      parts = [...oldParts, part];
      parts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    final updatedBundle =
        SessionMessageBundle(message: bundles[index].message, parts: parts);
    if (index == bundles.length - 1) {
      final items = List<SessionMessageBundle>.of(bundles);
      items[index] = updatedBundle;
      return items;
    }
    final items = [...bundles];
    items[index] = updatedBundle;
    return items;
  }

  List<SessionMessageBundle> _applyPartDelta(
    List<SessionMessageBundle> bundles,
    JsonMap payload,
  ) {
    final messageId = payload['messageID'] as String?;
    final partId = payload['partID'] as String?;
    final sessionId = payload['sessionID'] as String?;
    final typeName = payload['type'] as String?;
    final createdAt =
        payload['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    if (messageId == null ||
        partId == null ||
        sessionId == null ||
        typeName == null) {
      return bundles;
    }
    final delta =
        Map<String, dynamic>.from(payload['delta'] as Map? ?? const {});
    final index = bundles.indexWhere((item) => item.message.id == messageId);
    if (index < 0) return bundles;
    final oldParts = bundles[index].parts;
    final partIndex = oldParts.indexWhere((item) => item.id == partId);
    final List<MessagePart> parts;
    if (partIndex < 0) {
      parts = [
        ...oldParts,
        MessagePart(
          id: partId,
          sessionId: sessionId,
          messageId: messageId,
          type: PartType.values.firstWhere((item) => item.name == typeName),
          createdAt: createdAt,
          data: delta,
        ),
      ];
      parts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else {
      final existing = oldParts[partIndex];
      parts = List<MessagePart>.of(oldParts);
      parts[partIndex] = MessagePart(
        id: existing.id,
        sessionId: existing.sessionId,
        messageId: existing.messageId,
        type: existing.type,
        createdAt: existing.createdAt,
        data: _mergeDelta(existing.data, delta),
      );
    }
    final updatedBundle =
        SessionMessageBundle(message: bundles[index].message, parts: parts);
    if (index == bundles.length - 1) {
      final items = List<SessionMessageBundle>.of(bundles);
      items[index] = updatedBundle;
      return items;
    }
    final items = [...bundles];
    items[index] = updatedBundle;
    return items;
  }

  JsonMap _mergeDelta(JsonMap existing, JsonMap delta) {
    final merged = Map<String, dynamic>.from(existing);
    for (final entry in delta.entries) {
      final previous = merged[entry.key];
      final next = entry.value;
      if (previous is String && next is String) {
        merged[entry.key] = '$previous$next';
      } else {
        merged[entry.key] = next;
      }
    }
    return merged;
  }

  List<PermissionRequest> _upsertPermission(
    List<PermissionRequest> items,
    PermissionRequest request,
  ) {
    final next = [...items];
    final index = next.indexWhere((item) => item.id == request.id);
    if (index >= 0) {
      next[index] = request;
    } else {
      next.add(request);
    }
    return next;
  }

  List<QuestionRequest> _upsertQuestion(
    List<QuestionRequest> items,
    QuestionRequest request,
  ) {
    final next = [...items];
    final index = next.indexWhere((item) => item.id == request.id);
    if (index >= 0) {
      next[index] = request;
    } else {
      next.add(request);
    }
    return next;
  }
}
