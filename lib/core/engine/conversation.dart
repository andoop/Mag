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
    final effectiveTools = toolRegistry
        .availableForAgent(
          currentAgentDefinition,
          modelId: model,
        )
        .map((item) => item.id)
        .toList();
    final availableSkills = effectiveTools.contains('skill')
        ? await SkillRegistry.instance.available(
            workspace,
            agentDefinition: currentAgentDefinition,
          )
        : const <SkillInfo>[];
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
        currentStep: currentStep,
        maxSteps: maxSteps,
        format: latestUser?.format,
        sessionContracts: _sessionContractItems(messages, parts),
        allAgents: listAgents(),
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
        final userContent = _userMessageContent(message, messageParts);
        if (userContent is String) {
          conversation.add({
            'role': 'user',
            'content': promptAssembler.applyUserReminder(
              agent: message.agent,
              switchedFromPlan: switchedFromPlan,
              text: userContent,
              isZh: isZh,
            ),
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
          } else {
            final reminder = promptAssembler.applyUserReminder(
              agent: message.agent,
              switchedFromPlan: switchedFromPlan,
              text: '',
              isZh: isZh,
            );
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
          final output = (status == 'pending' || status == 'running')
              ? '[Tool execution was interrupted]'
              : (compacted
                  ? '[Old tool result content cleared]'
                  : state['output'] as String? ?? '');
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

  dynamic _userMessageContent(MessageInfo message, List<MessagePart> parts) {
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
