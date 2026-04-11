part of '../models.dart';

/// 与 OpenCode `packages/opencode/src/session/index.ts` 的默认标题及 `isDefaultTitle` 对齐。
class SessionTitlePolicy {
  SessionTitlePolicy._();

  static const parentPrefix = 'New session - ';
  static const childPrefix = 'Child session - ';

  /// ECMAScript `toISOString()` 风格：`2026-04-01T12:34:56.789Z`
  static String _utcIsoMs() {
    final u = DateTime.now().toUtc();
    return '${u.year.toString().padLeft(4, '0')}-'
        '${u.month.toString().padLeft(2, '0')}-'
        '${u.day.toString().padLeft(2, '0')}T'
        '${u.hour.toString().padLeft(2, '0')}:'
        '${u.minute.toString().padLeft(2, '0')}:'
        '${u.second.toString().padLeft(2, '0')}.'
        '${u.millisecond.toString().padLeft(3, '0')}Z';
  }

  static String defaultTitle({bool isChild = false}) {
    return '${isChild ? childPrefix : parentPrefix}${_utcIsoMs()}';
  }

  static final _parentRe = RegExp(
    r'^New session - \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  );
  static final _childRe = RegExp(
    r'^Child session - \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  );

  static bool matchesDefaultPattern(String title) {
    final t = title.trim();
    return _parentRe.hasMatch(t) || _childRe.hasMatch(t);
  }

  /// 子会话（如 subtask）不跑标题模型，与 OpenCode `parentID` 分支一致。
  static bool shouldAutoGenerateFromModel(String title) {
    final t = title.trim();
    if (t == 'New session' || t.isEmpty) return true;
    if (_childRe.hasMatch(t)) return false;
    return _parentRe.hasMatch(t);
  }
}

class SessionInfo {
  SessionInfo({
    required this.id,
    required this.projectId,
    required this.workspaceId,
    required this.title,
    required this.agent,
    required this.createdAt,
    required this.updatedAt,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cost = 0,
    this.summaryMessageId = '',
  });

  final String id;
  final String projectId;
  final String workspaceId;
  final String title;
  final String agent;
  final int createdAt;
  final int updatedAt;
  final int promptTokens;
  final int completionTokens;
  final double cost;
  final String summaryMessageId;

  int get totalTokens => promptTokens + completionTokens;
  bool get hasSummary => summaryMessageId.isNotEmpty;

  SessionInfo copyWith({
    String? title,
    String? agent,
    int? updatedAt,
    int? promptTokens,
    int? completionTokens,
    double? cost,
    String? summaryMessageId,
  }) {
    return SessionInfo(
      id: id,
      projectId: projectId,
      workspaceId: workspaceId,
      title: title ?? this.title,
      agent: agent ?? this.agent,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      cost: cost ?? this.cost,
      summaryMessageId: summaryMessageId ?? this.summaryMessageId,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'projectId': projectId,
        'workspaceId': workspaceId,
        'title': title,
        'agent': agent,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'cost': cost,
        'summaryMessageId': summaryMessageId,
      };

  factory SessionInfo.fromJson(JsonMap json) => SessionInfo(
        id: json['id'] as String,
        projectId: json['projectId'] as String,
        workspaceId: json['workspaceId'] as String,
        title: json['title'] as String,
        agent: json['agent'] as String,
        createdAt: json['createdAt'] as int,
        updatedAt: json['updatedAt'] as int,
        promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
        completionTokens: (json['completionTokens'] as num?)?.toInt() ?? 0,
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        summaryMessageId: (json['summaryMessageId'] as String?) ?? '',
      );
}

class AgentDefinition {
  AgentDefinition({
    required this.name,
    required this.mode,
    required this.permissionRules,
    required this.availableTools,
    this.description = '',
    this.descriptionZh = '',
    this.native = true,
    this.hidden = false,
    this.steps,
    this.promptOverride,
  });

  final String name;
  final String description;
  final String descriptionZh;
  final AgentMode mode;
  final bool native;
  final bool hidden;

  /// Max tool-use loop iterations. `null` means unlimited (OpenCode default).
  final int? steps;
  final String? promptOverride;
  final List<PermissionRule> permissionRules;
  final List<String> availableTools;

  String localizedDescription({bool zh = false}) =>
      zh && descriptionZh.isNotEmpty ? descriptionZh : description;

  JsonMap toJson() => {
        'name': name,
        'description': description,
        'descriptionZh': descriptionZh,
        'mode': mode.name,
        'native': native,
        'hidden': hidden,
        'steps': steps,
        'promptOverride': promptOverride,
        'permissionRules':
            permissionRules.map((item) => item.toJson()).toList(),
        'availableTools': availableTools,
      };

  factory AgentDefinition.fromJson(JsonMap json) => AgentDefinition(
        name: json['name'] as String,
        description: (json['description'] as String?) ?? '',
        descriptionZh: (json['descriptionZh'] as String?) ?? '',
        mode: AgentMode.values.firstWhere((item) => item.name == json['mode']),
        native: (json['native'] as bool?) ?? true,
        hidden: (json['hidden'] as bool?) ?? false,
        steps: json['steps'] as int?,
        promptOverride: json['promptOverride'] as String?,
        permissionRules: (json['permissionRules'] as List? ?? const [])
            .map((item) =>
                PermissionRule.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        availableTools:
            List<String>.from(json['availableTools'] as List? ?? const []),
      );
}

class MessageFormat {
  MessageFormat.text()
      : type = OutputFormatType.text,
        schema = null,
        retryCount = 0;

  MessageFormat.jsonSchema({
    required this.schema,
    this.retryCount = 2,
  }) : type = OutputFormatType.jsonSchema;

  final OutputFormatType type;
  final JsonMap? schema;
  final int retryCount;

  JsonMap toJson() => {
        'type': type.name,
        'schema': schema,
        'retryCount': retryCount,
      };

  factory MessageFormat.fromJson(JsonMap json) {
    final type = OutputFormatType.values.firstWhere(
      (item) => item.name == json['type'],
      orElse: () => OutputFormatType.text,
    );
    if (type == OutputFormatType.jsonSchema) {
      return MessageFormat.jsonSchema(
        schema: (json['schema'] as JsonMap?) ?? <String, dynamic>{},
        retryCount: (json['retryCount'] as int?) ?? 2,
      );
    }
    return MessageFormat.text();
  }
}

class MessageInfo {
  MessageInfo({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.agent,
    required this.createdAt,
    this.text = '',
    this.format,
    this.model,
    this.provider,
    this.error,
    this.structuredOutput,
    this.parentMessageId,
    this.summary = false,
    this.variant,
  });

  final String id;
  final String sessionId;
  final SessionRole role;
  final String agent;
  final int createdAt;
  final String text;
  final MessageFormat? format;
  final String? model;
  final String? provider;
  final String? error;
  final JsonMap? structuredOutput;
  final String? parentMessageId;
  final bool summary;
  final String? variant;

  JsonMap toJson() => {
        'id': id,
        'sessionId': sessionId,
        'role': role.name,
        'agent': agent,
        'createdAt': createdAt,
        'text': text,
        'format': format?.toJson(),
        'model': model,
        'provider': provider,
        'error': error,
        'structuredOutput': structuredOutput,
        'parentMessageId': parentMessageId,
        'summary': summary,
        'variant': variant,
      };

  factory MessageInfo.fromJson(JsonMap json) => MessageInfo(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        role:
            SessionRole.values.firstWhere((item) => item.name == json['role']),
        agent: json['agent'] as String,
        createdAt: json['createdAt'] as int,
        text: (json['text'] as String?) ?? '',
        format: json['format'] == null
            ? null
            : MessageFormat.fromJson(
                Map<String, dynamic>.from(json['format'] as Map)),
        model: json['model'] as String?,
        provider: json['provider'] as String?,
        error: json['error'] as String?,
        structuredOutput: json['structuredOutput'] == null
            ? null
            : Map<String, dynamic>.from(json['structuredOutput'] as Map),
        parentMessageId: json['parentMessageId'] as String?,
        summary: (json['summary'] as bool?) ?? false,
        variant: json['variant'] as String?,
      );
}

class MessagePart {
  MessagePart({
    required this.id,
    required this.sessionId,
    required this.messageId,
    required this.type,
    required this.createdAt,
    required this.data,
  });

  final String id;
  final String sessionId;
  final String messageId;
  final PartType type;
  final int createdAt;
  final JsonMap data;

  JsonMap toJson() => {
        'id': id,
        'sessionId': sessionId,
        'messageId': messageId,
        'type': type.name,
        'createdAt': createdAt,
        'data': data,
      };

  factory MessagePart.fromJson(JsonMap json) => MessagePart(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        messageId: json['messageId'] as String,
        type: PartType.values.firstWhere((item) => item.name == json['type']),
        createdAt: json['createdAt'] as int,
        data: Map<String, dynamic>.from(json['data'] as Map),
      );
}
