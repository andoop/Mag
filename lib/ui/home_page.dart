library home_page;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/rendering.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:pdfx/pdfx.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/models.dart';
import '../core/debug_trace.dart';
import '../core/device_capability_registry.dart';
import '../core/skill_registry.dart';
import '../core/workspace_bridge.dart';
import '../platform/device_capability_bridge.dart';
import '../platform/floating_window_bridge.dart';
import '../platform/shortcut_bridge.dart';
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
part 'home/pickers/settings_widgets.dart';
part 'home/pickers/settings_mcp.dart';
part 'home/pickers/settings_git.dart';
part 'home/pickers/settings_variables.dart';
part 'home/pickers/settings_sheet.dart';
part 'home/pickers/skills_sheet.dart';
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

class _MeasuredSize extends SingleChildRenderObjectWidget {
  const _MeasuredSize({
    super.child,
    required this.onChanged,
  });

  final ValueChanged<Size> onChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasuredSize(onChanged);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMeasuredSize renderObject,
  ) {
    renderObject.onChanged = onChanged;
  }
}

class _RenderMeasuredSize extends RenderProxyBox {
  _RenderMeasuredSize(this.onChanged);

  ValueChanged<Size> onChanged;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = size;
    if (_lastSize == newSize) return;
    _lastSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onChanged(newSize);
    });
  }
}

class _TimelineDetachNotification extends Notification {
  const _TimelineDetachNotification();
}

class _VisibleTimelineAnchor {
  const _VisibleTimelineAnchor({
    required this.stableId,
    required this.top,
    required this.bottom,
  });

  final String stableId;
  final double top;
  final double bottom;
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
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
  final ValueNotifier<double> _composerDockHeight = ValueNotifier<double>(0);
  bool _messageVersionScheduled = false;
  bool _isAutoScrolling = false;
  bool _pendingTimelineSync = false;
  bool _timelineSyncScheduled = false;
  int _timelineSyncGeneration = 0;
  double? _timelineSyncLastMaxExtent;
  int _timelineSyncStableFrames = 0;
  int _timelineSyncAttemptCount = 0;
  // Mutated from the composer part while voice input is active.
  // ignore: prefer_final_fields
  String _voiceInputPrefix = '';
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
  bool _pendingRevealEarlierMessages = false;
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
  Timer? _streamingTimelineSyncDebounce;
  int _lastStreamingTimelineSyncAt = 0;
  int _timelineViewportLockGeneration = 0;
  int _timelineViewportLockUntilMs = 0;
  double? _timelineViewportLockPixels;
  final GlobalKey _timelineViewportKey = GlobalKey();
  final Map<String, GlobalKey> _timelineEntryKeys = <String, GlobalKey>{};
  int _historyRevealGeneration = 0;
  String? _historyRevealAnchorStableId;
  double? _historyRevealAnchorTop;
  double? _historyRevealAnchorBottom;
  bool _historyRevealRestorePending = false;
  int _historyRevealRestoreAttempt = 0;
  // ignore: prefer_final_fields
  int _promptMentionRequestId = 0;
  // ignore: prefer_final_fields
  List<_ComposerAttachment> _promptAttachments = const [];
  bool _pendingScrollToBottomButtonVisible = false;

