part of '../../home_page.dart';

const int _kWriteStreamRenderThrottleMs = 100;
const int _kWriteStreamPreviewMaxChars = 60000;
const int _kWriteStreamPreviewMaxLines = 900;

class _TailTextWindow {
  const _TailTextWindow({
    required this.text,
    required this.omittedLines,
    required this.omittedChars,
  });

  final String text;
  final int omittedLines;
  final int omittedChars;

  bool get isTruncated => omittedLines > 0 || omittedChars > 0;
}

class _PreviewRenderPerfStats {
  int _renderCount = 0;
  int _lastReportAtMs = 0;
  int _maxContentChars = 0;
  int _maxWindowChars = 0;

  void record({
    required String path,
    required String mode,
    required int contentChars,
    required int windowChars,
    required bool truncated,
  }) {
    _renderCount += 1;
    if (contentChars > _maxContentChars) _maxContentChars = contentChars;
    if (windowChars > _maxWindowChars) _maxWindowChars = windowChars;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastReportAtMs != 0 && now - _lastReportAtMs < 1000) return;
    final windowMs = _lastReportAtMs == 0 ? 1000 : now - _lastReportAtMs;
    _lastReportAtMs = now;
    debugTrace(
      runId: 'stream-preview-render',
      hypothesisId: 'smooth-ui',
      location: 'ui/home/previews/file_preview.dart:_PreviewRenderPerfStats',
      message: 'preview render window',
      data: {
        'path': path,
        'mode': mode,
        'windowMs': windowMs,
        'renderCount': _renderCount,
        'maxContentChars': _maxContentChars,
        'maxWindowChars': _maxWindowChars,
        'truncated': truncated,
      },
    );
    _renderCount = 0;
    _maxContentChars = 0;
    _maxWindowChars = 0;
  }
}

_TailTextWindow _tailTextWindow(
  String text, {
  int maxChars = _kWriteStreamPreviewMaxChars,
  int maxLines = _kWriteStreamPreviewMaxLines,
}) {
  if (text.length <= maxChars) {
    final lines =
        text.isEmpty ? const <String>[] : const LineSplitter().convert(text);
    if (lines.length <= maxLines) {
      return _TailTextWindow(text: text, omittedLines: 0, omittedChars: 0);
    }
    final visible = lines.sublist(lines.length - maxLines).join('\n');
    return _TailTextWindow(
      text: visible,
      omittedLines: lines.length - maxLines,
      omittedChars: text.length - visible.length,
    );
  }

  final tail = text.substring(text.length - maxChars);
  final lines = const LineSplitter().convert(tail);
  if (lines.length <= maxLines) {
    return _TailTextWindow(
      text: tail,
      omittedLines: 0,
      omittedChars: text.length - tail.length,
    );
  }
  final visible = lines.sublist(lines.length - maxLines).join('\n');
  return _TailTextWindow(
    text: visible,
    omittedLines: lines.length - maxLines,
    omittedChars: text.length - visible.length,
  );
}

Future<void> _openWriteStreamPreview(
  BuildContext context, {
  required AppController controller,
  required WorkspaceInfo? workspace,
  required String path,
  required String initialContent,
  String? messageId,
  String? partId,
  String? contentKey,
  String previewKind = 'write',
  String previewPhase = 'new',
  ValueChanged<String>? onInsertPromptReference,
  PromptReferenceAction? onSendPromptReference,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => _WriteStreamPreviewPage(
        controller: controller,
        workspace: workspace,
        path: path,
        initialContent: initialContent,
        messageId: messageId,
        partId: partId,
        contentKey: contentKey ?? 'writeContentPreview',
        previewKind: previewKind,
        previewPhase: previewPhase,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      ),
    ),
  );
}

