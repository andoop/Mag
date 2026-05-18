part of '../home_page.dart';

class _TimelineTurnEntry {
  const _TimelineTurnEntry({
    required this.userIndex,
    required this.assistantIndices,
    required this.stableId,
  });

  final int? userIndex;
  final List<int> assistantIndices;
  final String stableId;
}

List<_TimelineTurnEntry> _buildTimelineEntries(
  List<SessionMessageBundle> renderedMessages,
) {
  final entries = <_TimelineTurnEntry>[];
  int? pendingUserIndex;
  final pendingAssistantIndices = <int>[];

  void flushPendingTurn() {
    if (pendingUserIndex == null && pendingAssistantIndices.isEmpty) return;
    final ids = <String>[
      if (pendingUserIndex != null)
        renderedMessages[pendingUserIndex!].message.id,
      for (final idx in pendingAssistantIndices)
        renderedMessages[idx].message.id,
    ];
    entries.add(
      _TimelineTurnEntry(
        userIndex: pendingUserIndex,
        assistantIndices: List<int>.unmodifiable(pendingAssistantIndices),
        stableId: ids.join('|'),
      ),
    );
    pendingUserIndex = null;
    pendingAssistantIndices.clear();
  }

  for (var i = 0; i < renderedMessages.length; i++) {
    final bundle = renderedMessages[i];
    if (bundle.message.role == SessionRole.user) {
      flushPendingTurn();
      pendingUserIndex = i;
      continue;
    }
    if (pendingUserIndex == null) {
      entries.add(
        _TimelineTurnEntry(
          userIndex: null,
          assistantIndices: List<int>.unmodifiable([i]),
          stableId: bundle.message.id,
        ),
      );
      continue;
    }
    pendingAssistantIndices.add(i);
  }

  flushPendingTurn();
  return List<_TimelineTurnEntry>.unmodifiable(entries);
}

String? _streamingAssistantMessageId(
  List<_TimelineTurnEntry> entries,
  List<SessionMessageBundle> renderedMessages,
) {
  for (var i = entries.length - 1; i >= 0; i--) {
    final assistantIndices = entries[i].assistantIndices;
    if (assistantIndices.isNotEmpty) {
      return renderedMessages[assistantIndices.last].message.id;
    }
  }
  return null;
}

List<MessagePart> _visibleTimelineParts(SessionMessageBundle bundle) {
  final parts = bundle.parts;
  final primary = <MessagePart>[];
  final hasCompaction = parts.any((p) => p.type == PartType.compaction);
  for (final p in parts) {
    if (bundle.message.role == SessionRole.user && p.type == PartType.text) {
      continue;
    }
    if (hasCompaction && p.type == PartType.text) {
      continue;
    }
    primary.add(p);
  }
  return List<MessagePart>.unmodifiable(primary);
}

bool _shouldStreamTimelinePart(
  List<MessagePart> visibleParts,
  int index,
  bool streamAssistantContent,
) {
  if (!streamAssistantContent) return false;
  final part = visibleParts[index];
  if (part.type != PartType.reasoning) return true;

  // Reasoning is only "thinking" while it is the active tail. Once answer text,
  // tool calls, or another visible part appears after it, the thinking phase has
  // finished even if the assistant turn is still streaming.
  for (var i = index + 1; i < visibleParts.length; i++) {
    if (visibleParts[i].type != PartType.stepStart) return false;
  }
  return true;
}

String _formatTimelineTimestamp(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

const Duration _kStreamingBubbleResizeDuration = Duration(milliseconds: 160);

BoxDecoration _chatSurfaceDecoration(
  BuildContext context, {
  required Color color,
  double radius = 24,
  bool elevated = true,
  bool accent = false,
}) {
  final oc = context.oc;
  final dark = context.isDarkMode;
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color:
          accent ? oc.accent.withOpacity(dark ? 0.28 : 0.18) : oc.borderColor,
    ),
    boxShadow: elevated
        ? [
            BoxShadow(
              color: dark
                  ? Colors.black.withOpacity(0.22)
                  : Colors.black.withOpacity(0.045),
              blurRadius: 22,
              spreadRadius: -8,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(dark ? 0.03 : 0.82),
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ]
        : null,
  );
}

double _assistantBubbleWidth(
  BuildContext context,
  BoxConstraints constraints,
) {
  if (!constraints.maxWidth.isFinite) {
    return MediaQuery.of(context).size.width;
  }
  return constraints.maxWidth;
}

