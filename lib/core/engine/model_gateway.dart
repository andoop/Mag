part of '../session_engine.dart';

class ModelGateway {
  bool _usesAnthropicApi(ModelConfig config) => config.provider == 'anthropic';

  bool _usesGitHubModelsApi(ModelConfig config) =>
      config.provider == 'github_models';

  bool _allowsEmptyApiKey(ModelConfig config) =>
      config.provider == 'ollama' || config.isMagProvider;

  // ---------------------------------------------------------------------------
  // Provider-specific parameter inference (ported from opencode transform.ts)
  // ---------------------------------------------------------------------------

  double? _inferTemperature(String model) {
    final lower = model.toLowerCase();
    if (lower.contains('qwen') || lower.contains('qwq')) return 0.55;
    if (lower.contains('gemini')) return 1.0;
    if (lower.contains('glm-4')) return 1.0;
    if (lower.contains('minimax')) return 1.0;
    if (lower.contains('kimi-k2')) {
      if (['thinking', 'k2.', 'k2p', 'k2-5'].any(lower.contains)) return 1.0;
      return 0.6;
    }
    return null;
  }

  double? _inferTopP(String model) {
    final lower = model.toLowerCase();
    if (lower.contains('qwen') || lower.contains('qwq')) return 1;
    if (['minimax-m2', 'gemini', 'kimi-k2.5', 'kimi-k2p5', 'kimi-k2-5']
        .any(lower.contains)) return 0.95;
    return null;
  }

  int? _inferTopK(String model) {
    final lower = model.toLowerCase();
    if (lower.contains('minimax-m2')) {
      if (['m2.', 'm25', 'm21'].any(lower.contains)) return 40;
      return 20;
    }
    if (lower.contains('gemini')) return 64;
    return null;
  }

