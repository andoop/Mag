part of '../session_engine.dart';

extension SessionEnginePrompt on SessionEngine {
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
    List<JsonMap>? userParts,
    String? variant,
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
    _emitSessionStatus(
      sessionId: session.id,
      status: const SessionRunStatus(phase: SessionRunPhase.busy),
      directory: workspace.treeUri,
    );
    try {
      final modelConfig = await _loadResolvedModelConfig();
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

      JsonMap? tryDecodeToolInput(String raw) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) return <String, dynamic>{};
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          // Tool arguments are often incomplete while streaming; keep raw text.
        }
        return null;
      }

      List<MessagePart> userPartsForMessage(MessageInfo message) {
        final items = cachedParts
            .where((part) =>
                part.messageId == message.id &&
                part.type != PartType.compaction)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return items;
      }

      String textFromUserParts(List<MessagePart> parts) {
        return parts
            .where((part) => part.type == PartType.text)
            .map((part) => part.data['text'] as String? ?? '')
            .where((text) => text.isNotEmpty)
            .join('\n');
      }

      Future<void> saveUserPartsForMessage(
        MessageInfo message, {
        String? fallbackText,
        bool synthetic = false,
        List<JsonMap>? parts,
      }) async {
        final existing = userPartsForMessage(message);
        if (existing.isNotEmpty) return;
        final specs = (parts ?? const <JsonMap>[])
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        final hasTextPart =
            specs.any((item) => item['type'] == PartType.text.name);
        final fallback = fallbackText ?? message.text;
        if (!hasTextPart && fallback.isNotEmpty) {
          specs.insert(0, {
            'type': PartType.text.name,
            'text': fallback,
            if (synthetic) 'synthetic': true,
          });
        }
        for (final spec in specs) {
          final typeName = spec['type'] as String? ?? PartType.text.name;
          final type = PartType.values.firstWhere(
            (item) => item.name == typeName,
            orElse: () => PartType.text,
          );
          final data = Map<String, dynamic>.from(spec)..remove('type');
          if (type == PartType.text &&
              (data['text'] as String? ?? '').isEmpty) {
            continue;
          }
          await saveTrackedPart(
            MessagePart(
              id: newId('part'),
              sessionId: session.id,
              messageId: message.id,
              type: type,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              data: data,
            ),
          );
        }
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
        variant: variant,
      );
      await saveTrackedMessage(userMessage);
      await saveUserPartsForMessage(
        userMessage,
        fallbackText: text,
        parts: userParts,
      );
      final userMsgCount =
          cachedMessages.where((m) => m.role == SessionRole.user).length;
      if (userMsgCount == 1) {
        unawaited(
          _ensureSessionTitle(
            workspace: workspace,
            sessionId: session.id,
            history: List.of(cachedMessages),
            historyParts: List.of(cachedParts),
          ),
        );
      }
      var currentUserMessage = userMessage;
      var currentAgent = userAgent;
      late MessageInfo assistant;

      Future<void> startAssistantTurn() async {
        assistant = MessageInfo(
          id: newId('message'),
          sessionId: session.id,
          role: SessionRole.assistant,
          agent: currentAgent,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          model: modelConfig.model,
          provider: modelConfig.provider,
          parentMessageId: currentUserMessage.id,
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
      }

      Future<void> upsertStreamingToolPart({
        required String callId,
        required String toolName,
        required String argumentsText,
      }) async {
        final existing = toolPartByCallId[callId];
        final decodedInput = tryDecodeToolInput(argumentsText);
        final existingState = Map<String, dynamic>.from(
            (existing?.data['state'] as Map?) ?? const {});
        final existingInput = Map<String, dynamic>.from(
            existingState['input'] as Map? ?? const {});
        final shouldCreate = existing == null;
        final shouldUpgradeInput = decodedInput != null &&
            jsonEncode(existingInput) != jsonEncode(decodedInput);
        if (!shouldCreate && !shouldUpgradeInput) {
          return;
        }
        final nextState = <String, dynamic>{
          'status': ToolStatus.pending.name,
          'input': decodedInput ?? existingInput,
          'raw': shouldCreate
              ? argumentsText
              : (existingState['raw'] ?? argumentsText),
        };
        final nextPart = MessagePart(
          id: existing?.id ?? newId('part'),
          sessionId: session.id,
          messageId: assistant.id,
          type: PartType.tool,
          createdAt:
              existing?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
          data: {
            'tool': toolName,
            'callID': callId,
            'state': {
              ...existingState,
              ...nextState,
            },
          },
        );
        await saveTrackedPart(nextPart);
      }

      Future<void> reloadPromptCaches() async {
        final msgs = await database.listMessages(session.id);
        final prts = await database.listPartsForSession(session.id);
        cachedMessages
          ..clear()
          ..addAll(msgs);
        cachedParts
          ..clear()
          ..addAll(prts);
        toolPartByCallId.clear();
        for (final p in cachedParts) {
          final callId = p.data['callID'] as String?;
          if (p.type == PartType.tool && callId != null && callId.isNotEmpty) {
            toolPartByCallId[callId] = p;
          }
        }
      }

      String syntheticContinueText({required bool overflow}) {
        final prefix = overflow
            ? 'The previous request exceeded the provider\'s size limit due to '
                'large media attachments. The conversation was compacted and '
                'media files were removed from context. If the user was asking '
                'about attached images or files, explain that the attachments '
                'were too large to process and suggest they try again with '
                'smaller or fewer files.\n\n'
            : '';
        return '$prefix'
            'Continue if you have next steps, or stop and ask for clarification '
            'if you are unsure how to proceed.';
      }

      Future<MessageInfo> replayUserAfterCompaction({
        required MessageInfo original,
        required bool overflow,
      }) async {
        final originalParts = userPartsForMessage(original);
        final replayText = textFromUserParts(originalParts).trim().isNotEmpty
            ? textFromUserParts(originalParts)
            : (original.text.trim().isNotEmpty
                ? original.text
                : syntheticContinueText(overflow: overflow));
        final replay = MessageInfo(
          id: newId('message'),
          sessionId: session.id,
          role: SessionRole.user,
          agent: original.agent,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          text: replayText,
          format: original.format,
          model: original.model,
          provider: original.provider,
          variant: original.variant,
        );
        await saveTrackedMessage(replay);
        if (originalParts.isNotEmpty) {
          for (final part in originalParts) {
            await saveTrackedPart(
              MessagePart(
                id: newId('part'),
                sessionId: session.id,
                messageId: replay.id,
                type: part.type,
                createdAt: DateTime.now().millisecondsSinceEpoch,
                data: Map<String, dynamic>.from(part.data),
              ),
            );
          }
        } else {
          await saveUserPartsForMessage(
            replay,
            fallbackText: replayText,
            synthetic: replayText == syntheticContinueText(overflow: overflow),
          );
        }
        return replay;
      }

      Future<void> ensureWithinContextBeforeStep(int stepIdx) async {
        if (stepIdx != 1) return;
        MessageInfo? latestAssistantMessage() {
          final assistants = cachedMessages
              .where((message) => message.role == SessionRole.assistant)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return assistants.isEmpty ? null : assistants.first;
        }

        final usageCheck = modelUsageFromLatestCompletedAssistant(
              messages: cachedMessages,
              parts: cachedParts,
            ) ??
            ModelUsage(
              inputTokens: activeSession.promptTokens,
              outputTokens: activeSession.completionTokens,
            );
        if (usageCheck.isEmpty) return;
        if ((latestAssistantMessage()?.summary ?? false) == true) {
          return;
        }
        if (!isContextOverflowForCompaction(
          tokens: usageCheck,
          model: modelConfig.model,
          limit: modelConfig.currentModelLimit,
        )) {
          return;
        }
        activeSession = await summarize(
          workspace: workspace,
          session: activeSession,
          modelConfig: modelConfig,
          currentAgent: currentAgent,
        );
        await reloadPromptCaches();
        currentUserMessage = await replayUserAfterCompaction(
          original: currentUserMessage,
          overflow: false,
        );
        currentAgent = currentUserMessage.agent;
      }

      final maxSteps = definition.steps;
      const maxElapsedMs = 10 * 60 * 1000; // 10 min safety net
      final consecutiveToolErrors = <String, int>{};
      var totalConsecutiveErrors = 0;
      const maxEmptyResponseRetries = 2;
      while (true) {
        var emptyResponseRetries = 0;
        var lastFinishReason = 'stop';
        var lastUsage = const ModelUsage();
        var loggedFirstDelta = false;
        var ranOutOfSteps = true;
        for (var step = 1; maxSteps == null || step <= maxSteps; step++) {
          cancelToken.throwIfCancelled();
          final elapsed =
              DateTime.now().millisecondsSinceEpoch - promptStartedAt;
          if (elapsed > maxElapsedMs) {
            _debugLog('prompt', 'elapsed time limit reached (${elapsed}ms)');
            break;
          }
          await ensureWithinContextBeforeStep(step);
          if (step == 1) {
            await startAssistantTurn();
          }
          _emitSessionStatus(
            sessionId: session.id,
            status: const SessionRunStatus(phase: SessionRunPhase.busy),
            directory: workspace.treeUri,
          );
          final buildConversationStartedAt =
              DateTime.now().millisecondsSinceEpoch;
          var conversation = await _buildConversation(
            workspace: workspace,
            messages: cachedMessages,
            parts: cachedParts,
            currentStep: step,
            maxSteps: maxSteps,
            currentAgent: currentAgent,
            model: modelConfig.model,
          );
          final contextWindow = contextWindowForModel(
            modelConfig.model,
            limit: modelConfig.currentModelLimit,
          );
          final maxOutputTokens = maxOutputTokensForModel(
            modelConfig.model,
            limit: modelConfig.currentModelLimit,
          );
          final inputBudget = usableInputTokensForModel(
            modelConfig.model,
            limit: modelConfig.currentModelLimit,
          );
          _debugLog('model-limit', 'computed model limits', {
            'provider': modelConfig.provider,
            'model': modelConfig.model,
            'contextWindow': contextWindow,
            'maxOutputTokens': maxOutputTokens,
            'inputBudget': inputBudget,
            'conversationEstimate':
                estimateSerializedMessagesTokens(conversation),
          });
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
          if (totalConsecutiveErrors >= 2) {
            final errSummary = consecutiveToolErrors.entries
                .where((e) => e.value >= 2)
                .map((e) => '- ${e.key}: ${e.value} consecutive failures')
                .join('\n');
            if (errSummary.isNotEmpty) {
              conversation = [
                ...conversation,
                {
                  'role': 'user',
                  'content': '<system-warning>\nYou have made repeated tool errors:\n$errSummary\n\n'
                      'STOP and reconsider your approach. Do NOT retry the same failing call.\n'
                      'Common fixes:\n'
                      '- If `write` failed because file exists → use `edit` instead\n'
                      '- If `edit` failed because no read → call `read` first\n'
                      '- If `edit` failed because oldString not found → call `read` to get current contents, then use exact text from the output\n'
                      '- If anchors are stale → call `read` to get fresh LINE#ID anchors\n'
                      'Read the error messages above carefully and take a DIFFERENT action.\n'
                      '</system-warning>',
                },
              ];
            }
          }
          final toolModels = [
            ...toolRegistry.availableForAgent(
              agentDefinition(currentAgent),
              modelId: modelConfig.model,
            ),
            if (currentUserMessage.format?.type == OutputFormatType.jsonSchema)
              ToolDefinitionModel(
                id: 'StructuredOutput',
                description: 'Return the final structured response as JSON.',
                parameters: currentUserMessage.format!.schema ??
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

          late ModelResponse response;
          var compactDueToOverflow = false;
          var attempt = 0;
          while (true) {
            try {
              cancelToken.throwIfCancelled();
              _debugLog('prompt-step', 'requesting model completion', {
                'step': step,
                'provider': modelConfig.provider,
                'model': modelConfig.model,
                'conversationItems': conversation.length,
                'toolCount': toolModels.length,
                'currentAgent': currentAgent,
              });
              response = await modelGateway.complete(
                config: modelConfig,
                messages: conversation,
                tools: toolModels,
                format: currentUserMessage.format,
                sessionId: session.id,
                variant: currentUserMessage.variant,
                cancelToken: cancelToken,
                onTextDelta: (delta) async {
                  if (!loggedFirstDelta) {
                    loggedFirstDelta = true;
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
                onToolCallDelta: ({
                  required toolCallId,
                  required toolName,
                  required argumentsText,
                  required argumentsDelta,
                }) async {
                  await upsertStreamingToolPart(
                    callId: toolCallId,
                    toolName: toolName,
                    argumentsText: argumentsText,
                  );
                },
              );
              break;
            } on CancelledException {
              rethrow;
            } catch (error) {
              if (_isContextOverflowError(error)) {
                compactDueToOverflow = true;
                lastFinishReason = 'length';
                _debugLog('prompt-overflow', 'context overflow, compacting', {
                  'step': step,
                  'provider': modelConfig.provider,
                  'model': modelConfig.model,
                  'error': error.toString(),
                });
                break;
              }
              if (!_isRetryableError(error) || attempt >= _maxRetryAttempts) {
                rethrow;
              }
              attempt++;
              final delay = _retryDelay(attempt);
              _debugLog(
                  'retry', 'attempt=$attempt delay=${delay}ms error=$error');
              _emitSessionStatus(
                sessionId: session.id,
                status: SessionRunStatus(
                  phase: SessionRunPhase.retry,
                  attempt: attempt,
                  message: _retryMessage(error),
                  next: DateTime.now().millisecondsSinceEpoch + delay,
                ),
                directory: workspace.treeUri,
              );
              try {
                await cancelToken
                    .guard(Future.delayed(Duration(milliseconds: delay)));
              } on CancelledException {
                rethrow;
              }
            }
          }

          if (compactDueToOverflow) {
            await flushStreamingText(force: true);
            await flushStreamingReasoning(force: true);
            ranOutOfSteps = false;
            break;
          }

          await flushStreamingText(force: true);
          await flushStreamingReasoning(force: true);
          lastFinishReason = response.finishReason;
          lastUsage = response.usage;
          _debugLog('prompt-step', 'model response received', {
            'step': step,
            'finishReason': response.finishReason,
            'toolCallCount': response.toolCalls.length,
            'toolCalls': response.toolCalls
                .map((call) => {
                      'id': call.id,
                      'name': call.name,
                      'argKeys': call.arguments.keys.toList(),
                      'hasRaw': call.arguments.containsKey('raw'),
                    })
                .toList(),
            'textPreview': response.text.length > 160
                ? '${response.text.substring(0, 160)}...'
                : response.text,
          });
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
          if (response.toolCalls.isEmpty) {
            final isEmptyResponse = response.text.trim().isEmpty;
            final isTimeout = response.finishReason == 'timeout';
            if (isEmptyResponse &&
                isTimeout &&
                emptyResponseRetries < maxEmptyResponseRetries) {
              emptyResponseRetries++;
              _debugLog(
                  'prompt-retry',
                  'empty/timeout response — retry $emptyResponseRetries/$maxEmptyResponseRetries',
                  {
                    'step': step,
                    'finishReason': response.finishReason,
                    'textLength': response.text.length,
                  });
              continue;
            }
            _debugLog('prompt-stop',
                'breaking because model returned no tool calls', {
              'step': step,
              'finishReason': response.finishReason,
              'textLength': response.text.length,
              'isEmptyResponse': isEmptyResponse,
              'isTimeout': isTimeout,
              'emptyResponseRetries': emptyResponseRetries,
            });
            ranOutOfSteps = false;
            break;
          }
          emptyResponseRetries = 0;
          var shouldBreak = false;
          for (final call in response.toolCalls) {
            cancelToken.throwIfCancelled();
            _debugLog('prompt-tool', 'executing tool call', {
              'step': step,
              'callId': call.id,
              'tool': call.name,
              'argKeys': call.arguments.keys.toList(),
              'args': call.arguments,
            });
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
              _debugLog('prompt-stop',
                  'breaking because structured output returned', {
                'step': step,
                'keys': structured.keys.toList(),
              });
              break;
            }
            final existingToolPart = toolPartByCallId[call.id];
            final toolPart = MessagePart(
              id: existingToolPart?.id ?? newId('part'),
              sessionId: session.id,
              messageId: assistant.id,
              type: PartType.tool,
              createdAt: existingToolPart?.createdAt ??
                  DateTime.now().millisecondsSinceEpoch,
              data: {
                'tool': call.name,
                'callID': call.id,
                'state': {
                  ...Map<String, dynamic>.from(
                    (existingToolPart?.data['state'] as Map?) ?? const {},
                  ),
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
            _debugLog('prompt-tool', 'tool execution finished', {
              'step': step,
              'callId': call.id,
              'tool': call.name,
              'metadata': metadata,
              'outputPreview': result.output.length > 200
                  ? '${result.output.substring(0, 200)}...'
                  : result.output,
            });
            if (metadata['failed'] == true) {
              final errorKey =
                  '${call.name}:${_classifyToolError(metadata['error'] as String? ?? '')}';
              consecutiveToolErrors[errorKey] =
                  (consecutiveToolErrors[errorKey] ?? 0) + 1;
              totalConsecutiveErrors++;
            } else {
              consecutiveToolErrors.clear();
              totalConsecutiveErrors = 0;
            }
            if (metadata['switchAgent'] == 'build') {
              currentAgent = 'build';
            }
          }
          activeSession = await _trackUsage(
            workspace: workspace,
            session: activeSession,
            usage: response.usage,
          );
          if (shouldBreak) {
            ranOutOfSteps = false;
            break;
          }
        }
        await saveTrackedPart(
          MessagePart(
            id: newId('part'),
            sessionId: session.id,
            messageId: assistant.id,
            type: PartType.stepFinish,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            data: {
              'reason': ranOutOfSteps ? 'max_steps' : lastFinishReason,
              'tokens': lastUsage.toJson(),
              'cost': activeSession.cost,
            },
          ),
        );
        final shouldAutoCompact = lastFinishReason == 'length' ||
            _shouldAutoCompactAfterTurn(lastUsage, modelConfig);
        await _pruneToolOutputsForContext(
          workspace: workspace,
          sessionId: session.id,
        );
        if (shouldAutoCompact) {
          activeSession = await summarize(
            workspace: workspace,
            session: activeSession,
            modelConfig: modelConfig,
            currentAgent: currentAgent,
          );
          await reloadPromptCaches();
          currentUserMessage = await replayUserAfterCompaction(
            original: currentUserMessage,
            overflow: lastFinishReason == 'length',
          );
          currentAgent = currentUserMessage.agent;
          _debugLog('prompt-compact', 'auto-compacted and replayed user turn', {
            'assistantMessageId': assistant.id,
            'replayUserMessageId': currentUserMessage.id,
            'overflow': lastFinishReason == 'length',
          });
          continue;
        }
        _debugLog('prompt-stop', 'turn finished', {
          'ranOutOfSteps': ranOutOfSteps,
          'lastFinishReason': lastFinishReason,
          'maxSteps': maxSteps,
          'assistantMessageId': assistant.id,
        });
        _debugLog('prompt', 'success finishReason=$lastFinishReason');
        return assistant;
      }
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
      _emitSessionStatus(
        sessionId: session.id,
        status: const SessionRunStatus.idle(),
        directory: workspace.treeUri,
      );
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
}