  /// 会话切换时必须重建时间线；不能仅依赖 [_stateRenderKey]，否则新建/切换会话后可能与旧 key 碰撞而不调用 setState，界面仍显示旧消息。
  String? _lastObservedSessionId;
  String _lastObservedModelKey = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timelineController.addListener(_handleTimelineScroll);
    _promptController.addListener(_handlePromptComposerChanged);
    _promptFocusNode.addListener(_handlePromptComposerChanged);
    _stickToBottom.addListener(_handleStickToBottomChanged);
    widget.controller.addListener(_onStateChanged);
    _scheduleScrollToBottomButtonVisibility(false, immediate: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!FloatingWindowBridge.isSupported) return;
    if (state == AppLifecycleState.paused) {
      final session = widget.controller.state.session;
      if (session != null) {
        FloatingWindowBridge.showBackgroundNotification(
          title: l(context, 'Mag 正在后台运行', 'Mag is running in the background'),
          body: l(context, '点击通知返回查看会话', 'Tap to return to your session'),
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      FloatingWindowBridge.hideBackgroundNotification();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onStateChanged);
    _stickToBottom.removeListener(_handleStickToBottomChanged);
    _timelineController
      ..removeListener(_handleTimelineScroll)
      ..dispose();
    _promptMentionDebounce?.cancel();
    _scrollToBottomButtonDebounce?.cancel();
    _streamingTimelineSyncDebounce?.cancel();
    _promptController.removeListener(_handlePromptComposerChanged);
    _promptFocusNode.removeListener(_handlePromptComposerChanged);
    unawaited(widget.controller.stopVoiceInput());
    _promptController.dispose();
    _promptFocusNode.dispose();
    _schemaController.dispose();
    _stickToBottom.dispose();
    _showScrollToBottomButton.dispose();
    _messageVersion.dispose();
    _composerDockHeight.dispose();
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
      _scheduleStreamingTimelineSync();
      _scheduleMessageVersionTick();
    }
  }

