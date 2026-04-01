import 'dart:convert';

import 'json_coerce.dart';

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

class WorkspaceInfo {
  WorkspaceInfo({
    required this.id,
    required this.name,
    required this.treeUri,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String treeUri;
  final int createdAt;

  JsonMap toJson() => {
        'id': id,
        'name': name,
        'treeUri': treeUri,
        'createdAt': createdAt,
      };

  factory WorkspaceInfo.fromJson(JsonMap json) => WorkspaceInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        treeUri: json['treeUri'] as String,
        createdAt: json['createdAt'] as int,
      );
}

class ProjectInfo {
  ProjectInfo({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String workspaceId;
  final String name;
  final int createdAt;

  JsonMap toJson() => {
        'id': id,
        'workspaceId': workspaceId,
        'name': name,
        'createdAt': createdAt,
      };

  factory ProjectInfo.fromJson(JsonMap json) => ProjectInfo(
        id: json['id'] as String,
        workspaceId: json['workspaceId'] as String,
        name: json['name'] as String,
        createdAt: json['createdAt'] as int,
      );
}

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
    this.native = true,
    this.hidden = false,
    this.steps = 8,
    this.promptOverride,
  });

  final String name;
  final String description;
  final AgentMode mode;
  final bool native;
  final bool hidden;
  final int steps;
  final String? promptOverride;
  final List<PermissionRule> permissionRules;
  final List<String> availableTools;

