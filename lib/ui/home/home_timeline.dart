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
        providerLabel: _providerLabel(modelConfig.provider),
        modelLabel: currentModelChoice?.name ?? modelConfig.model,
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
          onSelectProvider: () => _openProviderPicker(context),
          providerLabel: _providerLabel(modelConfig.provider),
          modelLabel: currentModelChoice?.name ?? modelConfig.model,
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
        return _buildMessage(renderedMessages[index - cursor]);
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

  Widget _buildMessage(SessionMessageBundle bundle) {
    final isUser = bundle.message.role == SessionRole.user;
    final label = isUser ? l(context, '你', 'You') : bundle.message.agent;
    final bubbleColor = isUser ? _kUserBubble : _kAgentBubble;
    return Padding(
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
              border: Border.all(color: _kSoftBorderColor),
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
                            color: Colors.black54,
                            letterSpacing: 0.1,
                          ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatTimestamp(bundle.message.createdAt),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: Colors.black38),
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
                for (final part in bundle.parts) ...[
                  const SizedBox(height: 10),
                  _PartTile(
                    part: part,
                    controller: widget.controller,
                    workspace: widget.controller.state.workspace,
                    serverUri: widget.controller.state.serverUri,
                    onInsertPromptReference: _appendPromptReference,
                    onSendPromptReference: _sendPromptReference,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionAppBarTitle extends StatelessWidget {
  const _SessionAppBarTitle({
    required this.title,
    required this.subtitle,
    required this.running,
  });

  final String title;
  final String subtitle;
  final bool running;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Colors.black54),
              ),
            ],
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
    required this.showMeta,
  });

  final String workspaceName;
  final String sessionTitle;
  final String agentName;
  final String providerLabel;
  final String modelLabel;
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: _kPanelBackground,
        borderRadius: BorderRadius.circular(22),
        border: const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
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
                ?.copyWith(color: Colors.black54),
          ),
          if (showMeta) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TinyTag(label: agentName, color: Colors.blueGrey.shade100),
                _TinyTag(label: providerLabel, color: Colors.green.shade100),
                _TinyTag(label: modelLabel, color: Colors.blue.shade100),
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
  });

  final SessionInfo? session;
  final String model;
  final VoidCallback? onInitializeMemory;
  final VoidCallback? onCompactSession;

  @override
  Widget build(BuildContext context) {
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
        color: _kPanelBackground,
        borderRadius: BorderRadius.circular(20),
        border: const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
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
                    ?.copyWith(color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.black.withOpacity(0.06),
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
                color: Colors.blue.shade100,
              ),
              _TinyTag(
                label:
                    '${l(context, "输出", "Output")} ${formatTokenCount(completionTokens)}',
                color: Colors.green.shade100,
              ),
              if (session?.hasSummary == true)
                _TinyTag(
                  label: l(context, '已 Compact', 'Compacted'),
                  color: Colors.orange.shade100,
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
                  backgroundColor: Colors.black.withOpacity(0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border:
                      Border.fromBorderSide(BorderSide(color: _kBorderColor)),
                ),
                child: Icon(
                  compacted ? Icons.compress_outlined : Icons.memory_outlined,
                  size: 15,
                  color: Colors.black87,
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
    required this.onSelectProvider,
    this.providerLabel,
    this.modelLabel,
  });

  final VoidCallback onSelectModel;
  final VoidCallback onSelectProvider;
  final String? providerLabel;
  final String? modelLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kPanelBackground,
        borderRadius: BorderRadius.circular(22),
        border: const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
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
              children: [
                if (modelLabel != null)
                  _TinyTag(label: modelLabel!, color: Colors.blue.shade100),
                if (providerLabel != null)
                  _TinyTag(label: providerLabel!, color: Colors.green.shade100),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onSelectProvider,
                icon: const Icon(Icons.hub_outlined),
                label: Text(l(context, 'Provider', 'Provider')),
              ),
              OutlinedButton.icon(
                onPressed: onSelectModel,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: Text(l(context, '模型', 'Model')),
              ),
            ],
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
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: _kMutedPanel,
          borderRadius: BorderRadius.circular(999),
          border: const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: _kBorderColor),
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
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: selected ? const Color(0xFFF0FDF4) : _kMutedPanel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(item.name)),
              if (item.free)
                _TinyTag(
                    label: l(context, '免费', 'Free'),
                    color: Colors.green.shade100),
              if (item.recommended)
                _TinyTag(
                    label: l(context, '推荐', 'Recommended'),
                    color: Colors.orange.shade100),
              if (item.latest)
                _TinyTag(
                    label: l(context, '最新', 'Latest'),
                    color: Colors.blue.shade100),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _providerLabel(item.providerId),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.black54),
          ),
        ],
      ),
      subtitle: Text(item.id),
      trailing: selected ? const Icon(Icons.check_circle_outline) : null,
      onTap: onTap,
    );
  }
}

class _ProviderListTile extends StatelessWidget {
  const _ProviderListTile({
    required this.item,
    required this.selected,
    required this.modelCount,
    required this.availability,
    required this.description,
    required this.onTap,
  });

  final _ProviderPreset item;
  final bool selected;
  final int modelCount;
  final String availability;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: selected ? const Color(0xFFF0FDF4) : _kMutedPanel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      title: Row(
        children: [
          Expanded(child: Text(item.name)),
          if (item.recommended)
            _TinyTag(
                label: l(context, '推荐', 'Recommended'),
                color: Colors.green.shade100),
          if (item.custom)
            _TinyTag(
                label: l(context, '自定义', 'Custom'),
                color: Colors.blueGrey.shade100),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${modelCountText(context, modelCount)} · $availability'),
          if (description.isNotEmpty) Text(description),
        ],
      ),
      trailing: selected ? const Icon(Icons.check_circle_outline) : null,
      onTap: onTap,
    );
  }
}
