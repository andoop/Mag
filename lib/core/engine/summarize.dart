part of '../session_engine.dart';

extension SessionEngineSummarize on SessionEngine {
  static const int _kPruneMinimum = 20000;
  static const int _kPruneProtect = 40000;
  static const Set<String> _kPruneProtectedTools = {'skill'};

  Future<int> _pruneToolOutputsForContext({
    required WorkspaceInfo workspace,
    required String sessionId,
  }) async {
    final messages = await database.listMessages(sessionId);
    final parts = await database.listPartsForSession(sessionId);
    if (messages.isEmpty || parts.isEmpty) return 0;
    final partsByMessage = <String, List<MessagePart>>{};
    for (final part in parts) {
      partsByMessage.putIfAbsent(part.messageId, () => []).add(part);
    }
    var total = 0;
    var pruned = 0;
    final toPrune = <MessagePart>[];
    var turns = 0;
    var reachedCompactedHistory = false;
    for (var msgIndex = messages.length - 1; msgIndex >= 0; msgIndex--) {
      final message = messages[msgIndex];
      if (message.role == SessionRole.user) {
        turns++;
      }
      if (turns < 2) {
        continue;
      }
      if (message.role == SessionRole.assistant && message.summary) {
        break;
      }
      final messageParts = partsByMessage[message.id] ?? const <MessagePart>[];
      for (var partIndex = messageParts.length - 1;
          partIndex >= 0;
          partIndex--) {
        final part = messageParts[partIndex];
        if (part.type != PartType.tool) {
          continue;
        }
        final state =
            Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
        if (state['status'] != ToolStatus.completed.name) {
          continue;
        }
        final tool = part.data['tool'] as String? ?? '';
        if (_kPruneProtectedTools.contains(tool)) {
          continue;
        }
        final time =
            Map<String, dynamic>.from(state['time'] as Map? ?? const {});
        if ((time['compacted'] as num?) != null) {
          reachedCompactedHistory = true;
          break;
        }
        final output = state['output'] as String? ?? '';
        if (output.isEmpty) {
          continue;
        }
        final estimate =
            math.max(1, estimateOpenCodeCharsAsTokens(output.length));
        total += estimate;
        if (total > _kPruneProtect) {
          pruned += estimate;
          toPrune.add(part);
        }
      }
      if (reachedCompactedHistory) {
        break;
      }
    }
    if (pruned <= _kPruneMinimum) {
      return 0;
    }
    final compactedAt = DateTime.now().millisecondsSinceEpoch;
    for (final part in toPrune) {
      final state =
          Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
      final time = Map<String, dynamic>.from(state['time'] as Map? ?? const {});
      time['compacted'] = compactedAt;
      state['time'] = time;
      await _savePart(
        workspace: workspace,
        part: MessagePart(
          id: part.id,
          sessionId: part.sessionId,
          messageId: part.messageId,
          type: part.type,
          createdAt: part.createdAt,
          data: {...part.data, 'state': state},
        ),
      );
    }
    return pruned;
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
    const summaryPrompt = '''
Provide a detailed prompt for continuing our conversation above.
Focus on information that would be helpful for continuing the conversation, including what we did, what we're doing, which files we're working on, and what we're going to do next.
The summary that you construct will be used so that another agent can read it and continue the work.
Do not call any tools. Respond only with the summary text.
Respond in the same language as the user's messages in the conversation.

When constructing the summary, try to stick to this template:
---
## Goal

[What goal(s) is the user trying to accomplish?]

## Instructions

- [What important instructions did the user give you that are relevant]
- [If there is a plan or spec, include information about it so next agent can continue using it]

## Discoveries

[What notable things were learned during this conversation that would be useful for the next agent to know when continuing the work]

## Accomplished

[What work has been completed, what work is still in progress, and what work is left?]

## Relevant files / directories

[Construct a structured list of relevant files that have been read, edited, or created that pertain to the task at hand. If all the files in a directory are relevant, include the path to the directory.]
---
''';
    final prompt = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are Mag summarizer. Produce a continuation summary that another agent can use to resume the same coding task.',
      },
      ..._messagesToConversation(
        messages: messages,
        parts: parts,
        currentAgent: currentAgent,
      ),
      {
        'role': 'user',
        'content': summaryPrompt,
      },
    ];
    final response = await modelGateway.complete(
      config: modelConfig,
      messages: prompt,
      tools: const [],
      format: null,
      sessionId: session.id,
    );
    final summaryText = response.text.trim();
    if (summaryText.isEmpty) return session;
    final compactionMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: currentAgent,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: '',
    );
    await _saveMessage(workspace: workspace, message: compactionMessage);
    await _savePart(
      workspace: workspace,
      part: MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: compactionMessage.id,
        type: PartType.compaction,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'label': 'Context compacted',
          'summary': summaryText,
        },
      ),
    );
    final summaryMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.assistant,
      agent: currentAgent,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: '',
      model: modelConfig.model,
      provider: modelConfig.provider,
      parentMessageId: compactionMessage.id,
      summary: true,
    );
    await _saveMessage(workspace: workspace, message: summaryMessage);
    await _savePart(
      workspace: workspace,
      part: MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: summaryMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: _assistantTextPartData(summaryText),
      ),
    );
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
    final tracked = await _trackUsage(
      workspace: workspace,
      session: session.copyWith(summaryMessageId: compactionMessage.id),
      usage: response.usage,
    );
    return tracked.copyWith(summaryMessageId: compactionMessage.id);
  }

  Future<SessionInfo> _trackUsage({
    required WorkspaceInfo workspace,
    required SessionInfo session,
    required ModelUsage usage,
  }) async {
    // Re-read the latest session from DB so we don't overwrite fields
    // updated concurrently (e.g. title set by the async _ensureSessionTitle).
    final fresh = await database.getSession(session.id);
    final base = fresh ?? session;
    final next = base.copyWith(
      promptTokens: usage.isEmpty ? session.promptTokens : usage.promptTokens,
      completionTokens:
          usage.isEmpty ? session.completionTokens : usage.completionTokens,
      cost: session.cost,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _saveSession(workspace: workspace, session: next);
    return next;
  }

  /// OpenCode `session/overflow.ts` + `prompt.ts` 在 turn 末尾的 overflow 判定。
  bool _shouldAutoCompactAfterTurn(
      ModelUsage lastUsage, ModelConfig modelConfig) {
    if (lastUsage.isEmpty) return false;
    return isContextOverflowForCompaction(
      tokens: lastUsage,
      model: modelConfig.model,
      limit: modelConfig.currentModelLimit,
    );
  }
}
