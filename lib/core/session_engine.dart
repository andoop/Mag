import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'agents.dart';
import 'database.dart';
import 'debug_trace.dart';
import 'models.dart';
import 'prompt_system.dart';
import 'tool_runtime.dart';
import 'workspace_bridge.dart';

const bool _kDebugEngine = false;

void _debugLog(String tag, String message, [JsonMap? data]) {
  if (!_kDebugEngine) return;
  // ignore: avoid_print
  print(
      '[session-engine][$tag] $message${data != null ? ' ${jsonEncode(data)}' : ''}');
}

/// Dart equivalent of AbortSignal/AbortController from mag.
/// Threaded through prompt → model gateway → tool execution → permission/question waits.
class CancelToken {
  final Completer<Never> _completer = Completer<Never>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completer.completeError(CancelledException());
  }

  void throwIfCancelled() {
    if (_cancelled) throw CancelledException();
  }

  /// Race [future] against cancellation. Returns the result of [future]
  /// or throws [CancelledException] if cancelled first.
  Future<T> guard<T>(Future<T> future) {
    if (_cancelled) return Future.error(CancelledException());
    return Future.any<T>([future, _completer.future]);
  }
}

class CancelledException implements Exception {
  @override
  String toString() => 'Prompt was cancelled';
}

const int _retryInitialDelayMs = 2000;
const int _retryBackoffFactor = 2;
const int _retryMaxDelayMs = 30000;
const int _maxRetryAttempts = 5;

int _retryDelay(int attempt) {
  return math.min(
    _retryInitialDelayMs * math.pow(_retryBackoffFactor, attempt - 1).toInt(),
    _retryMaxDelayMs,
  );
}

bool _isRetryableError(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('429') || msg.contains('too many requests')) return true;
  if (msg.contains('overloaded') || msg.contains('rate limit')) return true;
  if (msg.contains('502') || msg.contains('503') || msg.contains('504')) {
    return true;
  }
  if (msg.contains('freeusagelimiterror')) return true;
  return false;
}

String _retryMessage(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('429') ||
      msg.contains('too many requests') ||
      msg.contains('rate limit')) {
    return 'Rate limited, retrying...';
  }
  if (msg.contains('overloaded')) return 'Provider overloaded, retrying...';
  if (msg.contains('freeusagelimiterror')) {
    return 'Free usage limit, retrying...';
  }
  return 'Temporary error, retrying...';
}

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

class LocalEventBus {
  final StreamController<ServerEvent> _events = StreamController.broadcast();

  Stream<ServerEvent> get stream => _events.stream;

  void emit(ServerEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  Future<void> close() => _events.close();
}

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

class ModelGateway {
  bool _usesAnthropicApi(ModelConfig config) => config.provider == 'anthropic';

  bool _usesGitHubModelsApi(ModelConfig config) =>
      config.provider == 'github_models';

  bool _allowsEmptyApiKey(ModelConfig config) =>
      config.provider == 'ollama' || config.isMagProvider;

  Map<String, dynamic> _buildOpenAiPayload({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
  }) {
    final payload = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'stream': true,
      'stream_options': {'include_usage': true},
      'tools': tools
          .map(
            (tool) => {
              'type': 'function',
              'function': {
                'name': tool.id,
                'description': tool.description,
                'parameters': tool.parameters,
              },
            },
          )
          .toList(),
    };
    if (format?.type == OutputFormatType.jsonSchema) {
      payload['tool_choice'] = {
        'type': 'function',
        'function': {'name': 'StructuredOutput'}
      };
    }
    return payload;
  }