  /// Sanitize tool call IDs for Claude: only [a-zA-Z0-9_-] allowed.
  String _sanitizeToolCallIdForClaude(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  /// Normalize tool call IDs for Mistral: exactly 9 alphanumeric chars.
  String _normalizeToolCallIdForMistral(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').padRight(9, '0').substring(0, 9);

  /// Normalize messages for OpenAI-compatible providers.
  /// Handles tool call ID sanitization and sequence fixes.
  List<Map<String, dynamic>> _normalizeOpenAiMessages(
    List<Map<String, dynamic>> messages,
    ModelConfig config,
  ) {
    final lower = config.model.toLowerCase();
    final isMistral =
        config.provider == 'mistral' || lower.contains('mistral') || lower.contains('devstral');
    if (!isMistral) return messages;

    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < messages.length; i++) {
      final msg = Map<String, dynamic>.from(messages[i]);
      final role = msg['role'] as String? ?? '';

      // Normalize tool call IDs for Mistral
      if (role == 'assistant') {
        final toolCalls = (msg['tool_calls'] as List?)?.toList();
        if (toolCalls != null) {
          msg['tool_calls'] = toolCalls.map((tc) {
            final m = Map<String, dynamic>.from(tc as Map);
            final id = m['id'] as String? ?? '';
            m['id'] = _normalizeToolCallIdForMistral(id);
            return m;
          }).toList();
        }
      }
      if (role == 'tool') {
        final callId = msg['tool_call_id'] as String? ?? '';
        msg['tool_call_id'] = _normalizeToolCallIdForMistral(callId);
      }

      result.add(msg);

      // Mistral: tool messages cannot be followed by user messages directly
      if (role == 'tool' && i + 1 < messages.length) {
        final nextRole = messages[i + 1]['role'] as String? ?? '';
        if (nextRole == 'user') {
          result.add({'role': 'assistant', 'content': 'Done.'});
        }
      }
    }
    return result;
  }

  Map<String, dynamic> _buildOpenAiPayload({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
    required int maxOutputTokens,
  }) {
    final normalized = _normalizeOpenAiMessages(messages, config);
    final payload = <String, dynamic>{
      'model': config.model,
      'messages': normalized,
      'stream': true,
      'stream_options': {'include_usage': true},
      'max_tokens': maxOutputTokens,
    };
    final temperature = _inferTemperature(config.model);
    if (temperature != null) payload['temperature'] = temperature;
    final topP = _inferTopP(config.model);
    if (topP != null) payload['top_p'] = topP;
    final topK = _inferTopK(config.model);
    if (topK != null) payload['top_k'] = topK;
    if (tools.isNotEmpty) {
      payload['tools'] = tools
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
          .toList();
    }
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
    required int maxOutputTokens,
  }) {
    final isClaude = config.model.toLowerCase().contains('claude');
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
        var toolUseId = message['tool_call_id'] as String? ?? '';
        if (toolUseId.isEmpty) continue;
        if (isClaude) toolUseId = _sanitizeToolCallIdForClaude(toolUseId);
        final content = _extractText(message['content']);
        if (content.isEmpty) continue;
        conversation.add({
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': toolUseId,
              'content': content,
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
          var callId = map['id'] as String? ?? newId('toolcall');
          if (isClaude) callId = _sanitizeToolCallIdForClaude(callId);
          blocks.add({
            'type': 'tool_use',
            'id': callId,
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

    // Filter out empty assistant messages (Anthropic rejects empty content)
    conversation.removeWhere((msg) {
      if (msg['role'] != 'assistant' && msg['role'] != 'user') return false;
      final content = msg['content'];
      if (content == null) return true;
      if (content is String) return content.isEmpty;
      if (content is List) {
        final filtered = content.where((block) {
          if (block is Map) {
            final type = block['type'] as String? ?? '';
            if (type == 'text') return (block['text'] as String? ?? '').isNotEmpty;
            return true;
          }
          return true;
        }).toList();
        if (filtered.isEmpty) return true;
        msg['content'] = filtered;
        return false;
      }
      return false;
    });

    final payload = <String, dynamic>{
      'model': config.model,
      'max_tokens': maxOutputTokens,
      'messages': conversation,
    };
    final temperature = _inferTemperature(config.model);
    if (temperature != null) payload['temperature'] = temperature;
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

  JsonMap buildDebugPayload({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
  }) {
    final maxOut = inferMaxOutputTokens(config.model);
    if (_usesAnthropicApi(config)) {
      return _buildAnthropicPayload(
        config: config,
        messages: messages,
        tools: tools,
        format: format,
        maxOutputTokens: maxOut,
      );
    }
    return _buildOpenAiPayload(
      config: config,
      messages: messages,
      tools: tools,
      format: format,
      maxOutputTokens: maxOut,
    );
  }

  Future<ModelResponse> _completeAnthropic({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
    required int maxOutputTokens,
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
      maxOutputTokens: maxOutputTokens,
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
    required int maxOutputTokens,
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
      maxOutputTokens: maxOutputTokens,
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
    var closedByTimeout = false;
    var receivedModelFinishReason = false;

    final sseStream = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 300), onTimeout: (sink) {
      _debugLog('gateway', 'SSE idle timeout – closing stream');
      closedByTimeout = true;
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
        final incomingId = (map['id'] as String?)?.trim() ?? '';
        if (incomingId.isNotEmpty) {
          buffer.id = incomingId;
        }
        final function =
            Map<String, dynamic>.from(map['function'] as Map? ?? const {});
        final incomingName = (function['name'] as String?)?.trim() ?? '';
        if (incomingName.isNotEmpty) {
          buffer.name = incomingName;
        }
        final args = function['arguments'] as String? ?? '';
        if (args.isNotEmpty) {
          buffer.arguments.write(args);
        }
      }
      if (toolCalls.isNotEmpty || choice['finish_reason'] != null) {
        _debugLog('gateway-chunk', 'tool chunk / finish reason', {
          'eventCount': eventCount,
          'finishReason': choice['finish_reason'],
          'toolChunkCount': toolCalls.length,
          'toolChunks': toolCalls.map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            final function =
                Map<String, dynamic>.from(map['function'] as Map? ?? const {});
            final args = function['arguments'] as String? ?? '';
            return {
              'id': map['id'],
              'index': map['index'],
              'name': function['name'],
              'argsFragmentLength': args.length,
            };
          }).toList(),
          'bufferStates': toolBuffers.entries
              .map((entry) => {
                    'index': entry.key,
                    'id': entry.value.id,
                    'name': entry.value.name,
                    'argumentsLength': entry.value.arguments.length,
                  })
              .toList(),
        });
      }

      if (choice['finish_reason'] != null) {
        receivedModelFinishReason = true;
        // Do NOT break here. The OpenAI streaming protocol with
        // stream_options.include_usage sends the usage data in a separate
        // final chunk AFTER the finish_reason chunk (with choices: []).
        // Breaking early skips that chunk, leaving usage at zero for
        // providers that follow the standard (e.g. Qwen/Alibaba).
        // The loop terminates on [DONE] or the idle timeout.
      }
    }
    client.close(force: true);
    if (closedByTimeout && !receivedModelFinishReason) {
      finishReason = 'timeout';
      _debugLog('gateway',
          'stream closed by idle timeout without model finish_reason '
          '(events=$eventCount text=${text.length} reasoning=${reasoning.length})');
    }
    _debugLog('gateway',
        'complete end events=$eventCount tools=${toolBuffers.length}');

    final toolCalls = toolBuffers.entries.map((entry) {
      final buffer = entry.value;
      final callId = (buffer.id ?? '').trim();
      return ToolCall(
        id: callId.isNotEmpty ? callId : newId('toolcall'),
        name: buffer.name ?? 'invalid',
        arguments: _decodeArguments(buffer.arguments.toString()),
      );
    }).toList();
    _debugLog('gateway-result', 'assembled model response', {
      'finishReason': finishReason,
      'toolCallCount': toolCalls.length,
      'toolCalls': toolCalls
          .map((call) => {
                'id': call.id,
                'name': call.name,
                'argKeys': call.arguments.keys.toList(),
                'hasRaw': call.arguments.containsKey('raw'),
              })
          .toList(),
      'textLength': text.length,
      'reasoningLength': reasoning.length,
    });

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
    final maxOut = inferMaxOutputTokens(config.model);
    if (_usesAnthropicApi(config)) {
      return _completeAnthropic(
        config: config,
        messages: messages,
        tools: tools,
        format: format,
        maxOutputTokens: maxOut,
        cancelToken: cancelToken,
      );
    }
    return _completeOpenAiCompatible(
      config: config,
      messages: messages,
      tools: tools,
      format: format,
      maxOutputTokens: maxOut,
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
    } catch (_) {}
    final repaired = _repairJson(input);
    if (repaired != null) {
      try {
        return Map<String, dynamic>.from(jsonDecode(repaired) as Map);
      } catch (_) {}
    }
    return {'raw': input};
  }

  /// Attempts to repair common AI-generated JSON issues.
  static String? _repairJson(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (!s.startsWith('{')) {
      final idx = s.indexOf('{');
      if (idx < 0) return null;
      s = s.substring(idx);
    }
    // Strip trailing garbage after the last '}'
    final lastBrace = s.lastIndexOf('}');
    if (lastBrace >= 0) {
      s = s.substring(0, lastBrace + 1);
    } else {
      s = '$s}';
    }
    // Remove trailing commas before } or ]
    s = s.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
    // Try to fix truncated string values: if the JSON is truncated mid-string,
    // close the open string and object.
    try {
      jsonDecode(s);
      return s;
    } catch (_) {}
    // Truncated mid-string: count unescaped quotes
    var inString = false;
    var escaped = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == r'\') {
        escaped = true;
        continue;
      }
      if (c == '"') inString = !inString;
    }
    if (inString) {
      // Truncated inside a string value — close it
      s = '$s"}';
      s = s.replaceAll(RegExp(r',\s*([}\]])'), r'$1');
      try {
        jsonDecode(s);
        return s;
      } catch (_) {}
    }
    return null;
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
    final totalTokens = (usage['total_tokens'] as num?)?.toInt();
    return ModelUsage(
      inputTokens: math.max(0, promptTokens - cacheRead),
      outputTokens: completionTokens,
      reasoningTokens: reasoningTokens,
      cacheReadTokens: cacheRead,
      cacheWriteTokens: cacheWrite,
      totalTokensFromApi: totalTokens,
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
