part of '../home_page.dart';

extension _HomePageTimeline on _HomePageState {
  int _timelineItemCount(
    AppState state,
    List<SessionMessageBundle> renderedMessages,
  ) {
    var count = 2;
    if (state.todos.isNotEmpty) {
      count += 2;
    }
    if (state.messages.isEmpty && !state.isBusy) {
      count += 1;
    } else {
      if (_hasEarlierHistory(state)) {
        count += 1;
      }
      count += renderedMessages.length;
    }
    if (state.isBusy) {
      count += 2;
    }
    count += 1;
    return count;
  }

  Widget _buildTimelineItem(
    BuildContext context, {
    required AppState state,
    required ModelConfig modelConfig,
    required _ModelChoice? currentModelChoice,
    required bool showModelFreeTag,
    required bool showModelLatestTag,
    required bool isKeyboardOpen,
    required List<SessionMessageBundle> renderedMessages,
    required int index,
  }) {
    var cursor = 0;
    if (index == cursor++) {
      return _TimelineHeaderCard(
        workspaceName: state.workspace?.name ??
            l(context, '未选择工作区', 'No workspace selected'),
        sessionTitle: state.session?.title ?? l(context, '新会话', 'New session'),
        agentName: _selectedAgent ?? state.session?.agent ?? 'build',
        providerLabel:
            _providerLabel(modelConfig.provider, config: modelConfig, state: state),
        modelLabel: currentModelChoice?.name ?? modelConfig.model,
        showModelFreeTag: showModelFreeTag,
        showModelLatestTag: showModelLatestTag,
        showMeta: !isKeyboardOpen,
      );
    }
    if (index == cursor++) {
      return const SizedBox(height: 12);
    }
    if (state.todos.isNotEmpty) {
      if (index == cursor++) {
        return _TodoPanel(todos: state.todos);
      }
      if (index == cursor++) {
        return const SizedBox(height: 12);
      }
    }
    if (state.messages.isEmpty && !state.isBusy) {
      if (index == cursor++) {
        return _EmptyTimelineCard(
          onSelectModel: () => _openModelChooser(context),
          providerLabel:
              _providerLabel(modelConfig.provider, config: modelConfig, state: state),
          modelLabel: currentModelChoice?.name ?? modelConfig.model,
          showModelFreeTag: showModelFreeTag,
          showModelLatestTag: showModelLatestTag,
        );
      }
    } else {
      if (_hasEarlierHistory(state)) {
        if (index == cursor++) {
          return _TimelineLoadEarlierCard(
            onPressed: () => _revealEarlierMessages(),
          );
        }
      }
      final messageEnd = cursor + renderedMessages.length;
      if (index < messageEnd) {
        final msgIndex = index - cursor;
        final bundle = renderedMessages[msgIndex];
        final isLast = msgIndex == renderedMessages.length - 1;
        return _MessageBubble(
          key: ValueKey<String>(bundle.message.id),
          bundle: bundle,
          state: state,
          isStreamingAssistantMessage: state.isBusy &&
              isLast &&
              bundle.message.role == SessionRole.assistant,
          controller: widget.controller,
          onInsertPromptReference: _appendPromptReference,
          onSendPromptReference: _sendPromptReference,
        );
      }
      cursor = messageEnd;
    }
    if (state.isBusy) {
      if (index == cursor++) {
        return const SizedBox(height: 8);
      }
      if (index == cursor++) {
        return const _RunningIndicator();
      }
    }
    if (index == cursor++) {
      return const SizedBox(height: 12);
    }
    return const SizedBox.shrink();
  }

}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    super.key,
    required this.bundle,
    required this.state,
    required this.isStreamingAssistantMessage,
    required this.controller,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final SessionMessageBundle bundle;
  final AppState state;
  final bool isStreamingAssistantMessage;
  final AppController controller;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  Widget? _cached;
  SessionMessageBundle? _lastBundle;
  bool? _lastStreaming;
  int? _lastThemeKey;

  List<MessagePart>? _cachedPrimaryParts;
  List<MessagePart>? _cachedFooterParts;
  List<MessagePart>? _lastPartsList;
  int? _cachedTurnDurationMs;
  bool _turnDurationComputed = false;

  @override
  Widget build(BuildContext context) {
    final themeKey = context.themeCacheKey;
    if (identical(widget.bundle, _lastBundle) &&
        widget.isStreamingAssistantMessage == _lastStreaming &&
        themeKey == _lastThemeKey &&
        _cached != null) {
      return _cached!;
    }
    _lastBundle = widget.bundle;
    _lastStreaming = widget.isStreamingAssistantMessage;
    _lastThemeKey = themeKey;
    _cached = _buildContent(context);
    return _cached!;
  }

  void _refreshPartsSplit(List<MessagePart> parts) {
    if (identical(parts, _lastPartsList)) return;
    _lastPartsList = parts;
    final primary = <MessagePart>[];
    final footer = <MessagePart>[];
    for (final p in parts) {
      if (p.type == PartType.tool && (p.data['tool'] as String?) == 'fileref') {
        footer.add(p);
      } else {
        primary.add(p);
      }
    }
    _cachedPrimaryParts = primary;
    _cachedFooterParts = footer;
  }

  int? _computeTurnDuration() {
    final bundle = widget.bundle;
    if (bundle.message.role != SessionRole.assistant) return null;
    if (!widget.isStreamingAssistantMessage && _turnDurationComputed) {
      return _cachedTurnDurationMs;
    }
    final globalIdx = widget.state.messages
        .indexWhere((b) => b.message.id == bundle.message.id);
    if (globalIdx < 0) return null;
    final result = _turnDurationMsForAssistantBundle(widget.state, globalIdx);
    if (!widget.isStreamingAssistantMessage) {
      _cachedTurnDurationMs = result;
      _turnDurationComputed = true;
    }
    return result;
  }

  Widget _buildContent(BuildContext context) {
    final oc = context.oc;
    final bundle = widget.bundle;

    _refreshPartsSplit(bundle.parts);
    final primaryParts = _cachedPrimaryParts!;
    final footerParts = _cachedFooterParts!;

    final turnDurationMs = _computeTurnDuration();

    MessagePart? lastPlainTextPart;
    for (var i = primaryParts.length - 1; i >= 0; i--) {
      final p = primaryParts[i];
      if (p.type == PartType.text &&
          !((p.data['structured'] as bool?) ?? false)) {
        lastPlainTextPart = p;
        break;
      }
    }

    final isUser = bundle.message.role == SessionRole.user;
    final label = isUser ? l(context, '你', 'You') : bundle.message.agent;
    final bubbleColor = isUser ? oc.userBubble : oc.agentBubble;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: oc.softBorderColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: oc.foregroundMuted,
                              letterSpacing: 0.1,
                            ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTimestamp(bundle.message.createdAt),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: oc.foregroundFaint),
                      ),
                    ],
                  ),
                  if (bundle.message.text.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      bundle.message.text,
                      style: const TextStyle(fontSize: 15, height: 1.45),
                    ),
                  ],
                  for (final part in primaryParts) ...[
                    const SizedBox(height: 10),
                    _PartTile(
                      part: part,
                      message: bundle.message,
                      controller: widget.controller,
                      workspace: widget.controller.state.workspace,
                      serverUri: widget.controller.state.serverUri,
                      streamAssistantContent:
                          widget.isStreamingAssistantMessage,
                      turnDurationMs: turnDurationMs,
                      showAssistantTextMeta: !isUser &&
                          lastPlainTextPart != null &&
                          identical(part, lastPlainTextPart),
                      onInsertPromptReference:
                          widget.onInsertPromptReference,
                      onSendPromptReference:
                          widget.onSendPromptReference,
                    ),
                  ],
                  if (footerParts.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Divider(
                        height: 1, thickness: 1, color: oc.softBorderColor),
                    const SizedBox(height: 8),
                    Text(
                      l(context, '文件引用', 'File references'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: oc.foregroundHint,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    for (final part in footerParts) ...[
                      const SizedBox(height: 10),
                      _PartTile(
                        part: part,
                        message: bundle.message,
                        controller: widget.controller,
                        workspace: widget.controller.state.workspace,
                        serverUri: widget.controller.state.serverUri,
                        streamAssistantContent:
                            widget.isStreamingAssistantMessage,
                        turnDurationMs: turnDurationMs,
                        showAssistantTextMeta: false,
                        onInsertPromptReference:
                            widget.onInsertPromptReference,
                        onSendPromptReference:
                            widget.onSendPromptReference,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}

class _SessionAppBarTitle extends StatelessWidget {
  const _SessionAppBarTitle({
    required this.title,
    required this.running,
  });

  final String title;
  final bool running;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: running
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _TimelineHeaderCard extends StatelessWidget {
  const _TimelineHeaderCard({
    required this.workspaceName,
    required this.sessionTitle,
    required this.agentName,
    required this.providerLabel,
    required this.modelLabel,
    required this.showModelFreeTag,
    required this.showModelLatestTag,
    required this.showMeta,
  });

  final String workspaceName;
  final String sessionTitle;
  final String agentName;
  final String providerLabel;
  final String modelLabel;
  final bool showModelFreeTag;
  final bool showModelLatestTag;
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: oc.panelBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.fromBorderSide(BorderSide(color: oc.borderColor)),
        boxShadow: [
          BoxShadow(
            color: oc.shadow,
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sessionTitle,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            workspaceName,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: oc.foregroundMuted),
          ),
          if (showMeta) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _TinyTag(label: agentName, color: oc.tagBlueGrey),
                _TinyTag(label: providerLabel, color: oc.tagGreen),
                _TinyTag(label: modelLabel, color: oc.tagBlue),
                if (showModelFreeTag)
                  OcModelTag(
                    label: l(context, '免费', 'Free'),
                  ),
                if (showModelLatestTag)
                  OcModelTag(
                    label: l(context, '最新', 'Latest'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ContextStatsCard extends StatelessWidget {
  const _ContextStatsCard({
    required this.session,
    required this.model,
    required this.onInitializeMemory,
    required this.onCompactSession,
    required this.onViewRawContext,
  });

  final SessionInfo? session;
  final String model;
  final VoidCallback? onInitializeMemory;
  final VoidCallback? onCompactSession;
  final VoidCallback? onViewRawContext;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final ratio = _contextUsageRatio(session, model);
    final progressColor = ratio >= 0.95
        ? Colors.red.shade400
        : ratio >= 0.8
            ? Colors.orange.shade400
            : Colors.green.shade400;
    final promptTokens = session?.promptTokens ?? 0;
    final completionTokens = session?.completionTokens ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: oc.panelBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.fromBorderSide(BorderSide(color: oc.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                l(context, '上下文', 'Context'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                _contextUsageLabel(session, model),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: oc.foregroundMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: oc.progressBg,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TinyTag(
                label:
                    '${l(context, "输入", "Input")} ${formatTokenCount(promptTokens)}',
                color: oc.tagBlue,
              ),
              _TinyTag(
                label:
                    '${l(context, "输出", "Output")} ${formatTokenCount(completionTokens)}',
                color: oc.tagGreen,
              ),
              if (session?.hasSummary == true)
                _TinyTag(
                  label: l(context, '已 Compact', 'Compacted'),
                  color: oc.tagOrange,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _CompactActionButton(
                  onPressed: onCompactSession,
                  icon: Icons.compress_outlined,
                  label: l(context, '压缩会话', 'Compact Session'),
                ),
                _CompactActionButton(
                  onPressed: onInitializeMemory,
                  icon: Icons.note_add_outlined,
                  label: l(context, '初始化/更新 Mag.md',
                      'Initialize/Update Mag.md'),
                ),
                _CompactActionButton(
                  onPressed: onViewRawContext,
                  icon: Icons.data_object_outlined,
                  label: l(context, '查看原始 Context', 'View Raw Context'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextRingButton extends StatelessWidget {
  const _ContextRingButton({
    required this.ratio,
    required this.compacted,
    required this.onPressed,
  });

  final double ratio;
  final bool compacted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final progressColor = ratio >= 0.95
        ? Colors.red.shade400
        : ratio >= 0.8
            ? Colors.orange.shade400
            : Colors.green.shade400;
    final clampedRatio = ratio.clamp(0.0, 1.0);
    return Tooltip(
      message: compacted
          ? l(context, '上下文已压缩，点按查看详情', 'Context compacted, tap for details')
          : l(context, '查看上下文使用情况', 'View context usage'),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  value: clampedRatio,
                  strokeWidth: 2.2,
                  backgroundColor: oc.progressBg,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: oc.panelBackground,
                  shape: BoxShape.circle,
                  border:
                      Border.fromBorderSide(BorderSide(color: oc.borderColor)),
                ),
                child: Icon(
                  compacted ? Icons.compress_outlined : Icons.memory_outlined,
                  size: 15,
                  color: oc.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTimelineCard extends StatelessWidget {
  const _EmptyTimelineCard({
    required this.onSelectModel,
    this.providerLabel,
    this.modelLabel,
    this.showModelFreeTag = false,
    this.showModelLatestTag = false,
  });

  final VoidCallback onSelectModel;
  final String? providerLabel;
  final String? modelLabel;
  final bool showModelFreeTag;
  final bool showModelLatestTag;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: oc.panelBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.fromBorderSide(BorderSide(color: oc.borderColor)),
        boxShadow: [
          BoxShadow(
            color: oc.shadow,
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l(context, '开始对话', 'Start a conversation'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            l(
                context,
                '这个区域现在按 Mag web 的结构只保留 timeline 内容。模型、provider、session、agent 都通过顶部入口切换。',
                'This area now keeps only the timeline content, similar to Mag web. Model, provider, session, and agent are switched from the top controls.'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (providerLabel != null || modelLabel != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (modelLabel != null)
                  _TinyTag(label: modelLabel!, color: oc.tagBlue),
                if (providerLabel != null)
                  _TinyTag(label: providerLabel!, color: oc.tagGreen),
                if (showModelFreeTag)
                  OcModelTag(
                    label: l(context, '免费', 'Free'),
                  ),
                if (showModelLatestTag)
                  OcModelTag(
                    label: l(context, '最新', 'Latest'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onSelectModel,
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(l(context, '选择模型', 'Choose model')),
          ),
        ],
      ),
    );
  }
}

class _RunningIndicator extends StatelessWidget {
  const _RunningIndicator();

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: oc.mutedPanel,
          borderRadius: BorderRadius.circular(999),
          border: Border.fromBorderSide(BorderSide(color: oc.borderColor)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(l(context, '运行中', 'Running')),
          ],
        ),
      ),
    );
  }
}

class _TimelineLoadEarlierCard extends StatelessWidget {
  const _TimelineLoadEarlierCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: oc.panelBackground,
            side: BorderSide(color: oc.borderColor),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.expand_less, size: 16),
          label: Text(l(context, '加载更早消息', 'Load earlier')),
        ),
      ),
    );
  }
}

class _TinyTag extends StatelessWidget {
  const _TinyTag({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ModelListTile extends StatelessWidget {
  const _ModelListTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _ModelChoice item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final free = _modelChoiceIsFree(item);
    final latest = _modelChoiceIsLatest(item);
    return Material(
      color: selected ? oc.selectedFill : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                              color: oc.text,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        if (free) ...[
                          const SizedBox(width: 6),
                          OcModelTag(
                            label: l(context, '免费', 'Free'),
                          ),
                        ],
                        if (latest) ...[
                          const SizedBox(width: 6),
                          OcModelTag(
                            label: l(context, '最新', 'Latest'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${item.providerId}/${item.id}',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.2,
                        color: oc.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 1),
                  child: Icon(Icons.check, size: 16, color: oc.accent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _ProviderPreset item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Material(
      color: selected ? oc.selectedFill : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                        color: oc.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.note ?? item.baseUrl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.2,
                        color: oc.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Container(
                  margin: const EdgeInsets.only(left: 6, top: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: oc.selectedFill,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: oc.border),
                  ),
                  child: Text(
                    l(context, '已连接', 'Connected'),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: oc.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