  JsonMap _buildAnthropicPayload({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
  }) {
    final systemParts = <String>[];
    final conversation = <JsonMap>[];

    for (final message in messages) {
      final role = (message['role'] as String? ?? 'user').trim();
      if (role == 'system') {
        final text = _extractText(message['content']).trim();
        if (text.isNotEmpty) systemParts.add(text);
        continue;
      }
      if (role == 'tool') {
        final toolUseId = message['tool_call_id'] as String? ?? '';
        if (toolUseId.isEmpty) continue;
        conversation.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': toolUseId,
              'content': _extractText(message['content']),
            },
          ],
        });
        continue;
      }

      final blocks = <JsonMap>[];
      final text = _extractText(message['content']).trim();
      if (text.isNotEmpty) {
        blocks.add({'type': 'text', 'text': text});
      }
      if (role == 'assistant') {
        final toolCalls = (message['tool_calls'] as List?) ?? const [];
        for (final item in toolCalls) {
          final map = Map<String, dynamic>.from(item as Map);
          final function =
              Map<String, dynamic>.from(map['function'] as Map? ?? const {});
          blocks.add({
            'type': 'tool_use',
            'id': map['id'] as String? ?? newId('toolcall'),
            'name': function['name'] as String? ?? 'invalid',
            'input': _decodeArguments(
              function['arguments'] as String? ?? '{}',
            ),
          });
        }
      }
      if (blocks.isEmpty) continue;
      conversation.add({
        'role': role == 'assistant' ? 'assistant' : 'user',
        'content': blocks,
      });
    }

    final payload = <String, dynamic>{
      'model': config.model,
      'max_tokens': 4096,
      'messages': conversation,
    };
    if (systemParts.isNotEmpty) {
      payload['system'] = systemParts.join('\n\n');
    }
    if (tools.isNotEmpty) {
      payload['tools'] = tools
          .map(
            (tool) => {
              'name': tool.id,
              'description': tool.description,
              'input_schema': tool.parameters,
            },
          )
          .toList();
    }
    if (format?.type == OutputFormatType.jsonSchema) {
      payload['tool_choice'] = {
        'type': 'tool',
        'name': 'StructuredOutput',
      };
    }
    return payload;
  }

  Future<ModelResponse> _completeAnthropic({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final apiKey = config.apiKey.trim();
    if (apiKey.isEmpty) {
      throw Exception('Missing API key');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    if (cancelToken != null) {
      unawaited(cancelToken
          .guard(Completer<Never>().future)
          .then<void>((_) {})
          .catchError((_) {
        client.close(force: true);
      }));
    }
    final request = await client.postUrl(Uri.parse('${config.baseUrl}/messages'));
    request.headers.set('x-api-key', apiKey);
    request.headers.set('anthropic-version', '2023-06-01');
    request.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    final payload = _buildAnthropicPayload(
      config: config,
      messages: messages,
      tools: tools,
      format: format,
    );
    final encodedPayload = utf8.encode(jsonEncode(payload));
    request.contentLength = encodedPayload.length;
    request.add(encodedPayload);
    final response = await request.close();
    if (response.statusCode >= 400) {
      final body = await response.transform(utf8.decoder).join();
      client.close(force: true);
      throw Exception(
        _formatModelRequestError(
          statusCode: response.statusCode,
          body: body,
          isMagProvider: false,
          usesPublicToken: false,
          model: config.model,
        ),
      );
    }
    final body = await response.transform(utf8.decoder).join();
    client.close(force: true);
    final decoded = Map<String, dynamic>.from(jsonDecode(body) as Map);
    return _decodeAnthropicResponse(decoded);
  }

  Future<ModelResponse> _completeOpenAiCompatible({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
    CancelToken? cancelToken,
    FutureOr<void> Function(String delta)? onTextDelta,
    FutureOr<void> Function(String delta)? onReasoningDelta,
  }) async {
    cancelToken?.throwIfCancelled();
    final isMagProvider = config.isMagProvider;
    final usePublic = isMagProvider && config.usesMagPublicToken;
    final rawApiKey = config.apiKey.trim();
    final effectiveApiKey = usePublic ? 'public' : rawApiKey;
    _debugLog('gateway',
        'complete start provider=${config.provider} model=${config.model}');
    if (effectiveApiKey.isEmpty && !_allowsEmptyApiKey(config)) {
      throw Exception('Missing API key');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    if (cancelToken != null) {
      unawaited(cancelToken
          .guard(Completer<Never>().future)
          .then<void>((_) {})
          .catchError((_) {
        client.close(force: true);
      }));
    }
    final uri = Uri.parse('${config.baseUrl}/chat/completions');
    final request = await client.postUrl(uri);
    if (effectiveApiKey.isNotEmpty) {
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer $effectiveApiKey');
    }
    request.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    if (isMagProvider) {
      request.headers.set('HTTP-Referer', 'https://opencode.ai/');
      request.headers.set('X-Title', 'mag');
    }
    if (_usesGitHubModelsApi(config)) {
      request.headers.set('Accept', 'application/vnd.github+json');
      request.headers.set('X-GitHub-Api-Version', '2026-03-10');
    }
    final payload = _buildOpenAiPayload(
      config: config,
      messages: messages,
      tools: tools,
      format: format,
    );
    final encodedPayload = utf8.encode(jsonEncode(payload));
    request.contentLength = encodedPayload.length;
    request.add(encodedPayload);
    final response = await request.close();
    _debugLog('gateway', 'response status=${response.statusCode}');
    if (response.statusCode >= 400) {
      final body = await response.transform(utf8.decoder).join();
      client.close(force: true);
      throw Exception(
        _formatModelRequestError(
          statusCode: response.statusCode,
          body: body,
          isMagProvider: isMagProvider,
          usesPublicToken: usePublic,
          model: config.model,
        ),
      );
    }
    final mimeType = response.headers.contentType?.mimeType ?? '';
    if (mimeType != 'text/event-stream') {
      final body = await response.transform(utf8.decoder).join();
      client.close(force: true);
      return _decodeNonStreamingResponse(body);
    }

    final text = StringBuffer();
    final reasoning = StringBuffer();
    final toolBuffers = <int, _ToolCallBuffer>{};
    JsonMap lastChunk = <String, dynamic>{};
    var usage = const ModelUsage();
    var finishReason = 'stop';
    var eventCount = 0;

    final sseStream = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 90), onTimeout: (sink) {
      _debugLog('gateway', 'SSE idle timeout – closing stream');
      sink.close();
    });

    await for (final line in sseStream) {
      cancelToken?.throwIfCancelled();
      if (!line.startsWith('data: ')) continue;
      final payloadLine = line.substring(6).trim();
      if (payloadLine.isEmpty) continue;
      if (payloadLine == '[DONE]') break;
      eventCount++;
      if (eventCount == 1) {
        _debugLog('gateway', 'first SSE chunk');
      }
      final decoded = Map<String, dynamic>.from(jsonDecode(payloadLine) as Map);
      lastChunk = decoded;
      usage = _extractUsage(decoded, fallback: usage);
      final choices = (decoded['choices'] as List?) ?? const [];
      if (choices.isEmpty) continue;
      final choice = Map<String, dynamic>.from(choices.first as Map);
      finishReason = choice['finish_reason'] as String? ?? finishReason;
      final delta =
          Map<String, dynamic>.from(choice['delta'] as Map? ?? const {});

      final textDelta = _extractText(delta['content']);
      if (textDelta.isNotEmpty) {
        text.write(textDelta);
        if (onTextDelta != null) {
          await onTextDelta(textDelta);
        }
      }

      final reasoningDelta = _extractReasoning(delta);
      if (reasoningDelta.isNotEmpty) {
        reasoning.write(reasoningDelta);
        if (onReasoningDelta != null) {
          await onReasoningDelta(reasoningDelta);
        }
      }

      final toolCalls = (delta['tool_calls'] as List?) ?? const [];
      for (final item in toolCalls) {
        final map = Map<String, dynamic>.from(item as Map);
        final index = (map['index'] as int?) ?? 0;
        final buffer = toolBuffers.putIfAbsent(index, () => _ToolCallBuffer());
        buffer.id = map['id'] as String? ?? buffer.id;
        final function =
            Map<String, dynamic>.from(map['function'] as Map? ?? const {});
        buffer.name = function['name'] as String? ?? buffer.name;
        final args = function['arguments'] as String? ?? '';
        if (args.isNotEmpty) {
          buffer.arguments.write(args);
        }
      }

      if (choice['finish_reason'] != null) break;
    }
    client.close(force: true);
    _debugLog('gateway',
        'complete end events=$eventCount tools=${toolBuffers.length}');

    final toolCalls = toolBuffers.entries.map((entry) {
      final buffer = entry.value;
      return ToolCall(
        id: buffer.id ?? newId('toolcall'),
        name: buffer.name ?? 'invalid',
        arguments: _decodeArguments(buffer.arguments.toString()),
      );
    }).toList();

    return ModelResponse(
      text: text.toString(),
      toolCalls: toolCalls,
      finishReason: finishReason,
      raw: lastChunk,
      usage: usage,
    );
  }

  Future<ModelResponse> complete({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
    CancelToken? cancelToken,
    FutureOr<void> Function(String delta)? onTextDelta,
    FutureOr<void> Function(String delta)? onReasoningDelta,
  }) async {
    if (_usesAnthropicApi(config)) {
      return _completeAnthropic(
        config: config,
        messages: messages,
        tools: tools,
        format: format,
        cancelToken: cancelToken,
      );
    }
    return _completeOpenAiCompatible(
      config: config,
      messages: messages,
      tools: tools,
      format: format,
      cancelToken: cancelToken,
      onTextDelta: onTextDelta,
      onReasoningDelta: onReasoningDelta,
    );
  }

  ModelResponse _decodeAnthropicResponse(JsonMap decoded) {
    final content = (decoded['content'] as List? ?? const []);
    final text = StringBuffer();
    final toolCalls = <ToolCall>[];
    for (final item in content) {
      final block = Map<String, dynamic>.from(item as Map);
      final type = block['type'] as String? ?? '';
      if (type == 'text') {
        text.write(block['text'] as String? ?? '');
        continue;
      }
      if (type == 'tool_use') {
        toolCalls.add(ToolCall(
          id: block['id'] as String? ?? newId('toolcall'),
          name: block['name'] as String? ?? 'invalid',
          arguments: Map<String, dynamic>.from(
            block['input'] as Map? ?? const {},
          ),
        ));
      }
    }
    return ModelResponse(
      text: text.toString(),
      toolCalls: toolCalls,
      finishReason: decoded['stop_reason'] as String? ?? 'stop',
      raw: decoded,
      usage: _extractUsage(decoded),
    );
  }

  ModelResponse _decodeNonStreamingResponse(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final choice = (decoded['choices'] as List).first as Map<String, dynamic>;
    final message = Map<String, dynamic>.from(choice['message'] as Map);
    final content = _extractText(message['content']);
    final rawToolCalls = (message['tool_calls'] as List?) ?? const [];
    final toolCalls = rawToolCalls.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      final function =
          Map<String, dynamic>.from(map['function'] as Map? ?? const {});
      final rawArguments = function['arguments'] as String? ?? '{}';
      return ToolCall(
        id: map['id'] as String? ?? newId('toolcall'),
        name: function['name'] as String? ?? 'invalid',
        arguments: _decodeArguments(rawArguments),
      );
    }).toList();
    return ModelResponse(
      text: content,
      toolCalls: toolCalls,
      finishReason: choice['finish_reason'] as String? ?? 'stop',
      raw: decoded,
      usage: _extractUsage(decoded),
    );
  }

  JsonMap _decodeArguments(String input) {
    try {
      return Map<String, dynamic>.from(jsonDecode(input) as Map);
    } catch (_) {
      return {'raw': input};
    }
  }

  String _extractText(dynamic content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List) {
      return content
          .map((item) => item is Map ? item['text'] ?? '' : '')
          .whereType<String>()
          .join();
    }
    return content.toString();
  }

  String _extractReasoning(JsonMap delta) {
    final direct = delta['reasoning_content'] ?? delta['reasoning'];
    if (direct is String) return direct;
    if (direct is List) {
      return direct
          .map((item) => item is Map ? item['text'] ?? '' : '')
          .whereType<String>()
          .join();
    }
    final content = delta['content'];
    if (content is List) {
      return content
          .map((item) => item is Map && '${item['type']}'.contains('reason')
              ? item['text'] ?? ''
              : '')
          .whereType<String>()
          .join();
    }
    return '';
  }

  ModelUsage _extractUsage(
    JsonMap payload, {
    ModelUsage fallback = const ModelUsage(),
  }) {
    final usage =
        Map<String, dynamic>.from(payload['usage'] as Map? ?? const {});
    if (usage.isEmpty) return fallback;
    final promptTokens = (usage['prompt_tokens'] as num?)?.toInt() ??
        (usage['input_tokens'] as num?)?.toInt() ??
        0;
    final completionTokens = (usage['completion_tokens'] as num?)?.toInt() ??
        (usage['output_tokens'] as num?)?.toInt() ??
        0;
    final promptDetails = Map<String, dynamic>.from(
        usage['prompt_tokens_details'] as Map? ??
            usage['input_tokens_details'] as Map? ??
            const {});
    final completionDetails = Map<String, dynamic>.from(
        usage['completion_tokens_details'] as Map? ??
            usage['output_tokens_details'] as Map? ??
            const {});
    final cacheRead = (promptDetails['cached_tokens'] as num?)?.toInt() ??
        (usage['cache_read_tokens'] as num?)?.toInt() ??
        0;
    final cacheWrite =
        (promptDetails['cache_creation_tokens'] as num?)?.toInt() ??
            (usage['cache_write_tokens'] as num?)?.toInt() ??
            0;
    final reasoningTokens =
        (completionDetails['reasoning_tokens'] as num?)?.toInt() ??
            (usage['reasoning_tokens'] as num?)?.toInt() ??
            0;
    return ModelUsage(
      inputTokens: math.max(0, promptTokens - cacheRead),
      outputTokens: completionTokens,
      reasoningTokens: reasoningTokens,
      cacheReadTokens: cacheRead,
      cacheWriteTokens: cacheWrite,
    );
  }

  String _formatModelRequestError({
    required int statusCode,
    required String body,
    required bool isMagProvider,
    required bool usesPublicToken,
    required String model,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final type = error['type'] as String?;
          final message = error['message'] as String?;
          if (isMagProvider &&
              usesPublicToken &&
              type == 'FreeUsageLimitError') {
            return 'Mag 免费模型当前限流，请稍后再试，或切换其他免费模型/配置你自己的 API Key。当前模型：$model';
          }
          if (message != null && message.trim().isNotEmpty) {
            return 'Model request failed: $statusCode $message';
          }
        }
      }
    } catch (_) {}
    final compactBody = body.trim();
    final shortBody = compactBody.length > 240
        ? '${compactBody.substring(0, 240)}...'
        : compactBody;
    return 'Model request failed: $statusCode $shortBody';
  }
}

