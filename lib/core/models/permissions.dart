part of '../models.dart';

class PermissionRule {
  PermissionRule({
    required this.permission,
    required this.pattern,
    required this.action,
  });

  final String permission;
  final String pattern;
  final PermissionAction action;

  JsonMap toJson() => {
        'permission': permission,
        'pattern': pattern,
        'action': action.name,
      };

  factory PermissionRule.fromJson(JsonMap json) => PermissionRule(
        permission: json['permission'] as String,
        pattern: json['pattern'] as String,
        action: PermissionAction.values
            .firstWhere((item) => item.name == json['action']),
      );
}

class PermissionRequest {
  PermissionRequest({
    required this.id,
    required this.sessionId,
    required this.permission,
    required this.patterns,
    required this.metadata,
    required this.always,
    this.messageId,
    this.callId,
  });

  final String id;
  final String sessionId;
  final String permission;
  final List<String> patterns;
  final JsonMap metadata;
  final List<String> always;
  final String? messageId;
  final String? callId;

  JsonMap toJson() => {
        'id': id,
        'sessionId': sessionId,
        'permission': permission,
        'patterns': patterns,
        'metadata': metadata,
        'always': always,
        'messageId': messageId,
        'callId': callId,
      };

  factory PermissionRequest.fromJson(JsonMap json) => PermissionRequest(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        permission: json['permission'] as String,
        patterns: List<String>.from(json['patterns'] as List),
        metadata: Map<String, dynamic>.from(
            json['metadata'] as Map? ?? <String, dynamic>{}),
        always: List<String>.from(json['always'] as List? ?? const []),
        messageId: json['messageId'] as String?,
        callId: json['callId'] as String?,
      );
}

class QuestionOption {
  QuestionOption({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;

  JsonMap toJson() => {
        'label': label,
        'description': description,
      };

  factory QuestionOption.fromJson(JsonMap json) => QuestionOption(
        label: jsonStringCoerce(json['label'], ''),
        description: jsonStringCoerce(json['description'], ''),
      );
}

class QuestionInfo {
  QuestionInfo({
    required this.question,
    required this.header,
    required this.options,
    this.multiple = false,
    this.custom = true,
  });

  final String question;
  final String header;
  final List<QuestionOption> options;
  final bool multiple;
  final bool custom;

  JsonMap toJson() => {
        'question': question,
        'header': header,
        'options': options.map((item) => item.toJson()).toList(),
        'multiple': multiple,
        'custom': custom,
      };

  factory QuestionInfo.fromJson(JsonMap json) => QuestionInfo(
        question: jsonStringCoerce(json['question'], ''),
        header: jsonStringCoerce(json['header'], ''),
        options: ((json['options'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => QuestionOption.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(),
        multiple: (json['multiple'] as bool?) ?? false,
        custom: (json['custom'] as bool?) ?? true,
      );
}

class QuestionRequest {
  QuestionRequest({
    required this.id,
    required this.sessionId,
    required this.questions,
    this.messageId,
    this.callId,
  });

  final String id;
  final String sessionId;
  final List<QuestionInfo> questions;
  final String? messageId;
  final String? callId;

  JsonMap toJson() => {
        'id': id,
        'sessionId': sessionId,
        'questions': questions.map((item) => item.toJson()).toList(),
        'messageId': messageId,
        'callId': callId,
      };

  factory QuestionRequest.fromJson(JsonMap json) {
    final idRaw = jsonStringCoerce(json['id'], '');
    final sessionRaw = jsonStringCoerce(json['sessionId'], '');
    return QuestionRequest(
        id: idRaw.isEmpty ? newId('question') : idRaw,
        sessionId: sessionRaw,
        questions: ((json['questions'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => QuestionInfo.fromJson(
                  Map<String, dynamic>.from(item),
                ))
            .toList(),
        messageId: json['messageId'] as String?,
        callId: json['callId'] as String?,
      );
  }
}

class TodoItem {
  TodoItem({
    required this.id,
    required this.sessionId,
    required this.content,
    required this.status,
    this.priority = 'medium',
    this.position = 0,
  });

  final String id;
  final String sessionId;
  final String content;
  final String status;
  final String priority;

  /// 会话内顺序，与 OpenCode `TodoTable.position` 一致。
  final int position;

  JsonMap toJson() => {
        'id': id,
        'sessionId': sessionId,
        'content': content,
        'status': status,
        'priority': priority,
        'position': position,
      };

  factory TodoItem.fromJson(JsonMap json) {
    final idRaw = jsonStringCoerce(json['id'], '');
    return TodoItem(
        id: idRaw.isEmpty ? newId('todo') : idRaw,
        sessionId: jsonStringCoerce(json['sessionId'], ''),
        content: jsonStringCoerce(json['content'], ''),
        status: jsonStringCoerce(json['status'], 'pending'),
        priority: jsonStringCoerce(json['priority'], 'medium'),
        position: (json['position'] as num?)?.toInt() ?? 0,
      );
  }
}
