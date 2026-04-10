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
    final zh = platformIsZh;
    final system = await promptAssembler.buildSystemPrompts(
      PromptContext(
        workspace: workspace,
        agent: currentAgent,
        agentDefinition: currentAgentDefinition,
        model: model,
        effectiveTools: toolRegistry
            .availableForAgent(
              currentAgentDefinition,
              modelId: model,
            )
            .map((item) => item.id)
            .toList(),
        agentPrompt: currentAgentDefinition.promptOverride,
        hasSkillTool: true,
        currentStep: currentStep,
        maxSteps: maxSteps,
        format: latestUser?.format,
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
        summaryMessageId: summaryMessageId,
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
    String summaryMessageId = '',
    bool isZh = false,
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
        final compactionPart = messageParts
            .where((item) => item.type == PartType.compaction)
            .cast<MessagePart?>()
            .firstWhere((item) => item != null, orElse: () => null);
        final summaryText =
            (compactionPart?.data['summary'] as String? ?? '').trim().isNotEmpty
                ? (compactionPart!.data['summary'] as String? ?? '')
                : messageParts
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
            isZh: isZh,
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
          final status = state['status'] as String? ?? '';
          final output = (status == 'pending' || status == 'running')
              ? '[Tool execution was interrupted]'
              : state['output'] as String? ?? '';
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
}
