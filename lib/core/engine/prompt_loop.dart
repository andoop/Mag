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

      var lastSummarizeAt = 0;
      const summarizeCooldownMs = 30000; // 30s cooldown between compactions

      Future<void> ensureWithinContextBeforeStep(int stepIdx) async {
        final usageCheck = stepIdx == 1
            ? (modelUsageFromLatestCompletedAssistant(
                    messages: cachedMessages, parts: cachedParts) ??
                ModelUsage(
                  inputTokens: activeSession.promptTokens,
                  outputTokens: activeSession.completionTokens,
                ))
            : lastUsage;
        if (usageCheck.isEmpty) return;
        if (!isContextOverflowForCompaction(
          tokens: usageCheck,
          model: modelConfig.model,
        )) {
          return;
        }
        // For step 1 the usageCheck comes from the *previous* turn's
        // stepFinish, recorded BEFORE any post-turn compaction.  If
        // compaction already ran at the end of the last turn the actual
        // conversation may now be well within budget — verify with a
        // cheap token estimate before triggering another (redundant)
        // summarize round.
        if (stepIdx == 1 && activeSession.summaryMessageId.isNotEmpty) {
          final probe = _messagesToConversation(
            messages: cachedMessages,
            parts: cachedParts,
            currentAgent: currentAgent,
            summaryMessageId: activeSession.summaryMessageId,
          );
          final est = estimateSerializedMessagesTokens(probe);
          final budget = usableInputTokensForModel(modelConfig.model);
          if (est < budget) {
            _debugLog('compaction', 'skipping step-1 — stale usage but '
                'actual estimate $est < budget $budget');
            return;
          }
        }
        final now = DateTime.now().millisecondsSinceEpoch;
        if (lastSummarizeAt > 0 && now - lastSummarizeAt < summarizeCooldownMs) {
          _debugLog('compaction', 'skipping — cooldown active '
              '(${now - lastSummarizeAt}ms since last)');
          return;
        }
        lastSummarizeAt = now;
        activeSession = await summarize(
          workspace: workspace,
          session: activeSession,
          modelConfig: modelConfig,
          currentAgent: currentAgent,
        );
        await reloadPromptCaches();
      }

      final maxSteps = definition.steps;
      const hardMaxSteps = 256;
      const maxElapsedMs = 10 * 60 * 1000; // 10 min safety net
      final recentToolSignatures = <String>[];
      const repetitionWindow = 6;
      const repetitionThreshold = 3;
      final consecutiveToolErrors = <String, int>{};
      var totalConsecutiveErrors = 0;
      var emptyResponseRetries = 0;
      const maxEmptyResponseRetries = 2;

      dynamic _canonicalToolArgValue(dynamic value) {
        if (value is Map) {
          final normalized = <String, dynamic>{};
          final entries = value.entries.toList()
            ..sort((a, b) => a.key.compareTo(b.key));
          for (final entry in entries) {
            normalized[entry.key] = _canonicalToolArgValue(entry.value);
          }
          return normalized;
        }
        if (value is List) {
          return value.map(_canonicalToolArgValue).toList();
        }
        if (value is String) {
          if (value.length <= 80) return value;
          return '${value.substring(0, 80)}...(${value.length} chars)';
        }
        return value;
      }

      String _toolSignature(ToolCall call) {
        final normalizedArgs = Map<String, dynamic>.from(call.arguments);
        final path = normalizedArgs['filePath'] ?? normalizedArgs['path'];
        if (path != null) {
          normalizedArgs['filePath'] = path;
          normalizedArgs.remove('path');
        }
        final canonicalArgs = _canonicalToolArgValue(normalizedArgs);
        return '${call.name}:${jsonEncode(canonicalArgs)}';
      }

      bool _isRepetitiveToolPattern(List<ToolCall> calls) {
        if (calls.isEmpty) return false;
        final sig = calls.map(_toolSignature).join('|');
        recentToolSignatures.add(sig);
        if (recentToolSignatures.length < repetitionThreshold) return false;
        final window = recentToolSignatures.length > repetitionWindow
            ? recentToolSignatures.sublist(recentToolSignatures.length - repetitionWindow)
            : recentToolSignatures;
        final counts = <String, int>{};
        for (final s in window) {
          counts[s] = (counts[s] ?? 0) + 1;
        }
        final matched = counts.values.any((c) => c >= repetitionThreshold);
        if (matched) {
          _debugLog('prompt-stop', 'repetitive tool pattern matched', {
            'signature': sig,
            'window': window,
            'counts': counts,
            'threshold': repetitionThreshold,
          });
        }
        return matched;
      }

      var ranOutOfSteps = true;
      for (var step = 1; (maxSteps == null || step <= maxSteps) && step <= hardMaxSteps; step++) {
        cancelToken.throwIfCancelled();
        final elapsed = DateTime.now().millisecondsSinceEpoch - promptStartedAt;
        if (elapsed > maxElapsedMs) {
          _debugLog('prompt', 'elapsed time limit reached (${elapsed}ms)');
          break;
        }
        await ensureWithinContextBeforeStep(step);
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
          summaryMessageId: activeSession.summaryMessageId,
        );
        const maxPreSendCompact = 3;
        final contextWindow = inferContextWindow(modelConfig.model);
        final maxOutputTokens = inferMaxOutputTokens(modelConfig.model);
        final inputBudget = usableInputTokensForModel(modelConfig.model);
        _debugLog('model-limit', 'computed model limits', {
          'provider': modelConfig.provider,
          'model': modelConfig.model,
          'contextWindow': contextWindow,
          'maxOutputTokens': maxOutputTokens,
          'inputBudget': inputBudget,
          'conversationEstimate': estimateSerializedMessagesTokens(conversation),
        });
        for (var preSendRound = 0;
            preSendRound < maxPreSendCompact;
            preSendRound++) {
          var est = estimateSerializedMessagesTokens(conversation);
          if (est < inputBudget) break;
          final summaryBefore = activeSession.summaryMessageId;
          _debugLog('compaction', 'pre-send over budget',
              {'estimate': est, 'budget': inputBudget, 'round': preSendRound});
          lastSummarizeAt = DateTime.now().millisecondsSinceEpoch;
          activeSession = await summarize(
            workspace: workspace,
            session: activeSession,
            modelConfig: modelConfig,
            currentAgent: currentAgent,
          );
          await reloadPromptCaches();
          conversation = await _buildConversation(
            workspace: workspace,
            messages: cachedMessages,
            parts: cachedParts,
            currentStep: step,
            maxSteps: maxSteps,
            currentAgent: currentAgent,
            model: modelConfig.model,
            summaryMessageId: activeSession.summaryMessageId,
          );
          est = estimateSerializedMessagesTokens(conversation);
          if (est < inputBudget) break;
          if (activeSession.summaryMessageId == summaryBefore) {
            final pruned = await _pruneLargestToolOutputsForContext(
              workspace: workspace,
              sessionId: session.id,
              minPrunedEstimate: 8000,
            );
            if (pruned == 0) break;
            await reloadPromptCaches();
            conversation = await _buildConversation(
              workspace: workspace,
              messages: cachedMessages,
              parts: cachedParts,
              currentStep: step,
              maxSteps: maxSteps,
              currentAgent: currentAgent,
              model: modelConfig.model,
              summaryMessageId: activeSession.summaryMessageId,
            );
          }
        }
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
                'content':
                    '<system-warning>\nYou have made repeated tool errors:\n$errSummary\n\n'
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
          if (isEmptyResponse && isTimeout && emptyResponseRetries < maxEmptyResponseRetries) {
            emptyResponseRetries++;
            _debugLog('prompt-retry', 'empty/timeout response — retry $emptyResponseRetries/$maxEmptyResponseRetries', {
              'step': step,
              'finishReason': response.finishReason,
              'textLength': response.text.length,
            });
            continue;
          }
          _debugLog('prompt-stop', 'breaking because model returned no tool calls', {
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
            _debugLog('prompt-stop', 'breaking because structured output returned', {
              'step': step,
              'keys': structured.keys.toList(),
            });
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
            final errorKey = '${call.name}:${_classifyToolError(metadata['error'] as String? ?? '')}';
            consecutiveToolErrors[errorKey] = (consecutiveToolErrors[errorKey] ?? 0) + 1;
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
        if (_isRepetitiveToolPattern(response.toolCalls)) {
          _debugLog('prompt',
              'repetitive tool call pattern detected at step $step — breaking');
          ranOutOfSteps = false;
          break;
        }
      }
      if (ranOutOfSteps && maxSteps != null) {
        _debugLog('prompt',
            'max steps reached ($maxSteps), session=${session.id} — running wrap-up call');
        cancelToken.throwIfCancelled();
        final wrapUpConversation = await _buildConversation(
          workspace: workspace,
          messages: cachedMessages,
          parts: cachedParts,
          currentStep: maxSteps + 1,
          maxSteps: maxSteps,
          currentAgent: currentAgent,
          model: modelConfig.model,
          summaryMessageId: activeSession.summaryMessageId,
        );
        MessagePart? wrapUpTextPart;
        var wrapUpText = '';
        var lastWrapUpSaveText = '';
        var lastWrapUpEmitAt = 0;
        Future<void> flushWrapUpText({bool force = false}) async {
          if (wrapUpText.isEmpty) return;
          if (!force && wrapUpText == lastWrapUpSaveText) return;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (!force && now - lastWrapUpEmitAt < 80) return;
          lastWrapUpEmitAt = now;
          lastWrapUpSaveText = wrapUpText;
          wrapUpTextPart = MessagePart(
            id: wrapUpTextPart?.id ?? newId('part'),
            sessionId: session.id,
            messageId: assistant.id,
            type: PartType.text,
            createdAt: wrapUpTextPart?.createdAt ??
                DateTime.now().millisecondsSinceEpoch,
            data: _assistantTextPartData(wrapUpText),
          );
          await saveTrackedPart(wrapUpTextPart!);
        }

        try {
          final wrapUpResponse = await modelGateway.complete(
            config: modelConfig,
            messages: wrapUpConversation,
            tools: const [],
            format: null,
            cancelToken: cancelToken,
            onTextDelta: (delta) async {
              wrapUpTextPart ??= MessagePart(
                id: newId('part'),
                sessionId: session.id,
                messageId: assistant.id,
                type: PartType.text,
                createdAt: DateTime.now().millisecondsSinceEpoch,
                data: const {'text': ''},
              );
              wrapUpText += delta;
              _emitPartDelta(
                workspace: workspace,
                sessionId: session.id,
                messageId: assistant.id,
                partId: wrapUpTextPart!.id,
                partType: PartType.text,
                createdAt: wrapUpTextPart!.createdAt,
                delta: {'text': delta},
              );
              await flushWrapUpText();
            },
          );
          await flushWrapUpText(force: true);
          if (wrapUpResponse.text.trim().isNotEmpty && wrapUpTextPart == null) {
            await saveTrackedPart(
              MessagePart(
                id: newId('part'),
                sessionId: session.id,
                messageId: assistant.id,
                type: PartType.text,
                createdAt: DateTime.now().millisecondsSinceEpoch,
                data: _assistantTextPartData(wrapUpResponse.text),
              ),
            );
          }
          lastFinishReason = wrapUpResponse.finishReason;
          lastUsage = wrapUpResponse.usage;
          activeSession = await _trackUsage(
            workspace: workspace,
            session: activeSession,
            usage: wrapUpResponse.usage,
          );
          _debugLog('prompt', 'wrap-up call completed');
        } catch (e) {
          _debugLog('prompt', 'wrap-up call failed: $e');
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
      final sinceLastSummarize = DateTime.now().millisecondsSinceEpoch - lastSummarizeAt;
      if (_shouldAutoCompactAfterTurn(lastUsage, modelConfig.model) &&
          (lastSummarizeAt == 0 || sinceLastSummarize >= summarizeCooldownMs)) {
        activeSession = await summarize(
          workspace: workspace,
          session: activeSession,
          modelConfig: modelConfig,
          currentAgent: currentAgent,
        );
      }
      _debugLog('prompt-stop', 'turn finished', {
        'ranOutOfSteps': ranOutOfSteps,
        'lastFinishReason': lastFinishReason,
        'maxSteps': maxSteps,
        'assistantMessageId': assistant.id,
      });
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
