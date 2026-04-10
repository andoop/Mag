part of '../../home_page.dart';

/// 全屏路由打开预览，避免 bottom sheet 抢走手势（游戏/HTML 滚动等）。
Future<void> _openFilePreview(
  BuildContext context, {
  required AppController controller,
  required WorkspaceInfo workspace,
  required String path,
  int? initialLine,
  ValueChanged<String>? onInsertPromptReference,
  PromptReferenceAction? onSendPromptReference,
}) {
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
                                  ?.copyWith(color: context.oc.foregroundMuted),
                            ),
                          ),
                          if (loaded.focusLine != null)
                            Text(
                              l(context, '焦点: ${loaded.focusLine}',
                                  'Focus: ${loaded.focusLine}'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: context.oc.foregroundMuted),
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
                              decoration: _panelDecoration(context,
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
                                    ?.copyWith(color: context.oc.foregroundMuted),
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
                                child: Text(
                                    l(context, '排版', 'Formatted')),
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
                                  decoration: _panelDecoration(context,
                                    background: context.oc.panelBackground,
                                    radius: 14,
                                    elevated: false,
                                  ),
                                  child: isMdPath
                                      ? SingleChildScrollView(
                                          padding:
                                              const EdgeInsets.all(14),
                                          child: _FilePreviewMarkdown(
                                            text: fullText,
                                            workspace: widget.workspace,
                                            controller: widget.controller,
                                            onInsertPromptReference: widget
                                                .onInsertPromptReference,
                                            onSendPromptReference: widget
                                                .onSendPromptReference,
                                          ),
                                        )
                                      : _WorkspaceHtmlPreview(
                                          html: fullText),
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
      onTapLink: (linkText, href, title) {
        if (href != null && href.startsWith('fileref:')) {
          final enc = href.substring('fileref:'.length);
          final path = Uri.decodeComponent(enc);
          if (path.isNotEmpty) {
            _openFilePreview(
              context,
              controller: controller,
              workspace: workspace,
              path: path,
              onInsertPromptReference: onInsertPromptReference,
              onSendPromptReference: onSendPromptReference,
            );
          }
        }
      },
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
          border: Border.fromBorderSide(BorderSide(color: context.oc.borderColor)),
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
