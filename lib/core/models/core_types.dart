part of '../models.dart';

typedef JsonMap = Map<String, dynamic>;

String newId([String prefix = 'id']) {
  final now = DateTime.now().microsecondsSinceEpoch;
  final random = now.remainder(1000000).toRadixString(36);
  return '$prefix-${now.toRadixString(36)}-$random';
}

enum SessionRole { user, assistant }

enum OutputFormatType { text, jsonSchema }

enum PartType {
  text,
  reasoning,
  tool,
  stepStart,
  stepFinish,
  patch,
  retry,
  subtask,
  compaction,
  approvalRequest,
  approvalResult,
  error,
}

enum ToolStatus { pending, running, completed, error }

enum PermissionAction { allow, deny, ask }

enum PermissionReply { once, always, reject }

enum AgentMode { primary, subagent, all }

enum ModelVisibility { show, hide }