class _ToolCallBuffer {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

class SessionEngine {
  SessionEngine({
    required this.database,
    required this.events,
    required this.workspaceBridge,
    required this.promptAssembler,
    required this.permissionCenter,
    required this.questionCenter,
    required this.toolRegistry,
    required this.modelGateway,
  });

  final AppDatabase database;
  final LocalEventBus events;
  final WorkspaceBridge workspaceBridge;
  final PromptAssembler promptAssembler;
  final PermissionCenter permissionCenter;
  final QuestionCenter questionCenter;
  final ToolRegistry toolRegistry;
  final ModelGateway modelGateway;

  final Map<String, bool> _busy = {};
  final Map<String, CancelToken> _cancelTokens = {};

  AgentDefinition agentDefinition(String name) => AgentRegistry.resolve(name);

  List<AgentDefinition> listAgents() =>
      AgentRegistry.all().where((item) => !item.hidden).toList();

  Future<ProjectInfo> ensureProject(WorkspaceInfo workspace) async {
    final existing = await database.projectForWorkspace(workspace.id);
    if (existing != null) return existing;
    final project = ProjectInfo(
      id: newId('project'),
      workspaceId: workspace.id,
      name: workspace.name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await database.saveProject(project);
    return project;
  }

  Future<SessionInfo> createSession({
    required WorkspaceInfo workspace,
    String agent = 'build',
  }) async {
    final project = await ensureProject(workspace);
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = SessionInfo(
      id: newId('session'),
      projectId: project.id,
      workspaceId: workspace.id,
      title: 'New session',
      agent: agent,
      createdAt: now,
      updatedAt: now,
    );
    await _saveSession(workspace: workspace, session: session);
    return session;
  }

  Future<EngineSnapshot> snapshot(String sessionId) async {
    final messages = await database.listMessages(sessionId);
    final parts = await database.listPartsForSession(sessionId);
    final permissions = await database.listPermissionRequests();
    final questions = await database.listQuestionRequests();
    final todos = await database.listTodos(sessionId);
    return EngineSnapshot(
      messages: messages,
      parts: parts,
      permissions:
          permissions.where((item) => item.sessionId == sessionId).toList(),
      questions:
          questions.where((item) => item.sessionId == sessionId).toList(),
      todos: todos,
    );
  }

  /// Mirrors mag's `SessionPrompt.cancel()`.
  /// Aborts the cancel token, cleans up pending permissions/questions,
  /// and forces idle status.
  Future<void> cancel(String sessionId, {String? directory}) async {
    _debugLog('cancel', 'session=$sessionId');
    final token = _cancelTokens.remove(sessionId);
    token?.cancel();
    permissionCenter.cancelSession(sessionId);
    questionCenter.cancelSession(sessionId);
    _busy.remove(sessionId);
    events.emit(ServerEvent(
      type: 'session.status',
      properties: {'sessionID': sessionId, 'status': 'idle'},
      directory: directory,
    ));
  }

  /// Mirrors mag's fire-and-forget pattern in local_server prompt_async.
  Future<void> promptAsync({
    required WorkspaceInfo workspace,
    required SessionInfo session,
    required String text,
    String? agent,
    MessageFormat? format,
  }) {
    return prompt(
      workspace: workspace,
      session: session,
      text: text,
      agent: agent,
      format: format,
    ).then((_) {});
  }

  Future<void> prewarmWorkspaceContext(WorkspaceInfo workspace) {
    return promptAssembler.prewarmWorkspaceContext(workspace);
  }

  Future<SessionInfo> compactSession({
    required WorkspaceInfo workspace,
    required SessionInfo session,
  }) async {
    if (_busy[session.id] == true) {
      throw Exception('Session is already running');
    }
    final modelConfig = ModelConfig.fromJson(
      await database.getSetting('model_config') ??
          ModelConfig.defaults().toJson(),
    );
    final cancelToken = CancelToken();
    _cancelTokens[session.id] = cancelToken;
    _busy[session.id] = true;
    events.emit(ServerEvent(
      type: 'session.status',
      properties: {'sessionID': session.id, 'status': 'compacting'},
      directory: workspace.treeUri,
    ));
    try {
      return await summarize(
        workspace: workspace,
        session: session,
        modelConfig: modelConfig,
        currentAgent: session.agent,
      );
    } catch (error) {
      events.emit(ServerEvent(
        type: 'session.error',
        properties: {
          'sessionID': session.id,
          'message': error.toString(),
        },
        directory: workspace.treeUri,
      ));
      rethrow;
    } finally {
      _cancelTokens.remove(session.id);
      _busy.remove(session.id);
      events.emit(ServerEvent(
        type: 'session.status',
        properties: {'sessionID': session.id, 'status': 'idle'},
        directory: workspace.treeUri,
      ));
    }
  }

  /// Mirrors mag's `SessionPrompt.loop()` + `SessionProcessor.process()`.
  ///
  /// Key patterns from mag:
  /// - CancelToken (AbortSignal) threaded through everything
  /// - `defer(() => cancel(sessionId))` guarantees idle on any exit
  /// - Retry with exponential backoff for transient errors
  /// - Cleanup of incomplete tool parts on cancel/error
  Future<MessageInfo> prompt({
    required WorkspaceInfo workspace,
    required SessionInfo session,
    required String text,
    String? agent,
    MessageFormat? format,
  }) async {
    if (_busy[session.id] == true) {
      throw Exception('Session is already running');
    }
    final promptStartedAt = DateTime.now().millisecondsSinceEpoch;
    _debugLog('prompt',
        'start session=${session.id} agent=${agent ?? session.agent}');
    // #region agent log
    debugTrace(
      runId: 'prompt-pre',
      hypothesisId: 'H3',
      location: 'session_engine.dart:804',
      message: 'prompt started',
      data: {
        'sessionId': session.id,
        'agent': agent ?? session.agent,
        'textLength': text.length,
      },
    );
    // #endregion
    // Create cancel token (like mag's AbortController per session)
    final cancelToken = CancelToken();
    _cancelTokens[session.id] = cancelToken;
    _busy[session.id] = true;
    events.emit(ServerEvent(
      type: 'session.status',
      properties: {'sessionID': session.id, 'status': 'busy'},
      directory: workspace.treeUri,
    ));
    try {
      final modelConfig = ModelConfig.fromJson(
        await database.getSetting('model_config') ??
            ModelConfig.defaults().toJson(),
      );
      final cacheLoadStartedAt = DateTime.now().millisecondsSinceEpoch;
      final cachedMessages = await database.listMessages(session.id);
      final cachedParts = await database.listPartsForSession(session.id);
      // #region agent log
      debugTrace(
        runId: 'prompt-pre',
        hypothesisId: 'H3',
        location: 'session_engine.dart:830',
        message: 'prompt caches loaded',
        data: {
          'sessionId': session.id,
          'messages': cachedMessages.length,
          'parts': cachedParts.length,
          'elapsedMs':
              DateTime.now().millisecondsSinceEpoch - cacheLoadStartedAt,
          'sincePromptStartMs':
              DateTime.now().millisecondsSinceEpoch - promptStartedAt,
        },
      );
      // #endregion
      final toolPartByCallId = <String, MessagePart>{};
      void upsertCachedMessage(MessageInfo message) {
        final index =
            cachedMessages.indexWhere((item) => item.id == message.id);
        if (index >= 0) {
          cachedMessages[index] = message;
        } else {
          cachedMessages.add(message);
          cachedMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        }
      }

      void upsertCachedPart(MessagePart part) {
        final index = cachedParts.indexWhere((item) => item.id == part.id);
        if (index >= 0) {
          cachedParts[index] = part;
        } else {
          cachedParts.add(part);
          cachedParts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        }
        final callId = part.data['callID'] as String?;
        if (part.type == PartType.tool && callId != null && callId.isNotEmpty) {
          toolPartByCallId[callId] = part;
        }
      }

      for (final part in cachedParts) {
        upsertCachedPart(part);
      }

      Future<void> saveTrackedMessage(MessageInfo message) async {
        await _saveMessage(workspace: workspace, message: message);
        upsertCachedMessage(message);
      }

      Future<void> saveTrackedPart(MessagePart part) async {
        await _savePart(workspace: workspace, part: part);
        upsertCachedPart(part);
      }

      final userAgent = agent ?? session.agent;
      final definition = agentDefinition(userAgent);
      var activeSession = session.copyWith(
        agent: userAgent,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveSession(workspace: workspace, session: activeSession);
      final userMessage = MessageInfo(
        id: newId('message'),
        sessionId: session.id,
        role: SessionRole.user,
        agent: userAgent,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        text: text,
        format: format,
      );
      await saveTrackedMessage(userMessage);
      final assistant = MessageInfo(
        id: newId('message'),
        sessionId: session.id,
        role: SessionRole.assistant,
        agent: userAgent,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        model: modelConfig.model,
        provider: modelConfig.provider,
      );
      await saveTrackedMessage(assistant);
      await saveTrackedPart(
        MessagePart(
          id: newId('part'),
          sessionId: session.id,
          messageId: assistant.id,
          type: PartType.stepStart,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          data: const {},
        ),
      );
      var currentAgent = userAgent;
      var lastFinishReason = 'stop';
      var lastUsage = const ModelUsage();
      var loggedFirstDelta = false;
      for (var step = 1; step <= definition.steps; step++) {
        cancelToken.throwIfCancelled();
        events.emit(ServerEvent(
          type: 'session.status',
          properties: {'sessionID': session.id, 'status': 'busy'},
          directory: workspace.treeUri,
        ));
        final buildConversationStartedAt =
            DateTime.now().millisecondsSinceEpoch;
        final conversation = await _buildConversation(
          workspace: workspace,
          messages: cachedMessages,
          parts: cachedParts,
          currentStep: step,
          maxSteps: definition.steps,
          currentAgent: currentAgent,
          model: modelConfig.model,
          summaryMessageId: activeSession.summaryMessageId,
        );
        // #region agent log
        debugTrace(
          runId: 'prompt-step',
          hypothesisId: 'H3',
          location: 'session_engine.dart:919',
          message: 'conversation built',
          data: {
            'sessionId': session.id,
            'step': step,
            'messages': cachedMessages.length,
            'parts': cachedParts.length,
            'conversationItems': conversation.length,
            'elapsedMs': DateTime.now().millisecondsSinceEpoch -
                buildConversationStartedAt,
          },
        );
        // #endregion
        final toolModels = [
          ...toolRegistry.availableForAgent(agentDefinition(currentAgent)),
          if (userMessage.format?.type == OutputFormatType.jsonSchema)
            ToolDefinitionModel(
              id: 'StructuredOutput',
              description: 'Return the final structured response as JSON.',
              parameters: userMessage.format!.schema ??
                  <String, dynamic>{'type': 'object'},
            ),
        ];
        MessagePart? streamingTextPart;
        MessagePart? streamingReasoningPart;
        var streamedText = '';
        var streamedReasoning = '';
        var lastTextEmitAt = 0;
        var lastReasoningEmitAt = 0;
        var lastSavedText = '';
        var lastSavedReasoning = '';
        Future<void> flushStreamingText({bool force = false}) async {
          if (streamedText.isEmpty) return;
          if (!force && streamedText == lastSavedText) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (!force && now - lastTextEmitAt < 80) return;
          lastTextEmitAt = now;
          lastSavedText = streamedText;
          streamingTextPart = MessagePart(
            id: streamingTextPart?.id ?? newId('part'),
            sessionId: session.id,
            messageId: assistant.id,
            type: PartType.text,
            createdAt: streamingTextPart?.createdAt ??
                DateTime.now().millisecondsSinceEpoch,
            data: _assistantTextPartData(streamedText),
          );
          await saveTrackedPart(streamingTextPart!);
        }

        Future<void> flushStreamingReasoning({bool force = false}) async {
          if (streamedReasoning.isEmpty) return;
          if (!force && streamedReasoning == lastSavedReasoning) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (!force && now - lastReasoningEmitAt < 80) return;
          lastReasoningEmitAt = now;
          lastSavedReasoning = streamedReasoning;
          streamingReasoningPart = MessagePart(
            id: streamingReasoningPart?.id ?? newId('part'),
            sessionId: session.id,
            messageId: assistant.id,
            type: PartType.reasoning,
            createdAt: streamingReasoningPart?.createdAt ??
                DateTime.now().millisecondsSinceEpoch,
            data: {'text': streamedReasoning},
          );
          await saveTrackedPart(streamingReasoningPart!);
        }

        // --- Retry loop (mirrors mag processor.process() while(true)) ---
        late ModelResponse response;
        var attempt = 0;
        while (true) {
          try {
            cancelToken.throwIfCancelled();
            response = await modelGateway.complete(
              config: modelConfig,
              messages: conversation,
              tools: toolModels,
              format: userMessage.format,
              cancelToken: cancelToken,
              onTextDelta: (delta) async {
                if (!loggedFirstDelta) {
                  loggedFirstDelta = true;
                  // #region agent log
                  debugTrace(
                    runId: 'prompt-stream',
                    hypothesisId: 'H3',
                    location: 'session_engine.dart:996',
                    message: 'first model delta received',
                    data: {
                      'sessionId': session.id,
                      'step': step,
                      'sincePromptStartMs':
                          DateTime.now().millisecondsSinceEpoch -
                              promptStartedAt,
                    },
                  );
                  // #endregion
                }
                streamingTextPart ??= MessagePart(
                  id: newId('part'),
                  sessionId: session.id,
                  messageId: assistant.id,
                  type: PartType.text,
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                  data: const {'text': ''},
                );
                streamedText += delta;
                _emitPartDelta(
                  workspace: workspace,
                  sessionId: session.id,
                  messageId: assistant.id,
                  partId: streamingTextPart!.id,
                  partType: PartType.text,
                  createdAt: streamingTextPart!.createdAt,
                  delta: {'text': delta},
                );
                await flushStreamingText();
              },
              onReasoningDelta: (delta) async {
                streamingReasoningPart ??= MessagePart(
                  id: newId('part'),
                  sessionId: session.id,
                  messageId: assistant.id,
                  type: PartType.reasoning,
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                  data: const {'text': ''},
                );
                streamedReasoning += delta;
                _emitPartDelta(
                  workspace: workspace,
                  sessionId: session.id,
                  messageId: assistant.id,
                  partId: streamingReasoningPart!.id,
                  partType: PartType.reasoning,
                  createdAt: streamingReasoningPart!.createdAt,
                  delta: {'text': delta},
                );
                await flushStreamingReasoning();
              },
            );
            break; // Success – exit retry loop
          } on CancelledException {
            rethrow;
          } catch (error) {
            if (!_isRetryableError(error) || attempt >= _maxRetryAttempts) {
              rethrow;
            }
            attempt++;
            final delay = _retryDelay(attempt);
            _debugLog(
                'retry', 'attempt=$attempt delay=${delay}ms error=$error');
            events.emit(ServerEvent(
              type: 'session.status',
              properties: {
                'sessionID': session.id,
                'status': 'retry',
                'attempt': attempt,
                'message': _retryMessage(error),
                'next': DateTime.now().millisecondsSinceEpoch + delay,
              },
              directory: workspace.treeUri,
            ));
            // Sleep with cancellation support (like mag's SessionRetry.sleep)
            try {
              await cancelToken
                  .guard(Future.delayed(Duration(milliseconds: delay)));
            } on CancelledException {
              rethrow;
            }
          }
        }
        // --- End retry loop ---

        await flushStreamingText(force: true);
        await flushStreamingReasoning(force: true);
        lastFinishReason = response.finishReason;
        lastUsage = response.usage;
        if (response.text.trim().isNotEmpty && streamingTextPart == null) {
          await saveTrackedPart(
            MessagePart(
              id: newId('part'),
              sessionId: session.id,
              messageId: assistant.id,
              type: PartType.text,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              data: _assistantTextPartData(response.text),
            ),
          );
        }
        if (response.toolCalls.isEmpty) break;
        var shouldBreak = false;
        for (final call in response.toolCalls) {
          cancelToken.throwIfCancelled();
          if (call.name == 'StructuredOutput') {
            final structured = Map<String, dynamic>.from(call.arguments);
            final updatedAssistant = MessageInfo(
              id: assistant.id,
              sessionId: assistant.sessionId,
              role: assistant.role,
              agent: assistant.agent,
              createdAt: assistant.createdAt,
              text: assistant.text,
              format: assistant.format,
              model: assistant.model,
              provider: assistant.provider,
              error: assistant.error,
              structuredOutput: structured,
            );
            await saveTrackedMessage(updatedAssistant);
            await saveTrackedPart(
              MessagePart(
                id: newId('part'),
                sessionId: session.id,
                messageId: assistant.id,
                type: PartType.text,
                createdAt: DateTime.now().millisecondsSinceEpoch,
                data: {
                  'text':
                      const JsonEncoder.withIndent('  ').convert(structured),
                  'structured': true,
                },
              ),
            );
            shouldBreak = true;
            break;
          }
          final toolPart = MessagePart(
            id: newId('part'),
            sessionId: session.id,
            messageId: assistant.id,
            type: PartType.tool,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            data: {
              'tool': call.name,
              'callID': call.id,
              'state': {
                'status': ToolStatus.pending.name,
                'input': call.arguments,
              }
            },
          );
          await saveTrackedPart(toolPart);
          final result = await _executeTool(
            workspace: workspace,
            session: activeSession.copyWith(agent: currentAgent),
            message: assistant,
            agent: currentAgent,
            call: call,
            cancelToken: cancelToken,
            toolPartCache: toolPartByCallId,
            onPartSaved: upsertCachedPart,
          );
          final metadata = result.metadata;
          if (metadata['switchAgent'] == 'build') {
            currentAgent = 'build';
          }
        }
        activeSession = await _trackUsage(
          workspace: workspace,
          session: activeSession,
          usage: response.usage,
        );
        if (shouldBreak) break;
      }
      await saveTrackedPart(
        MessagePart(
          id: newId('part'),
          sessionId: session.id,
          messageId: assistant.id,
          type: PartType.stepFinish,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          data: {
            'reason': lastFinishReason,
            'tokens': lastUsage.toJson(),
            'cost': activeSession.cost,
          },
        ),
      );
      if (_shouldAutoCompact(activeSession, modelConfig.model)) {
        activeSession = await summarize(
          workspace: workspace,
          session: activeSession,
          modelConfig: modelConfig,
          currentAgent: currentAgent,
        );
      }
      _debugLog('prompt', 'success finishReason=$lastFinishReason');
      return assistant;
    } on CancelledException {
      _debugLog('prompt', 'cancelled session=${session.id}');
      // Cleanup incomplete tool parts (mirrors mag processor cleanup)
      await _cleanupIncompleteToolParts(
          workspace: workspace, sessionId: session.id);
      rethrow;
    } catch (error) {
      _debugLog('prompt', 'error: $error');
      await _cleanupIncompleteToolParts(
          workspace: workspace, sessionId: session.id);
      // Emit error event (mirrors mag: Session.Event.Error + set idle)
      events.emit(ServerEvent(
        type: 'session.error',
        properties: {
          'sessionID': session.id,
          'message': error.toString(),
        },
        directory: workspace.treeUri,
      ));
      rethrow;
    } finally {
      // Mirrors mag's `defer(() => cancel(sessionId))`.
      // Guarantees idle status is always set regardless of how the function exits.
      _cancelTokens.remove(session.id);
      _busy.remove(session.id);
      events.emit(ServerEvent(
        type: 'session.status',
        properties: {'sessionID': session.id, 'status': 'idle'},
        directory: workspace.treeUri,
      ));
    }
  }

  /// Mirrors mag's cleanup of incomplete tool parts after stream ends.
  Future<void> _cleanupIncompleteToolParts({
    required WorkspaceInfo workspace,
    required String sessionId,
  }) async {
    try {
      final parts = await database.listPartsForSession(sessionId);
      for (final part in parts) {
        if (part.type != PartType.tool) continue;
        final state =
            Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
        final status = state['status'] as String?;
        if (status == ToolStatus.completed.name ||
            status == ToolStatus.error.name) continue;
        state['status'] = ToolStatus.error.name;
        state['error'] = 'Tool execution aborted';
        final updated = MessagePart(
          id: part.id,
          sessionId: part.sessionId,
          messageId: part.messageId,
          type: part.type,
          createdAt: part.createdAt,
          data: {...part.data, 'state': state},
        );
        await _savePart(workspace: workspace, part: updated);
      }
    } catch (_) {}
  }

  Future<SessionInfo> summarize({
    required WorkspaceInfo workspace,
    required SessionInfo session,
    required ModelConfig modelConfig,
    required String currentAgent,
  }) async {
    final messages = await database.listMessages(session.id);
    if (messages.isEmpty) return session;
    final parts = await database.listPartsForSession(session.id);
    final prompt = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are Mag summarizer. Produce a concise but information-dense continuation summary for the same coding task. Preserve user constraints, decisions, errors, pending work, important file paths, and next steps.',
      },
      ..._messagesToConversation(
        messages: messages,
        parts: parts,
        currentAgent: currentAgent,
        summaryMessageId: session.summaryMessageId,
      ),
      {
        'role': 'user',
        'content':
            'Provide a detailed but concise summary of our conversation above. Focus on information that would be helpful for continuing the conversation, including what we did, what we are doing, which files we are working on, important constraints, and what we should do next.',
      },
    ];
    final response = await modelGateway.complete(
      config: modelConfig,
      messages: prompt,
      tools: const [],
      format: null,
    );
    final summaryText = response.text.trim();
    if (summaryText.isEmpty) return session;
    final summaryMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.assistant,
      agent: currentAgent,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: summaryText,
      model: modelConfig.model,
      provider: modelConfig.provider,
    );
    await _saveMessage(workspace: workspace, message: summaryMessage);
    await _savePart(
      workspace: workspace,
      part: MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: summaryMessage.id,
        type: PartType.compaction,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'label': 'Context compacted',
          'summary': summaryText,
        },
      ),
    );
    await _savePart(
      workspace: workspace,
      part: MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: summaryMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': summaryText},
      ),
    );
    final tracked = await _trackUsage(
      workspace: workspace,
      session: session.copyWith(summaryMessageId: summaryMessage.id),
      usage: response.usage,
    );
    return tracked.copyWith(summaryMessageId: summaryMessage.id);
  }

  Future<SessionInfo> _trackUsage({
    required WorkspaceInfo workspace,
    required SessionInfo session,
    required ModelUsage usage,
  }) async {
    final next = session.copyWith(
      promptTokens: usage.isEmpty ? session.promptTokens : usage.promptTokens,
      completionTokens:
          usage.isEmpty ? session.completionTokens : usage.completionTokens,
      cost: session.cost,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _saveSession(workspace: workspace, session: next);
    return next;
  }

  bool _shouldAutoCompact(SessionInfo session, String model) {
    final contextWindow = inferContextWindow(model);
    if (contextWindow <= 0) return false;
    return session.totalTokens >= (contextWindow * 0.95).floor();
  }

  Future<List<Map<String, dynamic>>> _buildConversation({
    required WorkspaceInfo workspace,
    required List<MessageInfo> messages,
    required List<MessagePart> parts,
    required int currentStep,
    required int maxSteps,
    required String currentAgent,
    required String model,
    required String summaryMessageId,
  }) async {
    final currentAgentDefinition = agentDefinition(currentAgent);
    MessageInfo? latestUser;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == SessionRole.user) {
        latestUser = messages[i];
        break;
      }
    }
    final system = await promptAssembler.buildSystemPrompts(
      PromptContext(
        workspace: workspace,
        agent: currentAgent,
        model: model,
        agentPrompt: currentAgentDefinition.promptOverride,
        hasSkillTool: true,
        currentStep: currentStep,
        maxSteps: maxSteps,
        format: latestUser?.format,
      ),
    );
    final conversation = <Map<String, dynamic>>[];
    conversation.addAll(system);
    conversation.addAll(
      _messagesToConversation(
        messages: messages,
        parts: parts,
        currentAgent: currentAgent,
        summaryMessageId: summaryMessageId,
      ),
    );
    if (currentStep >= maxSteps) {
      conversation.add({
        'role': 'assistant',
        'content': promptAssembler.maxStepsReminder(),
      });
    }
    return conversation;
  }

  List<Map<String, dynamic>> _messagesToConversation({
    required List<MessageInfo> messages,
    required List<MessagePart> parts,
    required String currentAgent,
    String summaryMessageId = '',
  }) {
    final partsByMessage = <String, List<MessagePart>>{};
    for (final part in parts) {
      partsByMessage.putIfAbsent(part.messageId, () => []).add(part);
    }
    var visibleMessages = messages;
    if (summaryMessageId.isNotEmpty) {
      final index = messages.indexWhere((item) => item.id == summaryMessageId);
      if (index >= 0) {
        visibleMessages = messages.sublist(index);
      }
    }
    final conversation = <Map<String, dynamic>>[];
    for (var i = 0; i < visibleMessages.length; i++) {
      final message = visibleMessages[i];
      final messageParts = partsByMessage[message.id] ?? const [];
      final isSummarySeed = i == 0 &&
          summaryMessageId.isNotEmpty &&
          message.id == summaryMessageId;
      if (isSummarySeed) {
        final summaryText = messageParts
            .where((item) => item.type == PartType.text)
            .map(_partRawText)
            .join('\n');
        if (summaryText.trim().isNotEmpty) {
          conversation.add({
            'role': 'user',
            'content': '<summary>\n$summaryText\n</summary>',
          });
        }
        continue;
      }
      if (message.role == SessionRole.user) {
        final switchedFromPlan =
            currentAgent == 'build' && message.agent == 'plan';
        conversation.add({
          'role': 'user',
          'content': promptAssembler.applyUserReminder(
            agent: message.agent,
            switchedFromPlan: switchedFromPlan,
            text: message.text,
          ),
        });
        continue;
      }
      final textParts = messageParts
          .where((item) => item.type == PartType.text)
          .map(_partRawText)
          .join('\n');
      final toolParts =
          messageParts.where((item) => item.type == PartType.tool).toList();
      if (toolParts.isNotEmpty) {
        conversation.add({
          'role': 'assistant',
          'content': textParts.isEmpty ? null : textParts,
          'tool_calls': toolParts.map((part) {
            final state = Map<String, dynamic>.from(
                part.data['state'] as Map? ?? const {});
            return {
              'id': part.data['callID'],
              'type': 'function',
              'function': {
                'name': part.data['tool'],
                'arguments': jsonEncode(state['input'] ?? <String, dynamic>{}),
              }
            };
          }).toList(),
        });
        for (final part in toolParts) {
          final state =
              Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
          final output = state['output'] as String? ?? '';
          conversation.add({
            'role': 'tool',
            'tool_call_id': part.data['callID'],
            'content': output,
          });
        }
      } else if (textParts.isNotEmpty) {
        conversation.add({'role': 'assistant', 'content': textParts});
      }
    }
    return conversation;
  }

  String _partRawText(MessagePart part) =>
      (part.data['rawText'] ?? part.data['text']) as String? ?? '';

  JsonMap _assistantTextPartData(String rawText) {
    final displayText = _sanitizeAssistantToolPayloads(rawText);
    if (displayText == rawText) {
      return {'text': rawText};
    }
    return {
      'text': displayText,
      'rawText': rawText,
    };
  }

  String _sanitizeAssistantToolPayloads(String rawText) {
    if (!rawText.contains('<write_content')) {
      return rawText;
    }
    return rawText.replaceAllMapped(
      RegExp(
        r"""<write_content\s+id=(?:"([^"]+)"|'([^']+)')\s*>[\s\S]*?</write_content>""",
        multiLine: true,
      ),
      (match) {
        final id = match.group(1) ?? match.group(2) ?? 'content';
        return '[write_content:$id omitted]';
      },
    );
  }

  Future<ToolExecutionResult> _executeTool({
    required WorkspaceInfo workspace,
    required SessionInfo session,
    required MessageInfo message,
    required String agent,
    required ToolCall call,
    CancelToken? cancelToken,
    Map<String, MessagePart>? toolPartCache,
    void Function(MessagePart part)? onPartSaved,
  }) async {
    cancelToken?.throwIfCancelled();
    final tool = toolRegistry[call.name] ?? toolRegistry['invalid']!;
    final argumentError = _validateToolArguments(tool, call);
    final ctx = ToolRuntimeContext(
      workspace: workspace,
      session: session,
      message: message,
      agent: agent,
      agentDefinition: agentDefinition(agent),
      bridge: workspaceBridge,
      database: database,
      askPermission: (request) => permissionCenter.ask(
        workspace: workspace,
        request: request,
        rules: agentDefinition(agent).permissionRules,
        cancelToken: cancelToken,
      ),
      askQuestion: (request) => questionCenter.ask(
        workspace: workspace,
        request: request,
        cancelToken: cancelToken,
      ),
      resolveInstructionReminder: (relativePath) =>
          promptAssembler.directoryInstructionReminder(
        workspace: workspace,
        relativePath: relativePath,
      ),
      runSubtask: ({
        required SessionInfo session,
        required String description,
        required String prompt,
        required String subagentType,
      }) async {
        final subSession = await createSession(
          workspace: workspace,
          agent: subagentType,
        );
        await this.prompt(
          workspace: workspace,
          session: subSession,
          text: prompt,
          agent: subagentType,
        );
        final messages = await database.listMessages(subSession.id);
        final parts = await database.listPartsForSession(subSession.id);
        final lastAssistant =
            messages.lastWhere((item) => item.role == SessionRole.assistant);
        final output = parts
            .where((item) =>
                item.messageId == lastAssistant.id &&
                item.type == PartType.text)
            .map((item) => item.data['text'] as String? ?? '')
            .join('\n');
        return ToolExecutionResult(
          title: description,
          output: '<task_result>$output</task_result>',
          metadata: {'taskSessionId': subSession.id},
        );
      },
      saveTodos: (items) async {
        await database.deleteTodosForSession(session.id);
        for (final item in items) {
          await database.saveTodo(item);
        }
        events.emit(ServerEvent(
          type: 'todo.updated',
          properties: {
            'sessionID': session.id,
            'todos': items.map((item) => item.toJson()).toList()
          },
          directory: workspace.treeUri,
        ));
      },
    );
    try {
      _debugLog('tool', 'execute ${call.name}');
      await _updateToolState(
        workspace: workspace,
        sessionId: session.id,
        callId: call.id,
        status: ToolStatus.running,
        toolPartCache: toolPartCache,
        onPartSaved: onPartSaved,
      );
      if (argumentError != null) {
        throw Exception(argumentError);
      }
      final result = await tool.execute(call.arguments, ctx);
      _invalidatePromptContextForToolResult(
        workspace: workspace,
        toolName: call.name,
        metadata: result.metadata,
      );
      await _updateToolState(
        workspace: workspace,
        sessionId: session.id,
        callId: call.id,
        status: ToolStatus.completed,
        output: result.output,
        displayOutput: result.displayOutput,
        title: result.title,
        metadata: result.metadata,
        attachments: result.attachments,
        toolPartCache: toolPartCache,
        onPartSaved: onPartSaved,
      );
      return result;
    } on CancelledException {
      rethrow;
    } catch (error) {
      _debugLog('tool', 'error ${call.name}: $error');
      await _updateToolState(
        workspace: workspace,
        sessionId: session.id,
        callId: call.id,
        status: ToolStatus.error,
        output: error.toString(),
        toolPartCache: toolPartCache,
        onPartSaved: onPartSaved,
      );
      return ToolExecutionResult(
        title: call.name,
        output: error.toString(),
        displayOutput: '${call.name} failed',
        metadata: {
          'failed': true,
          'error': error.toString(),
        },
      );
    }
  }

  String? _validateToolArguments(ToolDefinition tool, ToolCall call) {
    final args = call.arguments;
    if (args.containsKey('raw')) {
      final raw = (args['raw'] as String? ?? '').trim();
      final suffix = raw.isEmpty ? '' : ' Received: $raw';
      return 'Malformed tool arguments for `${call.name}`. Expected a valid JSON object matching the tool schema.$suffix';
    }
    if (tool.id == 'write') {
      final hasInlineContent = args.containsKey('content');
      final contentRef = (args['contentRef'] as String? ?? '').trim();
      if (!hasInlineContent && contentRef.isEmpty) {
        return 'Missing write payload. Provide `content` for short text or `contentRef` for a `<write_content id="...">` block.';
      }
    }
    final required =
        ((tool.parameters['required'] as List?) ?? const <dynamic>[])
            .whereType<String>();
    for (final key in required) {
      final value = args[key];
      if (value == null) {
        return 'Missing required `$key` for `${call.name}`.';
      }
      if (value is String && value.trim().isEmpty) {
        return 'Required `$key` for `${call.name}` cannot be empty.';
      }
    }
    return null;
  }

  Future<void> _updateToolState({
    required WorkspaceInfo workspace,
    required String sessionId,
    required String callId,
    required ToolStatus status,
    String? output,
    String? displayOutput,
    String? title,
    JsonMap? metadata,
    List<JsonMap>? attachments,
    Map<String, MessagePart>? toolPartCache,
    void Function(MessagePart part)? onPartSaved,
  }) async {
    final part = toolPartCache?[callId] ??
        (await database.listPartsForSession(sessionId)).lastWhere(
          (item) => item.type == PartType.tool && item.data['callID'] == callId,
        );
    final state =
        Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
    state['status'] = status.name;
    if (output != null) {
      state['output'] = output;
    }
    if (displayOutput != null) {
      state['displayOutput'] = displayOutput;
    }
    if (title != null) {
      state['title'] = title;
    }
    if (metadata != null) {
      state['metadata'] = metadata;
    }
    if (attachments != null) {
      state['attachments'] = attachments;
    }
    final updated = MessagePart(
      id: part.id,
      sessionId: part.sessionId,
      messageId: part.messageId,
      type: part.type,
      createdAt: part.createdAt,
      data: {...part.data, 'state': state},
    );
    await _savePart(workspace: workspace, part: updated);
    if (toolPartCache != null) {
      toolPartCache[callId] = updated;
    }
    onPartSaved?.call(updated);
  }

  Future<void> _savePart({
    required WorkspaceInfo workspace,
    required MessagePart part,
  }) async {
    await database.savePart(part);
    events.emit(ServerEvent(
      type: 'message.part.updated',
      properties: part.toJson(),
      directory: workspace.treeUri,
    ));
  }

  Future<void> _saveSession({
    required WorkspaceInfo workspace,
    required SessionInfo session,
  }) async {
    await database.saveSession(session);
    events.emit(ServerEvent(
      type: 'session.updated',
      properties: session.toJson(),
      directory: workspace.treeUri,
    ));
  }

  Future<void> _saveMessage({
    required WorkspaceInfo workspace,
    required MessageInfo message,
  }) async {
    await database.saveMessage(message);
    events.emit(ServerEvent(
      type: 'message.updated',
      properties: message.toJson(),
      directory: workspace.treeUri,
    ));
  }

  void _emitPartDelta({
    required WorkspaceInfo workspace,
    required String sessionId,
    required String messageId,
    required String partId,
    required PartType partType,
    required int createdAt,
    required JsonMap delta,
  }) {
    events.emit(ServerEvent(
      type: 'message.part.delta',
      properties: {
        'sessionID': sessionId,
        'messageID': messageId,
        'partID': partId,
        'type': partType.name,
        'createdAt': createdAt,
        'delta': delta,
      },
      directory: workspace.treeUri,
    ));
  }

  void _invalidatePromptContextForToolResult({
    required WorkspaceInfo workspace,
    required String toolName,
    JsonMap? metadata,
  }) {
    final writeLikeTools = {'write', 'edit', 'apply_patch'};
    if (!writeLikeTools.contains(toolName)) return;
    final paths = <String>{};
    final singlePath =
        metadata?['filepath'] as String? ?? metadata?['path'] as String?;
    if (singlePath != null && singlePath.trim().isNotEmpty) {
      paths.add(singlePath.trim());
    }
    final files = (metadata?['files'] as List? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty);
    paths.addAll(files);
    promptAssembler.invalidateWorkspaceContext(
      workspace.treeUri,
      paths: paths.isEmpty ? null : paths,
    );
  }
}
