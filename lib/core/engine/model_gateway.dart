part of '../session_engine.dart';

class _ModelInputCapabilities {
  const _ModelInputCapabilities({
    this.images = false,
    this.audio = false,
    this.video = false,
    this.pdf = false,
  });

  final bool images;
  final bool audio;
  final bool video;
  final bool pdf;
}

class ModelGateway {
  bool _usesAnthropicApi(ModelConfig config) => config.provider == 'anthropic';

  bool _usesGitHubModelsApi(ModelConfig config) =>
      config.provider == 'github_models';

  bool _allowsEmptyApiKey(ModelConfig config) =>
      config.provider == 'ollama' || config.isMagProvider;

  JsonMap _runtimeRequestOptions(ModelConfig config, {String? sessionId}) {
    final value = sessionId?.trim() ?? '';
    if (value.isEmpty) return const {};
    if (config.provider == 'openai' || config.provider == 'venice') {
      return {'promptCacheKey': value};
    }
    if (config.provider == 'openrouter') {
      return {'prompt_cache_key': value};
    }
    return const {};
  }

  JsonMap _variantRequestOptions(ModelConfig config, {String? variant}) {
    final key = variant?.trim() ?? '';
    if (key.isEmpty) return const {};
    final variants = config.currentModelVariants;
    if (variants == null) return const {};
    final selected = variants[key];
    if (selected == null) return const {};
    return Map<String, dynamic>.from(selected);
  }

  JsonMap _resolvedRequestOptions(
    ModelConfig config, {
    String? sessionId,
    bool small = false,
    String? variant,
  }) {
    return {
      ...Map<String, dynamic>.from(
        config.currentModelOptions ??
            inferProviderModelOptionsFallback(
              providerId: config.provider,
              modelId: config.model,
              capabilities: config.currentModelCapabilities,
            ),
      ),
      if (small)
        ...inferProviderSmallOptionsFallback(
          providerId: config.provider,
          modelId: config.model,
        ),
      if (!small) ..._variantRequestOptions(config, variant: variant),
      ..._runtimeRequestOptions(config, sessionId: sessionId),
    };
  }

  void _applyRequestOptions(
    Map<String, dynamic> payload,
    JsonMap options, {
    required Set<String> reservedKeys,
    required bool allowTemperature,
  }) {
    for (final entry in options.entries) {
      if (reservedKeys.contains(entry.key)) continue;
      if (entry.key == 'temperature' && !allowTemperature) continue;
      payload[entry.key] = entry.value;
    }
  }