  JsonMap toJson() => {
        'name': name,
        'description': description,
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
        mode: AgentMode.values.firstWhere((item) => item.name == json['mode']),
        native: (json['native'] as bool?) ?? true,
        hidden: (json['hidden'] as bool?) ?? false,
        steps: (json['steps'] as int?) ?? 8,
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

class ToolCall {
  ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final JsonMap arguments;

  JsonMap toJson() => {
        'id': id,
        'name': name,
        'arguments': arguments,
      };

  factory ToolCall.fromJson(JsonMap json) => ToolCall(
        id: json['id'] as String,
        name: json['name'] as String,
        arguments: Map<String, dynamic>.from(
            json['arguments'] as Map? ?? <String, dynamic>{}),
      );
}

class ToolDefinitionModel {
  ToolDefinitionModel({
    required this.id,
    required this.description,
    required this.parameters,
  });

  final String id;
  final String description;
  final JsonMap parameters;

  JsonMap toJson() => {
        'id': id,
        'description': description,
        'parameters': parameters,
      };
}

class ToolExecutionResult {
  ToolExecutionResult({
    required this.title,
    required this.output,
    this.displayOutput,
    JsonMap? metadata,
    List<JsonMap>? attachments,
  })  : metadata = metadata ?? <String, dynamic>{},
        attachments = attachments ?? const [];

  final String title;
  final String output;
  final String? displayOutput;
  final JsonMap metadata;
  final List<JsonMap> attachments;

  JsonMap toJson() => {
        'title': title,
        'output': output,
        'displayOutput': displayOutput,
        'metadata': metadata,
        'attachments': attachments,
      };
}

enum ModelVisibility { show, hide }

class ProviderModelCost {
  const ProviderModelCost({
    this.input = 0,
    this.output = 0,
  });

  final double input;
  final double output;

  JsonMap toJson() => {
        'input': input,
        'output': output,
      };

  factory ProviderModelCost.fromJson(JsonMap json) => ProviderModelCost(
        input: (json['input'] as num?)?.toDouble() ?? 0,
        output: (json['output'] as num?)?.toDouble() ?? 0,
      );
}

class ProviderModelLimit {
  const ProviderModelLimit({
    this.context = 0,
    this.input,
    this.output = 0,
  });

  final int context;
  final int? input;
  final int output;

  JsonMap toJson() => {
        'context': context,
        if (input != null) 'input': input,
        'output': output,
      };

  factory ProviderModelLimit.fromJson(JsonMap json) => ProviderModelLimit(
        context: (json['context'] as num?)?.toInt() ?? 0,
        input: (json['input'] as num?)?.toInt(),
        output: (json['output'] as num?)?.toInt() ?? 0,
      );
}

class ProviderModelInfo {
  const ProviderModelInfo({
    required this.id,
    required this.name,
    this.family,
    this.releaseDate = '',
    this.status = 'active',
    this.cost = const ProviderModelCost(),
    this.limit = const ProviderModelLimit(),
  });

  final String id;
  final String name;
  final String? family;
  final String releaseDate;
  final String status;
  final ProviderModelCost cost;
  final ProviderModelLimit limit;

  bool get isDeprecated => status == 'deprecated';

  ProviderModelInfo copyWith({
    String? id,
    String? name,
    Object? family = _unset,
    String? releaseDate,
    String? status,
    ProviderModelCost? cost,
    ProviderModelLimit? limit,
  }) {
    return ProviderModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      family: identical(family, _unset) ? this.family : family as String?,
      releaseDate: releaseDate ?? this.releaseDate,
      status: status ?? this.status,
      cost: cost ?? this.cost,
      limit: limit ?? this.limit,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'name': name,
        if (family != null) 'family': family,
        'release_date': releaseDate,
        'status': status,
        'cost': cost.toJson(),
        'limit': limit.toJson(),
      };

  factory ProviderModelInfo.fromJson(JsonMap json) => ProviderModelInfo(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? (json['id'] as String? ?? ''),
        family: json['family'] as String?,
        releaseDate: (json['release_date'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'active',
        cost: ProviderModelCost.fromJson(
          Map<String, dynamic>.from(json['cost'] as Map? ?? const {}),
        ),
        limit: ProviderModelLimit.fromJson(
          Map<String, dynamic>.from(json['limit'] as Map? ?? const {}),
        ),
      );

  factory ProviderModelInfo.fromModelsDevJson(JsonMap json) =>
      ProviderModelInfo(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? (json['id'] as String? ?? ''),
        family: json['family'] as String?,
        releaseDate: (json['release_date'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'active',
        cost: ProviderModelCost.fromJson(
          Map<String, dynamic>.from(json['cost'] as Map? ?? const {}),
        ),
        limit: ProviderModelLimit.fromJson(
          Map<String, dynamic>.from(json['limit'] as Map? ?? const {}),
        ),
      );
}

class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    required this.models,
    this.api,
    this.env = const [],
    this.custom = false,
    this.connected = false,
  });

  final String id;
  final String name;
  final String? api;
  final List<String> env;
  final Map<String, ProviderModelInfo> models;
  final bool custom;
  final bool connected;

  ProviderInfo copyWith({
    String? id,
    String? name,
    Object? api = _unset,
    List<String>? env,
    Map<String, ProviderModelInfo>? models,
    bool? custom,
    bool? connected,
  }) {
    return ProviderInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      api: identical(api, _unset) ? this.api : api as String?,
      env: env ?? this.env,
      models: models ?? this.models,
      custom: custom ?? this.custom,
      connected: connected ?? this.connected,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'name': name,
        if (api != null) 'api': api,
        'env': env,
        'models': models.map((key, value) => MapEntry(key, value.toJson())),
        'custom': custom,
        'connected': connected,
      };

  factory ProviderInfo.fromJson(JsonMap json) {
    final rawModels = Map<String, dynamic>.from(
      json['models'] as Map? ?? const {},
    );
    return ProviderInfo(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? (json['id'] as String? ?? ''),
      api: json['api'] as String?,
      env: (json['env'] as List? ?? const []).map((item) => item.toString()).toList(),
      models: rawModels.map(
        (key, value) => MapEntry(
          key,
          ProviderModelInfo.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      custom: (json['custom'] as bool?) ?? false,
      connected: (json['connected'] as bool?) ?? false,
    );
  }

  factory ProviderInfo.fromModelsDevJson(String id, JsonMap json) {
    final rawModels = Map<String, dynamic>.from(
      json['models'] as Map? ?? const {},
    );
    return ProviderInfo(
      id: id,
      name: (json['name'] as String?) ?? id,
      api: json['api'] as String?,
      env: (json['env'] as List? ?? const []).map((item) => item.toString()).toList(),
      models: rawModels.map(
        (key, value) => MapEntry(
          key,
          ProviderModelInfo.fromModelsDevJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
    );
  }
}

const Object _unset = Object();

class ProviderListResponse {
  const ProviderListResponse({
    required this.all,
    required this.connected,
    required this.defaultModels,
  });

  final List<ProviderInfo> all;
  final List<String> connected;
  final Map<String, String> defaultModels;

  JsonMap toJson() => {
        'all': all.map((item) => item.toJson()).toList(),
        'connected': connected,
        'default': defaultModels,
      };

  factory ProviderListResponse.fromJson(JsonMap json) => ProviderListResponse(
        all: (json['all'] as List? ?? const [])
            .map((item) => ProviderInfo.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        connected:
            (json['connected'] as List? ?? const []).map((item) => item.toString()).toList(),
        defaultModels: Map<String, String>.from(
          json['default'] as Map? ?? const <String, String>{},
        ),
      );
}

class ProviderAuthPromptCondition {
  const ProviderAuthPromptCondition({
    required this.key,
    required this.op,
    required this.value,
  });

  final String key;
  final String op;
  final String value;

  JsonMap toJson() => {
        'key': key,
        'op': op,
        'value': value,
      };

  factory ProviderAuthPromptCondition.fromJson(JsonMap json) =>
      ProviderAuthPromptCondition(
        key: (json['key'] as String?) ?? '',
        op: (json['op'] as String?) ?? 'eq',
        value: (json['value'] as String?) ?? '',
      );
}

class ProviderAuthPromptOption {
  const ProviderAuthPromptOption({
    required this.label,
    required this.value,
    this.hint,
  });

  final String label;
  final String value;
  final String? hint;

  JsonMap toJson() => {
        'label': label,
        'value': value,
        if (hint != null) 'hint': hint,
      };

  factory ProviderAuthPromptOption.fromJson(JsonMap json) =>
      ProviderAuthPromptOption(
        label: (json['label'] as String?) ?? '',
        value: (json['value'] as String?) ?? '',
        hint: json['hint'] as String?,
      );
}

class ProviderAuthPrompt {
  const ProviderAuthPrompt({
    required this.type,
    required this.key,
    required this.message,
    this.placeholder,
    this.options = const [],
    this.when,
  });

  final String type;
  final String key;
  final String message;
  final String? placeholder;
  final List<ProviderAuthPromptOption> options;
  final ProviderAuthPromptCondition? when;

  bool get isText => type == 'text';

  JsonMap toJson() => {
        'type': type,
        'key': key,
        'message': message,
        if (placeholder != null) 'placeholder': placeholder,
        if (options.isNotEmpty) 'options': options.map((item) => item.toJson()).toList(),
        if (when != null) 'when': when!.toJson(),
      };

  factory ProviderAuthPrompt.fromJson(JsonMap json) => ProviderAuthPrompt(
        type: (json['type'] as String?) ?? 'text',
        key: (json['key'] as String?) ?? '',
        message: (json['message'] as String?) ?? '',
        placeholder: json['placeholder'] as String?,
        options: (json['options'] as List? ?? const [])
            .map(
              (item) => ProviderAuthPromptOption.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
        when: json['when'] == null
            ? null
            : ProviderAuthPromptCondition.fromJson(
                Map<String, dynamic>.from(json['when'] as Map),
              ),
      );
}

class ProviderAuthMethod {
  const ProviderAuthMethod({
    required this.type,
    required this.label,
    this.prompts = const [],
  });

  final String type;
  final String label;
  final List<ProviderAuthPrompt> prompts;

  bool get isApi => type == 'api';
  bool get isOauth => type == 'oauth';

  JsonMap toJson() => {
        'type': type,
        'label': label,
        if (prompts.isNotEmpty) 'prompts': prompts.map((item) => item.toJson()).toList(),
      };

  factory ProviderAuthMethod.fromJson(JsonMap json) => ProviderAuthMethod(
        type: (json['type'] as String?) ?? 'api',
        label: (json['label'] as String?) ?? '',
        prompts: (json['prompts'] as List? ?? const [])
            .map(
              (item) => ProviderAuthPrompt.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(),
      );
}

class ProviderAuthAuthorization {
  const ProviderAuthAuthorization({
    required this.url,
    required this.method,
    required this.instructions,
  });

  final String url;
  final String method;
  final String instructions;

  bool get isCode => method == 'code';
  bool get isAuto => method == 'auto';

  JsonMap toJson() => {
        'url': url,
        'method': method,
        'instructions': instructions,
      };

  factory ProviderAuthAuthorization.fromJson(JsonMap json) =>
      ProviderAuthAuthorization(
        url: (json['url'] as String?) ?? '',
        method: (json['method'] as String?) ?? 'auto',
        instructions: (json['instructions'] as String?) ?? '',
      );
}

Map<String, List<ProviderAuthMethod>> providerAuthMethodsFromJson(JsonMap json) {
  return json.map(
    (key, value) => MapEntry(
      key,
      (value as List? ?? const [])
          .map(
            (item) => ProviderAuthMethod.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
    ),
  );
}

JsonMap providerAuthMethodsToJson(Map<String, List<ProviderAuthMethod>> methods) {
  return methods.map(
    (key, value) => MapEntry(
      key,
      value.map((item) => item.toJson()).toList(),
    ),
  );
}

List<ProviderInfo> normalizeProviderCatalog(List<ProviderInfo> input) {
  return input.map((provider) {
    final models = provider.models
      ..removeWhere((_, model) => model.isDeprecated);
    return provider.copyWith(models: Map<String, ProviderModelInfo>.from(models));
  }).toList();
}

const List<String> _providerSortPriority = [
  'gpt-5',
  'claude-sonnet-4',
  'big-pickle',
  'gemini-3-pro',
];

List<ProviderModelInfo> sortProviderModels(Iterable<ProviderModelInfo> models) {
  final list = models.toList();
  int priorityRank(String id) {
    for (var i = 0; i < _providerSortPriority.length; i++) {
      if (id.contains(_providerSortPriority[i])) {
        return i;
      }
    }
    return _providerSortPriority.length + 1;
  }

  list.sort((a, b) {
    final aRank = priorityRank(a.id);
    final bRank = priorityRank(b.id);
    if (aRank != bRank) return aRank.compareTo(bRank);
    final aLatest = a.id.contains('latest') ? 0 : 1;
    final bLatest = b.id.contains('latest') ? 0 : 1;
    if (aLatest != bLatest) return aLatest.compareTo(bLatest);
    return b.id.compareTo(a.id);
  });
  return list;
}

String? defaultModelIdForProvider(ProviderInfo provider) {
  final sorted = sortProviderModels(provider.models.values);
  if (sorted.isEmpty) return null;
  return sorted.first.id;
}

List<ProviderInfo> fallbackProviderCatalog() {
  final ids = [
    'mag',
    'anthropic',
    'openai',
    'google',
    'openrouter',
    'vercel',
    'deepseek',
    'github_models',
    'groq',
    'mistral',
    'ollama',
    'xai',
    'openai_compatible',
  ];
  return ids
      .map(
        (id) => ProviderInfo(
          id: id,
          name: id == 'github_models'
              ? 'GitHub Models'
              : id == 'openai_compatible'
                  ? 'OpenAI Compatible'
                  : id == 'xai'
                      ? 'xAI'
                      : '${id[0].toUpperCase()}${id.substring(1)}',
          api: _defaultBaseUrlForProvider(id),
          env: const [],
          models: id == 'mag'
              ? {
                  for (final item in _defaultConnectedModelsForProvider('mag'))
                    item: ProviderModelInfo(
                      id: item,
                      name: item,
                      cost: const ProviderModelCost(input: 0, output: 0),
                    ),
                }
              : const {},
        ),
      )
      .toList();
}

class ProviderConnection {
  ProviderConnection({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.models,
    this.custom = false,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final bool custom;

  ProviderConnection copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    List<String>? models,
    bool? custom,
  }) {
    return ProviderConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      custom: custom ?? this.custom,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'models': models,
        'custom': custom,
      };

  factory ProviderConnection.fromJson(JsonMap json) {
    final id = (json['id'] as String?) ?? 'mag';
    var models = (json['models'] as List? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
    if (id == 'mag') {
      models = filterMagZenFreeModels(models);
      if (models.isEmpty) {
        models = _defaultConnectedModelsForProvider('mag');
      }
    }
    return ProviderConnection(
      id: id,
      name: (json['name'] as String?) ?? 'Mag',
      baseUrl: (json['baseUrl'] as String?) ?? _defaultBaseUrlForProvider('mag'),
      apiKey: (json['apiKey'] as String?) ?? '',
      models: models,
      custom: (json['custom'] as bool?) ?? false,
    );
  }
}

class ModelVisibilityRule {
  ModelVisibilityRule({
    required this.providerId,
    required this.modelId,
    required this.visibility,
  });

  final String providerId;
  final String modelId;
  final ModelVisibility visibility;

  String get key => '$providerId/$modelId';

  JsonMap toJson() => {
        'providerId': providerId,
        'modelId': modelId,
        'visibility': visibility.name,
      };

  factory ModelVisibilityRule.fromJson(JsonMap json) {
    final raw = (json['visibility'] as String?) ?? ModelVisibility.show.name;
    return ModelVisibilityRule(
      providerId: (json['providerId'] as String?) ?? '',
      modelId: (json['modelId'] as String?) ?? '',
      visibility:
          raw == ModelVisibility.hide.name ? ModelVisibility.hide : ModelVisibility.show,
    );
  }
}

String _defaultBaseUrlForProvider(String providerId) {
  switch (providerId) {
    case 'anthropic':
      return 'https://api.anthropic.com/v1';
    case 'deepseek':
      return 'https://api.deepseek.com/v1';
    case 'google':
      return 'https://generativelanguage.googleapis.com/v1beta/openai';
    case 'mag':
      return 'https://opencode.ai/zen/v1';
    case 'groq':
      return 'https://api.groq.com/openai/v1';
    case 'mistral':
      return 'https://api.mistral.ai/v1';
    case 'ollama':
      return 'http://localhost:11434/v1';
    case 'openrouter':
      return 'https://openrouter.ai/api/v1';
    case 'openai':
      return 'https://api.openai.com/v1';
    case 'github_models':
      return 'https://models.github.ai/inference';
    case 'vercel':
      return 'https://ai-gateway.vercel.sh/v1';
    case 'xai':
      return 'https://api.x.ai/v1';
    case 'openai_compatible':
      return 'https://api.openai.com/v1';
    default:
      return 'https://api.openai.com/v1';
  }
}

List<String> _defaultConnectedModelsForProvider(String providerId) {
  switch (providerId) {
    case 'mag':
      return const [
        'minimax-m2.5-free',
        'mimo-v2-pro-free',
        'mimo-v2-omni-free',
        'nemotron-3-super-free',
        'big-pickle',
      ];
    default:
      return const [];
  }
}

/// Mag Zen 免费模型：`-free` 后缀或 `big-pickle`（与 [ModelConfig.isMagZenFreeModel] 一致）。
bool isMagZenFreeModelId(String modelId) {
  final m = modelId.trim().toLowerCase();
  if (m.endsWith('-free')) return true;
  if (m == 'big-pickle') return true;
  return false;
}

List<String> filterMagZenFreeModels(Iterable<String> models) {
  final filtered =
      models.map((e) => e.trim()).where(isMagZenFreeModelId).toList();
  filtered.sort();
  return filtered;
}

/// Mag 连接里只保留免费模型；当前选中非免费时回退到默认免费模型。
ModelConfig normalizeMagFreeModelsOnly(ModelConfig config) {
  final nextConnections = config.connections.map((c) {
    if (c.id != 'mag') return c;
    final m = filterMagZenFreeModels(c.models);
    return c.copyWith(
      models: m.isEmpty ? _defaultConnectedModelsForProvider('mag') : m,
    );
  }).toList();
  var modelId = config.currentModelId;
  if (config.currentProviderId == 'mag' && !isMagZenFreeModelId(modelId)) {
    modelId = _defaultConnectedModelsForProvider('mag').first;
  }
  return config.copyWith(
    connections: nextConnections,
    currentModelId: modelId,
  );
}

class ModelConfig {
  ModelConfig({
    required this.currentProviderId,
    required this.currentModelId,
    required this.connections,
    required this.visibilityRules,
  });

  final String currentProviderId;
  final String currentModelId;
  final List<ProviderConnection> connections;
  final List<ModelVisibilityRule> visibilityRules;

  static const String _defaultMagBaseUrl = 'https://opencode.ai/zen/v1';
  static const String _defaultMagModel = 'minimax-m2.5-free';

  factory ModelConfig.defaults() => ModelConfig(
        currentProviderId: 'mag',
        currentModelId: _defaultMagModel,
        connections: [
          ProviderConnection(
            id: 'mag',
            name: 'Mag',
            baseUrl: _defaultMagBaseUrl,
            apiKey: '',
            models: _defaultConnectedModelsForProvider('mag'),
          ),
        ],
        visibilityRules: const [],
      );

  String get provider => currentProviderId;
  String get model => currentModelId;

  ProviderConnection? get currentConnection {
    for (final item in connections) {
      if (item.id == currentProviderId) return item;
    }
    return null;
  }

  String get baseUrl => currentConnection?.baseUrl ?? _defaultMagBaseUrl;
  String get apiKey => currentConnection?.apiKey ?? '';

  List<String> get configuredProviderIds => connections.map((item) => item.id).toList();

  ProviderConnection? connectionFor(String providerId) {
    for (final item in connections) {
      if (item.id == providerId) return item;
    }
    return null;
  }

  ModelConfig copyWith({
    String? currentProviderId,
    String? currentModelId,
    List<ProviderConnection>? connections,
    List<ModelVisibilityRule>? visibilityRules,
  }) {
    return ModelConfig(
      currentProviderId: currentProviderId ?? this.currentProviderId,
      currentModelId: currentModelId ?? this.currentModelId,
      connections: connections ?? this.connections,
      visibilityRules: visibilityRules ?? this.visibilityRules,
    );
  }

  bool get isMagProvider => provider == 'mag';

  bool get isMagZenFreeModel {
    if (!isMagProvider) return false;
    final m = model.trim().toLowerCase();
    if (m.endsWith('-free')) return true;
    if (m == 'big-pickle') return true;
    return false;
  }

  bool get usesMagPublicToken =>
      isMagProvider && (apiKey.trim().isEmpty || isMagZenFreeModel);

  ModelVisibility? visibilityFor({
    required String providerId,
    required String modelId,
  }) {
    for (final item in visibilityRules) {
      if (item.providerId == providerId && item.modelId == modelId) {
        return item.visibility;
      }
    }
    return null;
  }

  JsonMap toJson() => {
        'currentProviderId': currentProviderId,
        'currentModelId': currentModelId,
        'connections': connections.map((item) => item.toJson()).toList(),
        'visibilityRules': visibilityRules.map((item) => item.toJson()).toList(),
      };

  factory ModelConfig.fromJson(JsonMap json) {
    if (json.containsKey('connections') || json.containsKey('currentProviderId')) {
      final connections = (json['connections'] as List? ?? const [])
          .map((item) => ProviderConnection.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList();
      final normalizedConnections =
          connections.isEmpty ? ModelConfig.defaults().connections : connections;
      final currentProviderId =
          (json['currentProviderId'] as String?) ?? normalizedConnections.first.id;
      final currentModelId = (json['currentModelId'] as String?) ?? _defaultMagModel;
      final visibilityRules = (json['visibilityRules'] as List? ?? const [])
          .map((item) =>
              ModelVisibilityRule.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      return normalizeMagFreeModelsOnly(ModelConfig(
        currentProviderId: currentProviderId,
        currentModelId: currentModelId,
        connections: normalizedConnections,
        visibilityRules: visibilityRules,
      ));
    }

    return normalizeMagFreeModelsOnly(ModelConfig.defaults());
  }
}

class WorkspaceEntry {
  WorkspaceEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.lastModified,
    required this.size,
    this.mimeType,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int lastModified;
  final int size;
  final String? mimeType;

  JsonMap toJson() => {
        'path': path,
        'name': name,
        'isDirectory': isDirectory,
        'lastModified': lastModified,
        'size': size,
        'mimeType': mimeType,
      };

  factory WorkspaceEntry.fromJson(JsonMap json) => WorkspaceEntry(
        path: json['path'] as String,
        name: json['name'] as String,
        isDirectory: json['isDirectory'] as bool,
        lastModified: (json['lastModified'] as int?) ?? 0,
        size: (json['size'] as int?) ?? 0,
        mimeType: json['mimeType'] as String?,
      );
}

class WorkspaceSearchEntry {
  WorkspaceSearchEntry({
    required this.path,
    required this.content,
  });

  final String path;
  final String content;

  JsonMap toJson() => {
        'path': path,
        'content': content,
      };

  factory WorkspaceSearchEntry.fromJson(JsonMap json) => WorkspaceSearchEntry(
        path: json['path'] as String,
        content: json['content'] as String,
      );
}

class ModelResponse {
  ModelResponse({
    required this.text,
    required this.toolCalls,
    required this.finishReason,
    required this.raw,
    this.usage = const ModelUsage(),
  });

  final String text;
  final List<ToolCall> toolCalls;
  final String finishReason;
  final JsonMap raw;
  final ModelUsage usage;
}

class ModelUsage {
  const ModelUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.reasoningTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int reasoningTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;

  int get promptTokens => inputTokens + cacheWriteTokens;
  int get completionTokens => outputTokens + cacheReadTokens;
  int get totalTokens => promptTokens + completionTokens;
  bool get isEmpty =>
      inputTokens == 0 &&
      outputTokens == 0 &&
      reasoningTokens == 0 &&
      cacheReadTokens == 0 &&
      cacheWriteTokens == 0;

  JsonMap toJson() => {
        'input': inputTokens,
        'output': outputTokens,
        'reasoning': reasoningTokens,
        'cache': {
          'read': cacheReadTokens,
          'write': cacheWriteTokens,
        },
      };
}

int inferContextWindow(String model) {
  final lower = model.toLowerCase();
  if (lower.contains('gemini')) return 1000000;
  if (lower.contains('gpt-4.1')) return 1047576;
  if (lower.contains('o1') || lower.contains('o3') || lower.contains('o4')) {
    return 200000;
  }
  if (lower.contains('claude')) return 200000;
  if (lower.contains('gpt-4o')) return 128000;
  if (lower.contains('gpt-4')) return 128000;
  if (lower.contains('deepseek-reasoner')) return 65536;
  if (lower.contains('deepseek')) return 65536;
  if (lower.contains('minimax')) return 1000000;
  return 128000;
}

String formatTokenCount(int tokens) {
  if (tokens >= 1000000) {
    final value =
        (tokens / 1000000).toStringAsFixed(tokens % 1000000 == 0 ? 0 : 1);
    return '${value}M';
  }
  if (tokens >= 1000) {
    final value = (tokens / 1000).toStringAsFixed(tokens % 1000 == 0 ? 0 : 1);
    return '${value}K';
  }
  return '$tokens';
}

class ServerEvent {
  ServerEvent({
    required this.type,
    required this.properties,
    this.directory,
  });

  final String type;
  final JsonMap properties;
  final String? directory;

  JsonMap toJson() => {
        'type': type,
        'properties': properties,
        if (directory != null) 'directory': directory,
      };

  factory ServerEvent.fromJson(JsonMap json) => ServerEvent(
        type: json['type'] as String,
        properties: Map<String, dynamic>.from(
            json['properties'] as Map? ?? <String, dynamic>{}),
        directory: json['directory'] as String?,
      );

  String encode() => jsonEncode(toJson());
}