  void _scheduleStreamingTimelineSync() {
    if (!_stickToBottom.value || _timelineUserInteracting) return;
    if (_timelineViewportLocked) return;
    if (_streamingTimelineSyncDebounce != null) return;
    const minIntervalMs = 120;
    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _lastStreamingTimelineSyncAt;
    if (elapsed >= minIntervalMs) {
      _lastStreamingTimelineSyncAt = now;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_stickToBottom.value || _timelineUserInteracting) {
          return;
        }
        _scrollTimelineToBottom(animate: false);
      });
      return;
    }
    _streamingTimelineSyncDebounce ??= Timer(
      Duration(milliseconds: minIntervalMs - elapsed),
      () {
        _streamingTimelineSyncDebounce = null;
        _lastStreamingTimelineSyncAt = DateTime.now().millisecondsSinceEpoch;
        if (!mounted || !_stickToBottom.value || _timelineUserInteracting) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_stickToBottom.value || _timelineUserInteracting) {
            return;
          }
          _scrollTimelineToBottom(animate: false);
        });
      },
    );
  }

  void _detachTimelineAutoScroll() {
    _timelineUserInteracting = true;
    _pendingTimelineSync = false;
    _streamingTimelineSyncDebounce?.cancel();
    _streamingTimelineSyncDebounce = null;
    if (_stickToBottom.value) {
      _stickToBottom.value = false;
    }
    _scheduleScrollToBottomButtonVisibility(true, immediate: true);
  }

  bool get _timelineViewportLocked =>
      DateTime.now().millisecondsSinceEpoch < _timelineViewportLockUntilMs;

  void _cancelTimelineViewportLock() {
    _timelineViewportLockGeneration++;
    _timelineViewportLockUntilMs = 0;
    _timelineViewportLockPixels = null;
  }

  void _lockTimelineViewport({
    Duration duration = const Duration(milliseconds: 320),
  }) {
    final pixels =
        _timelineController.hasClients ? _timelineController.offset : null;
    _detachTimelineAutoScroll();
    if (pixels == null) return;
    final generation = ++_timelineViewportLockGeneration;
    _timelineViewportLockPixels = pixels;
    _timelineViewportLockUntilMs =
        DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds;
    _restoreTimelineViewportLock(generation);
  }

  void _restoreTimelineViewportLock(int generation) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _timelineViewportLockGeneration) return;
      final targetPixels = _timelineViewportLockPixels;
      if (targetPixels == null || !_timelineController.hasClients) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now >= _timelineViewportLockUntilMs) return;
      final position = _timelineController.position;
      final target = targetPixels.clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((position.pixels - target).abs() > 0.5) {
        _markProgrammaticTimelineScroll(target);
        _timelineController.jumpTo(target);
      }
      _restoreTimelineViewportLock(generation);
    });
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
    return 0;
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

  GlobalKey _timelineEntryKey(String stableId) {
    return _timelineEntryKeys.putIfAbsent(
      stableId,
      () => GlobalKey(debugLabel: 'timeline-entry-$stableId'),
    );
  }

  _VisibleTimelineAnchor? _captureVisibleTimelineAnchor(
    List<_TimelineTurnEntry> entries,
  ) {
    final viewportContext = _timelineViewportKey.currentContext;
    if (viewportContext == null) return null;
    final viewportBox = viewportContext.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.hasSize) return null;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportBox.size.height;
    for (final entry in entries) {
      final context = _timelineEntryKey(entry.stableId).currentContext;
      if (context == null) continue;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (bottom <= viewportTop + 1) continue;
      if (top >= viewportBottom) continue;
      return _VisibleTimelineAnchor(
        stableId: entry.stableId,
        top: top,
        bottom: bottom,
      );
    }
    return null;
  }

  _VisibleTimelineAnchor? _measureTimelineAnchorById(String? stableId) {
    if (stableId == null || stableId.isEmpty) return null;
    final context = _timelineEntryKey(stableId).currentContext;
    if (context == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final top = box.localToGlobal(Offset.zero).dy;
    return _VisibleTimelineAnchor(
      stableId: stableId,
      top: top,
      bottom: top + box.size.height,
    );
  }

  void _reconcileTimelineWindow(AppState state) {
    final sessionId = state.session?.id ?? '';
    final initialStart = _initialHistoryStart(state.messages);
    final beforeHistoryStart = _historyStartIndex;
    final beforeStagedCount = _stagedMessageCount;
    var action = 'none';
    if (_historySessionId != sessionId) {
      _historyRevealGeneration++;
      _historyRevealAnchorStableId = null;
      _historyRevealAnchorTop = null;
      _historyRevealAnchorBottom = null;
      _historyRevealRestorePending = false;
      _historyRevealRestoreAttempt = 0;
      _historySessionId = sessionId;
      _historyStartIndex = initialStart;
      _stagedMessageCount = 0;
      action = 'session-reset';
      _scheduleStageMount(state);
      return;
    }
    if (_historyStartIndex > state.messages.length) {
      _historyStartIndex = initialStart;
      action = 'clamp-history-start';
    }
    final visibleCount = _visibleTimelineMessages(state).length;
    if (_stagedMessageCount == 0 && visibleCount > 0) {
      action = 'initial-stage';
      _scheduleStageMount(state);
      return;
    }
    if (_stagedMessageCount > visibleCount) {
      _stagedMessageCount = visibleCount;
      action = 'clamp-staged-count';
    }
    if (_stagedMessageCount < visibleCount && _stickToBottom.value) {
      action = 'continue-stage';
      _scheduleStageMount(state);
    }
    if (action != 'none' && action != 'continue-stage') {}
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
    final key = '${state.session?.id ?? ''}|$_historyStartIndex';
    final previousKey = _stagingKey;
    final resetStage = _stagingKey != key || _stagedMessageCount == 0;
    _stagingKey = key;
    if (resetStage) {
      final expandFullyForPinnedEntry = _stickToBottom.value &&
          _historyStartIndex == 0 &&
          (previousKey != key || _stagedMessageCount == 0);
      _stagedMessageCount = expandFullyForPinnedEntry
          ? visibleCount
          : (visibleCount <= init ? visibleCount : init);
    }
    if (_stagedMessageCount >= visibleCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _stagingKey != key) return;
      final latestVisible =
          _visibleTimelineMessages(widget.controller.state).length;
      if (_stagedMessageCount >= latestVisible) return;
      final before = _stagedMessageCount;
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
    _pendingRevealEarlierMessages = false;
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
    final visibleCountBefore = _visibleTimelineMessages(state).length;
    final nextVisibleCount = state.messages.length - nextStart;
    final renderedMessagesBefore = _renderedTimelineMessages(state);
    final renderedEntriesBefore =
        _renderedTimelineEntries(state, renderedMessagesBefore);
    final visibleAnchorBefore =
        _captureVisibleTimelineAnchor(renderedEntriesBefore);
    final beforeOffset = _timelineController.offset;
    final beforeMax = _timelineController.position.maxScrollExtent;
    final generation = ++_historyRevealGeneration;
    _historyRevealAnchorStableId = visibleAnchorBefore?.stableId;
    _historyRevealAnchorTop = visibleAnchorBefore?.top;
    _historyRevealAnchorBottom = visibleAnchorBefore?.bottom;
    _historyRevealRestorePending = visibleAnchorBefore != null;
    _historyRevealRestoreAttempt = 0;
    setState(() {
      _historyStartIndex = nextStart;
      _stagingKey = '${state.session?.id ?? ''}|$nextStart';
      _stagedMessageCount = nextVisibleCount;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _historyRevealGeneration) return;
      _restoreHistoryRevealAnchor(generation, immediate: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _historyRevealGeneration) return;
      });
    });
  }

  void _restoreHistoryRevealAnchor(int generation, {bool immediate = false}) {
    void runRestore() {
      if (!mounted || generation != _historyRevealGeneration) return;
      if (!_historyRevealRestorePending || !_timelineController.hasClients)
        return;
      _historyRevealRestoreAttempt += 1;
      final trackedStableId = _historyRevealAnchorStableId;
      final trackedTopBefore = _historyRevealAnchorTop;
      final trackedAnchor = _measureTimelineAnchorById(trackedStableId);
      if (trackedAnchor == null || trackedTopBefore == null) {
        if (_historyRevealRestoreAttempt < 8) {
          _restoreHistoryRevealAnchor(generation);
          return;
        }
        _historyRevealRestorePending = false;
        _historyRevealAnchorStableId = null;
        _historyRevealAnchorTop = null;
        _historyRevealAnchorBottom = null;
        return;
      }
      final delta = trackedAnchor.top - trackedTopBefore;
      final targetOffset = (_timelineController.offset + delta)
          .clamp(
            0.0,
            _timelineController.position.maxScrollExtent,
          )
          .toDouble();
      if (delta.abs() > 0.5) {
        _markProgrammaticTimelineScroll(targetOffset);
        _timelineController.jumpTo(targetOffset);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _historyRevealGeneration) return;
          final settledAnchor = _measureTimelineAnchorById(trackedStableId);
          final renderedMessages =
              _renderedTimelineMessages(widget.controller.state);
          final renderedEntries = _renderedTimelineEntries(
              widget.controller.state, renderedMessages);
          final visibleAnchor = _captureVisibleTimelineAnchor(renderedEntries);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || generation != _historyRevealGeneration) return;
            final settledAnchor2 = _measureTimelineAnchorById(trackedStableId);
            final renderedMessages2 =
                _renderedTimelineMessages(widget.controller.state);
            final renderedEntries2 = _renderedTimelineEntries(
                widget.controller.state, renderedMessages2);
            final visibleAnchor2 =
                _captureVisibleTimelineAnchor(renderedEntries2);
          });
        });
      }
      _historyRevealRestorePending = false;
      _historyRevealAnchorStableId = null;
      _historyRevealAnchorTop = null;
      _historyRevealAnchorBottom = null;
    }

    if (immediate) {
      runRestore();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      runRestore();
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

  Future<void> _openFloatingWindow() async {
    final state = widget.controller.state;
    final session = state.session;
    final workspace = state.workspace;
    final serverUri = state.serverUri;
    if (session == null || workspace == null || serverUri == null) {
      _showInfo(
          context, l(context, '当前没有可显示的会话', 'No active session to show.'));
      return;
    }
    if (!FloatingWindowBridge.isSupported) {
      _showInfo(
        context,
        l(
          context,
          '当前平台不支持小窗功能。',
          'Floating window is not supported on this platform.',
        ),
      );
      return;
    }
    final allowed = await FloatingWindowBridge.hasPermission();
    if (!mounted) return;
    if (!allowed) {
      await FloatingWindowBridge.openPermissionSettings();
      if (!mounted) return;
      _showInfo(
        context,
        l(
          context,
          '请开启“显示在其他应用上层”权限后再点一次小窗。',
          'Enable display-over-other-apps permission, then tap floating window again.',
        ),
      );
      return;
    }
    final opened = await FloatingWindowBridge.show(
      FloatingWindowConfig(
        serverUri: serverUri,
        session: session,
        workspace: workspace,
        darkMode: context.isDarkMode,
      ),
    );
    if (!mounted) return;
    if (opened) {
      // Window launched — move app to background so the overlay is visible.
      await FloatingWindowBridge.moveToBackground();
    } else {
      _showInfo(
        context,
        l(context, '无法打开小窗，请检查悬浮窗权限。', 'Unable to open floating window.'),
      );
    }
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

  // ignore: unused_element
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

  // ignore: unused_element
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
        leadingWidth: 32,
        leading: IconButton(
          tooltip: l(context, '项目', 'Projects'),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          onPressed: () => widget.controller.leaveProject(),
          icon: const Icon(Icons.arrow_back_rounded, size: 21),
        ),
        titleSpacing: 0,
        title: _SessionAppBarTitle(
          title: state.session?.title.isNotEmpty == true
              ? state.session!.title
              : (state.session == null
                  ? l(context, '新建会话', 'New session')
                  : (state.workspace?.name ??
                      l(context, '移动代理', 'Mobile Agent'))),
        ),
        actions: [
          if (FloatingWindowBridge.isSupported)
            _buildAppBarAction(
              tooltip: l(context, '小窗', 'Floating window'),
              onPressed: (state.session == null || state.messages.isEmpty)
                  ? null
                  : _openFloatingWindow,
              icon: Icons.picture_in_picture_alt_outlined,
            ),
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
                              return NotificationListener<
                                  _TimelineDetachNotification>(
                                onNotification: (_) {
                                  _lockTimelineViewport();
                                  return false;
                                },
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: _handleTimelineNotification,
                                  child: KeyedSubtree(
                                    key: ValueKey<String>(
                                        'timeline-${liveState.session?.id ?? 'none'}'),
                                    child: Builder(
                                      builder: (context) {
                                        final expandTimelineCacheExtent =
                                            _historyRevealRestorePending ||
                                                (_pendingTimelineSync &&
                                                    _stickToBottom.value);
                                        return ListView.builder(
                                          key: _timelineViewportKey,
                                          cacheExtent: expandTimelineCacheExtent
                                              ? 200000
                                              : null,
                                          controller: _timelineController,
                                          keyboardDismissBehavior:
                                              ScrollViewKeyboardDismissBehavior
                                                  .onDrag,
                                          physics: const BouncingScrollPhysics(
                                              parent:
                                                  AlwaysScrollableScrollPhysics()),
                                          padding: EdgeInsets.fromLTRB(12,
                                              isKeyboardOpen ? 8 : 12, 12, 16),
                                          itemCount: _timelineItemCount(
                                              liveState,
                                              renderedTimelineEntries),
                                          itemBuilder: (context, index) =>
                                              _buildTimelineItem(
                                            context,
                                            state: liveState,
                                            modelConfig: modelConfig,
                                            currentModelChoice:
                                                currentModelChoice,
                                            showModelFreeTag: showModelFreeTag,
                                            showModelLatestTag:
                                                showModelLatestTag,
                                            isKeyboardOpen: isKeyboardOpen,
                                            renderedMessages: renderedMessages,
                                            renderedEntries:
                                                renderedTimelineEntries,
                                            streamingAssistantMessageId:
                                                streamingAssistantMessageId,
                                            index: index,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  _MeasuredSize(
                    onChanged: (size) {
                      final height = size.height;
                      if ((_composerDockHeight.value - height).abs() < 0.5) {
                        return;
                      }
                      _composerDockHeight.value = height;
                    },
                    child: _buildComposerDock(context, state, isKeyboardOpen),
                  ),
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
                    return ValueListenableBuilder<double>(
                      valueListenable: _composerDockHeight,
                      builder: (context, composerDockHeight, _) {
                        final bottom = composerDockHeight > 0
                            ? composerDockHeight + 24
                            : (isKeyboardOpen ? 140.0 : 188.0);
                        return Positioned(
                          right: 16,
                          bottom: bottom,
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
      if (_stickToBottom.value) {
        _stickToBottom.value = false;
      }
      return;
    }
    if (!_stickToBottom.value && nextStick) {
      _stickToBottom.value = true;
    }
  }

  bool _handleTimelineNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final recentProgrammatic =
        _isRecentProgrammaticTimelineScroll(notification.metrics);
    if (notification is UserScrollNotification ||
        notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {}
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.idle) {
      if (_timelineViewportLocked) return false;
      final distance =
          notification.metrics.maxScrollExtent - notification.metrics.pixels;
      final atBottom = distance < 10;
      _timelineUserInteracting = false;
      if (_stickToBottom.value != atBottom) {
        _stickToBottom.value = atBottom;
      }
      _maybeRevealEarlierMessages(
        source: 'user-scroll-idle',
        pixels: notification.metrics.pixels,
        deferOnly: false,
      );
      return false;
    }
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle &&
        !recentProgrammatic) {
      _cancelTimelineViewportLock();
      _timelineUserInteracting = true;
      _pendingTimelineSync = false;
      if (_stickToBottom.value) {
        _stickToBottom.value = false;
      }
      _scheduleScrollToBottomButtonVisibility(true, immediate: true);
      return false;
    }
    if (notification is ScrollStartNotification && !recentProgrammatic) {
      _timelineUserInteracting = true;
      _pendingTimelineSync = false;
    }
    if (recentProgrammatic) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      final distance =
          notification.metrics.maxScrollExtent - notification.metrics.pixels;
      final nextStick =
          _computeStickToBottom(distance, current: _stickToBottom.value);
      final userScrollUpdate = notification is ScrollUpdateNotification &&
          notification.dragDetails != null;
      if (_timelineUserInteracting || userScrollUpdate) {
        // Deer-flow 的思路是用户一旦脱离底部，就进入 detached 状态；
        // 拖动/滚轮过程中不因为仍靠近底部而重新吸底，避免流式输出把用户拉回去。
        if (_stickToBottom.value) {
          _stickToBottom.value = false;
        }
      } else if (!_stickToBottom.value && nextStick) {
        _stickToBottom.value = true;
      }
      _maybeRevealEarlierMessages(
        source: notification is ScrollEndNotification
            ? 'scroll-end'
            : 'scroll-update',
        pixels: notification.metrics.pixels,
        deferOnly: _timelineUserInteracting || userScrollUpdate,
      );
      if (notification is ScrollEndNotification) {
        final atBottom = distance < 10;
        if (_stickToBottom.value != atBottom) {
          _stickToBottom.value = atBottom;
        }
        _timelineUserInteracting = false;
        _maybeRevealEarlierMessages(
          source: 'scroll-end-post-idle',
          pixels: notification.metrics.pixels,
          deferOnly: false,
        );
      }
    }
    return false;
  }

  void _maybeRevealEarlierMessages({
    required String source,
    required double pixels,
    required bool deferOnly,
  }) {
    final hasEarlier = _hasEarlierHistory(widget.controller.state);
    final nearTop = pixels < 180;
    if (!hasEarlier || !nearTop) {
      if (pixels > 240) {
        _pendingRevealEarlierMessages = false;
      }
      return;
    }
    if (deferOnly) {
      if (!_pendingRevealEarlierMessages) {
        _pendingRevealEarlierMessages = true;
      }
      return;
    }
    if (_timelineUserInteracting) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastBackfillAt <= 300) return;
    _lastBackfillAt = now;
    _pendingRevealEarlierMessages = false;
    _revealEarlierMessages();
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
    final generation = ++_timelineSyncGeneration;
    _timelineSyncLastMaxExtent = null;
    _timelineSyncStableFrames = 0;
    _timelineSyncAttemptCount = 0;
    if (_isAutoScrolling) {
      return;
    }
    if (_timelineSyncScheduled) {
      return;
    }
    _timelineSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runTimelineSyncWhenStable(generation);
    });
  }

  void _runTimelineSyncWhenStable(int generation) {
    _timelineSyncScheduled = false;
    if (!mounted || generation != _timelineSyncGeneration) return;
    if (!_pendingTimelineSync || !_stickToBottom.value) return;
    if (_isAutoScrolling || _timelineViewportLocked) {
      _timelineSyncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runTimelineSyncWhenStable(generation);
      });
      return;
    }
    if (!_timelineController.hasClients) {
      _timelineSyncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runTimelineSyncWhenStable(generation);
      });
      return;
    }
    final maxExtent = _timelineController.position.maxScrollExtent;
    final lastMaxExtent = _timelineSyncLastMaxExtent;
    _timelineSyncAttemptCount += 1;
    if (lastMaxExtent != null && (lastMaxExtent - maxExtent).abs() < 1) {
      _timelineSyncStableFrames += 1;
    } else {
      _timelineSyncStableFrames = 0;
    }
    _timelineSyncLastMaxExtent = maxExtent;
    const requiredStableFrames = 1;
    if (_timelineSyncStableFrames < requiredStableFrames &&
        _timelineSyncAttemptCount < 8) {
      _timelineSyncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runTimelineSyncWhenStable(generation);
      });
      return;
    }
    _pendingTimelineSync = false;
    _scrollTimelineToBottom(animate: false);
    if (_pendingTimelineSync) {
      _scheduleTimelineSync(widget.controller.state);
    }
  }

  void _scrollTimelineToBottom({bool animate = true}) {
    if (!_timelineController.hasClients) return;
    final offset = _timelineController.position.maxScrollExtent;
    final current = _timelineController.offset;
    final delta = (offset - current).abs();
    final isInitialEnter =
        _lastObservedSessionId != null && _stagedMessageCount <= 24;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_timelineController.hasClients) return;
      final currentOffset = _timelineController.offset;
      final maxExtent = _timelineController.position.maxScrollExtent;
      final distance = maxExtent - currentOffset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_timelineController.hasClients) return;
        final currentOffset2 = _timelineController.offset;
        final maxExtent2 = _timelineController.position.maxScrollExtent;
        final distance2 = maxExtent2 - currentOffset2;
        if (_stickToBottom.value &&
            !_timelineUserInteracting &&
            !_timelineViewportLocked &&
            !_pendingTimelineSync &&
            distance2 > 1) {
          _scrollTimelineToBottom(animate: false);
        }
      });
    });
    if (isInitialEnter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_timelineController.hasClients) return;
        final currentOffset = _timelineController.offset;
        final maxExtent = _timelineController.position.maxScrollExtent;
        final overshoot = currentOffset - maxExtent;
        if (overshoot > 1 && _stickToBottom.value) {
          _markProgrammaticTimelineScroll(maxExtent);
          _timelineController.jumpTo(maxExtent);
        }
      });
    }
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
    final isRecent = (pixels - target).abs() < 2;
    if (isRecent) {}
    return isRecent;
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
      lastPart?.id ?? '',
      lastPart?.type.name ?? '',
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
        final attachments = state['attachments'] as List? ?? const [];
        return [
          part.type.name,
          part.data['tool'] ?? '',
          part.data['callID'] ?? '',
          state['status'] ?? '',
          state['title'] ?? '',
          state['phase'] ?? '',
          (state['raw'] as String?)?.length ?? 0,
          (state['output'] as String?)?.length ?? 0,
          (state['displayOutput'] as String?)?.length ?? 0,
          attachments.length,
          for (final item in attachments)
            if (item is Map)
              [
                item['type'] ?? '',
                item['kind'] ?? '',
                item['path'] ?? item['url'] ?? item['filename'] ?? '',
                (item['preview'] as String?)?.length ?? 0,
                (item['fullPreview'] as String?)?.length ?? 0,
                (item['afterContent'] as String?)?.length ?? 0,
                item['additions'] ?? '',
                item['deletions'] ?? '',
              ].join('/'),
          (part.data['writeContentPreview'] as String?)?.length ?? 0,
          (part.data['editOldContentPreview'] as String?)?.length ?? 0,
          (part.data['editContentPreview'] as String?)?.length ?? 0,
        ].join(':');
      default:
        return '${part.type.name}:${part.createdAt}';
    }
  }
}
