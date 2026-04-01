part of '../home_page.dart';

/// OpenCode `TextPartDisplay` 底部：`IconButton` + `text-part-meta`（Agent · 模型 · 耗时）。
class _AssistantTextFooter extends StatefulWidget {
  const _AssistantTextFooter({
    required this.plainText,
    this.metaLine,
  });

  final String plainText;
  final String? metaLine;

  @override
  State<_AssistantTextFooter> createState() => _AssistantTextFooterState();
}

class _AssistantTextFooterState extends State<_AssistantTextFooter> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final meta = widget.metaLine?.trim();
    final hasMeta = meta != null && meta.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: _copied
                ? l(context, '已复制', 'Copied')
                : l(context, '复制回复', 'Copy response'),
            icon: Icon(
              _copied ? Icons.check : Icons.copy_outlined,
              size: 20,
              color: _copied ? kOcGreen : kOcMuted,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.plainText));
              if (!mounted) return;
              setState(() => _copied = true);
              Future<void>.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copied = false);
              });
              _showInfo(
                context,
                l(context, '回复已复制', 'Response copied'),
              );
            },
          ),
          if (hasMeta)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, left: 2),
                child: Text(
                  meta,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: kOcMuted,
                        height: 1.35,
                        fontSize: 12,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StreamingMarkdownText extends StatelessWidget {
  const _StreamingMarkdownText({
    required this.text,
    this.workspace,
    this.controller,
    this.onInsertPromptReference,
    this.onSendPromptReference,
    this.footerMeta,
    this.showResponseCopy = false,
  });

  final String text;
  final WorkspaceInfo? workspace;
  final AppController? controller;
  final ValueChanged<String>? onInsertPromptReference;
  final PromptReferenceAction? onSendPromptReference;
  final String? footerMeta;
  final bool showResponseCopy;

  @override
  Widget build(BuildContext context) {
    final withLinks = _injectFileRefWikiLinks(text);
    final normalized = _normalizeStreamingMarkdown(withLinks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownBody(
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
        if (href.startsWith('fileref:')) {
          final enc = href.substring('fileref:'.length);
          final path = Uri.decodeComponent(enc);
          final ws = workspace;
          final ctrl = controller;
          if (ws != null && ctrl != null && path.isNotEmpty) {
            _openFilePreview(
              context,
              controller: ctrl,
              workspace: ws,
              path: path,
              onInsertPromptReference: onInsertPromptReference,
              onSendPromptReference: onSendPromptReference,
            );
          }
          return;
        }
        _showInfo(
          context,
          l(context, '链接暂未接入外部打开: $href',
              'External link opening is not wired yet: $href'),
        );
      },
        ),
        if (showResponseCopy)
          _AssistantTextFooter(
            plainText: text,
            metaLine: footerMeta,
          ),
      ],
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

/// `[[file:lib/foo.dart]]` → markdown link，点击打开工作区文件（与系统提示中的约定一致）。
String _injectFileRefWikiLinks(String input) {
  return input.replaceAllMapped(
    RegExp(r'\[\[file:([^\]]+)\]\]'),
    (m) {
      final p = m.group(1)!.trim();
      if (p.isEmpty) return m.group(0)!;
      return '[$p](fileref:${Uri.encodeComponent(p)})';
    },
  );
}

bool _pathLooksMarkdownFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.md') || lower.endsWith('.markdown');
}

bool _pathLooksHtmlFile(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.htm');
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

/// OpenRouter 等会下发加密的 `[REDACTED]` 推理片段；与 OpenCode TUI 一致去掉后再展示。
String _sanitizeReasoningText(String raw) {
  return raw.replaceAll('[REDACTED]', '').trim();
}

int _bundleCompletionMs(SessionMessageBundle b) {
  var maxMs = b.message.createdAt;
  for (final p in b.parts) {
    if (p.createdAt > maxMs) maxMs = p.createdAt;
  }
  return maxMs;
}

/// 与 OpenCode `SessionTurn.turnDurationMs` 一致：从本轮用户消息到各 assistant 完成时刻的最大值。
int? _turnDurationMsForAssistantBundle(AppState state, int bundleIdx) {
  if (bundleIdx < 0 || bundleIdx >= state.messages.length) return null;
  final target = state.messages[bundleIdx];
  if (target.message.role != SessionRole.assistant) return null;

  var userIdx = -1;
  for (var i = bundleIdx; i >= 0; i--) {
    if (state.messages[i].message.role == SessionRole.user) {
      userIdx = i;
      break;
    }
  }
  if (userIdx < 0) return null;

  if (state.isBusy &&
      state.messages.isNotEmpty &&
      state.messages.last.message.role == SessionRole.assistant) {
    var lastTurnUser = -1;
    for (var i = state.messages.length - 1; i >= 0; i--) {
      if (state.messages[i].message.role == SessionRole.user) {
        lastTurnUser = i;
        break;
      }
    }
    if (bundleIdx > lastTurnUser) return null;
  }

  final startMs = state.messages[userIdx].message.createdAt;
  var endMs = target.message.createdAt;
  for (var j = userIdx + 1; j < state.messages.length; j++) {
    if (state.messages[j].message.role == SessionRole.user) break;
    if (state.messages[j].message.role == SessionRole.assistant) {
      final c = _bundleCompletionMs(state.messages[j]);
      if (c > endMs) endMs = c;
    }
  }
  final ms = endMs - startMs;
  return ms >= 0 ? ms : null;
}

String? _formatTurnDurationLabel(BuildContext context, int ms) {
  if (ms < 0) return null;
  final totalSec = (ms / 1000).round();
  if (totalSec < 60) {
    return l(context, '$totalSec 秒', '${totalSec}s');
  }
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return l(context, '$m 分 $s 秒', '${m}m ${s}s');
}

/// OpenCode `TextPartDisplay` 的 `meta()`：`Agent · model · duration · interrupted`。
String? _assistantReplyFooterMeta(
  BuildContext context,
  MessageInfo message,
  int? turnDurationMs,
) {
  if (message.role != SessionRole.assistant) return null;
  final agent = message.agent.trim();
  final agentLabel = agent.isEmpty
      ? ''
      : '${agent[0].toUpperCase()}${agent.substring(1)}';
  final model = (message.model ?? '').trim();
  final durLabel = turnDurationMs != null
      ? _formatTurnDurationLabel(context, turnDurationMs)
      : null;
  final interruptedLabel =
      (message.error != null && message.error!.trim().isNotEmpty)
          ? l(context, '已中断', 'Interrupted')
          : '';
  final parts = <String>[
    if (agentLabel.isNotEmpty) agentLabel,
    if (model.isNotEmpty) model,
    if (durLabel != null && durLabel.isNotEmpty) durLabel,
    if (interruptedLabel.isNotEmpty) interruptedLabel,
  ];
  if (parts.isEmpty) return null;
  return parts.join(' \u00B7 ');
}

/// 桌面弱色 Markdown + 分享页式「思考」标题与 `ResultsButton` 折叠详情；`TEXT_RENDER_THROTTLE_MS = 100`。
class _ReasoningPartTile extends StatefulWidget {
  const _ReasoningPartTile({
    required this.text,
    required this.streaming,
    this.workspace,
    this.controller,
    this.onInsertPromptReference,
    this.onSendPromptReference,
  });

  final String text;
  final bool streaming;
  final WorkspaceInfo? workspace;
  final AppController? controller;
  final ValueChanged<String>? onInsertPromptReference;
  final PromptReferenceAction? onSendPromptReference;

  @override
  State<_ReasoningPartTile> createState() => _ReasoningPartTileState();
}

class _ReasoningPartTileState extends State<_ReasoningPartTile> {
  static const int _throttleMs = 100;

  String _displayed = '';
  Timer? _pending;
  int _lastFlush = 0;
  /// 对齐 OpenCode 分享页 `ResultsButton`：完成后默认折叠。
  bool _detailsOpen = false;

  @override
  void initState() {
    super.initState();
    // 与 OpenCode `createThrottledValue` 一致：`last` 初值为 0，首帧可立即显示。
    _lastFlush = 0;
    _displayed = _sanitizeReasoningText(widget.text);
    if (widget.streaming) {
      _detailsOpen = true;
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  void _flushThrottled() {
    final sanitized = _sanitizeReasoningText(widget.text);
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = _throttleMs - (now - _lastFlush);
    if (remaining <= 0) {
      _pending?.cancel();
      _pending = null;
      _lastFlush = now;
      if (_displayed != sanitized) setState(() => _displayed = sanitized);
      return;
    }
    _pending?.cancel();
    _pending = Timer(Duration(milliseconds: remaining), () {
      if (!mounted) return;
      _pending = null;
      _lastFlush = DateTime.now().millisecondsSinceEpoch;
      final s = _sanitizeReasoningText(widget.text);
      if (_displayed != s) setState(() => _displayed = s);
    });
  }

  @override
  void didUpdateWidget(covariant _ReasoningPartTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.streaming && widget.streaming) {
      _detailsOpen = true;
    }
    if (oldWidget.streaming && !widget.streaming) {
      _detailsOpen = false;
      _pending?.cancel();
      _pending = null;
      _lastFlush = DateTime.now().millisecondsSinceEpoch;
      final s = _sanitizeReasoningText(widget.text);
      if (_displayed != s) setState(() => _displayed = s);
    } else if (oldWidget.text != widget.text) {
      if (widget.streaming) {
        _flushThrottled();
      } else {
        _pending?.cancel();
        _pending = null;
        _lastFlush = DateTime.now().millisecondsSinceEpoch;
        final s = _sanitizeReasoningText(widget.text);
        if (_displayed != s) setState(() => _displayed = s);
      }
    }
  }

  Widget _reasoningMarkdown(BuildContext context, String normalized) {
    const weak = kOcMuted;
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
        p: const TextStyle(
          fontSize: 15,
          height: 1.5,
          color: weak,
          fontStyle: FontStyle.normal,
        ),
        a: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: kOcAccent.withOpacity(0.85),
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w500,
        ),
        strong: const TextStyle(
          fontWeight: FontWeight.w700,
          color: weak,
        ),
        em: const TextStyle(
          fontStyle: FontStyle.italic,
          color: weak,
        ),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.45,
          color: weak.withOpacity(0.92),
          backgroundColor: const Color(0xFFF4F4F5),
        ),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(10),
          border: const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          color: const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(10),
          border: const Border(
            left: BorderSide(color: kOcBorder, width: 3),
          ),
        ),
        blockquotePadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        listIndent: 22,
        listBullet: const TextStyle(fontSize: 14, height: 1.45, color: weak),
        h1: const TextStyle(
          fontSize: 21,
          height: 1.28,
          fontWeight: FontWeight.w700,
          color: weak,
        ),
        h2: const TextStyle(
          fontSize: 18,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: weak,
        ),
        h3: const TextStyle(
          fontSize: 16,
          height: 1.32,
          fontWeight: FontWeight.w700,
          color: weak,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.black.withOpacity(0.08)),
          ),
        ),
      ),
      onTapLink: (_, href, __) {
        if (href == null || href.isEmpty) return;
        if (href.startsWith('fileref:')) {
          final enc = href.substring('fileref:'.length);
          final path = Uri.decodeComponent(enc);
          final ws = widget.workspace;
          final ctrl = widget.controller;
          if (ws != null && ctrl != null && path.isNotEmpty) {
            _openFilePreview(
              context,
              controller: ctrl,
              workspace: ws,
              path: path,
              onInsertPromptReference: widget.onInsertPromptReference,
              onSendPromptReference: widget.onSendPromptReference,
            );
          }
          return;
        }
        _showInfo(
          context,
          l(context, '链接暂未接入外部打开: $href',
              'External link opening is not wired yet: $href'),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_displayed.isEmpty) {
      return const SizedBox.shrink();
    }
    final withLinks = _injectFileRefWikiLinks(_displayed);
    final normalized = widget.streaming
        ? _normalizeStreamingMarkdown(withLinks)
        : withLinks;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l(context, '思考', 'Thinking'),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.3,
              color: Colors.black87,
            ),
          ),
          if (widget.streaming) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _reasoningMarkdown(context, normalized),
            ),
          ] else ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setState(() => _detailsOpen = !_detailsOpen),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _detailsOpen
                          ? l(context, '隐藏详情', 'Hide details')
                          : l(context, '显示详情', 'Show details'),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: kOcAccent,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _detailsOpen ? Icons.expand_less : Icons.chevron_right,
                      size: 18,
                      color: kOcAccent,
                    ),
                  ],
                ),
              ),
            ),
            if (_detailsOpen)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _reasoningMarkdown(context, normalized),
              ),
          ],
        ],
      ),
    );
  }
}

