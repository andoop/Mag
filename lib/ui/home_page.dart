library home_page;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdfx/pdfx.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/models.dart';
import '../core/workspace_bridge.dart';
import '../sdk/local_server_client.dart';
import '../store/app_controller.dart';
import 'i18n.dart';
import 'oc_theme.dart';

part 'home/constants.dart';
part 'home/timeline.dart';
part 'home/composer.dart';
part 'home/shell.dart';
part 'home/panels.dart';
part 'home/landing.dart';
part 'home/workspace_browser.dart';

part 'home/parts/tiles.dart';
part 'home/parts/markdown.dart';
part 'home/parts/reasoning.dart';
part 'home/parts/text_footer.dart';
part 'home/parts/tool_widgets.dart';

part 'home/attachments/attachment_tile.dart';
part 'home/attachments/file_results.dart';
part 'home/attachments/diff_preview.dart';
part 'home/attachments/media_tiles.dart';

part 'home/previews/web_preview.dart';
part 'home/previews/pdf_preview.dart';
part 'home/previews/file_preview.dart';
part 'home/previews/html_preview.dart';

part 'home/pickers/picker_utils.dart';
part 'home/pickers/oauth_sheet.dart';
part 'home/pickers/provider_picker.dart';
part 'home/pickers/model_picker.dart';
part 'home/pickers/variant_picker.dart';
part 'home/pickers/agent_picker.dart';
part 'home/pickers/settings_sheet.dart';
part 'home/pickers/presets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _PromptMentionMatch {
  const _PromptMentionMatch({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();
  final TextEditingController _schemaController = TextEditingController(
    text: const JsonEncoder.withIndent('  ')
        .convert(_structuredSchemaTemplates['answer']),
  );
  final ScrollController _timelineController = ScrollController();
  String? _selectedAgent;
  String? _selectedVariant;
  bool _selectedVariantDirty = false;
  // Mutated from part-file extensions that own composer/schema interactions.
  // ignore: prefer_final_fields
  bool _structuredOutputEnabled = false;
  // ignore: prefer_final_fields
  String _selectedSchemaTemplate = 'answer';
  final ValueNotifier<bool> _stickToBottom = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _showScrollToBottomButton =
      ValueNotifier<bool>(false);
  final ValueNotifier<int> _messageVersion = ValueNotifier<int>(0);
  bool _messageVersionScheduled = false;
  bool _isAutoScrolling = false;
  bool _pendingTimelineSync = false;
  bool _timelineSyncScheduled = false;
  bool _timelineUserInteracting = false;
  double? _lastProgrammaticScrollTarget;
  int _lastProgrammaticScrollAt = 0;
  String _lastTimelineAnchor = '';
  String _historySessionId = '';
  int _historyStartIndex = 0;
  int _stagedMessageCount = 0;
  String _stagingKey = '';
  String _timelineEntryCacheKey = '';
  List<_TimelineTurnEntry> _cachedTimelineEntries = const [];
  String? _cachedStreamingAssistantMessageId;
  int _lastBackfillAt = 0;
  String _lastStateRenderKey = '';
  String _lastStructuralKey = '';
  // ignore: prefer_final_fields
  List<WorkspaceEntry> _promptMentionSuggestions = const [];
  _PromptMentionMatch? _activePromptMention;
  // ignore: prefer_final_fields
  int _promptMentionSelectedIndex = 0;
  // ignore: prefer_final_fields
  bool _promptMentionSearching = false;
  Timer? _promptMentionDebounce;
  Timer? _scrollToBottomButtonDebounce;
  // ignore: prefer_final_fields
  int _promptMentionRequestId = 0;
  List<WorkspaceEntry> _promptAttachments = const [];
  bool _pendingScrollToBottomButtonVisible = false;

  /// 会话切换时必须重建时间线；不能仅依赖 [_stateRenderKey]，否则新建/切换会话后可能与旧 key 碰撞而不调用 setState，界面仍显示旧消息。
  String? _lastObservedSessionId;
  String _lastObservedModelKey = '';

  @override
  void initState() {
    super.initState();
    _timelineController.addListener(_handleTimelineScroll);
    _promptController.addListener(_handlePromptComposerChanged);
    _promptFocusNode.addListener(_handlePromptComposerChanged);
    _stickToBottom.addListener(_handleStickToBottomChanged);
    widget.controller.addListener(_onStateChanged);
    _scheduleScrollToBottomButtonVisibility(false, immediate: true);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    _stickToBottom.removeListener(_handleStickToBottomChanged);
    _timelineController
      ..removeListener(_handleTimelineScroll)
      ..dispose();
    _promptMentionDebounce?.cancel();
    _scrollToBottomButtonDebounce?.cancel();
    _promptController.removeListener(_handlePromptComposerChanged);
    _promptFocusNode.removeListener(_handlePromptComposerChanged);
    _promptController.dispose();
    _promptFocusNode.dispose();
    _schemaController.dispose();
    _stickToBottom.dispose();
    _showScrollToBottomButton.dispose();
    _messageVersion.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    final state = widget.controller.state;
    final sid = state.session?.id;
    final renderKey = _stateRenderKey(state);
    final sessionChanged = sid != _lastObservedSessionId;
    final modelKey = _currentVariantModelKey(state);
    final modelChanged = modelKey != _lastObservedModelKey;
    final variantChanged = () {
      if (sessionChanged || modelChanged) {
        _lastObservedModelKey = modelKey;
        _selectedVariantDirty = false;
        return _syncPromptVariantSelection(state, force: true);
      }
      return _syncPromptVariantSelection(state);
    }();
    if (sessionChanged) {
      _lastObservedSessionId = sid;
      _lastStateRenderKey = renderKey;
      _lastStructuralKey = _structuralRenderKey(state);
      _reconcileTimelineWindow(state);
      _scheduleTimelineSync(state);
      setState(() {});
      _stickToBottom.value = true;
      _scheduleScrollToBottomButtonVisibility(false, immediate: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_timelineController.hasClients) return;
        _scrollTimelineToBottom(animate: false);
      });
      return;
    }
    if (renderKey == _lastStateRenderKey) {
      if (variantChanged) {
        setState(() {});
      }
      return;
    }
    _lastStateRenderKey = renderKey;
    _reconcileTimelineWindow(state);
    _scheduleTimelineSync(state);
    final structuralKey = _structuralRenderKey(state);
    if (structuralKey != _lastStructuralKey || variantChanged) {
      _lastStructuralKey = structuralKey;
      setState(() {});
    } else {
      _scheduleMessageVersionTick();
    }
  }

  void _scheduleMessageVersionTick() {
    if (_messageVersionScheduled) return;
    _messageVersionScheduled = true;
    scheduleMicrotask(() {
      _messageVersionScheduled = false;
      if (!mounted) return;
      _messageVersion.value++;
    });
  }

  int _initialHistoryStart(List<SessionMessageBundle> messages) {
    const turnInit = 10;
    final userIndices = <int>[];
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].message.role == SessionRole.user) {
        userIndices.add(i);
      }
    }
    if (userIndices.length <= turnInit) return 0;
    return userIndices[userIndices.length - turnInit];
  }

  List<SessionMessageBundle> _visibleTimelineMessages(AppState state) {
    if (_historyStartIndex <= 0) return state.messages;
    return state.messages.sublist(_historyStartIndex);
  }

  List<SessionMessageBundle> _renderedTimelineMessages(AppState state) {
    final visible = _visibleTimelineMessages(state);
    if (_stagedMessageCount <= 0 || _stagedMessageCount >= visible.length) {
      return visible;
    }
    return visible.sublist(visible.length - _stagedMessageCount);
  }

  bool _isTimelineStaging(AppState state) {
    final visibleCount = _visibleTimelineMessages(state).length;
    return visibleCount > 0 &&
        _stagedMessageCount > 0 &&
        _stagedMessageCount < visibleCount;
  }

  List<_TimelineTurnEntry> _renderedTimelineEntries(
    AppState state,
    List<SessionMessageBundle> renderedMessages,
  ) {
    final firstMessage =
        renderedMessages.isEmpty ? null : renderedMessages.first.message;
    final lastMessage =
        renderedMessages.isEmpty ? null : renderedMessages.last.message;
    final cacheKey = [
      state.session?.id ?? '',
      _historyStartIndex,
      _stagedMessageCount,
      state.messages.length,
      renderedMessages.length,
      firstMessage?.id ?? '',
      firstMessage?.role.name ?? '',
      lastMessage?.id ?? '',
      lastMessage?.role.name ?? '',
    ].join('|');
    if (_timelineEntryCacheKey == cacheKey) {
      return _cachedTimelineEntries;
    }
    final entries = _buildTimelineEntries(renderedMessages);
    _timelineEntryCacheKey = cacheKey;
    _cachedTimelineEntries = entries;
    _cachedStreamingAssistantMessageId =
        _streamingAssistantMessageId(entries, renderedMessages);
    return entries;
  }

  String? _renderedStreamingAssistantMessageId(
    AppState state,
    List<SessionMessageBundle> renderedMessages,
    List<_TimelineTurnEntry> renderedEntries,
  ) {
    if (_timelineEntryCacheKey.isEmpty ||
        !identical(_cachedTimelineEntries, renderedEntries)) {
      _renderedTimelineEntries(state, renderedMessages);
    }
    return _cachedStreamingAssistantMessageId;
  }

  bool _hasEarlierHistory(AppState state) => _historyStartIndex > 0;

  void _reconcileTimelineWindow(AppState state) {
    final sessionId = state.session?.id ?? '';
    final initialStart = _initialHistoryStart(state.messages);
    if (_historySessionId != sessionId) {
      _historySessionId = sessionId;
      _historyStartIndex = initialStart;
      _stagedMessageCount = 0;
      _scheduleStageMount(state);
      return;
    }
    if (_historyStartIndex > state.messages.length) {
      _historyStartIndex = initialStart;
    }
    final visibleCount = _visibleTimelineMessages(state).length;
    if (_stagedMessageCount == 0 && visibleCount > 0) {
      _scheduleStageMount(state);
      return;
    }
    if (_stagedMessageCount > visibleCount) {
      _stagedMessageCount = visibleCount;
    }
    if (_stagedMessageCount < visibleCount && _stickToBottom.value) {
      _scheduleStageMount(state);
    }
  }

  void _scheduleStageMount(AppState state) {
    const init = 24;
    const batch = 16;
    final visibleCount = _visibleTimelineMessages(state).length;
    if (visibleCount <= 0) {
      _stagedMessageCount = 0;
      _stagingKey = '';
      return;
    }
    final key = '${state.session?.id ?? ''}|$_historyStartIndex|$visibleCount';
    final resetStage = _stagingKey != key || _stagedMessageCount == 0;
    _stagingKey = key;
    if (resetStage) {
      _stagedMessageCount = visibleCount <= init ? visibleCount : init;
    }
    if (_stagedMessageCount >= visibleCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stagingKey != key) return;
      final latestVisible =
          _visibleTimelineMessages(widget.controller.state).length;
      if (_stagedMessageCount >= latestVisible) return;
      setState(() {
        _stagedMessageCount =
            (_stagedMessageCount + batch).clamp(0, latestVisible);
      });
      if (_stagedMessageCount < latestVisible) {
        _scheduleStageMount(widget.controller.state);
      }
    });
  }

  void _revealEarlierMessages({bool all = false}) {
    final state = widget.controller.state;
    if (!_hasEarlierHistory(state) || !_timelineController.hasClients) return;
    const turnBatch = 8;
    final userIndices = <int>[];
    for (var i = 0; i < state.messages.length; i++) {
      if (state.messages[i].message.role == SessionRole.user) {
        userIndices.add(i);
      }
    }
    final currentTurnIndex =
        userIndices.indexWhere((index) => index >= _historyStartIndex);
    final nextTurnIndex =
        all ? 0 : (currentTurnIndex - turnBatch).clamp(0, currentTurnIndex);
    final nextStart = nextTurnIndex <= 0 ? 0 : userIndices[nextTurnIndex];
    if (nextStart == _historyStartIndex) return;
    final beforeOffset = _timelineController.offset;
    final beforeMax = _timelineController.position.maxScrollExtent;
    setState(() {
      _historyStartIndex = nextStart;
      _scheduleStageMount(widget.controller.state);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_timelineController.hasClients) return;
      final delta = _timelineController.position.maxScrollExtent - beforeMax;
      _timelineController.jumpTo(beforeOffset + delta);
    });
  }

  void _appendPromptReference(String text) {
    final existing = _promptController.text.trimRight();
    final next = existing.isEmpty ? text : '$existing\n\n$text';
    _promptController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() {});
  }

  Future<void> _sendPromptReference(String text) async {
    if (widget.controller.state.isBusy) {
      _showInfo(
          context,
          l(context, '当前会话正在执行，请稍后再发送',
              'The current session is still running. Please wait before sending another message.'));
      return;
    }
    final agent = _selectedAgent ?? widget.controller.state.session?.agent;
    await widget.controller.sendPrompt(
      text,
      agent: agent,
      variant: _effectiveSelectedVariant(widget.controller.state),
    );
    if (!mounted) return;
    _showInfo(context, l(context, '已作为下一条消息发送', 'Sent as the next message.'));
  }

  Future<void> _selectModel(_ModelChoice model) async {
    setState(() {
      _selectedVariant = null;
      _selectedVariantDirty = false;
    });
    await widget.controller.setCurrentModel(
      providerId: model.providerId,
      modelId: model.id,
    );
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<List<String>> _discoverModelsForProvider({
    required String providerId,
    required String baseUrl,
    required String apiKey,
    bool usePublicToken = false,
  }) async {
    final discovered = await widget.controller.discoverProviderModels(
      providerId: providerId,
      baseUrl: baseUrl,
      apiKey: apiKey,
      usePublicToken: usePublicToken,
    );
    if (discovered.isEmpty) {
      throw ProviderDiscoveryException(
        'Connected successfully, but the provider returned no models.',
      );
    }
    return discovered;
  }

  Future<void> _connectProviderPreset(
    _ProviderPreset preset, {
    required String apiKey,
    String? overrideBaseUrl,
  }) async {
    final current =
        widget.controller.state.modelConfig ?? ModelConfig.defaults();
    final baseUrl = (overrideBaseUrl ?? preset.baseUrl).trim();
    final models = await _discoverModelsForProvider(
      providerId: preset.id,
      baseUrl: baseUrl,
      apiKey: apiKey,
      usePublicToken: !preset.requiresApiKey && preset.id.startsWith('mag'),
    );
    final selectedModel = models.isNotEmpty
        ? models.first
        : (current.provider == preset.id
            ? current.model
            : ModelConfig.defaults().model);
    await widget.controller.connectProvider(
      ProviderConnection(
        id: preset.id,
        name: preset.name,
        baseUrl: baseUrl,
        apiKey: apiKey.trim(),
        models: models,
        custom: preset.custom,
      ),
      currentModelId: selectedModel,
      select: true,
    );
  }

  Future<void> _connectCustomProvider({
    required String providerId,
    required String name,
    required String baseUrl,
    required String apiKey,
    required List<String> models,
  }) async {
    await _discoverModelsForProvider(
      providerId: providerId,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );
    final filteredModels = models
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    await widget.controller.connectProvider(
      ProviderConnection(
        id: providerId.trim(),
        name: name.trim(),
        baseUrl: baseUrl.trim(),
        apiKey: apiKey.trim(),
        models: filteredModels,
        custom: true,
      ),
      currentModelId: filteredModels.isNotEmpty
          ? filteredModels.first
          : ModelConfig.defaults().model,
      select: true,
    );
  }

  List<_ModelChoice> _visibleModelChoices(AppState state) {
    final config = state.modelConfig ?? ModelConfig.defaults();
    return _connectedModelChoices(config, state: state)
        .where((item) => _isModelVisible(config, item))
        .toList();
  }

  _ModelChoice? _findModelChoice(
    String providerId,
    String modelId, {
    ModelConfig? config,
    AppState? state,
  }) {
    final source = config != null
        ? _connectedModelChoices(config, state: state)
        : _providerInfoById(providerId, state: state)
                ?.models
                .values
                .map(
                  (item) =>
                      _modelChoiceFromProviderModel(
                        providerId: providerId,
                        id: item.id,
                        info: item,
                        latestIds:
                            _providerInfoById(providerId, state: state) != null
                                ? _latestModelIdsForProvider(
                                    _providerInfoById(providerId,
                                        state: state)!,
                                  )
                                : const <String>{},
                      ) ??
                      _ModelChoice(
                        providerId: providerId,
                        id: item.id,
                        name: item.name,
                      ),
                )
                .toList() ??
            _builtinModelCatalog;
    for (final item in source) {
      if (item.providerId == providerId && item.id == modelId) {
        return item;
      }
    }
    return null;
  }

  String _modelKey(String providerId, String modelId) => '$providerId/$modelId';

  bool _matchesModelQuery(_ModelChoice item, String query) {
    if (query.isEmpty) return true;
    final providerLabel = _providerLabel(
      item.providerId,
      config: widget.controller.state.modelConfig,
      state: widget.controller.state,
    ).toLowerCase();
    return item.name.toLowerCase().contains(query) ||
        item.id.toLowerCase().contains(query) ||
        item.providerId.toLowerCase().contains(query) ||
        providerLabel.contains(query);
  }

  int _compareModelChoices(_ModelChoice a, _ModelChoice b, AppState state) {
    final current = state.modelConfig ?? ModelConfig.defaults();
    final recentOrder = <String, int>{};
    for (var i = 0; i < state.recentModelKeys.length; i++) {
      recentOrder[state.recentModelKeys[i]] = i;
    }

    final aKey = _modelKey(a.providerId, a.id);
    final bKey = _modelKey(b.providerId, b.id);
    final aIsCurrent =
        a.providerId == current.provider && a.id == current.model;
    final bIsCurrent =
        b.providerId == current.provider && b.id == current.model;
    if (aIsCurrent != bIsCurrent) return aIsCurrent ? -1 : 1;

    final aRecent = recentOrder[aKey];
    final bRecent = recentOrder[bKey];
    if (aRecent != null && bRecent != null && aRecent != bRecent) {
      return aRecent.compareTo(bRecent);
    }
    if (aRecent != null && bRecent == null) return -1;
    if (aRecent == null && bRecent != null) return 1;

    if (a.latest != b.latest) return a.latest ? -1 : 1;
    if (a.recommended != b.recommended) return a.recommended ? -1 : 1;
    if (a.free != b.free) return a.free ? -1 : 1;

    final aProvider = _providerById(
      a.providerId,
      config: current,
      state: state,
    );
    final bProvider = _providerById(
      b.providerId,
      config: current,
      state: state,
    );
    if ((aProvider?.recommended ?? false) !=
        (bProvider?.recommended ?? false)) {
      return (aProvider?.recommended ?? false) ? -1 : 1;
    }
    if ((aProvider?.popular ?? false) != (bProvider?.popular ?? false)) {
      return (aProvider?.popular ?? false) ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  Future<void> _openModelChooser(BuildContext context) async {
    await _openModelPicker(context);
  }

  Widget _buildAppBarAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(7),
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      splashRadius: 18,
      iconSize: 20,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;
    final modelConfig = state.modelConfig ?? ModelConfig.defaults();
    final currentModelChoice = _findModelChoice(
      modelConfig.provider,
      modelConfig.model,
      config: modelConfig,
      state: state,
    );
    final showModelFreeTag =
        currentModelChoice != null && _modelChoiceIsFree(currentModelChoice);
    final showModelLatestTag =
        currentModelChoice != null && _modelChoiceIsLatest(currentModelChoice);
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildSessionDrawer(context, state),
      appBar: AppBar(
        leadingWidth: 36,
        leading: IconButton(
          tooltip: l(context, '项目', 'Projects'),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          onPressed: () => widget.controller.leaveProject(),
          icon: const Icon(Icons.arrow_back_rounded, size: 21),
        ),
        titleSpacing: 2,
        title: _SessionAppBarTitle(
          title: state.session?.title.isNotEmpty == true
              ? state.session!.title
              : (state.session == null
                  ? l(context, '新建会话', 'New session')
                  : (state.workspace?.name ??
                      l(context, '移动代理', 'Mobile Agent'))),
          running: state.isBusy,
        ),
        actions: [
          _buildAppBarAction(
            tooltip: l(context, '切换主题', 'Toggle theme'),
            onPressed: () => widget.controller.toggleThemeMode(),
            icon: context.isDarkMode
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
          ),
          _buildAppBarAction(
            tooltip: l(context, '工作区文件', 'Workspace files'),
            onPressed: state.workspace == null
                ? null
                : () => _pushWorkspaceFileBrowser(
                      context,
                      workspace: state.workspace!,
                      controller: widget.controller,
                    ),
            icon: Icons.folder_open_outlined,
          ),
          _buildAppBarAction(
            tooltip: l(context, '设置', 'Settings'),
            onPressed: () => _openSettings(context, state.modelConfig),
            icon: Icons.settings_outlined,
          ),
          _buildAppBarAction(
            tooltip: l(context, '会话记录', 'Sessions'),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: Icons.chat_bubble_outline_rounded,
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: context.oc.pageBackground,
          child: Stack(
            children: [
              Column(
                children: [
                  if (state.error != null)
                    MaterialBanner(
                      content: Text(
                        state.error!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            if (state.session != null) {
                              widget.controller.refreshSession();
                            } else {
                              widget.controller.enterNewSessionLanding();
                            }
                          },
                          child: Text(l(context, '刷新', 'Refresh')),
                        )
                      ],
                    ),
                  Expanded(
                    child: state.session == null
                        ? _buildNewSessionLanding(context, state)
                        : ValueListenableBuilder<int>(
                            valueListenable: _messageVersion,
                            builder: (context, _, __) {
                              final liveState = widget.controller.state;
                              final renderedMessages =
                                  _renderedTimelineMessages(liveState);
                              final renderedTimelineEntries =
                                  _renderedTimelineEntries(
                                liveState,
                                renderedMessages,
                              );
                              final streamingAssistantMessageId =
                                  liveState.isBusy
                                      ? _renderedStreamingAssistantMessageId(
                                          liveState,
                                          renderedMessages,
                                          renderedTimelineEntries,
                                        )
                                      : null;
                              return NotificationListener<ScrollNotification>(
                                onNotification: _handleTimelineNotification,
                                child: ListView.builder(
                                  key: ValueKey<String>(
                                      'timeline-${liveState.session?.id ?? 'none'}'),
                                  controller: _timelineController,
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  physics: const BouncingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics()),
                                  padding: EdgeInsets.fromLTRB(
                                      12, isKeyboardOpen ? 8 : 12, 12, 16),
                                  itemCount: _timelineItemCount(
                                      liveState, renderedTimelineEntries),
                                  itemBuilder: (context, index) =>
                                      _buildTimelineItem(
                                    context,
                                    state: liveState,
                                    modelConfig: modelConfig,
                                    currentModelChoice: currentModelChoice,
                                    showModelFreeTag: showModelFreeTag,
                                    showModelLatestTag: showModelLatestTag,
                                    isKeyboardOpen: isKeyboardOpen,
                                    renderedMessages: renderedMessages,
                                    renderedEntries: renderedTimelineEntries,
                                    streamingAssistantMessageId:
                                        streamingAssistantMessageId,
                                    index: index,
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  _buildComposerDock(context, state, isKeyboardOpen),
                ],
              ),
              if (state.session != null)
                ValueListenableBuilder<bool>(
                  valueListenable: _showScrollToBottomButton,
                  builder: (context, showScrollToBottomButton, _) {
                    if (!showScrollToBottomButton ||
                        _isTimelineStaging(state)) {
                      return const SizedBox.shrink();
                    }
                    return Positioned(
                      right: 16,
                      bottom: isKeyboardOpen ? 104 : 132,
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: context.oc.panelBackground,
                          foregroundColor: context.oc.foreground,
                          elevation: 0,
                          side: BorderSide(color: context.oc.borderColor),
                        ),
                        onPressed: () {
                          _resumeTimelineAutoScroll();
                        },
                        icon: const Icon(Icons.arrow_downward, size: 16),
                        label: Text(l(context, '回到底部', 'Bottom')),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTimelineScroll() {
    if (!_timelineController.hasClients) return;
    if (_isRecentProgrammaticTimelineScroll()) return;
    final distance = _timelineDistanceFromBottom();
    final nextStick =
        _computeStickToBottom(distance, current: _stickToBottom.value);
    if (_timelineUserInteracting) {
      if (nextStick != _stickToBottom.value) {
        _stickToBottom.value = nextStick;
      }
      return;
    }
    if (!_stickToBottom.value && nextStick) {
      _stickToBottom.value = true;
    }
  }

  bool _handleTimelineNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _timelineUserInteracting = true;
      if (_stickToBottom.value) {
        _stickToBottom.value = false;
      }
      return false;
    }
    if (_isRecentProgrammaticTimelineScroll(notification.metrics)) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      final distance =
          notification.metrics.maxScrollExtent - notification.metrics.pixels;
      final nextStick =
          _computeStickToBottom(distance, current: _stickToBottom.value);
      if (_timelineUserInteracting ||
          (notification is ScrollUpdateNotification &&
              notification.dragDetails != null)) {
        if (nextStick != _stickToBottom.value) {
          _stickToBottom.value = nextStick;
        }
      } else if (!_stickToBottom.value && nextStick) {
        _stickToBottom.value = true;
      }
      if (notification.metrics.pixels < 180 &&
          _hasEarlierHistory(widget.controller.state)) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastBackfillAt > 300) {
          _lastBackfillAt = now;
          _revealEarlierMessages();
        }
      }
      if (notification is ScrollEndNotification) {
        _timelineUserInteracting = false;
      }
    }
    return false;
  }

  void _handleStickToBottomChanged() {
    _scheduleScrollToBottomButtonVisibility(!_stickToBottom.value);
  }

  void _scheduleScrollToBottomButtonVisibility(
    bool visible, {
    bool immediate = false,
  }) {
    _pendingScrollToBottomButtonVisible = visible;
    _scrollToBottomButtonDebounce?.cancel();
    _scrollToBottomButtonDebounce = null;
    if (immediate) {
      if (_showScrollToBottomButton.value != visible) {
        _showScrollToBottomButton.value = visible;
      }
      return;
    }
    if (_showScrollToBottomButton.value == visible) return;
    final delay = Duration(milliseconds: visible ? 120 : 160);
    _scrollToBottomButtonDebounce = Timer(delay, () {
      _scrollToBottomButtonDebounce = null;
      if (!mounted) return;
      if (_pendingScrollToBottomButtonVisible != visible) return;
      if (_showScrollToBottomButton.value != visible) {
        _showScrollToBottomButton.value = visible;
      }
    });
  }

  void _scheduleTimelineSync(AppState state) {
    final anchor = _timelineAnchor(state);
    if (anchor == _lastTimelineAnchor) return;
    _lastTimelineAnchor = anchor;
    _pendingTimelineSync = true;
    if (_isAutoScrolling) {
      return;
    }
    if (_timelineSyncScheduled) {
      return;
    }
    _timelineSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _timelineSyncScheduled = false;
      if (!mounted || !_pendingTimelineSync || !_stickToBottom.value) return;
      if (_isAutoScrolling) {
        return;
      }
      _pendingTimelineSync = false;
      _scrollTimelineToBottom(animate: false);
      if (_pendingTimelineSync) {
        _scheduleTimelineSync(widget.controller.state);
      }
    });
  }

  void _scrollTimelineToBottom({bool animate = true}) {
    if (!_timelineController.hasClients) return;
    final offset = _timelineController.position.maxScrollExtent;
    final current = _timelineController.offset;
    final delta = (offset - current).abs();
    if (delta < 2) {
      _markProgrammaticTimelineScroll(offset);
      if (_stickToBottom.value) return;
      final dist = _timelineDistanceFromBottom();
      _stickToBottom.value =
          _computeStickToBottom(dist, current: _stickToBottom.value);
      return;
    }
    if (animate) {
      _isAutoScrolling = true;
      _pendingTimelineSync = false;
      _markProgrammaticTimelineScroll(offset);
      _timelineController
          .animateTo(
        offset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      )
          .whenComplete(() {
        _isAutoScrolling = false;
        if (_timelineController.hasClients) {
          final dist = _timelineDistanceFromBottom();
          final shouldPin = _stickToBottom.value;
          if ((shouldPin && dist > 1) || _pendingTimelineSync) {
            _pendingTimelineSync = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted ||
                  !_timelineController.hasClients ||
                  !_stickToBottom.value) {
                return;
              }
              _scrollTimelineToBottom(animate: false);
            });
            return;
          }
          _stickToBottom.value =
              _computeStickToBottom(dist, current: _stickToBottom.value);
        }
      });
      return;
    }
    _markProgrammaticTimelineScroll(offset);
    _timelineController.jumpTo(offset);
    _stickToBottom.value = true;
  }

  double _timelineDistanceFromBottom([ScrollMetrics? metrics]) {
    if (metrics != null) {
      return metrics.maxScrollExtent - metrics.pixels;
    }
    if (!_timelineController.hasClients) return 0;
    return _timelineController.position.maxScrollExtent -
        _timelineController.offset;
  }

  void _markProgrammaticTimelineScroll(double targetOffset) {
    _lastProgrammaticScrollAt = DateTime.now().millisecondsSinceEpoch;
    _lastProgrammaticScrollTarget = targetOffset;
  }

  bool _isRecentProgrammaticTimelineScroll([ScrollMetrics? metrics]) {
    final target = _lastProgrammaticScrollTarget;
    if (target == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastProgrammaticScrollAt > 1500) return false;
    final pixels = metrics?.pixels ??
        (_timelineController.hasClients ? _timelineController.offset : null);
    if (pixels == null) return false;
    return (pixels - target).abs() < 2;
  }

  bool _computeStickToBottom(double distance, {required bool current}) {
    if (current) {
      return distance < 32;
    }
    return distance < 10;
  }

  void _resumeTimelineAutoScroll() {
    _timelineUserInteracting = false;
    _pendingTimelineSync = false;
    _stickToBottom.value = true;
    _scheduleScrollToBottomButtonVisibility(false, immediate: true);
    _scrollTimelineToBottom(animate: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stickToBottom.value) return;
      _scrollTimelineToBottom(animate: false);
    });
  }

  String _timelineAnchor(AppState state) {
    final lastBundle = state.messages.isEmpty ? null : state.messages.last;
    final lastPart =
        lastBundle?.parts.isEmpty == false ? lastBundle!.parts.last : null;
    return [
      state.session?.id ?? '',
      state.messages.length,
      state.todos.length,
      state.isBusy,
      lastBundle?.message.id ?? '',
      lastBundle?.message.text.length ?? 0,
      lastPart?.id ?? '',
      lastPart?.type.name ?? '',
      _partRenderHint(lastPart),
    ].join('|');
  }

  String _structuralRenderKey(AppState state) {
    final mc = state.modelConfig;
    return [
      state.session?.id ?? '',
      state.permissions.length,
      state.questions.length,
      state.todos.length,
      state.isBusy,
      state.error ?? '',
      mc?.provider ?? '',
      mc?.model ?? '',
      state.messages.length,
    ].join('|');
  }

  String _stateRenderKey(AppState state) {
    final lastBundle = state.messages.isEmpty ? null : state.messages.last;
    final lastPart =
        lastBundle?.parts.isEmpty == false ? lastBundle!.parts.last : null;
    final mc = state.modelConfig;
    return [
      state.session?.id ?? '',
      state.messages.length,
      state.permissions.length,
      state.questions.length,
      state.todos.length,
      state.isBusy,
      state.error ?? '',
      mc?.provider ?? '',
      mc?.model ?? '',
      lastBundle?.message.id ?? '',
      lastBundle?.message.text.length ?? 0,
      lastPart?.id ?? '',
      _partRenderHint(lastPart),
    ].join('|');
  }

  String _partRenderHint(MessagePart? part) {
    if (part == null) {
      return '';
    }
    switch (part.type) {
      case PartType.text:
      case PartType.reasoning:
        return '${part.type.name}:${(part.data['text'] as String?)?.length ?? 0}';
      case PartType.tool:
        final state = Map<String, dynamic>.from(
          part.data['state'] as Map? ?? const <String, dynamic>{},
        );
        return [
          part.type.name,
          state['status'] ?? '',
          (state['output'] as String?)?.length ?? 0,
          (state['displayOutput'] as String?)?.length ?? 0,
          (state['attachments'] as List?)?.length ?? 0,
        ].join(':');
      default:
        return '${part.type.name}:${part.createdAt}';
    }
  }
}
