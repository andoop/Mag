part of '../../home_page.dart';

/// OpenRouter 等会下发加密的 `[REDACTED]` 推理片段；与 OpenCode TUI 一致去掉后再展示。
String _sanitizeReasoningText(String raw) {
  return raw.replaceAll('[REDACTED]', '').trim();
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
  bool _detailsOpen = false;

  // Stable-split caching for streaming markdown
  String _stableReasonText = '';
  Widget? _stableReasonWidget;

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

  int _reasoningSplitPoint(String text) {
    bool inFence = false;
    int lastSafe = 0;
    final len = text.length;
    int i = 0;
    while (i < len) {
      if (i == 0 || (i > 0 && text[i - 1] == '\n')) {
        if (i + 2 < len &&
            text[i] == '`' &&
            text[i + 1] == '`' &&
            text[i + 2] == '`') {
          inFence = !inFence;
        }
      }
      if (!inFence && text[i] == '\n' && i + 1 < len && text[i + 1] == '\n') {
        lastSafe = i + 2;
        i += 2;
        continue;
      }
      i++;
    }
    return lastSafe;
  }

  Widget _buildReasoningStreaming(BuildContext context) {
    final text = _displayed;
    final splitAt = _reasoningSplitPoint(text);
    final stableText = splitAt > 0 ? text.substring(0, splitAt) : '';
    final activeText = text.substring(splitAt);

    if (stableText != _stableReasonText) {
      _stableReasonText = stableText;
      _stableReasonWidget = stableText.isEmpty
          ? null
          : _reasoningMarkdown(
              context, _normalizeStreamingMarkdown(stableText));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _stableReasonWidget ?? const SizedBox.shrink(),
        if (activeText.isNotEmpty)
          _reasoningMarkdown(context, _normalizeStreamingMarkdown(activeText)),
      ],
    );
  }

  Widget _reasoningMarkdown(BuildContext context, String normalized) {
    final oc = context.oc;
    final weak = oc.muted;
    return MarkdownBody(
      data: normalized,
      selectable: false,
      softLineBreak: true,
      shrinkWrap: true,
      builders: {
        'pre': _MarkdownCodeBlockBuilder(),
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        blockSpacing: 10,
        p: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: weak,
          fontStyle: FontStyle.normal,
        ),
        a: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: oc.accent.withOpacity(0.85),
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w500,
        ),
        strong: TextStyle(
          fontWeight: FontWeight.w700,
          color: weak,
        ),
        em: TextStyle(
          fontStyle: FontStyle.italic,
          color: weak,
        ),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.45,
          color: weak.withOpacity(0.92),
          backgroundColor: oc.bgDeep,
        ),
        codeblockDecoration: BoxDecoration(
          color: oc.bgDeep,
          borderRadius: BorderRadius.circular(10),
          border: Border.fromBorderSide(BorderSide(color: oc.borderColor)),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          color: oc.bgDeep,
          borderRadius: BorderRadius.circular(10),
          border: Border(
            left: BorderSide(color: oc.border, width: 3),
          ),
        ),
        blockquotePadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        listIndent: 22,
        listBullet: TextStyle(fontSize: 14, height: 1.45, color: weak),
        h1: TextStyle(
          fontSize: 21,
          height: 1.28,
          fontWeight: FontWeight.w700,
          color: weak,
        ),
        h2: TextStyle(
          fontSize: 18,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: weak,
        ),
        h3: TextStyle(
          fontSize: 16,
          height: 1.32,
          fontWeight: FontWeight.w700,
          color: weak,
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: oc.progressBg),
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

  @override
  Widget build(BuildContext context) {
    if (_displayed.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l(context, '思考', 'Thinking'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.3,
              color: context.oc.foreground,
            ),
          ),
          if (widget.streaming) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _buildReasoningStreaming(context),
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
                            color: context.oc.accent,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _detailsOpen ? Icons.expand_less : Icons.chevron_right,
                      size: 18,
                      color: context.oc.accent,
                    ),
                  ],
                ),
              ),
            ),
            if (_detailsOpen)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _reasoningMarkdown(context, _displayed),
              ),
          ],
        ],
      ),
    );
  }
}
