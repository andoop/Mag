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

typedef PromptReferenceAction = Future<void> Function(String);

const Color _kPageBackground = Color(0xFFF5F5F4);
const Color _kPanelBackground = Colors.white;
const Color _kMutedPanel = Color(0xFFFAFAF9);
const Color _kBorderColor = Color(0x14000000);
const Color _kSoftBorderColor = Color(0x0F000000);
const Color _kAgentBubble = Colors.white;
const Color _kUserBubble = Color(0xFFF0FDF4);

BoxDecoration _panelDecoration({
  Color background = _kPanelBackground,
  double radius = 18,
  bool elevated = true,
}) {
  return BoxDecoration(
    color: background,
    borderRadius: BorderRadius.circular(radius),
    border: const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
    boxShadow: elevated
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 1),
            ),
          ]
        : null,
  );
}

ButtonStyle _compactActionButtonStyle(BuildContext context) {
  return OutlinedButton.styleFrom(
    fixedSize: const Size.fromHeight(30),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
    side: const BorderSide(color: _kBorderColor),
    shape: const StadiumBorder(),
    foregroundColor: Colors.black87,
    backgroundColor: Colors.white.withOpacity(0.78),
  );
}

ButtonStyle _compactFilledActionButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    fixedSize: const Size.fromHeight(30),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
    shape: const StadiumBorder(),
  );
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14),
          const SizedBox(width: 5),
        ],
        Text(label),
      ],
    );
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: _compactFilledActionButtonStyle(context),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: _compactActionButtonStyle(context),
      child: child,
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(6),
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
      iconSize: 17,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.white.withOpacity(0.78),
        side: const BorderSide(color: _kBorderColor),
      ),
      icon: Icon(icon),
    );
  }
}

String _toolStatusLabel(BuildContext context, String status) {
  switch (status) {
    case 'running':
      return l(context, '运行中', 'Running');
    case 'pending':
      return l(context, '等待中', 'Pending');
    case 'completed':
      return l(context, '已完成', 'Completed');
    case 'error':
      return l(context, '错误', 'Error');
    default:
      return status;
  }
}

double _contextUsageRatio(SessionInfo? session, String model) {
  if (session == null) return 0;
  final window = inferContextWindow(model);
  if (window <= 0) return 0;
  return (session.totalTokens / window).clamp(0, 1);
}

String _contextUsageLabel(SessionInfo? session, String model) {
  if (session == null) return '--';
  final window = inferContextWindow(model);
  return '${formatTokenCount(session.totalTokens)} / ${formatTokenCount(window)}';
}

class _ProviderPreset {
  const _ProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey,
    this.note,
    this.recommended = false,
    this.popular = false,
    this.custom = false,
    this.requiresApiKey = true,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String? apiKey;
  final String? note;
  final bool recommended;
  final bool popular;
  final bool custom;
  final bool requiresApiKey;
}

class _ModelChoice {
  const _ModelChoice({
    required this.providerId,
    required this.id,
    required this.name,
    this.free = false,
    this.latest = false,
    this.recommended = false,
    this.unpaid = false,
  });