class _AssistantBubbleFrame extends StatelessWidget {
  const _AssistantBubbleFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = _assistantBubbleWidth(context, constraints);
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            child: child,
          ),
        );
      },
    );
  }
}

class _MessageBubbleFrame extends StatelessWidget {
  const _MessageBubbleFrame({
    required this.isUser,
    required this.child,
  });

  final bool isUser;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: child,
        ),
      );
    }
    return _AssistantBubbleFrame(child: child);
  }
}

class _AssistantFillWidth extends StatelessWidget {
  const _AssistantFillWidth({
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return SizedBox(
      width: double.infinity,
      child: child,
    );
  }
}

class _StreamingBubbleSize extends StatelessWidget {
  const _StreamingBubbleSize({
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return AnimatedSize(
      duration: _kStreamingBubbleResizeDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: _AssistantFillWidth(
        enabled: enabled,
        child: child,
      ),
    );
  }
}

bool _isContextToolPart(MessagePart part) {
  if (part.type != PartType.tool) return false;
  const names = {'read', 'glob', 'grep', 'list'};
  return names.contains(part.data['tool'] as String? ?? '');
}

bool _hasLongStreamingTextParts(Iterable<MessagePart> parts) {
  var total = 0;
  for (final part in parts) {
    if (!_isPlainTextLikePart(part)) continue;
    total += (part.data['text'] as String? ?? '').length;
    if (total > 3200) return true;
  }
  return false;
}

String _toolNameFromPart(MessagePart part) {
  if (part.type != PartType.tool) return '';
  return part.data['tool'] as String? ?? '';
}

String _toolStatusFromPart(MessagePart part) {
  if (part.type != PartType.tool) return 'completed';
  final toolState =
      Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
  return toolState['status'] as String? ?? 'pending';
}

int? _assistantTurnDurationMs(
  AppState state,
  SessionMessageBundle assistantBundle,
) {
  final bundleIdx = state.messages
      .indexWhere((item) => item.message.id == assistantBundle.message.id);
  if (bundleIdx < 0) return null;
  return _turnDurationMsForAssistantBundle(state, bundleIdx);
}

int _messageBundleVisualSignature(
  SessionMessageBundle bundle, {
  bool ignoreStreamingText = false,
}) {
  var hash = Object.hash(
    _messageTileVisualSignature(bundle.message),
    bundle.parts.length,
  );
  for (final part in bundle.parts) {
    hash = Object.hash(
      hash,
      _partTileVisualSignature(
        part,
        ignoreStreamingText: ignoreStreamingText,
      ),
    );
  }
  return hash;
}

int _timelineTurnVisualSignature(
  _TimelineTurnEntry entry,
  List<SessionMessageBundle> renderedMessages,
  String? streamingAssistantMessageId,
) {
  var hash = entry.userIndex == null
      ? 17
      : _messageBundleVisualSignature(renderedMessages[entry.userIndex!]);
  for (final index in entry.assistantIndices) {
    final bundle = renderedMessages[index];
    hash = Object.hash(
      hash,
      _messageBundleVisualSignature(
        bundle,
        ignoreStreamingText: bundle.message.id == streamingAssistantMessageId,
      ),
    );
  }
  return hash;
}

extension _HomePageTimeline on _HomePageState {
  int _timelineItemCount(
    AppState state,
    List<_TimelineTurnEntry> renderedEntries,
  ) {
    final showGlobalRunningIndicator = state.isBusy && renderedEntries.isEmpty;
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
      count += renderedEntries.length;
    }
    if (state.error != null && !state.isBusy) {
      count += 1;
    }
    if (showGlobalRunningIndicator) {
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
    required List<_TimelineTurnEntry> renderedEntries,
    required String? streamingAssistantMessageId,
    required int index,
  }) {
    var cursor = 0;
    if (index == cursor++) {
      final currentVariant = _effectiveSelectedVariant(state);
      return _TimelineHeaderCard(
        workspaceName: state.workspace?.name ??
            l(context, '未选择工作区', 'No workspace selected'),
        sessionTitle: state.session?.title ?? l(context, '新会话', 'New session'),
        agentName: _selectedAgent ?? state.session?.agent ?? 'build',
        providerLabel: _providerLabel(modelConfig.provider,
            config: modelConfig, state: state),
        modelLabel: currentModelChoice?.name ?? modelConfig.model,
        variantLabel: currentVariant,
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
        final currentVariant = _effectiveSelectedVariant(state);
        return _EmptyTimelineCard(
          onSelectModel: () => _openModelChooser(context),
          providerLabel: _providerLabel(modelConfig.provider,
              config: modelConfig, state: state),
          modelLabel: currentModelChoice?.name ?? modelConfig.model,
          variantLabel: currentVariant,
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
      final messageEnd = cursor + renderedEntries.length;
      if (index < messageEnd) {
        final entryIndex = index - cursor;
        final entry = renderedEntries[entryIndex];
        return KeyedSubtree(
          key: _timelineEntryKey(entry.stableId),
          child: _TimelineTurnGroup(
            key: ValueKey<String>(entry.stableId),
            entry: entry,
            renderedMessages: renderedMessages,
            state: state,
            streamingAssistantMessageId: streamingAssistantMessageId,
            controller: widget.controller,
            onInsertPromptReference: _appendPromptReference,
            onSendPromptReference: _sendPromptReference,
          ),
        );
      }
      cursor = messageEnd;
    }
    if (state.error != null && !state.isBusy) {
      if (index == cursor++) {
        return _TimelineErrorCard(
          message: state.error!,
        );
      }
    }
    if (state.isBusy && renderedEntries.isEmpty) {
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

class _TurnPartEntry {
  const _TurnPartEntry({
    required this.bundle,
    required this.part,
    required this.streamAssistantContent,
  });

  final SessionMessageBundle bundle;
  final MessagePart part;
  final bool streamAssistantContent;
}

class _TurnDisplayItem {
  const _TurnDisplayItem.part(this.entry) : entries = const [];
  const _TurnDisplayItem.contextGroup(this.entries) : entry = null;

  final _TurnPartEntry? entry;
  final List<_TurnPartEntry> entries;

  bool get isContextGroup => entry == null;
}

class _TimelineTurnGroup extends StatefulWidget {
  const _TimelineTurnGroup({
    super.key,
    required this.entry,
    required this.renderedMessages,
    required this.state,
    required this.streamingAssistantMessageId,
    required this.controller,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final _TimelineTurnEntry entry;
  final List<SessionMessageBundle> renderedMessages;
  final AppState state;
  final String? streamingAssistantMessageId;
  final AppController controller;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  State<_TimelineTurnGroup> createState() => _TimelineTurnGroupState();
}

class _TimelineTurnGroupState extends State<_TimelineTurnGroup> {
  Widget? _cached;
  int? _lastThemeKey;
  int? _lastEntrySignature;
  String? _lastStreamingAssistantMessageId;
  int? _lastLayoutWidth;

  @override
  void reassemble() {
    _cached = null;
    _lastLayoutWidth = null;
    super.reassemble();
  }

  @override
  Widget build(BuildContext context) {
    final themeKey = context.themeCacheKey;
    final entrySignature = _timelineTurnVisualSignature(
      widget.entry,
      widget.renderedMessages,
      widget.streamingAssistantMessageId,
    );
    final layoutWidth = MediaQuery.of(context).size.width.round();
    if (_cached != null &&
        _lastThemeKey == themeKey &&
        _lastEntrySignature == entrySignature &&
        _lastStreamingAssistantMessageId ==
            widget.streamingAssistantMessageId &&
        _lastLayoutWidth == layoutWidth) {
      return _cached!;
    }
    _lastThemeKey = themeKey;
    _lastEntrySignature = entrySignature;
    _lastStreamingAssistantMessageId = widget.streamingAssistantMessageId;
    _lastLayoutWidth = layoutWidth;
    _cached = _buildContent(context);
    return _cached!;
  }

  Widget _buildContent(BuildContext context) {
    final userBundle = widget.entry.userIndex == null
        ? null
        : widget.renderedMessages[widget.entry.userIndex!];
    final assistantBundles = [
      for (final idx in widget.entry.assistantIndices)
        widget.renderedMessages[idx],
    ];
    final hasAssistant = assistantBundles.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (userBundle != null)
            _MessageBubble(
              key: ValueKey<String>(userBundle.message.id),
              bundle: userBundle,
              state: widget.state,
              isStreamingAssistantMessage: false,
              controller: widget.controller,
              onInsertPromptReference: widget.onInsertPromptReference,
              onSendPromptReference: widget.onSendPromptReference,
              bottomPadding: hasAssistant ? 6 : 0,
            ),
          if (hasAssistant)
            _AssistantTurnBubble(
              bundles: assistantBundles,
              state: widget.state,
              streamingAssistantMessageId: widget.streamingAssistantMessageId,
              controller: widget.controller,
              onInsertPromptReference: widget.onInsertPromptReference,
              onSendPromptReference: widget.onSendPromptReference,
            ),
        ],
      ),
    );
  }
}

class _AssistantTurnBubble extends StatelessWidget {
  const _AssistantTurnBubble({
    required this.bundles,
    required this.state,
    required this.streamingAssistantMessageId,
    required this.controller,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final List<SessionMessageBundle> bundles;
  final AppState state;
  final String? streamingAssistantMessageId;
  final AppController controller;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  List<_TurnDisplayItem> _buildDisplayItems(List<_TurnPartEntry> entries) {
    final items = <_TurnDisplayItem>[];
    final contextGroup = <_TurnPartEntry>[];

    void flushContextGroup() {
      if (contextGroup.isEmpty) return;
      if (contextGroup.length == 1) {
        items.add(_TurnDisplayItem.part(contextGroup.single));
      } else {
        items.add(
          _TurnDisplayItem.contextGroup(
            List<_TurnPartEntry>.unmodifiable(contextGroup),
          ),
        );
      }
      contextGroup.clear();
    }

    for (final entry in entries) {
      if (_isContextToolPart(entry.part)) {
        contextGroup.add(entry);
        continue;
      }
      flushContextGroup();
      items.add(_TurnDisplayItem.part(entry));
    }
    flushContextGroup();
    return List<_TurnDisplayItem>.unmodifiable(items);
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final visibleEntries = <_TurnPartEntry>[];
    for (final bundle in bundles) {
      final streamAssistantContent =
          streamingAssistantMessageId == bundle.message.id;
      final visibleParts = _visibleTimelineParts(bundle);
      for (var i = 0; i < visibleParts.length; i++) {
        final part = visibleParts[i];
        visibleEntries.add(
          _TurnPartEntry(
            bundle: bundle,
            part: part,
            streamAssistantContent: _shouldStreamTimelinePart(
              visibleParts,
              i,
              streamAssistantContent,
            ),
          ),
        );
      }
    }
    if (visibleEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    _TurnPartEntry? lastPlainTextEntry;
    for (var i = visibleEntries.length - 1; i >= 0; i--) {
      final part = visibleEntries[i].part;
      if (part.type == PartType.text &&
          !((part.data['structured'] as bool?) ?? false)) {
        lastPlainTextEntry = visibleEntries[i];
        break;
      }
    }

    final displayItems = _buildDisplayItems(visibleEntries);
    final firstBundle = bundles.first;
    final turnDurationMs = _assistantTurnDurationMs(state, bundles.last);
    final compactionOnly = visibleEntries.length == 1 &&
        visibleEntries.first.part.type == PartType.compaction &&
        firstBundle.message.text.isEmpty;
    final isStreamingTurn = bundles
        .any((bundle) => bundle.message.id == streamingAssistantMessageId);

    if (compactionOnly) {
      final entry = visibleEntries.first;
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _CachedPartTile(
            key: ValueKey<String>('assistant-compaction-${entry.part.id}'),
            part: entry.part,
            message: entry.bundle.message,
            controller: controller,
            workspace: controller.state.workspace,
            serverUri: controller.state.serverUri,
            streamAssistantContent: false,
            turnDurationMs: null,
            showAssistantTextMeta: false,
            onInsertPromptReference: onInsertPromptReference,
            onSendPromptReference: onSendPromptReference,
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: _AssistantBubbleFrame(
        child: _StreamingBubbleSize(
          enabled: isStreamingTurn &&
              !_hasLongStreamingTextParts(
                visibleEntries.map((entry) => entry.part),
              ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
            decoration: _chatSurfaceDecoration(
              context,
              color: oc.agentBubble,
              radius: 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        firstBundle.message.agent,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: oc.foregroundMuted,
                              letterSpacing: 0.2,
                            ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatTimelineTimestamp(firstBundle.message.createdAt),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: oc.foregroundFaint),
                      ),
                    ],
                  ),
                ),
                for (final item in displayItems) ...[
                  const SizedBox(height: 10),
                  if (item.isContextGroup)
                    _ContextToolGroupTile(
                      key: ValueKey<String>(
                        'context-${item.entries.first.part.id}-${item.entries.last.part.id}',
                      ),
                      entries: item.entries,
                      controller: controller,
                      workspace: controller.state.workspace,
                      serverUri: controller.state.serverUri,
                      onInsertPromptReference: onInsertPromptReference,
                      onSendPromptReference: onSendPromptReference,
                    )
                  else
                    _CachedPartTile(
                      key: ValueKey<String>(
                          'assistant-part-${item.entry!.part.id}'),
                      part: item.entry!.part,
                      message: item.entry!.bundle.message,
                      controller: controller,
                      workspace: controller.state.workspace,
                      serverUri: controller.state.serverUri,
                      streamAssistantContent:
                          item.entry!.streamAssistantContent,
                      turnDurationMs: turnDurationMs,
                      showAssistantTextMeta:
                          identical(item.entry, lastPlainTextEntry),
                      onInsertPromptReference: onInsertPromptReference,
                      onSendPromptReference: onSendPromptReference,
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

class _ContextToolGroupTile extends StatefulWidget {
  const _ContextToolGroupTile({
    super.key,
    required this.entries,
    required this.controller,
    required this.workspace,
    required this.serverUri,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final List<_TurnPartEntry> entries;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final Uri? serverUri;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  State<_ContextToolGroupTile> createState() => _ContextToolGroupTileState();
}

class _ContextToolGroupTileState extends State<_ContextToolGroupTile>
    with AutomaticKeepAliveClientMixin<_ContextToolGroupTile> {
  late bool _expanded;
  bool _userToggled = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _expanded = _shouldExpand(widget.entries);
  }

  @override
  void didUpdateWidget(covariant _ContextToolGroupTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_userToggled) return;
    if (_shouldExpand(widget.entries)) {
      _expanded = true;
    }
  }

  bool _shouldExpand(List<_TurnPartEntry> entries) {
    for (final entry in entries) {
      final status = _toolStatusFromPart(entry.part);
      if (status == 'running' || status == 'pending' || status == 'error') {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final oc = context.oc;
    final toolNames = widget.entries
        .map((entry) => _toolNameFromPart(entry.part))
        .where((name) => name.isNotEmpty)
        .toSet()
        .join(' · ');
    return Container(
      width: double.infinity,
      decoration: _panelDecoration(context,
          background: oc.composerOptionBg, radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              const _TimelineDetachNotification().dispatch(context);
              setState(() {
                _userToggled = true;
                _expanded = !_expanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.travel_explore_outlined,
                    size: 18,
                    color: oc.foregroundMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l(context, '上下文', 'Context'),
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: oc.foregroundMuted,
                                  ),
                        ),
                        if (toolNames.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            toolNames,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: oc.foregroundHint),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: oc.shadow,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: oc.softBorderColor),
                    ),
                    child: Text(
                      '${widget.entries.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: oc.foregroundMuted,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOutCubic,
                    child: Icon(
                      Icons.expand_more,
                      color: oc.foregroundMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          _SmoothExpansion(
            open: _expanded,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Divider(height: 1, thickness: 1, color: oc.softBorderColor),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 38),
                      child: _DeferredHeavyContent(
                        cacheKey: widget.entries
                            .map((entry) => entry.part.id)
                            .join('|'),
                        builder: (context) => Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < widget.entries.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              _CachedPartTile(
                                key: ValueKey<String>(
                                  'context-part-${widget.entries[i].part.id}',
                                ),
                                part: widget.entries[i].part,
                                message: widget.entries[i].bundle.message,
                                controller: widget.controller,
                                workspace: widget.workspace,
                                serverUri: widget.serverUri,
                                streamAssistantContent:
                                    widget.entries[i].streamAssistantContent,
                                turnDurationMs: null,
                                showAssistantTextMeta: false,
                                onInsertPromptReference:
                                    widget.onInsertPromptReference,
                                onSendPromptReference:
                                    widget.onSendPromptReference,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                _QuickCollapseButton(
                  onPressed: () {
                    setState(() {
                      _userToggled = true;
                      _expanded = false;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    this.bottomPadding = 10,
  });

  final SessionMessageBundle bundle;
  final AppState state;
  final bool isStreamingAssistantMessage;
  final AppController controller;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;
  final double bottomPadding;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  Widget? _cached;
  int? _lastBundleSignature;
  bool? _lastStreaming;
  int? _lastThemeKey;
  double? _lastBottomPadding;
  int? _lastLayoutWidth;

  List<MessagePart>? _cachedPrimaryParts;
  List<MessagePart>? _cachedFooterParts;
  int? _lastPartsRevision;
  int? _cachedTurnDurationMs;
  bool _turnDurationComputed = false;

  @override
  void reassemble() {
    _cached = null;
    _lastLayoutWidth = null;
    super.reassemble();
  }

  @override
  Widget build(BuildContext context) {
    final themeKey = context.themeCacheKey;
    final bundleSignature = _messageBundleVisualSignature(
      widget.bundle,
      ignoreStreamingText: widget.isStreamingAssistantMessage,
    );
    final layoutWidth = MediaQuery.of(context).size.width.round();
    if (_lastBundleSignature == bundleSignature &&
        widget.isStreamingAssistantMessage == _lastStreaming &&
        themeKey == _lastThemeKey &&
        widget.bottomPadding == _lastBottomPadding &&
        _lastLayoutWidth == layoutWidth &&
        _cached != null) {
      return _cached!;
    }
    if (_lastBundleSignature != bundleSignature) {
      _turnDurationComputed = false;
    }
    _lastBundleSignature = bundleSignature;
    _lastStreaming = widget.isStreamingAssistantMessage;
    _lastThemeKey = themeKey;
    _lastBottomPadding = widget.bottomPadding;
    _lastLayoutWidth = layoutWidth;
    _cached = _buildContent(context);
    return _cached!;
  }

  void _refreshPartsSplit(List<MessagePart> parts) {
    final partsRevision = widget.bundle.revision;
    if (_lastPartsRevision == partsRevision) return;
    _lastPartsRevision = partsRevision;
    final primary = <MessagePart>[];
    final footer = <MessagePart>[];
    final hasCompaction = parts.any((p) => p.type == PartType.compaction);
    for (final p in parts) {
      if (widget.bundle.message.role == SessionRole.user &&
          p.type == PartType.text) {
        continue;
      }
      if (hasCompaction && p.type == PartType.text) {
        continue;
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
    final userText = isUser
        ? _userMessageText(bundle.message, bundle.parts)
        : bundle.message.text;
    final label = isUser ? l(context, '你', 'You') : bundle.message.agent;
    final bubbleColor = isUser ? oc.userBubble : oc.agentBubble;
    final hasCompaction =
        primaryParts.any((p) => p.type == PartType.compaction);
    final compactionOnly = !isUser &&
        bundle.message.text.isEmpty &&
        footerParts.isEmpty &&
        primaryParts.length == 1 &&
        primaryParts.first.type == PartType.compaction;
    final compactionBoundaryOnly = isUser &&
        bundle.message.text.isEmpty &&
        footerParts.isEmpty &&
        primaryParts.length == 1 &&
        primaryParts.first.type == PartType.compaction;
    if (compactionBoundaryOnly) {
      return const SizedBox.shrink();
    }
    if (compactionOnly) {
      return RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: _CachedPartTile(
                key: ValueKey<String>(
                    'message-compaction-${primaryParts.first.id}'),
                part: primaryParts.first,
                message: bundle.message,
                controller: widget.controller,
                workspace: widget.controller.state.workspace,
                serverUri: widget.controller.state.serverUri,
                streamAssistantContent: false,
                turnDurationMs: null,
                showAssistantTextMeta: false,
                onInsertPromptReference: widget.onInsertPromptReference,
                onSendPromptReference: widget.onSendPromptReference,
              ),
            ),
          ),
        ),
      );
    }
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.only(bottom: widget.bottomPadding),
        child: _MessageBubbleFrame(
          isUser: isUser,
          child: _StreamingBubbleSize(
            enabled: widget.isStreamingAssistantMessage &&
                !isUser &&
                !_hasLongStreamingTextParts(primaryParts),
            child: SizedBox(
              width: isUser ? null : double.infinity,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  isUser ? 15 : 14,
                  12,
                  isUser ? 15 : 14,
                  13,
                ),
                decoration: _chatSurfaceDecoration(
                  context,
                  color: bubbleColor,
                  radius: isUser ? 24 : 24,
                  elevated: !isUser,
                  accent: isUser,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: oc.foregroundMuted,
                                  letterSpacing: 0.2,
                                ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatTimelineTimestamp(bundle.message.createdAt),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: oc.foregroundFaint),
                          ),
                        ],
                      ),
                    ),
                    if (!hasCompaction && userText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        userText,
                        style: const TextStyle(fontSize: 15, height: 1.45),
                      ),
                    ],
                    for (var i = 0; i < primaryParts.length; i++) ...[
                      const SizedBox(height: 10),
                      _CachedPartTile(
                        key: ValueKey<String>(
                            'message-part-${primaryParts[i].id}'),
                        part: primaryParts[i],
                        message: bundle.message,
                        controller: widget.controller,
                        workspace: widget.controller.state.workspace,
                        serverUri: widget.controller.state.serverUri,
                        streamAssistantContent: _shouldStreamTimelinePart(
                          primaryParts,
                          i,
                          widget.isStreamingAssistantMessage,
                        ),
                        turnDurationMs: turnDurationMs,
                        showAssistantTextMeta: !isUser &&
                            lastPlainTextPart != null &&
                            identical(primaryParts[i], lastPlainTextPart),
                        onInsertPromptReference: widget.onInsertPromptReference,
                        onSendPromptReference: widget.onSendPromptReference,
                      ),
                    ],
                    if (footerParts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: oc.softBorderColor,
                      ),
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
                        _CachedPartTile(
                          key: ValueKey<String>('message-footer-${part.id}'),
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
                          onSendPromptReference: widget.onSendPromptReference,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _userMessageText(MessageInfo message, List<MessagePart> parts) {
    final text = parts
        .where((part) => part.type == PartType.text)
        .map((part) => part.data['text'] as String? ?? '')
        .where((text) => text.isNotEmpty)
        .join('\n');
    if (text.isNotEmpty) return text;
    return message.text;
  }
}

class _SessionAppBarTitle extends StatelessWidget {
  const _SessionAppBarTitle({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: oc.foreground,
        letterSpacing: -0.1,
      ),
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
    this.variantLabel,
    required this.showModelFreeTag,
    required this.showModelLatestTag,
    required this.showMeta,
  });

  final String workspaceName;
  final String sessionTitle;
  final String agentName;
  final String providerLabel;
  final String modelLabel;
  final String? variantLabel;
  final bool showModelFreeTag;
  final bool showModelLatestTag;
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final dark = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: _chatSurfaceDecoration(
        context,
        color: oc.panelBackground,
        radius: 26,
        accent: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: oc.accent.withOpacity(dark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(
                    color: oc.accent.withOpacity(dark ? 0.26 : 0.16),
                  ),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: oc.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sessionTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                            letterSpacing: -0.2,
                            color: oc.foreground,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      workspaceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: oc.foregroundMuted,
                            height: 1.2,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showMeta) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _TinyTag(label: agentName, color: oc.tagBlueGrey),
                _TinyTag(label: providerLabel, color: oc.tagGreen),
                _TinyTag(label: modelLabel, color: oc.tagBlue),
                if (variantLabel != null && variantLabel!.isNotEmpty)
                  _TinyTag(label: variantLabel!, color: oc.tagOrange),
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
    this.modelLimit,
    required this.onInitializeMemory,
    required this.onCompactSession,
    required this.onViewRawContext,
  });

  final SessionInfo? session;
  final String model;
  final ProviderModelLimit? modelLimit;
  final VoidCallback? onInitializeMemory;
  final VoidCallback? onCompactSession;
  final VoidCallback? onViewRawContext;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final ratio = _contextUsageRatio(session, model, limit: modelLimit);
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
                _contextUsageLabel(session, model, limit: modelLimit),
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
                  label:
                      l(context, '初始化/更新 Mag.md', 'Initialize/Update Mag.md'),
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
          width: 32,
          height: 32,
          child: Container(
            decoration: BoxDecoration(
              color: oc.panelBackground.withOpacity(0.78),
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: oc.borderColor)),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: clampedRatio,
                    strokeWidth: 1.8,
                    backgroundColor: oc.progressBg,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                Icon(
                  compacted ? Icons.compress_outlined : Icons.memory_outlined,
                  size: 16,
                  color: oc.foreground,
                ),
              ],
            ),
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
    this.variantLabel,
    this.showModelFreeTag = false,
    this.showModelLatestTag = false,
  });

  final VoidCallback onSelectModel;
  final String? providerLabel;
  final String? modelLabel;
  final String? variantLabel;
  final bool showModelFreeTag;
  final bool showModelLatestTag;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final dark = context.isDarkMode;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: _chatSurfaceDecoration(
        context,
        color: oc.panelBackground,
        radius: 26,
        accent: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: oc.accent.withOpacity(dark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: oc.accent.withOpacity(dark ? 0.28 : 0.16),
                  ),
                ),
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 19,
                  color: oc.accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l(context, '从一个好问题开始', 'Start with a good question'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: oc.foreground,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.15,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      l(
                        context,
                        '描述目标、贴上上下文，或用 @ 引用文件。Mag 会把工作区理解成一次清晰的对话。',
                        'Describe the goal, add context, or reference files with @. Mag turns the workspace into a focused conversation.',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: oc.foregroundMuted,
                            height: 1.42,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (providerLabel != null || modelLabel != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (modelLabel != null)
                  _TinyTag(label: modelLabel!, color: oc.tagBlue),
                if (providerLabel != null)
                  _TinyTag(label: providerLabel!, color: oc.tagGreen),
                if (variantLabel != null && variantLabel!.isNotEmpty)
                  _TinyTag(label: variantLabel!, color: oc.tagOrange),
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
          const SizedBox(height: 15),
          FilledButton.tonalIcon(
            onPressed: onSelectModel,
            icon: const Icon(Icons.auto_awesome_outlined, size: 17),
            label: Text(l(context, '调整模型', 'Tune model')),
            style: FilledButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            ),
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

class _TimelineErrorCard extends StatelessWidget {
  const _TimelineErrorCard({
    required this.message,
  });

  final String message;

  String _providerMessage() {
    var value = message.trim();
    while (value.startsWith('Exception: ')) {
      value = value.substring('Exception: '.length).trimLeft();
    }
    return value.isEmpty ? message : value;
  }

  String _title(BuildContext context) {
    final lower = message.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('connection') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('network') ||
        lower.contains('failed host lookup')) {
      return l(context, '连接中断', 'Connection interrupted');
    }
    if (lower.contains('cancel') ||
        lower.contains('stopped') ||
        lower.contains('aborted')) {
      return l(context, '已停止', 'Stopped');
    }
    if (lower.contains('model request failed') ||
        lower.contains('provider') ||
        lower.contains('api key') ||
        lower.contains('quota') ||
        lower.contains('billing') ||
        lower.contains('not supported') ||
        lower.contains('403') ||
        lower.contains('401') ||
        lower.contains('429')) {
      return l(context, '模型请求失败', 'Model request failed');
    }
    return l(context, '生成未完成', 'Generation did not finish');
  }

  String _detail(BuildContext context) {
    final lower = message.toLowerCase();
    if (lower.contains('socketexception') ||
        lower.contains('connection') ||
        lower.contains('timed out') ||
        lower.contains('timeout') ||
        lower.contains('network') ||
        lower.contains('failed host lookup')) {
      return l(context, '网络连接不稳定，稍后刷新或重新发送即可。',
          'The network connection was interrupted. Refresh or try again.');
    }
    if (lower.contains('cancel') ||
        lower.contains('stopped') ||
        lower.contains('aborted')) {
      return l(context, '本次生成已停止。', 'This generation was stopped.');
    }
    if (lower.contains('model request failed') ||
        lower.contains('provider') ||
        lower.contains('api key') ||
        lower.contains('quota') ||
        lower.contains('billing') ||
        lower.contains('not supported') ||
        lower.contains('403') ||
        lower.contains('401') ||
        lower.contains('429')) {
      return _providerMessage();
    }
    return l(context, '这次回复没有完成，可以重新发送或稍后再试。',
        'This response did not finish. Try sending again later.');
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            decoration: BoxDecoration(
              color: oc.mutedPanel.withOpacity(context.isDarkMode ? 0.58 : 0.8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: oc.softBorderColor),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: oc.foregroundHint,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(context),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: oc.foreground,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _detail(context),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: oc.foregroundMuted,
                              height: 1.2,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
    final oc = context.oc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(context.isDarkMode ? 0.34 : 0.52),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: oc.softBorderColor),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: oc.foreground,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.05,
            ),
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
    this.onDisconnect,
  });

  final _ProviderPreset item;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDisconnect;

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
              if (selected) ...[
                Container(
                  margin: const EdgeInsets.only(left: 6, top: 1),
                  padding: const EdgeInsets.only(
                      left: 8, right: 2, top: 3, bottom: 3),
                  decoration: BoxDecoration(
                    color: oc.selectedFill,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: oc.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l(context, '已连接', 'Connected'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: oc.accent,
                        ),
                      ),
                      if (onDisconnect != null) ...[
                        Container(
                          width: 1,
                          height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          color: oc.border,
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: onDisconnect,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.link_off_rounded,
                              size: 14,
                              color: oc.muted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