/// 全屏路由打开预览，避免 bottom sheet 抢走手势（游戏/HTML 滚动等）。
Future<void> _openFilePreview(
  BuildContext context, {
  required AppController controller,
  required WorkspaceInfo workspace,
  required String path,
  Uri? serverUri,
  int? initialLine,
  ValueChanged<String>? onInsertPromptReference,
  PromptReferenceAction? onSendPromptReference,
}) {
  if (_pathLooksHtmlFile(path) && serverUri != null) {
    final previewUrl = _workspacePreviewUrl(
      serverUri: serverUri,
      workspace: workspace,
      path: path,
    );
    return _openWebPreview(
      context,
      title: path,
      subtitle: previewUrl.toString(),
      url: previewUrl.toString(),
    );
  }
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => _FilePreviewSheet(
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

class _WriteStreamPreviewPage extends StatefulWidget {
  const _WriteStreamPreviewPage({
    required this.controller,
    required this.workspace,
    required this.path,
    required this.initialContent,
    this.messageId,
    this.partId,
    required this.contentKey,
    required this.previewKind,
    required this.previewPhase,
    this.onInsertPromptReference,
    this.onSendPromptReference,
  });

  final AppController controller;
  final WorkspaceInfo? workspace;
  final String path;
  final String initialContent;
  final String? messageId;
  final String? partId;
  final String contentKey;
  final String previewKind;
  final String previewPhase;
  final ValueChanged<String>? onInsertPromptReference;
  final PromptReferenceAction? onSendPromptReference;

  @override
  State<_WriteStreamPreviewPage> createState() =>
      _WriteStreamPreviewPageState();
}

class _WriteStreamPreviewPageState extends State<_WriteStreamPreviewPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (mounted) setState(() {});
  }

  String _currentContent() {
    final partId = widget.partId;
    if (partId == null || partId.isEmpty) return widget.initialContent;
    for (final bundle in widget.controller.state.messages) {
      if (widget.messageId != null && bundle.message.id != widget.messageId) {
        continue;
      }
      for (final part in bundle.parts) {
        if (part.id != partId) continue;
        final preview = part.data[widget.contentKey] as String?;
        if (preview != null) return preview;
      }
    }
    return widget.initialContent;
  }

  @override
  Widget build(BuildContext context) {
    final content = _currentContent();
    final isEditPreview = widget.previewKind == 'edit';
    final isEditOldPreview = isEditPreview && widget.previewPhase == 'old';
    final title = widget.path.isEmpty
        ? (isEditPreview
            ? l(context, '编辑预览', 'Edit preview')
            : l(context, '写入预览', 'Write preview'))
        : widget.path;
    final lines =
        content.isEmpty ? 0 : const LineSplitter().convert(content).length;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          leading: const BackButton(),
          bottom: TabBar(
            tabs: [
              Tab(text: l(context, '过程', 'Process')),
              Tab(text: l(context, '预览', 'Preview')),
            ],
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEditPreview
                      ? (isEditOldPreview
                          ? l(context, '实时原文定位 · $lines 行',
                              'Live original text · $lines line(s)')
                          : l(context, '实时替换内容 · $lines 行',
                              'Live replacement · $lines line(s)'))
                      : l(context, '实时草稿 · $lines 行',
                          'Live draft · $lines line(s)'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: context.oc.foregroundMuted),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      _WriteStreamPreviewBody(
                        path: widget.path,
                        content: content,
                        streaming: true,
                        sourceOnly: true,
                        workspace: widget.workspace,
                        controller: widget.controller,
                        onInsertPromptReference: widget.onInsertPromptReference,
                        onSendPromptReference: widget.onSendPromptReference,
                      ),
                      _WriteStreamPreviewBody(
                        path: widget.path,
                        content: content,
                        streaming: true,
                        sourceOnly: isEditPreview,
                        workspace: widget.workspace,
                        controller: widget.controller,
                        onInsertPromptReference: widget.onInsertPromptReference,
                        onSendPromptReference: widget.onSendPromptReference,
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

class _WriteStreamPreviewBody extends StatefulWidget {
  const _WriteStreamPreviewBody({
    required this.path,
    required this.content,
    required this.streaming,
    required this.workspace,
    required this.controller,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
    this.sourceOnly = false,
  });

  final String path;
  final String content;
  final bool streaming;
  final WorkspaceInfo? workspace;
  final AppController controller;
  final ValueChanged<String>? onInsertPromptReference;
  final PromptReferenceAction? onSendPromptReference;
  final bool sourceOnly;

  @override
  State<_WriteStreamPreviewBody> createState() =>
      _WriteStreamPreviewBodyState();
}

class _WriteStreamPreviewBodyState extends State<_WriteStreamPreviewBody> {
  final ScrollController _scrollController = ScrollController();
  final _PreviewRenderPerfStats _renderPerf = _PreviewRenderPerfStats();
  Timer? _renderTimer;
  String _renderedContent = '';
  int _lastRenderFlushMs = 0;
  bool _followTail = true;
  bool _showJumpToBottom = false;
  bool _programmaticScroll = false;
  DateTime? _programmaticUntil;

  @override
  void initState() {
    super.initState();
    _renderedContent = widget.content;
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToBottom(jump: true));
  }

  @override
  void didUpdateWidget(covariant _WriteStreamPreviewBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _scheduleContentRender();
    }
  }

  @override
  void dispose() {
    _renderTimer?.cancel();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleContentRender() {
    if (!widget.streaming) {
      _renderTimer?.cancel();
      _renderTimer = null;
      _setRenderedContent(widget.content);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining =
        _kWriteStreamRenderThrottleMs - (now - _lastRenderFlushMs);
    if (remaining <= 0) {
      _renderTimer?.cancel();
      _renderTimer = null;
      _setRenderedContent(widget.content);
      return;
    }
    _renderTimer ??= Timer(Duration(milliseconds: remaining), () {
      if (!mounted) return;
      _renderTimer = null;
      _setRenderedContent(widget.content);
    });
  }

  void _setRenderedContent(String content) {
    if (_renderedContent == content) return;
    _lastRenderFlushMs = DateTime.now().millisecondsSinceEpoch;
    setState(() => _renderedContent = content);
    if (_followTail) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final now = DateTime.now();
    if (_programmaticScroll ||
        (_programmaticUntil != null && now.isBefore(_programmaticUntil!))) {
      return;
    }
    final position = _scrollController.position;
    final distanceToBottom = position.maxScrollExtent - position.pixels;
    final shouldFollow = distanceToBottom <= 24;
    final shouldShowButton = distanceToBottom > 96;
    if (shouldFollow != _followTail || shouldShowButton != _showJumpToBottom) {
      setState(() {
        _followTail = shouldFollow;
        _showJumpToBottom = shouldShowButton;
      });
    }
  }

  void _scrollToBottom({bool jump = false}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    _programmaticScroll = true;
    _programmaticUntil = DateTime.now().add(
      const Duration(milliseconds: 260),
    );
    if (jump) {
      _scrollController.jumpTo(target);
      _finishProgrammaticScroll();
    } else {
      _scrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(_finishProgrammaticScroll);
    }
    if (!_followTail || _showJumpToBottom) {
      setState(() {
        _followTail = true;
        _showJumpToBottom = false;
      });
    }
  }

  void _finishProgrammaticScroll() {
    _programmaticScroll = false;
    _programmaticUntil = DateTime.now().add(
      const Duration(milliseconds: 120),
    );
    if (!mounted) return;
    if (!_followTail || _showJumpToBottom) {
      setState(() {
        _followTail = true;
        _showJumpToBottom = false;
      });
    }
  }

  Widget _scrollingPreview(BuildContext context, Widget child,
      {required Color background}) {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: _panelDecoration(
            context,
            background: background,
            radius: 12,
            elevated: false,
          ),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: _showJumpToBottom,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: child,
              ),
            ),
          ),
        ),
        _FloatingPillAction(
          visible: _showJumpToBottom,
          icon: Icons.keyboard_arrow_down_rounded,
          label: l(context, '到底部', 'Bottom'),
          onPressed: _scrollToBottom,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMarkdown = _pathLooksMarkdownFile(widget.path);
    final isHtml = _pathLooksHtmlFile(widget.path);
    final window = isHtml && !widget.sourceOnly
        ? _TailTextWindow(
            text: _renderedContent,
            omittedLines: 0,
            omittedChars: 0,
          )
        : _tailTextWindow(_renderedContent);
    _renderPerf.record(
      path: widget.path,
      mode: widget.sourceOnly
          ? 'source'
          : isHtml
              ? 'html'
              : isMarkdown
                  ? 'markdown'
                  : 'source',
      contentChars: _renderedContent.length,
      windowChars: window.text.length,
      truncated: window.isTruncated,
    );
    if (isMarkdown && !widget.sourceOnly) {
      return _scrollingPreview(
        context,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (window.isTruncated) _PreviewWindowNotice(window: window),
            _StreamingMarkdownText(
              text: window.text,
              streaming: widget.streaming,
              workspace: widget.workspace,
              controller: widget.controller,
              onInsertPromptReference: widget.onInsertPromptReference,
              onSendPromptReference: widget.onSendPromptReference,
            ),
          ],
        ),
        background: context.oc.panelBackground,
      );
    }
    if (isHtml && !widget.sourceOnly) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          decoration: _panelDecoration(
            context,
            background: context.oc.panelBackground,
            radius: 12,
            elevated: false,
          ),
          child: _WorkspaceHtmlPreview(html: _renderedContent),
        ),
      );
    }
    return _scrollingPreview(
      context,
      _WriteStreamSourcePreview(
        path: widget.path,
        content: window.text,
        window: window,
      ),
      background: context.oc.shadow,
    );
  }
}