  final String providerId;
  final String id;
  final String name;
  final bool free;
  final bool latest;
  final bool recommended;
  final bool unpaid;
}

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
  bool _structuredOutputEnabled = false;
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
    final renderKey = _stateRenderKey(state);
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
        apiKey: preset.apiKey ?? current.apiKey,
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
        apiKey: provider?.apiKey ?? current.apiKey,
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
          PopupMenuButton<String>(
            tooltip: l(context, '更多', 'More'),
            onSelected: (value) {
              switch (value) {
                case 'agent':
                  _openAgentPicker(context);
                  return;
                case 'session':
                  _openSessionPicker(context);
                  return;
                case 'compact':
                  widget.controller.compactSession();
                  return;
                case 'memory':
                  widget.controller.initializeProjectMemory();
                  return;
                case 'settings':
                  _openSettings(context, state.modelConfig);
                  return;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'agent',
                child: Text(l(context, '切换 Agent', 'Switch Agent')),
              ),
              PopupMenuItem(
                value: 'session',
                child: Text(l(context, '切换会话', 'Switch Session')),
              ),
              PopupMenuItem(
                value: 'compact',
                child: Text(l(context, '压缩当前会话', 'Compact Session')),
              ),
              PopupMenuItem(
                value: 'memory',
                child: Text(l(
                    context, '初始化/更新项目记忆', 'Initialize/Update Project Memory')),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Text(l(context, '设置', 'Settings')),
              ),
            ],
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

  Widget _buildComposerDock(
      BuildContext context, AppState state, bool isKeyboardOpen) {
    final currentModel = state.modelConfig ?? ModelConfig.defaults();
    final currentModelChoice =
        _findModelChoice(currentModel.provider, currentModel.model);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: _kPageBackground,
        border: const Border(top: BorderSide(color: _kSoftBorderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
              12, isKeyboardOpen ? 4 : 8, 12, isKeyboardOpen ? 6 : 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.permissions.isNotEmpty || state.questions.isNotEmpty)
                ConstrainedBox(
                  constraints:
                      BoxConstraints(maxHeight: isKeyboardOpen ? 120 : 168),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      children: [
                        if (state.permissions.isNotEmpty)
                          _PermissionPanel(
                              controller: widget.controller, state: state),
                        if (state.questions.isNotEmpty)
                          _QuestionPanel(
                              controller: widget.controller, state: state),
                      ],
                    ),
                  ),
                ),
              SizedBox(height: isKeyboardOpen ? 4 : 6),
              Container(
                decoration: BoxDecoration(
                  color: _kPanelBackground,
                  borderRadius: BorderRadius.circular(24),
                  border: const Border.fromBorderSide(
                      BorderSide(color: _kBorderColor)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: isKeyboardOpen
                          ? const SizedBox.shrink()
                          : Padding(
                              key: const ValueKey('composer-tools'),
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _PromptTrayButton(
                                      icon: Icons.psychology_outlined,
                                      label: _selectedAgent ??
                                          state.session?.agent ??
                                          'build',
                                      onTap: () => _openAgentPicker(context),
                                    ),
                                    const SizedBox(width: 6),
                                    _PromptTrayButton(
                                      icon: Icons.auto_awesome_outlined,
                                      label: currentModelChoice?.name ??
                                          currentModel.model,
                                      onTap: () => _openModelChooser(context),
                                    ),
                                    const SizedBox(width: 6),
                                    _PromptTrayButton(
                                      icon: Icons.tune_outlined,
                                      label: l(context, '选项', 'Options'),
                                      onTap: () =>
                                          _openComposerOptionsSheet(context),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              10, isKeyboardOpen ? 2 : 3, 10, 8),
                          child: TextField(
                            controller: _promptController,
                            minLines: 1,
                            maxLines: isKeyboardOpen ? 4 : 3,
                            textInputAction: TextInputAction.newline,
                            style: const TextStyle(fontSize: 14, height: 1.32),
                            decoration: InputDecoration(
                              hintText: l(context, '问我关于这个工作区的任何事',
                                  'Ask anything about this workspace'),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.fromLTRB(
                                  38, isKeyboardOpen ? 7 : 8, 86, 11),
                              hintStyle: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: Colors.black45),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _CompactIconButton(
                            tooltip: l(context, '附件', 'Attach'),
                            onPressed: () => _showInfo(
                                context,
                                l(context, '移动端附件入口下一步接入',
                                    'Attachment support on mobile is coming next.')),
                            icon: Icons.add,
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (state.session != null) ...[
                                _ContextRingButton(
                                  ratio: _contextUsageRatio(
                                      state.session, currentModel.model),
                                  compacted: state.session?.hasSummary == true,
                                  onPressed: () => _openContextStatsSheet(
                                    context,
                                    session: state.session,
                                    model: currentModel.model,
                                    onInitializeMemory: state.isBusy
                                        ? null
                                        : widget
                                            .controller.initializeProjectMemory,
                                    onCompactSession: state.isBusy
                                        ? null
                                        : widget.controller.compactSession,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              state.isBusy
                                  ? FilledButton(
                                      style: FilledButton.styleFrom(
                                        shape: const CircleBorder(),
                                        padding: const EdgeInsets.all(0),
                                        minimumSize: const Size(36, 36),
                                        fixedSize: const Size(36, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: Colors.red.shade500,
                                        elevation: 0,
                                      ),
                                      onPressed: () =>
                                          widget.controller.cancelPrompt(),
                                      child: const Icon(Icons.stop,
                                          color: Colors.white, size: 16),
                                    )
                                  : FilledButton(
                                      style: FilledButton.styleFrom(
                                        shape: const CircleBorder(),
                                        padding: const EdgeInsets.all(0),
                                        minimumSize: const Size(36, 36),
                                        fixedSize: const Size(36, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor:
                                            const Color(0xFF111827),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                      ),
                                      onPressed: () async {
                                        final text =
                                            _promptController.text.trim();
                                        if (text.isEmpty) return;
                                        MessageFormat? format;
                                        if (_structuredOutputEnabled) {
                                          try {
                                            final decoded = jsonDecode(
                                                _schemaController.text.trim());
                                            format = MessageFormat.jsonSchema(
                                              schema: Map<String, dynamic>.from(
                                                  decoded as Map),
                                            );
                                          } catch (_) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(l(
                                                        context,
                                                        'Schema 不是合法 JSON 对象',
                                                        'Schema is not a valid JSON object'))),
                                              );
                                            }
                                            return;
                                          }
                                        }
                                        _promptController.clear();
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        await widget.controller.sendPrompt(
                                          text,
                                          agent: _selectedAgent ??
                                              state.session?.agent,
                                          format: format,
                                        );
                                      },
                                      child: const Icon(Icons.arrow_upward,
                                          size: 16),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSessionPicker(BuildContext context) async {
    final state = widget.controller.state;
    if (state.sessions.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.72,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l(context, '会话', 'Sessions'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: state.sessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = state.sessions[index];
                        final selected = item.id == state.session?.id;
                        final currentModel = state.modelConfig?.model ??
                            ModelConfig.defaults().model;
                        final ratio = _contextUsageRatio(item, currentModel);
                        final percent = (ratio * 100).round();
                        return ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          tileColor: selected
                              ? Colors.blue.shade50
                              : Colors.grey.shade50,
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.agent} · ${_contextUsageLabel(item, currentModel)} · $percent%',
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle_outline)
                              : null,
                          onTap: () async {
                            _stickToBottom = true;
                            Navigator.of(context).pop();
                            await widget.controller.switchSession(item);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAgentPicker(BuildContext context) async {
    final state = widget.controller.state;
    if (state.agents.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l(context, 'Agents', 'Agents'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...state.agents.map((agent) {
                  final selected =
                      (_selectedAgent ?? state.session?.agent ?? 'build') ==
                          agent.name;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      tileColor:
                          selected ? Colors.blue.shade50 : Colors.grey.shade50,
                      title: Text(agent.name),
                      subtitle: agent.description.isEmpty
                          ? null
                          : Text(agent.description),
                      trailing: selected
                          ? const Icon(Icons.check_circle_outline)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedAgent = agent.name;
                        });
                        Navigator.of(context).pop();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
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

  Future<void> _openSettings(BuildContext context, ModelConfig? config) async {
    final current = config ?? ModelConfig.defaults();
    final baseUrl = TextEditingController(text: current.baseUrl);
    final apiKey = TextEditingController(text: current.apiKey);
    final model = TextEditingController(text: current.model);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: baseUrl,
                  decoration: InputDecoration(
                      labelText: l(context, 'Base URL', 'Base URL'))),
              const SizedBox(height: 12),
              TextField(
                  controller: apiKey,
                  decoration: InputDecoration(
                      labelText: l(context, 'API Key', 'API Key'))),
              const SizedBox(height: 12),
              TextField(
                  controller: model,
                  decoration:
                      InputDecoration(labelText: l(context, '模型', 'Model'))),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  await widget.controller.saveModelConfig(
                    ModelConfig(
                      baseUrl: baseUrl.text.trim(),
                      apiKey: apiKey.text.trim(),
                      model: model.text.trim(),
                      provider: current.provider,
                    ),
                  );
                  if (mounted) Navigator.of(context).pop();
                },
                child: Text(l(context, '保存', 'Save')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openProviderPicker(BuildContext context) async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final state = widget.controller.state;
            final current = state.modelConfig ?? ModelConfig.defaults();
            final items = _providerPresets.where((item) {
              if (query.isEmpty) return true;
              return item.name.toLowerCase().contains(query) ||
                  item.id.toLowerCase().contains(query) ||
                  (item.note?.toLowerCase().contains(query) ?? false);
            }).toList()
              ..sort((a, b) {
                final aCurrent = a.id == current.provider;
                final bCurrent = b.id == current.provider;
                if (aCurrent != bCurrent) return aCurrent ? -1 : 1;
                if (a.recommended && !b.recommended) return -1;
                if (!a.recommended && b.recommended) return 1;
                if (a.popular && !b.popular) return -1;
                if (!a.popular && b.popular) return 1;
                return a.name.compareTo(b.name);
              });
            final popular = items.where((item) => item.popular).toList();
            final other = items.where((item) => !item.popular).toList();
            final currentProvider = _providerById(current.provider);
            return FractionallySizedBox(
              heightFactor: 0.9,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16,
                      MediaQuery.of(context).viewInsets.bottom + 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l(context, 'Providers', 'Providers'),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        l(context, '像 Mag 一样把 provider 作为模型管理入口来切换。',
                            'Manage providers as the entry point for model selection, similar to Mag.'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (value) {
                          query = value.trim().toLowerCase();
                          setModalState(() {});
                        },
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText:
                              l(context, '搜索 provider', 'Search provider'),
                          prefixIcon: const Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          children: [
                            if (currentProvider != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l(context, '当前', 'Current'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Text(
                                      currentProvider.name,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${modelCountText(context, _providerModelCount(currentProvider.id))} · ${_providerAvailabilityLabel(context, currentProvider)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            if (popular.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(l(context, '热门', 'Popular'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...popular.map((item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _ProviderListTile(
                                      item: item,
                                      selected: item.id == current.provider,
                                      modelCount: _providerModelCount(item.id),
                                      availability: _providerAvailabilityLabel(
                                          context, item),
                                      description: _providerNote(context, item),
                                      onTap: () => _selectProvider(item),
                                    ),
                                  )),
                            ],
                            if (other.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(l(context, '所有 Providers', 'All Providers'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...other.map((item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _ProviderListTile(
                                      item: item,
                                      selected: item.id == current.provider,
                                      modelCount: _providerModelCount(item.id),
                                      availability: _providerAvailabilityLabel(
                                          context, item),
                                      description: _providerNote(context, item),
                                      onTap: () => _selectProvider(item),
                                    ),
                                  )),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openModelPicker(BuildContext context) async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final state = widget.controller.state;
            final current = state.modelConfig ?? ModelConfig.defaults();
            final currentChoice =
                _findModelChoice(current.provider, current.model);
            final filteredRecent = _recentModelChoices(state)
                .where((item) => _matchesModelQuery(item, query))
                .toList();
            final recentKeys = filteredRecent
                .map((item) => _modelKey(item.providerId, item.id))
                .toSet();
            final filteredSuggested = _suggestedModelChoices(state)
                .where((item) => _matchesModelQuery(item, query))
                .where((item) =>
                    !recentKeys.contains(_modelKey(item.providerId, item.id)))
                .toList();
            final allModels = _modelCatalog
                .where((item) => _matchesModelQuery(item, query))
                .toList()
              ..sort((a, b) => _compareModelChoices(a, b, state));
            final promotedKeys = <String>{
              _modelKey(current.provider, current.model),
              if (query.isEmpty)
                ...filteredRecent
                    .map((item) => _modelKey(item.providerId, item.id)),
              if (query.isEmpty)
                ...filteredSuggested
                    .map((item) => _modelKey(item.providerId, item.id)),
            };
            final visibleModels = query.isEmpty
                ? allModels
                    .where((item) => !promotedKeys
                        .contains(_modelKey(item.providerId, item.id)))
                    .toList()
                : allModels;
            final popularProviders =
                _providerPresets.where((item) => item.popular).take(4).toList();
            return FractionallySizedBox(
              heightFactor: 0.92,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16,
                      MediaQuery.of(context).viewInsets.bottom + 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l(context, '模型', 'Models'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  l(
                                      context,
                                      '按 Mag 的单列表思路展示最近使用、推荐项和完整模型列表。',
                                      'Show recent, suggested, and the full model catalog in a single Mag-style list.'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _openProviderPicker(this.context);
                            },
                            icon: const Icon(Icons.hub_outlined),
                            label: Text(l(context, 'Provider', 'Provider')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (value) {
                          query = value.trim().toLowerCase();
                          setModalState(() {});
                        },
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: l(context, '搜索模型或 provider',
                              'Search model or provider'),
                          prefixIcon: const Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l(context, '当前', 'Current'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text(
                                    currentChoice?.name ?? current.model,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_providerLabel(current.provider)} · ${current.model}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  if (!_hasPaidProvider(state)) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      l(
                                          context,
                                          '当前还没有付费 provider，免费模型会优先排在前面。',
                                          'No paid provider is configured yet, so free models are prioritized first.'),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (query.isEmpty && filteredRecent.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(l(context, '最近使用', 'Recent'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...filteredRecent.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ModelListTile(
                                    item: item,
                                    selected:
                                        current.provider == item.providerId &&
                                            current.model == item.id,
                                    onTap: () => _selectModel(item),
                                  ),
                                ),
                              ),
                            ],
                            if (query.isEmpty &&
                                filteredSuggested.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(l(context, '推荐', 'Suggested'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...filteredSuggested.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ModelListTile(
                                    item: item,
                                    selected:
                                        current.provider == item.providerId &&
                                            current.model == item.id,
                                    onTap: () => _selectModel(item),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              query.isEmpty
                                  ? l(context, '所有模型', 'All Models')
                                  : l(context, '结果', 'Results'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            if (visibleModels.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Text(l(context, '没有找到匹配的模型',
                                    'No matching models found')),
                              )
                            else
                              ...visibleModels.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ModelListTile(
                                    item: item,
                                    selected:
                                        current.provider == item.providerId &&
                                            current.model == item.id,
                                    onTap: () => _selectModel(item),
                                  ),
                                ),
                              ),
                            if (query.isEmpty && !_hasPaidProvider(state)) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        l(context, '连接更多 Providers',
                                            'Connect More Providers'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    ...popularProviders.map(
                                      (item) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          tileColor: Colors.white,
                                          title: Row(
                                            children: [
                                              Expanded(child: Text(item.name)),
                                              if (item.recommended)
                                                _TinyTag(
                                                  label: 'Recommended',
                                                  color: Colors.green.shade100,
                                                ),
                                            ],
                                          ),
                                          subtitle:
                                              Text(item.note ?? item.baseUrl),
                                          onTap: () async {
                                            Navigator.of(context).pop();
                                            await _selectProvider(item);
                                            if (!mounted) return;
                                            if (item.requiresApiKey) {
                                              _openSettings(
                                                  this.context,
                                                  widget.controller.state
                                                      .modelConfig);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          _openProviderPicker(this.context);
                                        },
                                        icon: const Icon(
                                            Icons.grid_view_outlined),
                                        label: Text(l(context, '查看全部 providers',
                                            'View all providers')),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSchemaEditor(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l(context, '结构化输出 Schema', 'Structured Output Schema'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _structuredSchemaTemplates.keys
                    .map(
                      (key) => ChoiceChip(
                        label: Text(_schemaTemplateLabels[key] ?? key),
                        selected: _selectedSchemaTemplate == key,
                        onSelected: (_) {
                          setState(() {
                            _selectedSchemaTemplate = key;
                            _schemaController.text =
                                const JsonEncoder.withIndent('  ')
                                    .convert(_structuredSchemaTemplates[key]);
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _schemaController,
                minLines: 10,
                maxLines: 18,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: l(context, '输入 JSON Schema', 'Enter JSON Schema'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  try {
                    final decoded = jsonDecode(_schemaController.text.trim());
                    Map<String, dynamic>.from(decoded as Map);
                    Navigator.of(context).pop();
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(l(context, 'Schema 必须是合法 JSON 对象',
                              'Schema must be a valid JSON object'))),
                    );
                  }
                },
                child: Text(l(context, '完成', 'Done')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openComposerOptionsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.38,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l(context, '选项', 'Options'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ComposerOptionTile(
                    icon: Icons.hub_outlined,
                    title: l(context, '切换 Provider', 'Switch Provider'),
                    subtitle: l(context, '选择模型来源', 'Choose model provider'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openProviderPicker(context);
                    },
                  ),
                  _ComposerOptionTile(
                    icon: Icons.tune_outlined,
                    title: _structuredOutputEnabled
                        ? l(context, '关闭结构化输出', 'Disable Structured Output')
                        : l(context, '开启结构化输出', 'Enable Structured Output'),
                    subtitle: l(
                      context,
                      '控制是否按 Schema 输出',
                      'Toggle schema-based structured output',
                    ),
                    trailing: _structuredOutputEnabled
                        ? const Icon(Icons.check_circle,
                            size: 18, color: Color(0xFF2563EB))
                        : null,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() {
                        _structuredOutputEnabled = !_structuredOutputEnabled;
                      });
                    },
                  ),
                  if (_structuredOutputEnabled)
                    _ComposerOptionTile(
                      icon: Icons.data_object,
                      title: l(context, '编辑 Schema', 'Edit Schema'),
                      subtitle: l(
                        context,
                        '配置结构化输出格式',
                        'Configure structured output schema',
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _openSchemaEditor(context);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openContextStatsSheet(
    BuildContext context, {
    required SessionInfo? session,
    required String model,
    required VoidCallback? onInitializeMemory,
    required VoidCallback? onCompactSession,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.58,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l(context, '上下文', 'Context'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _contextUsageLabel(session, model),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    _CompactIconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icons.close,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ContextStatsCard(
                  session: session,
                  model: model,
                  onInitializeMemory: onInitializeMemory,
                  onCompactSession: onCompactSession,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const Map<String, String> _schemaTemplateLabels = {
  'answer': 'Answer',
  'summary': 'Summary',
  'patchPlan': 'Patch Plan',
  'taskResult': 'Task Result',
};

const Map<String, Map<String, dynamic>> _structuredSchemaTemplates = {
  'answer': {
    'type': 'object',
    'properties': {
      'answer': {'type': 'string'},
    },
    'required': ['answer'],
    'additionalProperties': false,
  },
  'summary': {
    'type': 'object',
    'properties': {
      'summary': {'type': 'string'},
      'key_points': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'risks': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['summary', 'key_points'],
    'additionalProperties': false,
  },
  'patchPlan': {
    'type': 'object',
    'properties': {
      'goal': {'type': 'string'},
      'steps': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'files': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'risks': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['goal', 'steps'],
    'additionalProperties': false,
  },
  'taskResult': {
    'type': 'object',
    'properties': {
      'status': {
        'type': 'string',
        'enum': ['done', 'blocked', 'needs_input'],
      },
      'summary': {'type': 'string'},
      'changed_files': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'next_actions': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['status', 'summary'],
    'additionalProperties': false,
  },
};

const List<_ProviderPreset> _providerPresets = [
  _ProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    apiKey: 'sk-b52ed1f5968949169101d5708d7e198c',
    note: 'Official DeepSeek API with deepseek-chat preconfigured.',
    recommended: true,
    popular: true,
  ),
  _ProviderPreset(
    id: 'mag',
    name: 'Mag',
    baseUrl: 'https://opencode.ai/zen/v1',
    note: 'Mag Zen free-model entry with optional public token fallback.',
    recommended: true,
    popular: true,
    requiresApiKey: false,
  ),
  _ProviderPreset(
    id: 'mag_go',
    name: 'Mag Go',
    baseUrl: 'https://opencode.ai/zen/v1',
    note: 'Recommended Mag Go entry.',
    recommended: true,
    popular: true,
    requiresApiKey: false,
  ),
  _ProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    note: 'Recommended Mag-style entry with free and aggregated models.',
    recommended: true,
    popular: true,
  ),
  _ProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    note: 'Official OpenAI API.',
    popular: true,
  ),
  _ProviderPreset(
    id: 'github_models',
    name: 'GitHub Models',
    baseUrl: 'https://models.github.ai/inference',
    note: 'GitHub Models using a GitHub token.',
    popular: true,
  ),
  _ProviderPreset(
    id: 'openai_compatible',
    name: 'OpenAI Compatible',
    baseUrl: 'https://api.openai.com/v1',
    note: 'Custom OpenAI-compatible endpoint.',
    custom: true,
  ),
];

const List<_ModelChoice> _modelCatalog = [
  _ModelChoice(
    providerId: 'deepseek',
    id: 'deepseek-chat',
    name: 'DeepSeek Chat',
    recommended: true,
    latest: true,
  ),
  _ModelChoice(
    providerId: 'mag',
    id: 'minimax-m2.5-free',
    name: 'MiniMax M2.5 Free',
    free: true,
    recommended: true,
    unpaid: true,
  ),
  _ModelChoice(
    providerId: 'mag',
    id: 'mimo-v2-pro-free',
    name: 'MiMo V2 Pro Free',
    free: true,
    recommended: true,
    unpaid: true,
  ),
  _ModelChoice(
    providerId: 'mag',
    id: 'mimo-v2-omni-free',
    name: 'MiMo V2 Omni Free',
    free: true,
    recommended: true,
    unpaid: true,
  ),
  _ModelChoice(
    providerId: 'mag',
    id: 'nemotron-3-super-free',
    name: 'Nemotron 3 Super Free',
    free: true,
    recommended: true,
    unpaid: true,
  ),
  _ModelChoice(
    providerId: 'mag',
    id: 'big-pickle',
    name: 'Big Pickle',
    free: true,
    recommended: true,
    unpaid: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'openrouter/free',
    name: 'OpenRouter Free Router',
    free: true,
    latest: true,
    recommended: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'qwen/qwen3-coder:free',
    name: 'Qwen 3 Coder Free',
    free: true,
    recommended: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'z-ai/glm-4.5-air:free',
    name: 'GLM 4.5 Air Free',
    free: true,
    recommended: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'openai/gpt-4.1-mini',
    name: 'GPT-4.1 Mini',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'google/gemini-2.5-flash',
    name: 'Gemini 2.5 Flash',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'anthropic/claude-sonnet-4',
    name: 'Claude Sonnet 4',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'openai',
    id: 'gpt-4.1-mini',
    name: 'GPT-4.1 Mini',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'openai',
    id: 'gpt-4.1',
    name: 'GPT-4.1',
  ),
  _ModelChoice(
    providerId: 'github_models',
    id: 'openai/gpt-4.1-mini',
    name: 'GPT-4.1 Mini',
  ),
  _ModelChoice(
    providerId: 'github_models',
    id: 'openai/gpt-4.1',
    name: 'GPT-4.1',
  ),
  _ModelChoice(
    providerId: 'openai_compatible',
    id: 'gpt-4.1-mini',
    name: 'GPT-4.1 Mini',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'openai_compatible',
    id: 'openrouter/free',
    name: 'OpenRouter Free Router',
    free: true,
  ),
];

_ProviderPreset? _providerById(String id) {
  for (final item in _providerPresets) {
    if (item.id == id) return item;
  }
  return null;
}

String _providerLabel(String id) => _providerById(id)?.name ?? id;

List<_ModelChoice> _modelsForProvider(String providerId) {
  final items =
      _modelCatalog.where((item) => item.providerId == providerId).toList();
  if (items.isNotEmpty) return items;
  return _modelCatalog
      .where((item) => item.providerId == 'openai_compatible')
      .toList();
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

class _PromptTrayButton extends StatelessWidget {
  const _PromptTrayButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const foregroundColor = Colors.black87;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: _kBorderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerOptionTile extends StatelessWidget {
  const _ComposerOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: const Border.fromBorderSide(
                BorderSide(color: _kBorderColor),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: const Border.fromBorderSide(
                      BorderSide(color: _kBorderColor),
                    ),
                  ),
                  child: Icon(icon, size: 17, color: Colors.black87),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    const Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: Colors.black38,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StreamingMarkdownText extends StatelessWidget {
  const _StreamingMarkdownText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizeStreamingMarkdown(text);
    return MarkdownBody(
      data: normalized,
      selectable: true,
      softLineBreak: true,
      shrinkWrap: true,
      builders: {
        'pre': _MarkdownCodeBlockBuilder(),
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        blockSpacing: 10,
        p: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
        a: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: Colors.blue.shade700,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w500,
        ),
        strong: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
        em: const TextStyle(
          fontStyle: FontStyle.italic,
          color: Colors.black87,
        ),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.45,
          color: Colors.red.shade900,
          backgroundColor: const Color(0xFFF8FAFC),
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: Colors.blueGrey.shade200, width: 3),
          ),
        ),
        blockquotePadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        listIndent: 22,
        listBullet: const TextStyle(fontSize: 14, height: 1.45),
        h1: const TextStyle(
          fontSize: 21,
          height: 1.28,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
        h2: const TextStyle(
          fontSize: 18,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
        h3: const TextStyle(
          fontSize: 16,
          height: 1.32,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.black.withOpacity(0.08)),
          ),
        ),
      ),
      onTapLink: (_, href, __) {
        if (href == null || href.isEmpty) return;
        _showInfo(
          context,
          l(context, '链接暂未接入外部打开: $href',
              'External link opening is not wired yet: $href'),
        );
      },
    );
  }
}

class _MarkdownCodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final codeElement = element.children != null && element.children!.isNotEmpty
        ? element.children!.first
        : null;
    final className =
        codeElement is md.Element ? codeElement.attributes['class'] ?? '' : '';
    final language = className.startsWith('language-')
        ? _normalizeMarkdownLanguage(className.substring('language-'.length))
        : '';
    final rawCode = codeElement?.textContent ?? element.textContent;
    final code = rawCode.replaceAll(RegExp(r'\n$'), '');
    return _MarkdownCodeBlock(
      code: code,
      language: language,
    );
  }
}

class _MarkdownCodeBlock extends StatelessWidget {
  const _MarkdownCodeBlock({
    required this.code,
    required this.language,
  });

  final String code;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.02),
              border: const Border(
                bottom: BorderSide(color: _kBorderColor),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    language.isEmpty ? 'text' : language,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 10.5,
                          color: Colors.black87,
                        ),
                  ),
                ),
                const Spacer(),
                _CompactIconButton(
                  tooltip: l(context, '复制代码', 'Copy code'),
                  onPressed: () => _copyText(
                    context,
                    code,
                    l(context, '代码已复制', 'Code copied'),
                  ),
                  icon: Icons.content_copy_outlined,
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: HighlightView(
              code,
              language: language,
              theme: githubTheme,
              padding: EdgeInsets.zero,
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizeMarkdownLanguage(String language) {
  switch (language.trim().toLowerCase()) {
    case 'sh':
    case 'shell':
    case 'zsh':
      return 'bash';
    case 'yml':
      return 'yaml';
    case 'py':
      return 'python';
    case 'js':
      return 'javascript';
    case 'ts':
      return 'typescript';
    case 'kt':
      return 'kotlin';
    case 'jsonc':
      return 'json';
    case 'md':
      return 'markdown';
    default:
      return language.trim().toLowerCase();
  }
}

String _normalizeStreamingMarkdown(String input) {
  var text = input;
  final trimmedRight = text.trimRight();
  if (trimmedRight.isEmpty) return text;

  final fenceCount =
      RegExp(r'(^|\n)```', multiLine: true).allMatches(text).length;
  if (fenceCount.isOdd) {
    text = '${text.trimRight()}\n```';
  }

  final inlineTickCount = RegExp(r'(?<!`)`(?!`)').allMatches(text).length;
  if (inlineTickCount.isOdd) {
    text = '${text.trimRight()}`';
  }

  text = _closeRepeatedMarkdownToken(text, '**');
  text = _closeRepeatedMarkdownToken(text, '__');
  text = _closeRepeatedMarkdownToken(text, '~~');
  text = _closeSingleLineMarkdownToken(text, '*');
  text = _closeSingleLineMarkdownToken(text, '_');
  text = _closeMarkdownLink(text);

  return text;
}

String _closeRepeatedMarkdownToken(String text, String token) {
  final count = token == '**'
      ? RegExp(r'(?<!\*)\*\*(?!\*)').allMatches(text).length
      : token == '__'
          ? RegExp(r'(?<!_)__(?!_)').allMatches(text).length
          : RegExp(r'(?<!~)~~(?!~)').allMatches(text).length;
  if (count.isOdd) {
    return '${text.trimRight()}$token';
  }
  return text;
}

String _closeSingleLineMarkdownToken(String text, String token) {
  final lines = text.split('\n');
  if (lines.isEmpty) return text;
  final lastLine = lines.last;
  if (lastLine.startsWith('```')) return text;
  final escapedToken = RegExp.escape(token);
  final count = RegExp('(?<!$escapedToken)$escapedToken(?!$escapedToken)')
      .allMatches(lastLine)
      .length;
  if (count.isOdd) {
    lines[lines.length - 1] = '${lastLine.trimRight()}$token';
    return lines.join('\n');
  }
  return text;
}

String _closeMarkdownLink(String text) {
  final lines = text.split('\n');
  if (lines.isEmpty) return text;
  final lastLine = lines.last;
  if (!lastLine.contains('[') && !lastLine.contains('](')) return text;

  final openBrackets = '['.allMatches(lastLine).length;
  final closeBrackets = ']'.allMatches(lastLine).length;
  final openParens = '('.allMatches(lastLine).length;
  final closeParens = ')'.allMatches(lastLine).length;

  var updated = lastLine;
  if (openBrackets > closeBrackets) {
    updated = '$updated]';
  }
  if (updated.contains('](') && openParens > closeParens) {
    updated = '$updated)';
  }
  lines[lines.length - 1] = updated;
  return lines.join('\n');
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

class _PartTile extends StatelessWidget {
  const _PartTile({
    required this.part,
    required this.controller,
    required this.workspace,
    required this.serverUri,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final MessagePart part;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final Uri? serverUri;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    switch (part.type) {
      case PartType.stepStart:
        return _StatusPartTile(
          label: l(context, '思考中', 'Thinking'),
          detail:
              l(context, 'Agent 正在规划下一步。', 'Agent is planning the next step.'),
          color: const Color(0xFFFFFBEB),
        );
      case PartType.reasoning:
        final text = part.data['text'] as String? ?? '';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: _panelDecoration(
              background: const Color(0xFFFFFBEB), radius: 14, elevated: false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l(context, '推理', 'Reasoning'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(text, style: const TextStyle(height: 1.45)),
            ],
          ),
        );
      case PartType.stepFinish:
        final tokenMap =
            Map<String, dynamic>.from(part.data['tokens'] as Map? ?? const {});
        final cacheMap =
            Map<String, dynamic>.from(tokenMap['cache'] as Map? ?? const {});
        final detailParts = <String>[
          (part.data['reason'] as String?) ?? 'stop',
          if (((tokenMap['input'] as num?)?.toInt() ?? 0) > 0)
            '${l(context, '输入', 'Input')} ${formatTokenCount((tokenMap['input'] as num?)?.toInt() ?? 0)}',
          if (((tokenMap['output'] as num?)?.toInt() ?? 0) > 0)
            '${l(context, '输出', 'Output')} ${formatTokenCount((tokenMap['output'] as num?)?.toInt() ?? 0)}',
          if (((cacheMap['read'] as num?)?.toInt() ?? 0) > 0)
            '${l(context, '缓存读', 'Cache read')} ${formatTokenCount((cacheMap['read'] as num?)?.toInt() ?? 0)}',
        ];
        return _StatusPartTile(
          label: l(context, '步骤完成', 'Step Complete'),
          detail: detailParts.join(' · '),
          color: const Color(0xFFF0FDF4),
        );
      case PartType.compaction:
        return _StatusPartTile(
          label: l(context, '上下文已压缩', 'Context Compacted'),
          detail: l(
            context,
            '已按 Mag 风格生成续聊摘要，后续上下文将从摘要继续。',
            'A continuation summary was generated and future context will continue from it.',
          ),
          color: const Color(0xFFFFFBEB),
        );
      case PartType.error:
        return _StatusPartTile(
          label: l(context, '错误', 'Error'),
          detail: part.data['message'] as String? ??
              l(context, '未知错误', 'Unknown error'),
          color: const Color(0xFFFEF2F2),
        );
      case PartType.text:
        final text = part.data['text'] as String? ?? '';
        final isStructured = (part.data['structured'] as bool?) ?? false;
        if (!isStructured) {
          return _StreamingMarkdownText(text: text);
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: _panelDecoration(
              background: const Color(0xFFF8FAFC), radius: 14, elevated: false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l(context, '结构化输出', 'Structured Output'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              SelectableText(
                text,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
        );
      case PartType.tool:
        final toolState =
            Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
        final attachments = (toolState['attachments'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final toolName = part.data['tool'] as String? ?? '';
        final toolTitle = toolState['title'] as String?;
        final toolStatus = toolState['status'] as String? ?? 'pending';
        final displayOutput = (toolState['displayOutput'] as String?) ??
            (toolState['output'] as String?);
        final truncatedOutput = displayOutput != null &&
                displayOutput.length > 800
            ? '${displayOutput.substring(0, 800)}\n... (${displayOutput.length} chars total)'
            : displayOutput;
        return _ToolPartTile(
          toolName: toolName,
          toolTitle: toolTitle,
          status: toolStatus,
          output: truncatedOutput,
          attachments: attachments,
          controller: controller,
          workspace: workspace,
          serverUri: serverUri,
          onInsertPromptReference: onInsertPromptReference,
          onSendPromptReference: onSendPromptReference,
        );
      default:
        return Text('${part.type.name}: ${part.data}');
    }
  }
}

class _ToolPartTile extends StatefulWidget {
  const _ToolPartTile({
    required this.toolName,
    required this.toolTitle,
    required this.status,
    required this.output,
    required this.attachments,
    required this.controller,
    required this.workspace,
    required this.serverUri,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final String toolName;
  final String? toolTitle;
  final String status;
  final String? output;
  final List<Map<String, dynamic>> attachments;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final Uri? serverUri;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  State<_ToolPartTile> createState() => _ToolPartTileState();
}

class _ToolPartTileState extends State<_ToolPartTile> {
  bool? _expanded;

  bool _defaultExpanded() {
    final isRunning = widget.status == 'running' || widget.status == 'pending';
    final isError = widget.status == 'error';
    final hasOutput = widget.output != null && widget.output!.isNotEmpty;
    final hasAttachments = widget.attachments.isNotEmpty;
    return isRunning || isError || (hasOutput && !hasAttachments);
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.status == 'running' || widget.status == 'pending';
    final isError = widget.status == 'error';
    final label = widget.toolTitle ?? widget.toolName;
    final expanded = _expanded ?? _defaultExpanded();
    final collapsedSummary = widget.output?.split('\n').first.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        color: isError
            ? const Color(0xFFFFFBFB)
            : isRunning
                ? const Color(0xFFFFFCF2)
                : const Color(0xFFFAFAF9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kSoftBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !expanded),
            child: Row(
              children: [
                if (isRunning)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                  ),
                if (isError)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(Icons.error_outline,
                        size: 14, color: Colors.red.shade700),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.toolName} · ${_toolStatusLabel(context, widget.status)}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        (!expanded &&
                                collapsedSummary != null &&
                                collapsedSummary.isNotEmpty)
                            ? collapsedSummary
                            : label,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Colors.black45, height: 1.2),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.black45,
                ),
              ],
            ),
          ),
          if (expanded &&
              widget.output != null &&
              widget.output!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.output!,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 11, height: 1.4),
              ),
            ),
          ],
          if (expanded && widget.attachments.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...widget.attachments.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _AttachmentTile(
                  attachment: item,
                  controller: widget.controller,
                  workspace: widget.workspace,
                  serverUri: widget.serverUri,
                  onInsertPromptReference: widget.onInsertPromptReference,
                  onSendPromptReference: widget.onSendPromptReference,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.controller,
    required this.workspace,
    required this.serverUri,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final Map<String, dynamic> attachment;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final Uri? serverUri;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final type = attachment['type'] as String? ?? 'file';
    final mime = attachment['mime'] as String? ?? 'application/octet-stream';
    final path = attachment['url'] as String? ?? '';
    final filename = attachment['filename'] as String? ?? path;
    if (type == 'text_preview' && workspace != null) {
      return _TextPreviewAttachmentTile(
        attachment: attachment,
        controller: controller,
        workspace: workspace!,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      );
    }
    if (type == 'glob_results') {
      return _GlobResultsAttachmentTile(
        attachment: attachment,
        controller: controller,
        workspace: workspace,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      );
    }
    if (type == 'grep_results') {
      return _GrepResultsAttachmentTile(
        attachment: attachment,
        controller: controller,
        workspace: workspace,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      );
    }
    if (type == 'webpage') {
      return _WebAttachmentTile(attachment: attachment);
    }
    if (type == 'browser_page' && workspace != null && serverUri != null) {
      return _BrowserAttachmentTile(
        attachment: attachment,
        workspace: workspace!,
        serverUri: serverUri!,
      );
    }
    if (type == 'diff_preview') {
      return _DiffPreviewAttachmentTile(
        attachment: attachment,
        controller: controller,
        workspace: workspace,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      );
    }
    if (mime.startsWith('image/') && workspace != null && path.isNotEmpty) {
      return _ImageAttachmentTile(
        filename: filename,
        mime: mime,
        controller: controller,
        treeUri: workspace!.treeUri,
        relativePath: path,
      );
    }
    if (mime == 'application/pdf' && workspace != null && path.isNotEmpty) {
      return _PdfAttachmentTile(
        filename: filename,
        controller: controller,
        treeUri: workspace!.treeUri,
        relativePath: path,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
          background: _kMutedPanel, radius: 14, elevated: false),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border:
                  const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
            ),
            child: Icon(
              mime == 'application/pdf'
                  ? Icons.picture_as_pdf
                  : Icons.attach_file,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$filename\n$mime',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _StatusPartTile extends StatelessWidget {
  const _StatusPartTile({
    required this.label,
    required this.detail,
    required this.color,
  });

  final String label;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kSoftBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            detail,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _TextPreviewAttachmentTile extends StatelessWidget {
  const _TextPreviewAttachmentTile({
    required this.attachment,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final Map<String, dynamic> attachment;
  final AppController controller;
  final WorkspaceInfo workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final path = attachment['path'] as String? ?? '';
    final filename = attachment['filename'] as String? ?? path;
    final preview = attachment['preview'] as String? ?? '';
    final startLine = attachment['startLine'];
    final endLine = attachment['endLine'];
    final lineCount = attachment['lineCount'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
          background: const Color(0xFFF8FAFC), radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            filename,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            l(context, '文本片段', 'Text preview'),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Colors.black54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CompactActionButton(
                label: l(context, '打开', 'Open'),
                onPressed: () => _openFilePreview(
                  context,
                  controller: controller,
                  workspace: workspace,
                  path: path,
                  initialLine: startLine as int?,
                  onInsertPromptReference: onInsertPromptReference,
                  onSendPromptReference: onSendPromptReference,
                ),
              ),
              if (preview.isNotEmpty)
                _CompactActionButton(
                  label: l(context, '查看片段', 'View snippet'),
                  onPressed: () => _openTextPreviewSheet(
                    context,
                    title: filename,
                    subtitle: '$path · $startLine-$endLine / $lineCount',
                    content: preview,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$path · $startLine-$endLine / $lineCount',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.black54),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _GlobResultsAttachmentTile extends StatelessWidget {
  const _GlobResultsAttachmentTile({
    required this.attachment,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final Map<String, dynamic> attachment;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final items = (attachment['items'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final count = attachment['count'];
    final pattern = attachment['pattern'] as String? ?? '*';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
          background: const Color(0xFFEEF2FF), radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Glob · $pattern',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(l(context, '匹配: $count', 'Matches: $count')),
          const SizedBox(height: 8),
          ...items.map(
            (item) => _FileResultRow(
              path: item['path'] as String? ?? '',
              controller: controller,
              workspace: workspace,
              onInsertPromptReference: onInsertPromptReference,
              onSendPromptReference: onSendPromptReference,
            ),
          ),
        ],
      ),
    );
  }
}

class _GrepResultsAttachmentTile extends StatelessWidget {
  const _GrepResultsAttachmentTile({
    required this.attachment,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final Map<String, dynamic> attachment;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final items = (attachment['items'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final pattern = attachment['pattern'] as String? ?? '';
    final count = attachment['count'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
          background: const Color(0xFFFFF7ED), radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grep · $pattern',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(l(context, '匹配: $count', 'Matches: $count')),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _GrepResultRow(
                path: item['path'] as String? ?? '',
                line: item['line'] as int? ?? 1,
                text: item['text'] as String? ?? '',
                controller: controller,
                workspace: workspace,
                onInsertPromptReference: onInsertPromptReference,
                onSendPromptReference: onSendPromptReference,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileResultRow extends StatelessWidget {
  const _FileResultRow({
    required this.path,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final String path;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final canOpen = workspace != null && path.isNotEmpty;
    return InkWell(
      onTap: canOpen
          ? () => _openFilePreview(
                context,
                controller: controller,
                workspace: workspace!,
                path: path,
                onInsertPromptReference: onInsertPromptReference,
                onSendPromptReference: onSendPromptReference,
              )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.description, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(path)),
          ],
        ),
      ),
    );
  }
}

class _GrepResultRow extends StatelessWidget {
  const _GrepResultRow({
    required this.path,
    required this.line,
    required this.text,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final String path;
  final int line;
  final String text;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final canOpen = workspace != null && path.isNotEmpty;
    return InkWell(
      onTap: canOpen
          ? () => _openFilePreview(
                context,
                controller: controller,
                workspace: workspace!,
                path: path,
                initialLine: line,
                onInsertPromptReference: onInsertPromptReference,
                onSendPromptReference: onSendPromptReference,
              )
          : null,
      child: Text(
        '$path:$line: $text',
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }
}

class _DiffPreviewAttachmentTile extends StatelessWidget {
  const _DiffPreviewAttachmentTile({
    required this.attachment,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final Map<String, dynamic> attachment;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final path = attachment['path'] as String? ?? '';
    final kind = attachment['kind'] as String? ?? 'update';
    final preview = attachment['preview'] as String? ?? '';
    final canOpen = workspace != null && path.isNotEmpty && kind != 'delete';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
          background: const Color(0xFFF5F3FF), radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$kind · $path',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (canOpen)
                OutlinedButton(
                  onPressed: () => _openFilePreview(
                    context,
                    controller: controller,
                    workspace: workspace!,
                    path: path,
                    onInsertPromptReference: onInsertPromptReference,
                    onSendPromptReference: onSendPromptReference,
                  ),
                  child: Text(l(context, '打开', 'Open')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CompactActionButton(
                label: l(context, '插入', 'Insert'),
                icon: Icons.playlist_add_outlined,
                onPressed: () => onInsertPromptReference(
                  _asPromptReference(
                    path: path,
                    language: null,
                    startLine: 1,
                    endLine: preview.split('\n').length,
                    content: preview,
                  ),
                ),
              ),
              _CompactActionButton(
                label: l(context, '发送', 'Send'),
                icon: Icons.send_outlined,
                filled: true,
                onPressed: () async {
                  await onSendPromptReference(
                    _asPromptReference(
                      path: path,
                      language: null,
                      startLine: 1,
                      endLine: preview.split('\n').length,
                      content: preview,
                    ),
                  );
                },
              ),
              _CompactActionButton(
                label: l(context, '查看 diff', 'View diff'),
                icon: Icons.difference_outlined,
                onPressed: () => _openDiffPreviewSheet(
                  context,
                  title: '$kind · $path',
                  subtitle: path,
                  diff: attachment['fullPreview'] as String? ?? preview,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiffPreviewBody extends StatelessWidget {
  const _DiffPreviewBody({required this.preview});

  final String preview;

  @override
  Widget build(BuildContext context) {
    final lines = const LineSplitter().convert(preview);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 80,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines.map(_buildLine).toList(),
        ),
      ),
    );
  }

  Widget _buildLine(String line) {
    Color? background;
    Color? foreground;
    if (line.startsWith('+')) {
      background = const Color(0xFFDCFCE7);
      foreground = Colors.green.shade900;
    } else if (line.startsWith('-')) {
      background = const Color(0xFFFEE2E2);
      foreground = Colors.red.shade900;
    } else if (line.startsWith('@@')) {
      background = const Color(0xFFEDE9FE);
      foreground = Colors.deepPurple.shade900;
    }
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text(
        line.isEmpty ? ' ' : line,
        softWrap: false,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.35,
          color: foreground,
        ),
      ),
    );
  }
}

Future<void> _openDiffPreviewSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String diff,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CompactIconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icons.close,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: _panelDecoration(
                      background: Colors.black.withOpacity(0.035),
                      radius: 14,
                      elevated: false),
                  child: SingleChildScrollView(
                    child: _DiffPreviewBody(preview: diff),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _openTextPreviewSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String content,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CompactIconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icons.close,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: _panelDecoration(
                      background: Colors.black.withOpacity(0.035),
                      radius: 14,
                      elevated: false),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      content,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12, height: 1.4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _WebAttachmentTile extends StatelessWidget {
  const _WebAttachmentTile({required this.attachment});

  final Map<String, dynamic> attachment;

  @override
  Widget build(BuildContext context) {
    final title = attachment['title'] as String? ?? 'Web page';
    final url = attachment['url'] as String? ?? '';
    final excerpt = attachment['excerpt'] as String? ?? '';
    final statusCode = attachment['statusCode'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
          background: const Color(0xFFF0FDF4), radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: const Border.fromBorderSide(
                      BorderSide(color: _kBorderColor)),
                ),
                child: const Icon(Icons.language, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
            ],
          ),
          const SizedBox(height: 4),
          Text(url,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(l(context, '状态: $statusCode', 'Status: $statusCode')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (url.isNotEmpty)
                _CompactActionButton(
                  label: l(context, '预览', 'Preview'),
                  onPressed: () => _openWebPreviewSheet(
                    context,
                    title: title,
                    subtitle: url,
                    url: url,
                  ),
                ),
              if (excerpt.isNotEmpty)
                _CompactActionButton(
                  label: l(context, '查看摘要', 'View summary'),
                  onPressed: () => _openTextPreviewSheet(
                    context,
                    title: title,
                    subtitle: url,
                    content: excerpt,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrowserAttachmentTile extends StatelessWidget {
  const _BrowserAttachmentTile({
    required this.attachment,
    required this.workspace,
    required this.serverUri,
  });

  final Map<String, dynamic> attachment;
  final WorkspaceInfo workspace;
  final Uri serverUri;

  @override
  Widget build(BuildContext context) {
    final path = attachment['path'] as String? ?? '';
    final title = attachment['title'] as String? ?? path;
    final previewUrl = _workspacePreviewUrl(
      serverUri: serverUri,
      workspace: workspace,
      path: path,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
          background: const Color(0xFFEFF6FF), radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: const Border.fromBorderSide(
                      BorderSide(color: _kBorderColor)),
                ),
                child: const Icon(Icons.web, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
            ],
          ),
          const SizedBox(height: 4),
          Text(path,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CompactActionButton(
                label: l(context, '打开网页', 'Open page'),
                onPressed: () => _openWebPreviewSheet(
                  context,
                  title: title,
                  subtitle: path,
                  url: previewUrl.toString(),
                ),
              ),
              _CompactActionButton(
                label: l(context, '复制链接', 'Copy link'),
                onPressed: () => _copyText(
                  context,
                  previewUrl.toString(),
                  l(context, '预览链接已复制', 'Preview link copied'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Uri _workspacePreviewUrl({
  required Uri serverUri,
  required WorkspaceInfo workspace,
  required String path,
}) {
  final baseSegments =
      serverUri.pathSegments.where((item) => item.isNotEmpty).toList();
  final pathSegments =
      path.split('/').where((item) => item.isNotEmpty).toList();
  return serverUri.replace(
    pathSegments: [
      ...baseSegments,
      'workspace-file',
      workspace.id,
      ...pathSegments,
    ],
    queryParameters: null,
  );
}

Future<void> _openWebPreviewSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String url,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: _WebPreviewSheet(
        title: title,
        subtitle: subtitle,
        url: url,
      ),
    ),
  );
}

class _WebPreviewSheet extends StatefulWidget {
  const _WebPreviewSheet({
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final String title;
  final String subtitle;
  final String url;

  @override
  State<_WebPreviewSheet> createState() => _WebPreviewSheetState();
}

class _WebPreviewSheetState extends State<_WebPreviewSheet> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: _panelDecoration(
                  background: _kPanelBackground, radius: 16, elevated: false),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CompactIconButton(
                    tooltip: l(context, '复制链接', 'Copy URL'),
                    onPressed: () => _copyText(
                      context,
                      widget.url,
                      l(context, '链接已复制', 'URL copied'),
                    ),
                    icon: Icons.copy_all_outlined,
                  ),
                  const SizedBox(width: 6),
                  _CompactIconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icons.close,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: _panelDecoration(
                      background: Colors.white, radius: 16, elevated: false),
                  child: WebViewWidget(controller: _controller),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfAttachmentTile extends StatelessWidget {
  const _PdfAttachmentTile({
    required this.filename,
    required this.controller,
    required this.treeUri,
    required this.relativePath,
  });

  final String filename;
  final AppController controller;
  final String treeUri;
  final String relativePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
          background: const Color(0xFFFEF2F2), radius: 14, elevated: false),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border:
                  const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
            ),
            child: const Icon(Icons.picture_as_pdf, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filename,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _CompactActionButton(
            label: l(context, '预览', 'Preview'),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => FractionallySizedBox(
                  heightFactor: 0.92,
                  child: _PdfPreviewSheet(
                    filename: filename,
                    controller: controller,
                    treeUri: treeUri,
                    relativePath: relativePath,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ImageAttachmentTile extends StatelessWidget {
  const _ImageAttachmentTile({
    required this.filename,
    required this.mime,
    required this.controller,
    required this.treeUri,
    required this.relativePath,
  });

  final String filename;
  final String mime;
  final AppController controller;
  final String treeUri;
  final String relativePath;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: controller.loadWorkspaceBytes(
        treeUri: treeUri,
        relativePath: relativePath,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Text(l(context, '附件加载失败: $filename',
              'Attachment failed to load: $filename'));
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: _panelDecoration(
              background: _kMutedPanel, radius: 14, elevated: false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                filename,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Text(
                      l(context, '不支持的图片: $mime', 'Unsupported image: $mime')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PdfPreviewSheet extends StatefulWidget {
  const _PdfPreviewSheet({
    required this.filename,
    required this.controller,
    required this.treeUri,
    required this.relativePath,
  });

  final String filename;
  final AppController controller;
  final String treeUri;
  final String relativePath;

  @override
  State<_PdfPreviewSheet> createState() => _PdfPreviewSheetState();
}

class _PdfPreviewSheetState extends State<_PdfPreviewSheet> {
  late final Future<PdfControllerPinch> _controllerFuture = _loadController();
  PdfControllerPinch? _controller;
  int _page = 1;
  int _pages = 0;

  Future<PdfControllerPinch> _loadController() async {
    final bytes = await widget.controller.loadWorkspaceBytes(
      treeUri: widget.treeUri,
      relativePath: widget.relativePath,
    );
    final controller = PdfControllerPinch(
      document: PdfDocument.openData(bytes),
    );
    _controller = controller;
    return controller;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: _panelDecoration(
                  background: _kPanelBackground, radius: 16, elevated: false),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.filename,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l(context, 'PDF 预览', 'PDF preview'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  if (_pages > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text('$_page / $_pages'),
                    ),
                  _CompactIconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icons.close,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<PdfControllerPinch>(
                future: _controllerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                        child: Text(l(context, 'PDF 预览加载失败',
                            'Failed to load PDF preview')));
                  }
                  return PdfViewPinch(
                    controller: snapshot.data!,
                    onDocumentLoaded: (document) {
                      if (!mounted) return;
                      setState(() {
                        _pages = document.pagesCount;
                      });
                    },
                    onPageChanged: (page) {
                      if (!mounted) return;
                      setState(() {
                        _page = page;
                      });
                    },
                    onDocumentError: (_) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(l(
                                context, 'PDF 渲染失败', 'Failed to render PDF'))),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openFilePreview(
  BuildContext context, {
  required AppController controller,
  required WorkspaceInfo workspace,
  required String path,
  int? initialLine,
  ValueChanged<String>? onInsertPromptReference,
  PromptReferenceAction? onSendPromptReference,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _FilePreviewSheet(
        controller: controller,
        workspace: workspace,
        path: path,
        initialLine: initialLine,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      ),
    ),
  );
}

class _FilePreviewSheet extends StatefulWidget {
  const _FilePreviewSheet({
    required this.controller,
    required this.workspace,
    required this.path,
    this.initialLine,
    this.onInsertPromptReference,
    this.onSendPromptReference,
  });

  final AppController controller;
  final WorkspaceInfo workspace;
  final String path;
  final int? initialLine;
  final ValueChanged<String>? onInsertPromptReference;
  final PromptReferenceAction? onSendPromptReference;

  @override
  State<_FilePreviewSheet> createState() => _FilePreviewSheetState();
}

class _FilePreviewSheetState extends State<_FilePreviewSheet> {
  static const int _pageSize = 160;
  static const double _previewFontSize = 12;
  static const double _previewLineHeight = 1.35;
  late final Future<_LoadedFilePreview> _future = _load();
  int? _currentStart;

  Future<_LoadedFilePreview> _load() async {
    final content = await widget.controller.loadWorkspaceText(
      treeUri: widget.workspace.treeUri,
      relativePath: widget.path,
    );
    final lines = const LineSplitter().convert(content);
    final focus = widget.initialLine ?? 1;
    final start = _normalizePageStart(focus > 40 ? focus - 40 : 1);
    return _LoadedFilePreview(
      totalLines: lines.length,
      focusLine: focus,
      initialStartLine: start,
      lines: lines,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              decoration: _panelDecoration(
                  background: _kPanelBackground, radius: 16, elevated: false),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.path,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l(context, '文件预览', 'File preview'),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  _CompactIconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icons.close,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<_LoadedFilePreview>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                        child: Text(l(context, '文件预览加载失败',
                            'Failed to load file preview')));
                  }
                  final loaded = snapshot.data!;
                  final currentStart = _currentStart ?? loaded.initialStartLine;
                  final currentEnd = _pageEnd(currentStart, loaded.totalLines);
                  final visibleLines =
                      loaded.lines.sublist(currentStart - 1, currentEnd);
                  final visibleCode = visibleLines.join('\n');
                  final numberedVisibleCode =
                      _numberLines(visibleLines, startLine: currentStart);
                  final language = _languageForPath(widget.path);
                  final focusIndex = loaded.focusLine == null
                      ? null
                      : (loaded.focusLine! >= currentStart &&
                              loaded.focusLine! <= currentEnd)
                          ? loaded.focusLine! - currentStart
                          : null;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l(
                                  context,
                                  '显示 $currentStart-$currentEnd / ${loaded.totalLines}',
                                  'Showing $currentStart-$currentEnd / ${loaded.totalLines}'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.black54),
                            ),
                          ),
                          if (loaded.focusLine != null)
                            Text(
                              l(context, '焦点: ${loaded.focusLine}',
                                  'Focus: ${loaded.focusLine}'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.black54),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _CompactActionButton(
                              label: l(context, '上一页', 'Prev'),
                              onPressed: currentStart > 1
                                  ? () {
                                      setState(() {
                                        _currentStart = _normalizePageStart(
                                            currentStart - _pageSize);
                                      });
                                    }
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            _CompactActionButton(
                              label: l(context, '下一页', 'Next'),
                              onPressed: currentEnd < loaded.totalLines
                                  ? () {
                                      setState(() {
                                        _currentStart = _normalizePageStart(
                                            currentStart + _pageSize);
                                      });
                                    }
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            if (loaded.focusLine != null)
                              _CompactActionButton(
                                label: l(context, '跳到焦点', 'Go to Focus'),
                                onPressed: () {
                                  setState(() {
                                    _currentStart = _normalizePageStart(
                                      (loaded.focusLine! > 40)
                                          ? loaded.focusLine! - 40
                                          : 1,
                                    );
                                  });
                                },
                              ),
                            const SizedBox(width: 8),
                            _CompactIconButton(
                              tooltip: l(context, '复制路径', 'Copy path'),
                              onPressed: () => _copyText(context, widget.path,
                                  l(context, '路径已复制', 'Path copied')),
                              icon: Icons.copy_all_outlined,
                            ),
                            _CompactIconButton(
                              tooltip: l(context, '复制片段', 'Copy snippet'),
                              onPressed: () => _copyText(
                                context,
                                numberedVisibleCode,
                                l(context, '片段已复制', 'Snippet copied'),
                              ),
                              icon: Icons.content_copy_outlined,
                            ),
                            _CompactIconButton(
                              tooltip:
                                  l(context, '复制为 prompt 引用', 'Copy as prompt'),
                              onPressed: () => _copyText(
                                context,
                                _asPromptReference(
                                  path: widget.path,
                                  language: language,
                                  startLine: currentStart,
                                  endLine: currentEnd,
                                  content: visibleCode,
                                ),
                                l(context, 'Prompt 引用已复制',
                                    'Prompt reference copied'),
                              ),
                              icon: Icons.format_quote_outlined,
                            ),
                            if (widget.onInsertPromptReference != null)
                              _CompactIconButton(
                                tooltip:
                                    l(context, '插入到输入框', 'Insert into prompt'),
                                onPressed: () {
                                  widget.onInsertPromptReference!(
                                    _asPromptReference(
                                      path: widget.path,
                                      language: language,
                                      startLine: currentStart,
                                      endLine: currentEnd,
                                      content: visibleCode,
                                    ),
                                  );
                                  _showInfo(
                                      context,
                                      l(context, '已插入到输入框',
                                          'Inserted into the composer.'));
                                },
                                icon: Icons.playlist_add_outlined,
                              ),
                            if (widget.onSendPromptReference != null)
                              _CompactIconButton(
                                tooltip: l(context, '作为下一条消息发送',
                                    'Send as next message'),
                                onPressed: () async {
                                  await widget.onSendPromptReference!(
                                    _asPromptReference(
                                      path: widget.path,
                                      language: language,
                                      startLine: currentStart,
                                      endLine: currentEnd,
                                      content: visibleCode,
                                    ),
                                  );
                                },
                                icon: Icons.send_outlined,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Container(
                              constraints: BoxConstraints(
                                minWidth:
                                    MediaQuery.of(context).size.width - 24,
                              ),
                              padding: const EdgeInsets.all(12),
                              decoration: _panelDecoration(
                                background: Colors.black.withOpacity(0.035),
                                radius: 14,
                                elevated: false,
                              ),
                              child: Stack(
                                children: [
                                  if (focusIndex != null)
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      top: focusIndex *
                                          (_previewFontSize *
                                              _previewLineHeight),
                                      child: Container(
                                        height: _previewFontSize *
                                            _previewLineHeight,
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.18),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                      ),
                                    ),
                                  if (language == null)
                                    SelectableText(
                                      numberedVisibleCode,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: _previewFontSize,
                                        height: _previewLineHeight,
                                      ),
                                    )
                                  else
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SizedBox(
                                          width: 52,
                                          child: Text(
                                            _lineNumberColumn(
                                              startLine: currentStart,
                                              count: visibleLines.length,
                                              focusLine: loaded.focusLine,
                                            ),
                                            textAlign: TextAlign.right,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: _previewFontSize,
                                              height: _previewLineHeight,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        HighlightView(
                                          visibleCode,
                                          language: language,
                                          theme: githubTheme,
                                          padding: EdgeInsets.zero,
                                          textStyle: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: _previewFontSize,
                                            height: _previewLineHeight,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadedFilePreview {
  const _LoadedFilePreview({
    required this.totalLines,
    required this.focusLine,
    required this.initialStartLine,
    required this.lines,
  });

  final int totalLines;
  final int? focusLine;
  final int initialStartLine;
  final List<String> lines;
}

int _normalizePageStart(int candidate) {
  if (candidate < 1) return 1;
  return candidate;
}

int _pageEnd(int start, int totalLines) {
  final end = start + _FilePreviewSheetState._pageSize - 1;
  return end > totalLines ? totalLines : end;
}

String _numberLines(List<String> lines, {required int startLine}) {
  final buffer = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    buffer.writeln('${(startLine + i).toString().padLeft(4)}|${lines[i]}');
  }
  return buffer.toString().trimRight();
}

String _lineNumberColumn({
  required int startLine,
  required int count,
  int? focusLine,
}) {
  final buffer = StringBuffer();
  for (var i = 0; i < count; i++) {
    final line = startLine + i;
    final prefix = line == focusLine ? '>' : ' ';
    buffer.writeln('$prefix$line');
  }
  return buffer.toString().trimRight();
}

String? _languageForPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.dart')) return 'dart';
  if (lower.endsWith('.kt') || lower.endsWith('.kts')) return 'kotlin';
  if (lower.endsWith('.java')) return 'java';
  if (lower.endsWith('.js')) return 'javascript';
  if (lower.endsWith('.ts')) return 'typescript';
  if (lower.endsWith('.tsx')) return 'tsx';
  if (lower.endsWith('.json')) return 'json';
  if (lower.endsWith('.yaml') || lower.endsWith('.yml')) return 'yaml';
  if (lower.endsWith('.md')) return 'markdown';
  if (lower.endsWith('.xml')) return 'xml';
  if (lower.endsWith('.html')) return 'xml';
  if (lower.endsWith('.css')) return 'css';
  if (lower.endsWith('.sh')) return 'bash';
  if (lower.endsWith('.py')) return 'python';
  if (lower.endsWith('.go')) return 'go';
  if (lower.endsWith('.rs')) return 'rust';
  if (lower.endsWith('.sql')) return 'sql';
  return null;
}

Future<void> _copyText(
    BuildContext context, String text, String message) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: text));
  _showInfoWithMessenger(messenger, message);
}

String _asPromptReference({
  required String path,
  required String? language,
  required int startLine,
  required int endLine,
  required String content,
}) {
  final info = '$path:$startLine-$endLine';
  final fence = language ?? '';
  return '$info\n```$fence\n$content\n```';
}

void _showInfo(BuildContext context, String message) {
  _showInfoWithMessenger(ScaffoldMessenger.maybeOf(context), message);
}

void _showInfoWithMessenger(ScaffoldMessengerState? messenger, String message) {
  messenger?.showSnackBar(
    SnackBar(content: Text(message)),
  );
}

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({required this.controller, required this.state});

  final AppController controller;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final request = state.permissions.first;
    final metadata = request.metadata;
    final preview = metadata['preview'] is Map
        ? Map<String, dynamic>.from(metadata['preview'] as Map)
        : null;
    final tool = metadata['tool'] as String?;
    final filePath =
        metadata['path'] as String? ?? metadata['filePath'] as String?;
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                l(context, '权限: ${request.permission}',
                    'Permission: ${request.permission}'),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(request.patterns.join(', '),
                style: Theme.of(context).textTheme.bodySmall),
            if (tool != null || filePath != null) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (tool != null) l(context, '工具: $tool', 'Tool: $tool'),
                  if (filePath != null)
                    l(context, '目标: $filePath', 'Target: $filePath'),
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (preview != null) ...[
              const SizedBox(height: 12),
              _PermissionPreviewCard(
                preview: preview,
                controller: controller,
                workspace: state.workspace,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CompactActionButton(
                  label: l(context, '允许一次', 'Allow once'),
                  onPressed: () => controller.replyPermission(
                      request.id, PermissionReply.once),
                ),
                _CompactActionButton(
                  label: l(context, '始终允许', 'Always allow'),
                  filled: true,
                  onPressed: () => controller.replyPermission(
                      request.id, PermissionReply.always),
                ),
                TextButton(
                  onPressed: () => controller.replyPermission(
                      request.id, PermissionReply.reject),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                  ),
                  child: Text(l(context, '拒绝', 'Reject')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionPreviewCard extends StatelessWidget {
  const _PermissionPreviewCard({
    required this.preview,
    required this.controller,
    required this.workspace,
  });

  final Map<String, dynamic> preview;
  final AppController controller;
  final WorkspaceInfo? workspace;

  @override
  Widget build(BuildContext context) {
    final kind = preview['kind'] as String? ?? 'update';
    final path = preview['path'] as String? ?? '';
    final sourcePath = preview['sourcePath'] as String?;
    final diff = preview['preview'] as String? ?? '';
    final fullDiff = preview['fullPreview'] as String? ?? diff;
    final canOpen = workspace != null && path.isNotEmpty && kind != 'delete';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
          background: const Color(0xFFF5F3FF), radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l(context, '待确认变更 · $kind', 'Pending Change · $kind'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(path, style: Theme.of(context).textTheme.bodySmall),
          if (sourcePath != null && sourcePath.isNotEmpty)
            Text(l(context, '来源: $sourcePath', 'From: $sourcePath'),
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (canOpen)
                _CompactActionButton(
                  label: l(context, '打开目标文件', 'Open target file'),
                  onPressed: () => _openFilePreview(
                    context,
                    controller: controller,
                    workspace: workspace!,
                    path: path,
                  ),
                ),
              _CompactActionButton(
                label: l(context, '更多上下文', 'More context'),
                onPressed: () => _openDiffPreviewSheet(
                  context,
                  title: l(context, '待确认变更', 'Pending Change'),
                  subtitle: path,
                  diff: fullDiff,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionPanel extends StatefulWidget {
  const _QuestionPanel({required this.controller, required this.state});

  final AppController controller;
  final AppState state;

  @override
  State<_QuestionPanel> createState() => _QuestionPanelState();
}

class _QuestionPanelState extends State<_QuestionPanel> {
  final Map<int, Set<String>> _selected = {};
  final Map<int, TextEditingController> _customControllers = {};

  @override
  void dispose() {
    for (final controller in _customControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.state.questions.first;
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l(context, '问题', 'Question'),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            for (var i = 0; i < request.questions.length; i++) ...[
              _QuestionForm(
                info: request.questions[i],
                selected: _selected.putIfAbsent(i, () => <String>{}),
                customController: _customControllers.putIfAbsent(
                    i, () => TextEditingController()),
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                OutlinedButton(
                  onPressed: () =>
                      widget.controller.replyQuestion(request.id, const []),
                  child: Text(l(context, '忽略', 'Dismiss')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final answers = <List<String>>[];
                    for (var i = 0; i < request.questions.length; i++) {
                      final info = request.questions[i];
                      final selected = _selected[i] ?? <String>{};
                      final current = selected.toList();
                      final custom = _customControllers[i]?.text.trim() ?? '';
                      if (info.custom && custom.isNotEmpty) {
                        current.add(custom);
                      }
                      answers.add(current);
                    }
                    await widget.controller.replyQuestion(request.id, answers);
                  },
                  child: Text(l(context, '提交', 'Submit')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionForm extends StatelessWidget {
  const _QuestionForm({
    required this.info,
    required this.selected,
    required this.customController,
    required this.onChanged,
  });

  final QuestionInfo info;
  final Set<String> selected;
  final TextEditingController customController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(info.header, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(info.question),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: info.options.map((option) {
            final isSelected = selected.contains(option.label);
            return FilterChip(
              label: Text(option.label),
              selected: isSelected,
              onSelected: (value) {
                if (!info.multiple) {
                  selected
                    ..clear()
                    ..add(option.label);
                } else if (value) {
                  selected.add(option.label);
                } else {
                  selected.remove(option.label);
                }
                onChanged();
              },
            );
          }).toList(),
        ),
        if (info.custom) ...[
          const SizedBox(height: 8),
          TextField(
            controller: customController,
            decoration: InputDecoration(
              labelText: l(context, '自定义答案', 'Custom answer'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ],
    );
  }
}

class _TodoPanel extends StatelessWidget {
  const _TodoPanel({required this.todos});

  final List<TodoItem> todos;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l(context, '待办', 'Todos'),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            for (final todo in todos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: todo.status == 'completed'
                            ? const Color(0xFF10B981)
                            : todo.status == 'in_progress'
                                ? const Color(0xFFF59E0B)
                                : todo.status == 'cancelled'
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${todoStatusText(context, todo.status)} - ${todo.content}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
