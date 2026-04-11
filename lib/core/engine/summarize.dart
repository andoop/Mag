part of '../session_engine.dart';

extension SessionEngineSummarize on SessionEngine {
  String _compactedToolOutput(MessagePart part) {
    final state = Map<String, dynamic>.from(part.data['state'] as Map? ?? {});
    final tool = part.data['tool'] as String? ?? 'tool';
    final displayOutput = (state['displayOutput'] as String? ?? '').trim();
    final metadata = Map<String, dynamic>.from(state['metadata'] as Map? ?? {});
    final compactMetadata = <String, dynamic>{};
    for (final entry in metadata.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value == null) continue;
      if (value is num || value is bool) {
        compactMetadata[key] = value;
        continue;
      }
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isEmpty || trimmed.length > 160) continue;
        if (key == 'preview') continue;
        compactMetadata[key] = trimmed;
      }
    }
    final lines = <String>['[output compacted]'];
    if (displayOutput.isNotEmpty) {
      lines.add('Summary: $displayOutput');
    } else {
      lines.add('Summary: output from `$tool` was compacted.');
    }
    if (compactMetadata.isNotEmpty) {
      lines.add('Metadata: ${jsonEncode(compactMetadata)}');
    }
    return lines.join('\n');
  }

  /// OpenCode `compaction.prune` 思路的简化版：从大到小清空已完成 tool 的 output，避免 summary 请求本身超窗。
  Future<int> _pruneLargestToolOutputsForContext({
    required WorkspaceInfo workspace,
    required String sessionId,
    int minPrunedEstimate = 20000,
  }) async {
    final parts = await database.listPartsForSession(sessionId);
    final candidates = <MessagePart>[];
    for (final p in parts) {
      if (p.type != PartType.tool) continue;
      final state = Map<String, dynamic>.from(p.data['state'] as Map? ?? {});
      if (state['status'] != ToolStatus.completed.name) continue;
      final tool = p.data['tool'] as String? ?? '';
      if (tool == 'skill') continue;
      final out = state['output'] as String? ?? '';
      if (out.isEmpty || out == '[output compacted]') continue;
      candidates.add(p);
    }
    candidates.sort((a, b) {
      final la =
          ((((a.data['state'] as Map?)?['output']) as String?) ?? '').length;
      final lb =
          ((((b.data['state'] as Map?)?['output']) as String?) ?? '').length;
      return lb.compareTo(la);
    });
    var totalEst = 0;
    for (final p in candidates) {
      if (totalEst >= minPrunedEstimate) break;
      final state = Map<String, dynamic>.from(p.data['state'] as Map? ?? {});
      final out = state['output'] as String? ?? '';
      if (out.isEmpty || out == '[output compacted]') continue;
      totalEst += math.max(1, estimateOpenCodeCharsAsTokens(out.length));
      state['output'] = _compactedToolOutput(p);
      await _savePart(
        workspace: workspace,
        part: MessagePart(
          id: p.id,
          sessionId: p.sessionId,
          messageId: p.messageId,
          type: p.type,
          createdAt: p.createdAt,
          data: {...p.data, 'state': state},
        ),
      );
    }
    return totalEst;
  }

  Future<SessionInfo> summarize({
    required WorkspaceInfo workspace,
    required SessionInfo session,
    required ModelConfig modelConfig,
    required String currentAgent,
  }) async {
    var messages = await database.listMessages(session.id);
    if (messages.isEmpty) return session;
    var parts = await database.listPartsForSession(session.id);
    final budget = usableInputTokensForModel(
      modelConfig.model,
      limit: modelConfig.currentModelLimit,
    );
    for (var pass = 0; pass < 16; pass++) {
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
      final est = estimateSerializedMessagesTokens(prompt);
      if (est < budget) break;
      final pruned = await _pruneLargestToolOutputsForContext(
        workspace: workspace,
        sessionId: session.id,
        minPrunedEstimate: 8000,
      );
      if (pruned == 0) break;
      messages = await database.listMessages(session.id);
      parts = await database.listPartsForSession(session.id);
    }
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
      text: '',
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
