library home_page;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdfx/pdfx.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/models.dart';
import '../sdk/local_server_client.dart';
import '../store/app_controller.dart';
import 'i18n.dart';


part 'home/home_constants.dart';
part 'home/home_catalog.dart';
part 'home/home_timeline.dart';
part 'home/home_composer.dart';
part 'home/home_shell.dart';
part 'home/home_pickers.dart';
part 'home/home_parts.dart';
part 'home/home_panels.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _schemaController = TextEditingController(
    text: const JsonEncoder.withIndent('  ')
        .convert(_structuredSchemaTemplates['answer']),
  );
  final ScrollController _timelineController = ScrollController();
  String? _selectedAgent;
  // Mutated from part-file extensions that own composer/schema interactions.
  // ignore: prefer_final_fields
  bool _structuredOutputEnabled = false;
  // ignore: prefer_final_fields
  String _selectedSchemaTemplate = 'answer';
  bool _stickToBottom = true;
  String _lastTimelineAnchor = '';
  String _historySessionId = '';
  int _historyStartIndex = 0;
  int _stagedMessageCount = 0;
  String _stagingKey = '';
  int _lastBackfillAt = 0;
  int _lastTimelineSyncAt = 0;
  String _lastStateRenderKey = '';
  /// 会话切换时必须重建时间线；不能仅依赖 [_stateRenderKey]，否则新建/切换会话后可能与旧 key 碰撞而不调用 setState，界面仍显示旧消息。
  String? _lastObservedSessionId;

  @override
  void initState() {
    super.initState();
    _timelineController.addListener(_handleTimelineScroll);
    widget.controller.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStateChanged);
    _timelineController
      ..removeListener(_handleTimelineScroll)
      ..dispose();
    _promptController.dispose();
    _schemaController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (!mounted) return;
    final state = widget.controller.state;
    final sid = state.session?.id;
    final renderKey = _stateRenderKey(state);
    final sessionChanged = sid != _lastObservedSessionId;
    if (sessionChanged) {
      _lastObservedSessionId = sid;
      _lastStateRenderKey = renderKey;
      _reconcileTimelineWindow(state);
      _scheduleTimelineSync(state);
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_timelineController.hasClients) return;
        _timelineController.jumpTo(0);
      });
      return;
    }
    if (renderKey == _lastStateRenderKey) {
      return;
    }
    _lastStateRenderKey = renderKey;
    _reconcileTimelineWindow(state);
    _scheduleTimelineSync(state);
    setState(() {});
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
    if (_stagedMessageCount < visibleCount && _stickToBottom) {
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
    await widget.controller.sendPrompt(text, agent: agent);
    if (!mounted) return;
    _showInfo(context, l(context, '已作为下一条消息发送', 'Sent as the next message.'));
  }

  Future<void> _selectProvider(_ProviderPreset preset) async {
    final current =
        widget.controller.state.modelConfig ?? ModelConfig.defaults();
    final models = _modelsForProvider(preset.id);
    final selectedModel = models.any((item) => item.id == current.model)
        ? current.model
        : (models.isNotEmpty ? models.first.id : current.model);
    await widget.controller.saveModelConfig(
      ModelConfig(
        baseUrl: preset.baseUrl,
        apiKey: current.apiKey,
        model: selectedModel,
        provider: preset.id,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  Future<void> _selectModel(_ModelChoice model) async {
    final current =
        widget.controller.state.modelConfig ?? ModelConfig.defaults();
    final provider = _providerById(model.providerId);
    await widget.controller.saveModelConfig(
      ModelConfig(
        baseUrl: provider?.baseUrl ?? current.baseUrl,
        apiKey: current.apiKey,
        model: model.id,
        provider: model.providerId,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  bool _hasPaidProvider(AppState state) {
    final config = state.modelConfig ?? ModelConfig.defaults();
    final preset = _providerById(config.provider);
    if (preset == null) return false;
    if (!preset.requiresApiKey) return false;
    return config.apiKey.trim().isNotEmpty;
  }

  List<_ModelChoice> _unpaidModelChoices() =>
      _modelCatalog.where((item) => item.unpaid).toList();

  _ModelChoice? _findModelChoice(String providerId, String modelId) {
    for (final item in _modelCatalog) {
      if (item.providerId == providerId && item.id == modelId) {
        return item;
      }
    }
    return null;
  }

  String _modelKey(String providerId, String modelId) => '$providerId/$modelId';

  bool _matchesModelQuery(_ModelChoice item, String query) {
    if (query.isEmpty) return true;
    final providerLabel = _providerLabel(item.providerId).toLowerCase();
    return item.name.toLowerCase().contains(query) ||
        item.id.toLowerCase().contains(query) ||
        item.providerId.toLowerCase().contains(query) ||
        providerLabel.contains(query);
  }

  List<_ModelChoice> _recentModelChoices(AppState state) {
    final items = <_ModelChoice>[];
    for (final key in state.recentModelKeys) {
      final split = key.indexOf('/');
      if (split <= 0 || split >= key.length - 1) continue;
      final item =
          _findModelChoice(key.substring(0, split), key.substring(split + 1));
      if (item != null) {
        items.add(item);
      }
    }
    return items;
  }

  List<_ModelChoice> _suggestedModelChoices(AppState state) {
    final config = state.modelConfig ?? ModelConfig.defaults();
    final currentProviderModels = _modelsForProvider(config.provider);
    final candidates = <_ModelChoice>[
      ...currentProviderModels
          .where((item) => item.free || item.recommended || item.latest),
      ..._unpaidModelChoices(),
      ..._modelCatalog.where((item) => item.latest || item.recommended),
    ];
    final seen = <String>{};
    final output = <_ModelChoice>[];
    for (final item in candidates) {
      final key = _modelKey(item.providerId, item.id);
      if (seen.add(key)) {
        output.add(item);
      }
    }
    return output.take(6).toList();
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

    final aProvider = _providerById(a.providerId);
    final bProvider = _providerById(b.providerId);
    if ((aProvider?.recommended ?? false) !=
        (bProvider?.recommended ?? false)) {
      return (aProvider?.recommended ?? false) ? -1 : 1;
    }
    if ((aProvider?.popular ?? false) != (bProvider?.popular ?? false)) {
      return (aProvider?.popular ?? false) ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  int _providerModelCount(String providerId) =>
      _modelsForProvider(providerId).length;

  bool _providerHasFreeModels(String providerId) =>
      _modelsForProvider(providerId).any((item) => item.free || item.unpaid);

  String _providerAvailabilityLabel(
      BuildContext context, _ProviderPreset preset) {
    if (!preset.requiresApiKey) return l(context, '免费可用', 'Free access');
    if (_providerHasFreeModels(preset.id)) {
      return l(context, '免费和付费', 'Free and paid');
    }
    return l(context, '需要 API Key', 'API key required');
  }

  String _providerNote(BuildContext context, _ProviderPreset preset) {
    switch (preset.id) {
      case 'deepseek':
        return l(context, 'DeepSeek 官方接口，已预置 deepseek-chat。',
            'Official DeepSeek API with `deepseek-chat` preconfigured.');
      case 'mag':
        return l(context, 'Mag Zen 免费模型入口，未填 key 时会尝试 public token。',
            'Mag Zen free-model entry. It will try a public token when no key is set.');
      case 'mag_go':
        return l(
            context, 'Mag Go 推荐入口。', 'Recommended Mag Go entry.');
      case 'openrouter':
        return l(context, 'Mag 风格推荐入口，支持免费模型和多家模型聚合。',
            'Mag-style recommended entry with free models and aggregated providers.');
      case 'openai':
        return l(context, '官方 OpenAI API。', 'Official OpenAI API.');
      case 'github_models':
        return l(context, 'GitHub Models，使用 GitHub token。',
            'GitHub Models using your GitHub token.');
      case 'openai_compatible':
        return l(
            context, '自定义 OpenAI 兼容接口。', 'Custom OpenAI-compatible endpoint.');
      default:
        return preset.note ?? preset.baseUrl;
    }
  }

  Future<void> _openModelChooser(BuildContext context) async {
    await _openModelPicker(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;
    final modelConfig = state.modelConfig ?? ModelConfig.defaults();
    final currentModelChoice =
        _findModelChoice(modelConfig.provider, modelConfig.model);
    final renderedMessages = _renderedTimelineMessages(state);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: _SessionAppBarTitle(
          title: state.session?.title.isNotEmpty == true
              ? state.session!.title
              : (state.workspace?.name ?? l(context, '移动代理', 'Mobile Agent')),
          subtitle:
              '${currentModelChoice?.name ?? modelConfig.model} · ${_providerLabel(modelConfig.provider)}',
          running: state.isBusy,
        ),
        actions: [
          IconButton(
            tooltip: l(context, '模型', 'Model'),
            onPressed: () => _openModelChooser(context),
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: l(context, '工作区', 'Workspace'),
            onPressed: widget.controller.pickWorkspace,
            icon: const Icon(Icons.folder_open),
          ),
          IconButton(
            tooltip: l(context, '新建会话', 'New Session'),
            onPressed: () => widget.controller.createSession(
              agent: _selectedAgent ?? state.session?.agent ?? 'build',
            ),
            icon: const Icon(Icons.add_comment),
          ),
          IconButton(
            tooltip: l(context, '更多', 'More'),
            onPressed: () => _openMoreMenu(context),
            icon: const Icon(Icons.more_horiz),
          ),
        ],
      ),
      body: SafeArea(
        child: Container(
          color: _kPageBackground,
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
                          onPressed: () => widget.controller.refreshSession(),
                          child: Text(l(context, '刷新', 'Refresh')),
                        )
                      ],
                    ),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleTimelineNotification,
                      child: ListView.builder(
                        key: ValueKey<String>(
                            'timeline-${state.session?.id ?? 'none'}'),
                        controller: _timelineController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics()),
                        padding: EdgeInsets.fromLTRB(
                            12, isKeyboardOpen ? 8 : 12, 12, 16),
                        itemCount: _timelineItemCount(state, renderedMessages),
                        itemBuilder: (context, index) => _buildTimelineItem(
                          context,
                          state: state,
                          modelConfig: modelConfig,
                          currentModelChoice: currentModelChoice,
                          isKeyboardOpen: isKeyboardOpen,
                          renderedMessages: renderedMessages,
                          index: index,
                        ),
                      ),
                    ),
                  ),
                  _buildComposerDock(context, state, isKeyboardOpen),
                ],
              ),
              if (!_stickToBottom)
                Positioned(
                  right: 16,
                  bottom: isKeyboardOpen ? 104 : 132,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      elevation: 0,
                      side: const BorderSide(color: _kBorderColor),
                    ),
                    onPressed: () {
                      _stickToBottom = true;
                      setState(() {});
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _scrollTimelineToBottom();
                      });
                    },
                    icon: const Icon(Icons.arrow_downward, size: 16),
                    label: Text(l(context, '回到底部', 'Bottom')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }


  void _handleTimelineScroll() {
    if (!_timelineController.hasClients) return;
    final distance = _timelineController.position.maxScrollExtent -
        _timelineController.offset;
    final nextStick = distance < 24;
    if (nextStick != _stickToBottom) {
      setState(() {
        _stickToBottom = nextStick;
      });
    }
  }

  bool _handleTimelineNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        _stickToBottom) {
      setState(() {
        _stickToBottom = false;
      });
      return false;
    }
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      final distance =
          notification.metrics.maxScrollExtent - notification.metrics.pixels;
      final nextStick = distance < 24;
      if (nextStick != _stickToBottom) {
        setState(() {
          _stickToBottom = nextStick;
        });
      }
      if (notification.metrics.pixels < 180 &&
          _hasEarlierHistory(widget.controller.state)) {
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastBackfillAt > 300) {
          _lastBackfillAt = now;
          _revealEarlierMessages();
        }
      }
    }
    return false;
  }

  void _scheduleTimelineSync(AppState state) {
    final anchor = _timelineAnchor(state);
    if (anchor == _lastTimelineAnchor) return;
    _lastTimelineAnchor = anchor;
    final now = DateTime.now().millisecondsSinceEpoch;
    final canAnimate = !state.isBusy;
    if (!canAnimate && now - _lastTimelineSyncAt < 48) {
      return;
    }
    _lastTimelineSyncAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_stickToBottom) return;
      _scrollTimelineToBottom(animate: canAnimate);
    });
  }

  void _scrollTimelineToBottom({bool animate = true}) {
    if (!_timelineController.hasClients) return;
    final offset = _timelineController.position.maxScrollExtent;
    if (animate) {
      _timelineController.animateTo(
        offset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
      return;
    }
    _timelineController.jumpTo(offset);
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

  String _stateRenderKey(AppState state) {
    final lastBundle = state.messages.isEmpty ? null : state.messages.last;
    final lastPart =
        lastBundle?.parts.isEmpty == false ? lastBundle!.parts.last : null;
    return [
      state.session?.id ?? '',
      state.messages.length,
      state.permissions.length,
      state.questions.length,
      state.todos.length,
      state.isBusy,
      state.error ?? '',
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

  String _formatTimestamp(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
}
