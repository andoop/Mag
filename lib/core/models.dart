import 'dart:convert';

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
        label: json['label'] as String,
        description: json['description'] as String,
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
        question: json['question'] as String,
        header: json['header'] as String,
        options: (json['options'] as List)
            .map((item) =>
                QuestionOption.fromJson(Map<String, dynamic>.from(item as Map)))
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

  factory QuestionRequest.fromJson(JsonMap json) => QuestionRequest(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        questions: (json['questions'] as List)
            .map((item) =>
                QuestionInfo.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        messageId: json['messageId'] as String?,
        callId: json['callId'] as String?,
      );
}

class TodoItem {
  TodoItem({
    required this.id,
    required this.sessionId,
    required this.content,
    required this.status,
    this.priority = 'medium',
  });

  final String id;
  final String sessionId;
  final String content;
  final String status;
  final String priority;

  JsonMap toJson() => {
        'id': id,
        'sessionId': sessionId,
        'content': content,
        'status': status,
        'priority': priority,
      };

  factory TodoItem.fromJson(JsonMap json) => TodoItem(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        content: json['content'] as String,
        status: json['status'] as String,
        priority: (json['priority'] as String?) ?? 'medium',
      );
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

class ModelConfig {
  ModelConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.provider = 'openai_compatible',
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final String provider;

  static const String _defaultMagBaseUrl = 'https://opencode.ai/zen/v1';
  static const String _defaultMagModel = 'minimax-m2.5-free';

  factory ModelConfig.defaults() => ModelConfig(
        baseUrl: _defaultMagBaseUrl,
        apiKey: '',
        model: _defaultMagModel,
        provider: 'mag',
      );

  bool get isMagProvider => provider.toLowerCase().startsWith('mag');

  /// Mag Zen 免费档：与 OpenCode 一致使用公共 token，无需用户 API Key。
  /// 见 `opencode` provider 在无密钥时对 `cost.input == 0` 模型使用 `apiKey: "public"`。
  bool get isMagZenFreeModel {
    if (!isMagProvider) return false;
    final m = model.trim().toLowerCase();
    if (m.endsWith('-free')) return true;
    if (m == 'big-pickle') return true;
    return false;
  }

  /// 本次请求是否走 `Bearer public`（空密钥或免费模型）。
  bool get usesMagPublicToken =>
      isMagProvider && (apiKey.trim().isEmpty || isMagZenFreeModel);

  JsonMap toJson() => {
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'provider': provider,
      };

  factory ModelConfig.fromJson(JsonMap json) {
    var baseUrl = (json['baseUrl'] as String?) ?? _defaultMagBaseUrl;
    final apiKey = (json['apiKey'] as String?) ?? '';
    var model = (json['model'] as String?) ?? _defaultMagModel;
    var provider = (json['provider'] as String?) ?? 'mag';
    final lowerP = provider.toLowerCase();
    if (lowerP.startsWith('opencode')) {
      provider = 'mag${provider.substring('opencode'.length)}';
    }

    if (provider.toLowerCase().startsWith('mag')) {
      final normalizedBaseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      if (normalizedBaseUrl == 'https://opencode.ai' ||
          !normalizedBaseUrl.contains('/zen/v1')) {
        baseUrl = _defaultMagBaseUrl;
      }
      if (model.trim().isEmpty || model == 'mag/free') {
        model = _defaultMagModel;
      }
    }

    return ModelConfig(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      provider: provider,
    );
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
