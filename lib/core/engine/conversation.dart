part of '../session_engine.dart';

extension SessionEngineConversation on SessionEngine {
  Future<List<Map<String, dynamic>>> _buildConversation({
    required WorkspaceInfo workspace,
    required List<MessageInfo> messages,
    required List<MessagePart> parts,
    required int currentStep,
    required int? maxSteps,
    required String currentAgent,
    required String model,
  }) async {
    final currentAgentDefinition = agentDefinition(currentAgent);
    MessageInfo? latestUser;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == SessionRole.user) {
        latestUser = messages[i];
        break;
      }
    }
    final zh = platformIsZh;
    final effectiveTools = (await availableToolModels(
      workspace,
      currentAgentDefinition,
      modelId: model,
    ))
        .map((item) => item.id)
        .toList();
    final availableSkills = effectiveTools.contains('skill')
        ? await SkillRegistry.instance.available(
            workspace,
            agentDefinition: currentAgentDefinition,
          )
        : const <SkillInfo>[];
    final sessionContracts = _sessionContractItems(messages, parts);
    final system = await promptAssembler.buildSystemPrompts(
      PromptContext(
        workspace: workspace,
        agent: currentAgent,
        agentDefinition: currentAgentDefinition,
        model: model,
        effectiveTools: effectiveTools,
        agentPrompt: currentAgentDefinition.promptOverride,
        hasSkillTool: effectiveTools.contains('skill'),
        availableSkills: availableSkills,
        format: latestUser?.format,
        allAgents: listAgents(),
        deviceCapabilities:
            DeviceCapabilityRegistry.instance.promptCatalog(zh: zh),
        isZh: zh,
      ),
    );
    final conversation = <Map<String, dynamic>>[];
    conversation.addAll(system);
    conversation.addAll(
      _messagesToConversation(
        messages: messages,
        parts: parts,
        currentAgent: currentAgent,
        latestUserId: latestUser?.id,
        sessionContracts: sessionContracts,
        isZh: zh,
      ),
    );
    if (maxSteps != null && currentStep >= maxSteps) {
      conversation.add({
        'role': 'assistant',
        'content': promptAssembler.maxStepsReminder(zh: zh),
      });
    }
    return conversation;
  }

  List<Map<String, dynamic>> _messagesToConversation({
    required List<MessageInfo> messages,
    required List<MessagePart> parts,
    required String currentAgent,
    required String? latestUserId,
    required List<String> sessionContracts,
    bool isZh = false,
  }) {
    final partsByMessage = <String, List<MessagePart>>{};
    for (final part in parts) {
      partsByMessage.putIfAbsent(part.messageId, () => []).add(part);
    }
    List<MessageInfo> filterCompactedMessages() {
      final result = <MessageInfo>[];
      final completed = <String>{};
      for (var i = messages.length - 1; i >= 0; i--) {
        final message = messages[i];
        result.add(message);
        final messageParts =
            partsByMessage[message.id] ?? const <MessagePart>[];
        if (message.role == SessionRole.user &&
            completed.contains(message.id) &&
            messageParts.any((part) => part.type == PartType.compaction)) {
          break;
        }
        if (message.role == SessionRole.assistant &&
            message.summary &&
            (message.error == null || message.error!.isEmpty) &&
            (message.parentMessageId?.isNotEmpty ?? false)) {
          completed.add(message.parentMessageId!);
        }
      }
      return result.reversed.toList();
    }

    var visibleMessages = filterCompactedMessages();
    if (visibleMessages.isEmpty) {
      visibleMessages = messages;
    }
    final retainedImageMessageIds = <String>{};
    var retainedHistoricalImageTurns = 0;
    for (final message in visibleMessages.reversed) {
      if (message.role != SessionRole.user) continue;
      final messageParts = partsByMessage[message.id] ?? const <MessagePart>[];
      final hasDataImage = messageParts.any((part) {
        if (part.type != PartType.file) return false;
        final mime = part.data['mime'] as String? ?? '';
        final url = part.data['url'] as String? ?? '';
        return mime.startsWith('image/') && url.startsWith('data:');
      });
      if (!hasDataImage) continue;
      if (message.id == latestUserId) {
        retainedImageMessageIds.add(message.id);
        continue;
      }
      if (retainedHistoricalImageTurns < 2) {
        retainedImageMessageIds.add(message.id);
        retainedHistoricalImageTurns++;
      }
    }
    // Pre-pass: assign a chronological sequence number to every tool part and
    // remember, per file path, the sequence of the LAST editing operation that
    // touched it. We later fold any read/write/edit/apply_patch output that is
    // superseded by a later edit to the same path. This is a runtime-only
    // compaction of the model context — it does NOT mutate the DB or the UI.
    final toolPartSeq = <String, int>{};
    final lastEditSeqForPath = <String, int>{};
    var seq = 0;
    for (final message in visibleMessages) {
      if (message.role != SessionRole.assistant) continue;
      final mParts = partsByMessage[message.id] ?? const <MessagePart>[];
      for (final part in mParts) {
        if (part.type != PartType.tool) continue;
        final callId = part.data['callID'] as String?;
        if (callId == null) continue;
        final current = seq++;
        toolPartSeq[callId] = current;
        final toolName = jsonStringCoerce(part.data['tool'], '');
        if (!_editingFileTools.contains(toolName)) continue;
        final state =
            Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
        if ((state['status'] as String? ?? '') != 'completed') continue;
        for (final path in _toolPartPaths(part)) {
          final existing = lastEditSeqForPath[path];
          if (existing == null || current > existing) {
            lastEditSeqForPath[path] = current;
          }
        }
      }
    }

    final conversation = <Map<String, dynamic>>[];
    for (var i = 0; i < visibleMessages.length; i++) {
      final message = visibleMessages[i];
      final messageParts = partsByMessage[message.id] ?? const [];
      final hasCompactionPart =
          messageParts.any((item) => item.type == PartType.compaction);
      if (message.role == SessionRole.user && hasCompactionPart) {
        conversation.add({
          'role': 'user',
          'content': 'What did we do so far?',
        });
        continue;
      }
      if (message.role == SessionRole.user) {
        final switchedFromPlan =
            currentAgent == 'build' && message.agent == 'plan';
        final isLatestUser = message.id == latestUserId;
        final userContent = _userMessageContent(
          message,
          messageParts,
          includeImageData: retainedImageMessageIds.contains(message.id),
        );
        if (userContent is String) {
          var text = promptAssembler.applyUserReminder(
            agent: message.agent,
            switchedFromPlan: switchedFromPlan,
            text: userContent,
            isZh: isZh,
          );
          if (isLatestUser) {
            text = promptAssembler.applyLatestUserContext(
              text: text,
              sessionContracts: sessionContracts,
              isZh: isZh,
            );
          }
          conversation.add({
            'role': 'user',
            'content': text,
          });
        } else {
          final blocks = userContent.cast<Map<String, dynamic>>();
          final firstText = blocks.isNotEmpty &&
                  blocks.first['type'] == 'text' &&
                  (blocks.first['text'] as String? ?? '').isNotEmpty
              ? Map<String, dynamic>.from(blocks.first)
              : null;
          if (firstText != null) {
            firstText['text'] = promptAssembler.applyUserReminder(
              agent: message.agent,
              switchedFromPlan: switchedFromPlan,
              text: firstText['text'] as String? ?? '',
              isZh: isZh,
            );
            if (isLatestUser) {
              firstText['text'] = promptAssembler.applyLatestUserContext(
                text: firstText['text'] as String? ?? '',
                sessionContracts: sessionContracts,
                isZh: isZh,
              );
            }
            blocks[0] = firstText;
          } else {
            var reminder = promptAssembler.applyUserReminder(
              agent: message.agent,
              switchedFromPlan: switchedFromPlan,
              text: '',
              isZh: isZh,
            );
            if (isLatestUser) {
              reminder = promptAssembler.applyLatestUserContext(
                text: reminder,
                sessionContracts: sessionContracts,
                isZh: isZh,
              );
            }
            if (reminder.isEmpty) {
              conversation.add({
                'role': 'user',
                'content': blocks,
              });
              continue;
            }
            blocks.insert(
              0,
              {
                'type': 'text',
                'text': reminder,
              },
            );
          }
          conversation.add({
            'role': 'user',
            'content': blocks,
          });
        }
        continue;
      }
      final textParts = messageParts
          .where((item) => item.type == PartType.text)
          .map(_partRawText)
          .join('\n');
      final reasoningText = messageParts
          .where((item) => item.type == PartType.reasoning)
          .map((item) => item.data['text'] as String? ?? '')
          .where((item) => item.isNotEmpty)
          .join('\n');
      final toolParts =
          messageParts.where((item) => item.type == PartType.tool).toList();
      if (toolParts.isNotEmpty) {
        conversation.add({
          'role': 'assistant',
          'content': textParts.isEmpty ? null : textParts,
          if (reasoningText.isNotEmpty) 'reasoning_text': reasoningText,
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
          final status = state['status'] as String? ?? '';
          final time =
              Map<String, dynamic>.from(state['time'] as Map? ?? const {});
          final compacted = (time['compacted'] as num?) != null;
          var output = (status == 'pending' || status == 'running')
              ? '[Tool execution was interrupted]'
              : (compacted
                  ? '[Old tool result content cleared]'
                  : state['output'] as String? ?? '');
          if (status != 'pending' && status != 'running' && !compacted) {
            final folded = _foldSupersededToolOutput(
              part: part,
              toolPartSeq: toolPartSeq,
              lastEditSeqForPath: lastEditSeqForPath,
            );
            if (folded != null) output = folded;
          }
          conversation.add({
            'role': 'tool',
            'tool_call_id': part.data['callID'],
            'content': output,
          });
        }
      } else if (textParts.isNotEmpty || reasoningText.isNotEmpty) {
        conversation.add({
          'role': 'assistant',
          'content': textParts,
          if (reasoningText.isNotEmpty) 'reasoning_text': reasoningText,
        });
      }
    }
    return conversation;
  }

  /// Tools whose outputs are bound to a file path and therefore foldable when
  /// a later edit to the same path supersedes them.
  static const Set<String> _foldableFileTools = {
    'read',
    'write',
    'edit',
    'apply_patch',
  };

  /// Tools that, when run, change a file's content (and thus invalidate
  /// earlier reads/edits of the same path in the model's context).
  static const Set<String> _editingFileTools = {
    'write',
    'edit',
    'apply_patch',
  };

  String _normalizeFoldPath(String path) {
    var p = path.trim();
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    if (p.startsWith('/')) p = p.substring(1);
    return p;
  }

  /// Extracts the workspace-relative file path(s) a tool part operated on,
  /// looking at the recorded read-ledger metadata first (most reliable) and
  /// falling back to the tool input arguments.
  Set<String> _toolPartPaths(MessagePart part) {
    final paths = <String>{};
    final state =
        Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
    final metadata =
        Map<String, dynamic>.from(state['metadata'] as Map? ?? const {});
    final single = metadata['readLedger'];
    if (single is Map) {
      final p = single['path'] as String? ?? '';
      if (p.isNotEmpty) paths.add(_normalizeFoldPath(p));
    }
    final multiple = metadata['readLedgers'];
    if (multiple is List) {
      for (final item in multiple.whereType<Map>()) {
        final p = item['path'] as String? ?? '';
        if (p.isNotEmpty) paths.add(_normalizeFoldPath(p));
      }
    }
    final files = metadata['files'];
    if (files is List) {
      for (final f in files.whereType<String>()) {
        if (f.isNotEmpty) paths.add(_normalizeFoldPath(f));
      }
    }
    final metaPath = metadata['path'] as String? ?? metadata['filepath'] as String? ?? '';
    if (metaPath.isNotEmpty) paths.add(_normalizeFoldPath(metaPath));
    if (paths.isEmpty) {
      final input =
          Map<String, dynamic>.from(state['input'] as Map? ?? const {});
      final inputPath = input['filePath'] as String? ?? '';
      if (inputPath.isNotEmpty) paths.add(_normalizeFoldPath(inputPath));
    }
    return paths;
  }

  /// Returns folded replacement content if this tool part's output is
  /// superseded by a strictly-later edit to the same path; otherwise null
  /// (meaning: keep the original output verbatim).
  String? _foldSupersededToolOutput({
    required MessagePart part,
    required Map<String, int> toolPartSeq,
    required Map<String, int> lastEditSeqForPath,
  }) {
    final toolName = jsonStringCoerce(part.data['tool'], '');
    if (!_foldableFileTools.contains(toolName)) return null;
    final callId = part.data['callID'] as String?;
    if (callId == null) return null;
    final mySeq = toolPartSeq[callId];
    if (mySeq == null) return null;
    final paths = _toolPartPaths(part);
    if (paths.isEmpty) return null;
    // Fold only when EVERY path this part touched has a strictly-later edit.
    for (final path in paths) {
      final lastEdit = lastEditSeqForPath[path];
      if (lastEdit == null || lastEdit <= mySeq) return null;
    }
    final label = paths.length == 1 ? paths.first : '${paths.length} files';
    if (toolName == 'read') {
      return '[Stale read of $label folded: the file was modified by a later '
          'edit. This earlier content is no longer current. Re-read only if '
          'you need the latest content.]';
    }
    return '[Earlier $toolName of $label folded: superseded by a later edit. '
        'See the most recent edit result for the current file state.]';
  }

  List<String> _sessionContractItems(
    List<MessageInfo> messages,
    List<MessagePart> parts,
  ) {
    final partsByMessage = <String, List<MessagePart>>{};
    for (final part in parts) {
      partsByMessage.putIfAbsent(part.messageId, () => []).add(part);
    }
    final out = <String>[];
    final seen = <String>{};

    void addItem(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      final normalized = trimmed.toLowerCase();
      if (!seen.add(normalized)) return;
      out.add(trimmed);
    }

    for (final message in messages.reversed) {
      if (message.role != SessionRole.user) continue;
      final messageParts = partsByMessage[message.id] ?? const <MessagePart>[];
      final textBlocks = messageParts
          .where((part) => part.type == PartType.text)
          .map((part) => part.data['text'] as String? ?? '')
          .where((text) => text.trim().isNotEmpty)
          .toList();
      final fallback = message.text.trim();
      if (textBlocks.isEmpty && fallback.isNotEmpty) {
        textBlocks.add(fallback);
      }
      for (final block in textBlocks) {
        for (final item in _extractContractLines(block)) {
          addItem(item);
          if (out.length >= 8) return out.reversed.toList();
        }
      }
    }
    return out.reversed.toList();
  }

  List<String> _extractContractLines(String text) {
    final rawLines = text
        .split(RegExp(r'[\n\r]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final items = <String>[];
    for (final raw in rawLines) {
      var line = raw.replaceFirst(RegExp(r'^[-*]\s+'), '').trim();
      if (line.isEmpty || line.length > 220) continue;
      final lower = line.toLowerCase();
      final hasSignal = line.contains('必须') ||
          line.contains('不要') ||
          line.contains('不能') ||
          line.contains('别') ||
          line.contains('只用') ||
          line.contains('统一') ||
          line.contains('完全一致') ||
          line.contains('不考虑') ||
          lower.contains('must ') ||
          lower.contains('must not') ||
          lower.contains('do not ') ||
          lower.contains("don't ") ||
          lower.contains('without ') ||
          lower.contains('only use ') ||
          lower.contains('use ') ||
          lower.contains('keep ') ||
          lower.contains('strict ') ||
          lower.contains('filePath'.toLowerCase()) ||
          lower.contains('compat');
      if (!hasSignal) continue;
      if (line.endsWith('。') || line.endsWith('.')) {
        line = line.substring(0, line.length - 1).trim();
      }
      if (line.isNotEmpty) {
        items.add(line);
      }
    }
    return items;
  }

  dynamic _userMessageContent(
    MessageInfo message,
    List<MessagePart> parts, {
    bool includeImageData = true,
  }) {
    final blocks = <Map<String, dynamic>>[];
    for (final part in parts) {
      if (part.type == PartType.text) {
        final text = part.data['text'] as String? ?? '';
        final ignored = (part.data['ignored'] as bool?) ?? false;
        if (!ignored && text.isNotEmpty) {
          blocks.add({'type': 'text', 'text': text});
        }
        continue;
      }
      if (part.type == PartType.file) {
        final mime = part.data['mime'] as String? ?? 'application/octet-stream';
        final filename = part.data['filename'] as String? ?? 'file';
        final url = part.data['url'] as String? ?? '';
        final source = Map<String, dynamic>.from(
          part.data['source'] as Map? ?? const {},
        );
        final sourceText = Map<String, dynamic>.from(
          source['text'] as Map? ?? const {},
        )['value'] as String?;
        if (mime == 'text/plain' || mime == 'application/x-directory') {
          if (sourceText != null && sourceText.isNotEmpty) {
            blocks.add({'type': 'text', 'text': sourceText});
          }
          continue;
        }
        if (url.startsWith('data:') &&
            (mime.startsWith('image/') ||
                mime.startsWith('audio/') ||
                mime.startsWith('video/') ||
                mime == 'application/pdf')) {
          if (mime.startsWith('image/') && !includeImageData) {
            blocks.add({
              'type': 'text',
              'text':
                  '[Image omitted from context: $filename, $mime, attached earlier]',
            });
            continue;
          }
          blocks.add({
            'type': 'file',
            'mediaType': mime,
            'url': url,
            'filename': filename,
          });
          continue;
        }
        blocks.add({
          'type': 'text',
          'text': '[Attached $mime: $filename]',
        });
      }
    }
    if (blocks.isEmpty) return message.text;
    if (blocks.length == 1 && blocks.first['type'] == 'text') {
      return blocks.first['text'] as String? ?? message.text;
    }
    return blocks;
  }

  @visibleForTesting
  List<Map<String, dynamic>> debugMessagesToConversation({
    required List<MessageInfo> messages,
    required List<MessagePart> parts,
    required String currentAgent,
    required String? latestUserId,
    List<String> sessionContracts = const <String>[],
    bool isZh = false,
  }) =>
      _messagesToConversation(
        messages: messages,
        parts: parts,
        currentAgent: currentAgent,
        latestUserId: latestUserId,
        sessionContracts: sessionContracts,
        isZh: isZh,
      );

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
}