  /// Sanitize tool call IDs for Claude: only [a-zA-Z0-9_-] allowed.
  String _sanitizeToolCallIdForClaude(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  /// Normalize tool call IDs for Mistral: exactly 9 alphanumeric chars.
  String _normalizeToolCallIdForMistral(String id) => id
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .padRight(9, '0')
      .substring(0, 9);

  /// Normalize messages for OpenAI-compatible providers.
  /// Handles tool call ID sanitization and sequence fixes.
  List<Map<String, dynamic>> _normalizeOpenAiMessages(
    List<Map<String, dynamic>> messages,
    ModelConfig config,
  ) {
    final interleavedField = _interleavedReasoningField(config);
    messages = messages.map((item) {
      final msg = Map<String, dynamic>.from(item);
      final reasoningText =
          (msg.remove('reasoning_text') as String? ?? '').trim();
      if (interleavedField != null &&
          (msg['role'] as String? ?? '') == 'assistant' &&
          reasoningText.isNotEmpty) {
        msg[interleavedField] = reasoningText;
      }
      return msg;
    }).toList();
    final lower = config.model.toLowerCase();
    final isMistral = config.provider == 'mistral' ||
        lower.contains('mistral') ||
        lower.contains('devstral');
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

  String? _mimeToModality(String mime) {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('audio/')) return 'audio';
    if (mime.startsWith('video/')) return 'video';
    if (mime == 'application/pdf') return 'pdf';
    return null;
  }

  bool _isEmptyBase64DataUrl(String value) {
    final match = RegExp(r'^data:([^;]+);base64,(.*)$').firstMatch(value);
    if (match == null) return false;
    final data = match.group(2) ?? '';
    return data.isEmpty;
  }

  List<Map<String, dynamic>> _sanitizeUserPartsForModel(
    List<Map<String, dynamic>> messages,
    ModelConfig config,
  ) {
    return messages.map((message) {
      if ((message['role'] as String? ?? '') != 'user') return message;
      final content = message['content'];
      if (content is! List) return message;
      final next = content.map((item) {
        if (item is! Map) return item;
        return _sanitizeUserPart(
          Map<String, dynamic>.from(item),
          config,
        );
      }).toList();
      return {
        ...message,
        'content': next,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _transformOpenAiUserParts(
    List<Map<String, dynamic>> messages,
    ModelConfig config,
  ) {
    return messages.map((message) {
      if ((message['role'] as String? ?? '') != 'user') return message;
      final content = message['content'];
      if (content is! List) return message;
      final next = content.map((item) {
        if (item is! Map) return item;
        return _normalizeOpenAiUserPart(
          Map<String, dynamic>.from(item),
          config,
        );
      }).toList();
      return {
        ...message,
        'content': next,
      };
    }).toList();
  }

  Map<String, dynamic> _sanitizeUserPart(
    Map<String, dynamic> part,
    ModelConfig config,
  ) {
    final type = part['type'] as String? ?? '';
    if (type == 'file') {
      return _sanitizeUserFilePart(part, config);
    }
    if (type == 'image_url') {
      return _sanitizeImageUrlPart(part, config);
    }
    return part;
  }

  Map<String, dynamic> _normalizeOpenAiUserPart(
    Map<String, dynamic> part,
    ModelConfig config,
  ) {
    final type = part['type'] as String? ?? '';
    if (type == 'file') {
      return _normalizeOpenAiFilePart(part, config);
    }
    if (type == 'image_url' && !_supportsImageInput(config)) {
      return _unsupportedUserFileText('image/*');
    }
    return part;
  }

  Map<String, dynamic> _normalizeOpenAiFilePart(
    Map<String, dynamic> part,
    ModelConfig config,
  ) {
    final mediaType = part['mediaType'] as String? ?? '';
    final url = part['url'] as String? ?? '';
    if (mediaType.startsWith('image/')) {
      if (!_supportsImageInput(config)) {
        return _unsupportedUserFileText(mediaType,
            filename: part['filename'] as String?);
      }
      return {
        'type': 'image_url',
        'image_url': {'url': url},
      };
    }
    if (mediaType == 'application/pdf') {
      if (!_supportsPdfInput(config)) {
        return _unsupportedUserFileText(mediaType,
            filename: part['filename'] as String?);
      }
    }
    return part;
  }

  Map<String, dynamic> _sanitizeUserFilePart(
    Map<String, dynamic> part,
    ModelConfig config,
  ) {
    final mediaType = part['mediaType'] as String? ?? '';
    final filename = part['filename'] as String?;
    final url = part['url'] as String? ?? '';
    final modality = _mimeToModality(mediaType);
    if (modality == null) return part;
    if (modality == 'image' &&
        url.startsWith('data:') &&
        _isEmptyBase64DataUrl(url)) {
      return {
        'type': 'text',
        'text':
            'ERROR: Image file is empty or corrupted. Please provide a valid image.',
      };
    }
    if (_supportsInputModality(config, modality)) return part;
    return _unsupportedUserFileText(mediaType, filename: filename);
  }

  Map<String, dynamic> _sanitizeImageUrlPart(
    Map<String, dynamic> part,
    ModelConfig config,
  ) {
    final imageUrl = Map<String, dynamic>.from(
      part['image_url'] as Map? ?? const {},
    );
    final url = imageUrl['url'] as String? ?? '';
    if (url.startsWith('data:image/') && _isEmptyBase64DataUrl(url)) {
      return {
        'type': 'text',
        'text':
            'ERROR: Image file is empty or corrupted. Please provide a valid image.',
      };
    }
    if (_supportsImageInput(config)) return part;
    return _unsupportedUserFileText('image/*');
  }

  Map<String, dynamic> _unsupportedUserFileText(
    String mediaType, {
    String? filename,
  }) {
    final modality = _mimeToModality(mediaType) ??
        (mediaType == 'application/pdf' ? 'pdf' : 'file');
    final name = (filename != null && filename.trim().isNotEmpty)
        ? '"$filename"'
        : modality;
    return {
      'type': 'text',
      'text':
          'ERROR: Cannot read $name (this model does not support $modality input). Inform the user.',
    };
  }

  _ModelInputCapabilities _inputCapabilities(ModelConfig config) {
    final catalogModalities = config.currentModelModalities?.input
            .map((item) => item.toLowerCase())
            .toSet() ??
        const <String>{};
    return _ModelInputCapabilities(
      images: catalogModalities.contains('image'),
      audio: catalogModalities.contains('audio'),
      video: catalogModalities.contains('video'),
      pdf: catalogModalities.contains('pdf'),
    );
  }

  bool _supportsImageInput(ModelConfig config) {
    return _supportsInputModality(config, 'image');
  }

  bool _supportsPdfInput(ModelConfig config) {
    return _supportsInputModality(config, 'pdf');
  }

  bool _supportsTemperatureControl(ModelConfig config) {
    return config.currentModelCapabilities?.temperature ?? false;
  }

  bool _supportsToolCalls(ModelConfig config) {
    return config.currentModelCapabilities?.toolCall ?? true;
  }

  bool _providerNeedsCompatibilityToolStub(ModelConfig config) {
    final provider = config.provider.toLowerCase();
    final model = config.model.toLowerCase();
    final baseUrl = config.baseUrl.toLowerCase();
    return provider.contains('litellm') ||
        model.contains('litellm') ||
        baseUrl.contains('litellm') ||
        provider.contains('bedrock') ||
        baseUrl.contains('bedrock');
  }

  bool _historyContainsToolCalls(List<Map<String, dynamic>> messages) {
    for (final message in messages) {
      final role = (message['role'] as String? ?? '').trim();
      if (role == 'tool') return true;
      final toolCalls = message['tool_calls'];
      if (toolCalls is List && toolCalls.isNotEmpty) return true;
    }
    return false;
  }

  JsonMap _normalizeToolSchema(JsonMap schema) {
    dynamic visit(dynamic value) {
      if (value is List) {
        return value.map(visit).toList(growable: false);
      }
      if (value is! Map) return value;
      final out = <String, dynamic>{};
      for (final entry in value.entries) {
        final key = entry.key.toString();
        if (key == r'$schema' ||
            key == 'default' ||
            key == 'example' ||
            key == 'examples' ||
            key == 'title') {
          continue;
        }
        final normalized = visit(entry.value);
        if (key == 'required' && normalized is List && normalized.isEmpty) {
          continue;
        }
        out[key] = normalized;
      }
      return out;
    }

    return Map<String, dynamic>.from(visit(schema) as Map);
  }

  String _normalizeToolName(String id) {
    final trimmed = id.trim();
    if (trimmed.isEmpty) return 'invalid_tool';
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  ToolDefinitionModel _noopCompatibilityTool() {
    return ToolDefinitionModel(
      id: '_noop',
      description:
          'Do not call this tool. It exists only for API compatibility and must never be invoked.',
      parameters: const {
        'type': 'object',
        'properties': {
          'reason': {'type': 'string', 'description': 'Unused'},
        },
        'additionalProperties': false,
      },
    );
  }

  List<ToolDefinitionModel> _prepareToolsForProvider(
    ModelConfig config,
    List<ToolDefinitionModel> tools,
    List<Map<String, dynamic>> messages,
  ) {
    final normalized = tools
        .map(
          (tool) => ToolDefinitionModel(
            id: _normalizeToolName(tool.id),
            description: tool.description.trim(),
            parameters: _normalizeToolSchema(tool.parameters),
          ),
        )
        .toList(growable: true);
    if (_supportsToolCalls(config) &&
        normalized.isEmpty &&
        _providerNeedsCompatibilityToolStub(config) &&
        _historyContainsToolCalls(messages)) {
      normalized.add(_noopCompatibilityTool());
    }
    return normalized;
  }

  String? _interleavedReasoningField(ModelConfig config) {
    final interleaved = config.currentModelCapabilities?.interleaved;
    if (interleaved == null || !interleaved.enabled) return null;
    final field = interleaved.field?.trim() ?? '';
    return field.isEmpty ? null : field;
  }

  bool _transportSupportsInputModality(ModelConfig config, String modality) {
    if (_usesAnthropicApi(config)) {
      return modality == 'image' || modality == 'pdf';
    }
    return modality == 'image';
  }

  bool _supportsInputModality(ModelConfig config, String modality) {
    final capabilities = _inputCapabilities(config);
    switch (modality) {
      case 'image':
        return capabilities.images &&
            _transportSupportsInputModality(config, modality);
      case 'audio':
        return capabilities.audio &&
            _transportSupportsInputModality(config, modality);
      case 'video':
        return capabilities.video &&
            _transportSupportsInputModality(config, modality);
      case 'pdf':
        return capabilities.pdf &&
            _transportSupportsInputModality(config, modality);
      default:
        return false;
    }
  }

  int _resolvedMaxOutputTokens(ModelConfig config) => maxOutputTokensForModel(
        config.model,
        limit: config.currentModelLimit,
      );

  int? _requestedMaxOutputTokens(ModelConfig config) =>
      _usesGitHubModelsApi(config) ? null : _resolvedMaxOutputTokens(config);

  Map<String, dynamic> _buildOpenAiPayload({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
    required int? maxOutputTokens,
    String? sessionId,
    bool small = false,
    String? variant,
  }) {
    final sanitized = _sanitizeUserPartsForModel(messages, config);
    final openAiReady = _transformOpenAiUserParts(sanitized, config);
    final normalized = _normalizeOpenAiMessages(openAiReady, config);
    final normalizedTools = _prepareToolsForProvider(config, tools, normalized);
    final payload = <String, dynamic>{
      'model': config.model,
      'messages': normalized,
      'stream': true,
      'stream_options': {'include_usage': true},
    };
    if (maxOutputTokens != null) payload['max_tokens'] = maxOutputTokens;
    _applyRequestOptions(
      payload,
      _resolvedRequestOptions(
        config,
        sessionId: sessionId,
        small: small,
        variant: variant,
      ),
      reservedKeys: const {
        'model',
        'messages',
        'stream',
        'stream_options',
        'max_tokens',
        'tools',
        'tool_choice',
      },
      allowTemperature: _supportsTemperatureControl(config),
    );
    if (_supportsToolCalls(config) && normalizedTools.isNotEmpty) {
      payload['tools'] = normalizedTools
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
    if (_supportsToolCalls(config) &&
        format?.type == OutputFormatType.jsonSchema) {
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
    String? sessionId,
    bool small = false,
    String? variant,
  }) {
    final isClaude = config.model.toLowerCase().contains('claude');
    final systemParts = <String>[];
    final conversation = <JsonMap>[];

    final sanitized = _sanitizeUserPartsForModel(messages, config);
    for (final message in sanitized) {
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
      if (role == 'user') {
        blocks.addAll(_anthropicUserBlocks(message['content']));
      } else {
        final text = _extractText(message['content']).trim();
        if (text.isNotEmpty) {
          blocks.add({'type': 'text', 'text': text});
        }
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
              source: 'anthropic-payload-history',
              provider: config.provider,
              model: config.model,
              toolName: function['name'] as String?,
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
            if (type == 'text') {
              return (block['text'] as String? ?? '').isNotEmpty;
            }
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
    final normalizedTools =
        _prepareToolsForProvider(config, tools, conversation);

    final payload = <String, dynamic>{
      'model': config.model,
      'max_tokens': maxOutputTokens,
      'messages': conversation,
    };
    _applyRequestOptions(
      payload,
      _resolvedRequestOptions(
        config,
        sessionId: sessionId,
        small: small,
        variant: variant,
      ),
      reservedKeys: const {
        'model',
        'max_tokens',
        'messages',
        'system',
        'tools',
        'tool_choice',
      },
      allowTemperature: _supportsTemperatureControl(config),
    );
    if (systemParts.isNotEmpty) {
      payload['system'] = systemParts.join('\n\n');
    }
    if (_supportsToolCalls(config) && normalizedTools.isNotEmpty) {
      payload['tools'] = normalizedTools
          .map(
            (tool) => {
              'name': tool.id,
              'description': tool.description,
              'input_schema': tool.parameters,
            },
          )
          .toList();
    }
    if (_supportsToolCalls(config) &&
        format?.type == OutputFormatType.jsonSchema) {
      payload['tool_choice'] = {
        'type': 'tool',
        'name': 'StructuredOutput',
      };
    }
    return payload;
  }

  List<JsonMap> _anthropicUserBlocks(dynamic content) {
    if (content == null) return const [];
    if (content is String) {
      final text = content.trim();
      return text.isEmpty
          ? const []
          : <JsonMap>[
              {'type': 'text', 'text': text}
            ];
    }
    if (content is! List) {
      final text = content.toString().trim();
      return text.isEmpty
          ? const []
          : <JsonMap>[
              {'type': 'text', 'text': text}
            ];
    }
    final blocks = <JsonMap>[];
    for (final item in content) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final type = map['type'] as String? ?? '';
      if (type == 'text') {
        final text = (map['text'] as String? ?? '').trim();
        if (text.isNotEmpty) {
          blocks.add({'type': 'text', 'text': text});
        }
        continue;
      }
      if (type == 'image_url') {
        final imageUrl = Map<String, dynamic>.from(
          map['image_url'] as Map? ?? const {},
        );
        final url = imageUrl['url'] as String? ?? '';
        final fileBlock = _anthropicFileBlockFromDataUrl(url);
        if (fileBlock != null) {
          blocks.add(fileBlock);
        } else if (url.isNotEmpty) {
          blocks.add({'type': 'text', 'text': '[Attached image: $url]'});
        }
        continue;
      }
      if (type == 'file') {
        final url = map['url'] as String? ?? '';
        final filename = map['filename'] as String? ?? 'file';
        final mediaType = map['mediaType'] as String? ?? '';
        final fileBlock = _anthropicFileBlockFromDataUrl(url);
        if (fileBlock != null) {
          blocks.add(fileBlock);
        } else if (url.isNotEmpty) {
          blocks.add({
            'type': 'text',
            'text': '[Attached $mediaType: $filename]',
          });
        }
      }
    }
    return blocks;
  }

  JsonMap? _anthropicFileBlockFromDataUrl(String url) {
    final match = RegExp(r'^data:([^;]+);base64,(.+)$').firstMatch(url);
    if (match == null) return null;
    final mediaType = match.group(1) ?? '';
    final data = match.group(2) ?? '';
    if (mediaType.isEmpty || data.isEmpty) return null;
    if (mediaType.startsWith('image/')) {
      return {
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': mediaType,
          'data': data,
        },
      };
    }
    if (mediaType == 'application/pdf') {
      return {
        'type': 'document',
        'source': {
          'type': 'base64',
          'media_type': mediaType,
          'data': data,
        },
      };
    }
    return null;
  }

  JsonMap buildDebugPayload({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
    String? sessionId,
    bool small = false,
    String? variant,
  }) {
    final maxOut = _resolvedMaxOutputTokens(config);
    if (_usesAnthropicApi(config)) {
      return _buildAnthropicPayload(
        config: config,
        messages: messages,
        tools: tools,
        format: format,
        maxOutputTokens: maxOut,
        sessionId: sessionId,
        small: small,
        variant: variant,
      );
    }
    return _buildOpenAiPayload(
      config: config,
      messages: messages,
      tools: tools,
      format: format,
      maxOutputTokens: _requestedMaxOutputTokens(config),
      sessionId: sessionId,
      small: small,
      variant: variant,
    );
  }

  Future<ModelResponse> _completeAnthropic({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
    required int maxOutputTokens,
    String? sessionId,
    bool small = false,
    String? variant,
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
    final request =
        await client.postUrl(Uri.parse('${config.baseUrl}/messages'));
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
      sessionId: sessionId,
      small: small,
      variant: variant,
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
    required int? maxOutputTokens,
    String? sessionId,
    bool small = false,
    String? variant,
    CancelToken? cancelToken,
    FutureOr<void> Function(String delta)? onTextDelta,
    FutureOr<void> Function(String delta)? onReasoningDelta,
    FutureOr<void> Function({
      required String toolCallId,
      required String toolName,
      required String argumentsText,
      required String argumentsDelta,
    })?
        onToolCallDelta,
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
      sessionId: sessionId,
      small: small,
      variant: variant,
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
        final incomingId = (map['id'] as String?)?.trim() ?? '';
        final function =
            Map<String, dynamic>.from(map['function'] as Map? ?? const {});
        final incomingName = (function['name'] as String?)?.trim() ?? '';
        final existing = toolBuffers[index];
        if (existing == null) {
          if (incomingId.isEmpty) {
            throw Exception(
              'Invalid tool call delta: expected id for new tool call at index $index',
            );
          }
          if (incomingName.isEmpty) {
            throw Exception(
              'Invalid tool call delta: expected function.name for new tool call at index $index',
            );
          }
        }
        final buffer = existing ?? _ToolCallBuffer();
        if (incomingId.isNotEmpty) {
          buffer.id = incomingId;
        }
        if (incomingName.isNotEmpty) {
          buffer.name = incomingName;
        }
        toolBuffers[index] = buffer;
        final args = function['arguments'] as String? ?? '';
        if (args.isNotEmpty) {
          buffer.arguments.write(args);
        }
        final readyId = (buffer.id ?? '').trim();
        final readyName = (buffer.name ?? '').trim();
        if (onToolCallDelta != null &&
            readyId.isNotEmpty &&
            readyName.isNotEmpty) {
          await onToolCallDelta(
            toolCallId: readyId,
            toolName: readyName,
            argumentsText: buffer.arguments.toString(),
            argumentsDelta: args,
          );
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
      _debugLog(
          'gateway',
          'stream closed by idle timeout without model finish_reason '
              '(events=$eventCount text=${text.length} reasoning=${reasoning.length})');
    }
    _debugLog('gateway',
        'complete end events=$eventCount tools=${toolBuffers.length}');

    final toolCalls = toolBuffers.entries.map((entry) {
      final buffer = entry.value;
      final callId = (buffer.id ?? '').trim();
      final toolName = (buffer.name ?? '').trim();
      if (callId.isEmpty) {
        throw Exception(
          'Invalid tool call stream ended without id for index ${entry.key}',
        );
      }
      if (toolName.isEmpty) {
        throw Exception(
          'Invalid tool call stream ended without function.name for index ${entry.key}',
        );
      }
      return ToolCall(
        id: callId,
        name: toolName,
        arguments: _decodeArguments(
          buffer.arguments.toString(),
          source: 'openai-stream',
          provider: config.provider,
          model: config.model,
          toolName: toolName,
        ),
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
    String? sessionId,
    bool small = false,
    String? variant,
    CancelToken? cancelToken,
    FutureOr<void> Function(String delta)? onTextDelta,
    FutureOr<void> Function(String delta)? onReasoningDelta,
    FutureOr<void> Function({
      required String toolCallId,
      required String toolName,
      required String argumentsText,
      required String argumentsDelta,
    })?
        onToolCallDelta,
  }) async {
    final maxOut = _resolvedMaxOutputTokens(config);
    if (_usesAnthropicApi(config)) {
      return _completeAnthropic(
        config: config,
        messages: messages,
        tools: tools,
        format: format,
        maxOutputTokens: maxOut,
        sessionId: sessionId,
        small: small,
        variant: variant,
        cancelToken: cancelToken,
      );
    }
    return _completeOpenAiCompatible(
      config: config,
      messages: messages,
      tools: tools,
      format: format,
      maxOutputTokens: _requestedMaxOutputTokens(config),
      sessionId: sessionId,
      small: small,
      variant: variant,
      cancelToken: cancelToken,
      onTextDelta: onTextDelta,
      onReasoningDelta: onReasoningDelta,
      onToolCallDelta: onToolCallDelta,
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
        arguments: _decodeArguments(
          rawArguments,
          source: 'openai-nonstream',
          toolName: function['name'] as String?,
        ),
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

  JsonMap _decodeArguments(
    String input, {
    String? source,
    String? provider,
    String? model,
    String? toolName,
  }) {
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(input) as Map);
      _logToolArgumentDecode(
        outcome: 'json',
        input: input,
        source: source,
        provider: provider,
        model: model,
        toolName: toolName,
      );
      return decoded;
    } catch (_) {}
    final repaired = _repairJson(input);
    if (repaired != null) {
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(repaired) as Map);
        _logToolArgumentDecode(
          outcome: 'repaired',
          input: input,
          source: source,
          provider: provider,
          model: model,
          toolName: toolName,
        );
        return decoded;
      } catch (_) {}
    }
    _logToolArgumentDecode(
      outcome: 'raw',
      input: input,
      source: source,
      provider: provider,
      model: model,
      toolName: toolName,
    );
    return {'raw': input};
  }

  void _logToolArgumentDecode({
    required String outcome,
    required String input,
    String? source,
    String? provider,
    String? model,
    String? toolName,
  }) {
    _debugLog('tool-args', 'decoded tool arguments', {
      'outcome': outcome,
      'source': source,
      'provider': provider,
      'model': model,
      'tool': toolName,
      'length': input.length,
      'preview': input.length > 200 ? '${input.substring(0, 200)}...' : input,
    });
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