class _PreviewWindowNotice extends StatelessWidget {
  const _PreviewWindowNotice({required this.window});

  final _TailTextWindow window;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (window.omittedLines > 0)
        l(context, '省略 ${window.omittedLines} 行',
            '${window.omittedLines} line(s) omitted'),
      if (window.omittedChars > 0)
        l(context, '省略 ${window.omittedChars} 字符',
            '${window.omittedChars} chars omitted'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        l(context, '仅渲染尾部窗口 · ${parts.join(' · ')}',
            'Rendering tail window · ${parts.join(' · ')}'),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: context.oc.foregroundMuted),
      ),
    );
  }
}

class _WriteStreamSourcePreview extends StatelessWidget {
  const _WriteStreamSourcePreview({
    required this.path,
    required this.content,
    required this.window,
  });

  final String path;
  final String content;
  final _TailTextWindow window;

  @override
  Widget build(BuildContext context) {
    final language = _languageForPath(path);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 72,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (window.isTruncated) _PreviewWindowNotice(window: window),
            language == null
                ? SelectableText(
                    content,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  )
                : HighlightView(
                    content,
                    language: language,
                    theme: _codeHighlightTheme(context),
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
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
  bool _sourceMode = false;

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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.path,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        leading: const BackButton(),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    final fullText = loaded.lines.join('\n');
                    final isMdPath = _pathLooksMarkdownFile(widget.path);
                    final isHtmlPath = _pathLooksHtmlFile(widget.path);
                    final currentStart =
                        _currentStart ?? loaded.initialStartLine;
                    final currentEnd =
                        _pageEnd(currentStart, loaded.totalLines);
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
                    final sourceColumn = Column(
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
                                    ?.copyWith(
                                        color: context.oc.foregroundMuted),
                              ),
                            ),
                            if (loaded.focusLine != null)
                              Text(
                                l(context, '焦点: ${loaded.focusLine}',
                                    'Focus: ${loaded.focusLine}'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: context.oc.foregroundMuted),
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
                                tooltip: l(
                                    context, '复制为 prompt 引用', 'Copy as prompt'),
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
                                  tooltip: l(
                                      context, '插入到输入框', 'Insert into prompt'),
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
                                  context,
                                  background: context.oc.shadow,
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
                                            color:
                                                Colors.amber.withOpacity(0.18),
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
                                                color: context.oc.muted,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          HighlightView(
                                            visibleCode,
                                            language: language,
                                            theme: _codeHighlightTheme(context),
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
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isMdPath || isHtmlPath)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Text(
                                  l(context, '查看方式', 'View as'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: context.oc.foregroundMuted),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _sourceMode = false),
                                  style: TextButton.styleFrom(
                                    foregroundColor: !_sourceMode
                                        ? context.oc.accent
                                        : context.oc.muted,
                                    minimumSize: Size.zero,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(l(context, '排版', 'Formatted')),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _sourceMode = true),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _sourceMode
                                        ? context.oc.accent
                                        : context.oc.muted,
                                    minimumSize: Size.zero,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: Text(l(context, '源码', 'Source')),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: (isMdPath || isHtmlPath) && !_sourceMode
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    width: double.infinity,
                                    decoration: _panelDecoration(
                                      context,
                                      background: context.oc.panelBackground,
                                      radius: 14,
                                      elevated: false,
                                    ),
                                    child: isMdPath
                                        ? SingleChildScrollView(
                                            padding: const EdgeInsets.all(14),
                                            child: _FilePreviewMarkdown(
                                              text: fullText,
                                              workspace: widget.workspace,
                                              controller: widget.controller,
                                              onInsertPromptReference: widget
                                                  .onInsertPromptReference,
                                              onSendPromptReference:
                                                  widget.onSendPromptReference,
                                            ),
                                          )
                                        : _WorkspaceHtmlPreview(html: fullText),
                                  ),
                                )
                              : sourceColumn,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilePreviewMarkdown extends StatelessWidget {
  const _FilePreviewMarkdown({
    required this.text,
    required this.workspace,
    required this.controller,
    this.onInsertPromptReference,
    this.onSendPromptReference,
  });

  final String text;
  final WorkspaceInfo workspace;
  final AppController controller;
  final ValueChanged<String>? onInsertPromptReference;
  final PromptReferenceAction? onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: text,
      selectable: false,
      softLineBreak: true,
      shrinkWrap: true,
      builders: {
        'pre': _MarkdownCodeBlockBuilder(),
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        blockSpacing: 10,
        p: TextStyle(fontSize: 15, height: 1.5, color: context.oc.foreground),
        a: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: context.oc.accent,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w500,
        ),
        strong: TextStyle(
          fontWeight: FontWeight.w700,
          color: context.oc.foreground,
        ),
        em: TextStyle(
          fontStyle: FontStyle.italic,
          color: context.oc.foreground,
        ),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.45,
          color: context.isDarkMode
              ? const Color(0xFFE06C75)
              : Colors.red.shade900,
          backgroundColor: context.oc.composerOptionBg,
        ),
        codeblockDecoration: BoxDecoration(
          color: context.oc.composerOptionBg,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.fromBorderSide(BorderSide(color: context.oc.borderColor)),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          color: context.oc.composerOptionBg,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: context.oc.border, width: 3),
          ),
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
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..clearMaterialBanners()
    ..showMaterialBanner(
      MaterialBanner(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: messenger.hideCurrentMaterialBanner,
            child: const Text('OK'),
          ),
        ],
      ),
    );
  Future<void>.delayed(const Duration(seconds: 4), () {
    messenger.hideCurrentMaterialBanner();
  });
}
