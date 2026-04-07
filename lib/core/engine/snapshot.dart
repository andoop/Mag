part of '../session_engine.dart';

class EngineSnapshot {
  EngineSnapshot({
    required this.messages,
    required this.parts,
    required this.permissions,
    required this.questions,
    required this.todos,
  });

  final List<MessageInfo> messages;
  final List<MessagePart> parts;
  final List<PermissionRequest> permissions;
  final List<QuestionRequest> questions;
  final List<TodoItem> todos;
}