class _PartTile extends StatelessWidget {
  const _PartTile({
    required this.part,
    required this.message,
    required this.controller,
    required this.workspace,
    required this.serverUri,
    this.streamAssistantContent = false,
    this.turnDurationMs,
    this.showAssistantTextMeta = false,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final MessagePart part;
  final MessageInfo message;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final Uri? serverUri;
  final bool streamAssistantContent;
  final int? turnDurationMs;
  final bool showAssistantTextMeta;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    switch (part.type) {
      case PartType.stepStart:
        // OpenCode 桌面时间线无独立 step_start 卡片；忙状态由底部指示与推理/正文体现。
        return const SizedBox.shrink();
      case PartType.reasoning:
        final text = part.data['text'] as String? ?? '';
        return _ReasoningPartTile(
          text: text,
          streaming: streamAssistantContent,
          workspace: workspace,
          controller: controller,
          onInsertPromptReference: onInsertPromptReference,
          onSendPromptReference: onSendPromptReference,
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
          final footerMeta = showAssistantTextMeta &&
                  message.role == SessionRole.assistant
              ? _assistantReplyFooterMeta(
                  context,
                  message,
                  turnDurationMs,
                )
              : null;
          return _StreamingMarkdownText(
            text: text,
            workspace: workspace,
            controller: controller,
            onInsertPromptReference: onInsertPromptReference,
            onSendPromptReference: onSendPromptReference,
            footerMeta: footerMeta,
            showResponseCopy: showAssistantTextMeta &&
                message.role == SessionRole.assistant,
          );
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
        if (toolName == 'todowrite') {
          return _TodoWriteToolPart(
            toolStatus: toolStatus,
            todos: _resolveTodoWriteTodos(toolState),
          );
        }
        if (toolName == 'fileref') {
          final metadata =
              Map<String, dynamic>.from(toolState['metadata'] as Map? ?? const {});
          final input = Map<String, dynamic>.from(toolState['input'] as Map? ?? const {});
          List<Map<String, dynamic>> refs;
          final metaRefs = metadata['refs'];
          if (metaRefs is List) {
            refs = metaRefs
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else {
            final ir = input['refs'];
            refs = ir is List
                ? ir
                    .whereType<Map>()
                    .map((e) => Map<String, dynamic>.from(e))
                    .toList()
                : <Map<String, dynamic>>[];
          }
          return _FileRefToolPart(
            toolStatus: toolStatus,
            refs: refs,
            controller: controller,
            workspace: workspace,
            onInsertPromptReference: onInsertPromptReference,
            onSendPromptReference: onSendPromptReference,
          );
        }
        if (toolName == 'question' && toolStatus != 'error') {
          final questions = _resolveQuestionToolQuestions(toolState);
          if (questions.isEmpty) {
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
          }
          return _QuestionToolPart(
            toolStatus: toolStatus,
            questions: questions,
            answers: _resolveQuestionToolAnswers(toolState),
          );
        }
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

/// OpenCode 与 `message-part.tsx` 一致：`metadata.todos` 优先，否则回退 `state.input.todos`。
List<Map<String, dynamic>> _resolveTodoWriteTodos(
    Map<String, dynamic> toolState) {
  final metadata = toolState['metadata'] as Map?;
  final metaTodos = metadata?['todos'];
  if (metaTodos is List) {
    return metaTodos
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  final input = toolState['input'] as Map?;
  final inputTodos = input?['todos'];
  if (inputTodos is List) {
    return inputTodos
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
  return [];
}

/// OpenCode `message-part.tsx`：`input.questions` 始终作为题干来源。
List<Map<String, dynamic>> _resolveQuestionToolQuestions(
    Map<String, dynamic> toolState) {
  final input = toolState['input'] as Map?;
  final raw = input?['questions'];
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

/// `metadata.answers`：与题目顺序对应的标签数组列表。
List<List<String>> _resolveQuestionToolAnswers(
    Map<String, dynamic> toolState) {
  final metadata = toolState['metadata'] as Map?;
  final raw = metadata?['answers'];
  if (raw is! List) return [];
  final out = <List<String>>[];
  for (final e in raw) {
    if (e is List) {
      out.add(e.map((x) => x.toString()).toList());
    } else {
      out.add([]);
    }
  }
  return out;
}

/// `fileref` 工具：可点击路径，打开预览（.md / .html 支持排版视图）。
class _FileRefToolPart extends StatelessWidget {
  const _FileRefToolPart({
    required this.toolStatus,
    required this.refs,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final String toolStatus;
  final List<Map<String, dynamic>> refs;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final isRunning = toolStatus == 'running' || toolStatus == 'pending';
    final isError = toolStatus == 'error';
    final ws = workspace;

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
          Row(
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
                child: Text(
                  l(context, '文件引用', 'File references'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          if (refs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: refs.map((r) {
                final path = r['path'] as String? ?? '';
                final kind = (r['kind'] as String?) ?? 'modified';
                final exists = r['exists'] as bool? ?? true;
                final label = kind == 'created'
                    ? l(context, '新建', 'new')
                    : l(context, '修改', 'mod');
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: ws != null && path.isNotEmpty
                        ? () => _openFilePreview(
                              context,
                              controller: controller,
                              workspace: ws,
                              path: path,
                              onInsertPromptReference: onInsertPromptReference,
                              onSendPromptReference: onSendPromptReference,
                            )
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: exists
                            ? kOcSelectedFill
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: exists
                              ? kOcAccent.withOpacity(0.35)
                              : Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.insert_drive_file_outlined,
                            size: 14,
                            color: exists ? kOcAccent : Colors.orange.shade800,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              path,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.25,
                                color: kOcText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: kOcMuted.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// OpenCode 风格：用结构化 todos 展示只读勾选清单，而非原始 JSON output。
class _TodoWriteToolPart extends StatelessWidget {
  const _TodoWriteToolPart({
    required this.toolStatus,
    required this.todos,
  });

  final String toolStatus;
  final List<Map<String, dynamic>> todos;

  @override
  Widget build(BuildContext context) {
    final isRunning = toolStatus == 'running' || toolStatus == 'pending';
    final isError = toolStatus == 'error';
    final completed = todos
        .where((t) => (t['status'] as String?) == 'completed')
        .length;
    final total = todos.length;
    final ratioSubtitle = total > 0 ? '$completed/$total' : '';

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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                      l(context, '任务', 'Todos'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (ratioSubtitle.isNotEmpty ||
                        (isRunning && total == 0)) ...[
                      const SizedBox(height: 2),
                      Text(
                        isRunning && total == 0
                            ? l(context, '正在更新任务…', 'Updating todos…')
                            : ratioSubtitle,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Colors.black45, height: 1.2),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (todos.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...todos.map((t) => _todoWriteRow(context, t)),
          ],
        ],
      ),
    );
  }

  Widget _todoWriteRow(BuildContext context, Map<String, dynamic> t) {
    final status = t['status'] as String? ?? 'pending';
    final done = status == 'completed';
    final content = t['content'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: done,
              onChanged: null,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                content,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: done ? Colors.black38 : Colors.black87,
                  decoration:
                      done ? TextDecoration.lineThrough : TextDecoration.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// OpenCode `message-part.tsx` question 注册：`ui.tool.questions` + 副标题；有 answers 时展示 Q/A。
class _QuestionToolPart extends StatefulWidget {
  const _QuestionToolPart({
    required this.toolStatus,
    required this.questions,
    required this.answers,
  });

  final String toolStatus;
  final List<Map<String, dynamic>> questions;
  final List<List<String>> answers;

  @override
  State<_QuestionToolPart> createState() => _QuestionToolPartState();
}

class _QuestionToolPartState extends State<_QuestionToolPart> {
  bool? _expanded;

  bool _completed() => widget.answers.isNotEmpty;

  bool _defaultExpanded() {
    final isRunning =
        widget.toolStatus == 'running' || widget.toolStatus == 'pending';
    if (isRunning) return false;
    return _completed();
  }

  String _subtitle(BuildContext context) {
    final count = widget.questions.length;
    if (count == 0) return '';
    if (_completed()) {
      return l(context, '$count 已回答', '$count answered');
    }
    if (count == 1) {
      return l(context, '1 道题', '1 question');
    }
    return l(context, '$count 道题', '$count questions');
  }

  @override
  Widget build(BuildContext context) {
    final isRunning =
        widget.toolStatus == 'running' || widget.toolStatus == 'pending';
    final expanded = _expanded ?? _defaultExpanded();
    final completed = _completed();
    final noneLabel = l(context, '（无答案）', '(no answer)');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        color: isRunning
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
                const Icon(Icons.chat_bubble_outline_rounded,
                    size: 16, color: Colors.black45),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l(context, '问题', 'Questions'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                          color: Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_subtitle(context).isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(context),
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: Colors.black45, height: 1.2),
                        ),
                      ],
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
          if (expanded) ...[
            if (completed) ...[
              const SizedBox(height: 8),
              ...List.generate(widget.questions.length, (i) {
                final q = widget.questions[i];
                final text = q['question'] as String? ?? '';
                final ans = i < widget.answers.length
                    ? widget.answers[i]
                    : <String>[];
                final line = ans.isEmpty ? noneLabel : ans.join(', ');
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        line,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ] else if (isRunning) ...[
              const SizedBox(height: 8),
              Text(
                l(context, '等待你在面板中作答…', 'Waiting for your answers…'),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Colors.black45, height: 1.2),
              ),
            ],
          ],
        ],
      ),
    );
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
                  onPressed: () => _openWebPreview(
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
                onPressed: () => _openWebPreview(
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

Future<void> _openWebPreview(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String url,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => _WebPreviewSheet(
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
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          widget.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: l(context, '复制链接', 'Copy URL'),
            onPressed: () => _copyText(
              context,
              widget.url,
              l(context, '链接已复制', 'URL copied'),
            ),
            icon: const Icon(Icons.copy_all_outlined),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              widget.subtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: _panelDecoration(
                      background: Colors.white, radius: 16, elevated: false),
                  child: WebViewWidget(controller: _controller),
                ),
              ),
            ),
          ),
        ],
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
                                    ?.copyWith(color: Colors.black54),
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _sourceMode = false),
                                style: TextButton.styleFrom(
                                  foregroundColor: !_sourceMode
                                      ? kOcAccent
                                      : kOcMuted,
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
                                      ? kOcAccent
                                      : kOcMuted,
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
                                    background: Colors.white,
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
      selectable: true,
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
      ),
    );
  }
}

class _WorkspaceHtmlPreview extends StatefulWidget {
  const _WorkspaceHtmlPreview({required this.html});

  final String html;

  @override
  State<_WorkspaceHtmlPreview> createState() => _WorkspaceHtmlPreviewState();
}

class _WorkspaceHtmlPreviewState extends State<_WorkspaceHtmlPreview> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(widget.html, baseUrl: 'about:blank');
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
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
