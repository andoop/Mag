part of '../../home_page.dart';

/// OpenRouter 等会下发加密的 `[REDACTED]` 推理片段；与 OpenCode TUI 一致去掉后再展示。
String _sanitizeReasoningText(String raw) {
  return raw.replaceAll('[REDACTED]', '').trim();
}

const double _kReasoningDetailsMaxHeight = 340;

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
  String _displayed = '';
  Timer? _pending;
  int _lastFlush = 0;
  bool _detailsOpen = false;
  int? _thinkingStartedAtMs;
  int? _thinkingDurationSeconds;
  int? _cachedThemeKey;
  MarkdownStyleSheet? _cachedReasoningStyle;

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
      _thinkingStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  void _syncDisplayedReasoning(String text) {
    if (_displayed == text) return;
    setState(() => _displayed = text);
  }

  void _flushPaced() {
    final sanitized = _sanitizeReasoningText(widget.text);
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = _kStreamingTextRenderPaceMs - (now - _lastFlush);
    if (remaining <= 0) {
      _pending?.cancel();
      _pending = null;
      _lastFlush = now;
      if (!widget.streaming) {
        _syncDisplayedReasoning(sanitized);
        return;
      }
      if (!sanitized.startsWith(_displayed) ||
          sanitized.length <= _displayed.length) {
        _syncDisplayedReasoning(sanitized);
        return;
      }
      final end = _nextStreamingTextIndex(sanitized, _displayed.length);
      _syncDisplayedReasoning(sanitized.substring(0, end));
      if (end < sanitized.length) {
        _pending = Timer(
          const Duration(milliseconds: _kStreamingTextRenderPaceMs),
          () {
            if (!mounted) return;
            _pending = null;
            _flushPaced();
          },
        );
      }
      return;
    }
    _pending?.cancel();
    _pending = Timer(Duration(milliseconds: remaining), () {
      if (!mounted) return;
      _pending = null;
      _flushPaced();
    });
  }

  @override
  void didUpdateWidget(covariant _ReasoningPartTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.streaming && widget.streaming) {
      _thinkingStartedAtMs = DateTime.now().millisecondsSinceEpoch;
      _thinkingDurationSeconds = null;
    }
    if (oldWidget.streaming && !widget.streaming) {
      _pending?.cancel();
      _pending = null;
      _lastFlush = DateTime.now().millisecondsSinceEpoch;
      final startedAt = _thinkingStartedAtMs;
      if (startedAt != null) {
        final elapsedMs = _lastFlush - startedAt;
        _thinkingDurationSeconds = (elapsedMs / 1000).ceil().clamp(1, 999);
        _thinkingStartedAtMs = null;
      }
      final s = _sanitizeReasoningText(widget.text);
      if (_displayed != s) setState(() => _displayed = s);
    } else if (oldWidget.text != widget.text) {
      if (widget.streaming) {
        _flushPaced();
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
          _streamingTextTail(
            context,
            _normalizeStreamingMarkdown(activeText),
            color: context.oc.muted,
          ),
      ],
    );
  }

  Widget _reasoningMarkdown(BuildContext context, String normalized) {
    final oc = context.oc;
    final weak = oc.muted;
    final styleSheet = _cachedReasoningStyle ??=
        MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
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
    );
    return MarkdownBody(
      data: normalized,
      selectable: false,
      softLineBreak: true,
      shrinkWrap: true,
      builders: {
        'pre': _MarkdownCodeBlockBuilder(),
      },
      styleSheet: styleSheet,
      onTapLink: (_, href, __) => _handleMarkdownLinkTap(context, href),
    );
  }

  String _completedThinkingLabel(BuildContext context) {
    final seconds = _thinkingDurationSeconds;
    if (seconds == null) {
      return l(context, '已完成思考', 'Thought completed');
    }
    return l(context, '已思考 ${seconds}s', 'Thought for ${seconds}s');
  }

  Widget _buildReasoningTrigger(BuildContext context, bool hasReasoning) {
    final oc = context.oc;
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: oc.foregroundMuted,
          fontWeight: FontWeight.w600,
        );
    return InkWell(
      onTap: hasReasoning
          ? () => setState(() => _detailsOpen = !_detailsOpen)
          : null,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology_alt_outlined,
              size: 16,
              color: oc.foregroundMuted,
            ),
            const SizedBox(width: 6),
            if (widget.streaming)
              _ThinkingShimmerText(
                text: l(context, '正在思考...', 'Thinking...'),
                style: labelStyle,
              )
            else
              Text(
                _completedThinkingLabel(context),
                style: labelStyle,
              ),
            if (hasReasoning) ...[
              const SizedBox(width: 4),
              Icon(
                _detailsOpen ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: oc.foregroundMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeKey = context.themeCacheKey;
    if (_cachedThemeKey != themeKey || _cachedReasoningStyle == null) {
      _cachedThemeKey = themeKey;
      _cachedReasoningStyle = null;
    }
    final hasReasoning = _displayed.isNotEmpty;
    if (!hasReasoning && !widget.streaming) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildReasoningTrigger(context, hasReasoning),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: _detailsOpen && hasReasoning
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _ReasoningDetailsPanel(
                      onCollapse: () => setState(() => _detailsOpen = false),
                      child: widget.streaming
                          ? _buildReasoningStreaming(context)
                          : _reasoningMarkdown(context, _displayed),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _ReasoningDetailsPanel extends StatefulWidget {
  const _ReasoningDetailsPanel({
    required this.child,
    required this.onCollapse,
  });

  final Widget child;
  final VoidCallback onCollapse;

  @override
  State<_ReasoningDetailsPanel> createState() => _ReasoningDetailsPanelState();
}

class _ReasoningDetailsPanelState extends State<_ReasoningDetailsPanel> {
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: _kReasoningDetailsMaxHeight),
      decoration: BoxDecoration(
        color: oc.bgDeep.withOpacity(0.62),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: oc.softBorderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l(context, '思考过程', 'Reasoning details'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: oc.foregroundMuted,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                InkWell(
                  onTap: widget.onCollapse,
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.keyboard_arrow_up_rounded,
                          size: 16,
                          color: oc.foregroundMuted,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          l(context, '收起', 'Collapse'),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: oc.foregroundMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: oc.softBorderColor),
          Flexible(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollController,
                primary: false,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingShimmerText extends StatefulWidget {
  const _ThinkingShimmerText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  State<_ThinkingShimmerText> createState() => _ThinkingShimmerTextState();
}

class _ThinkingShimmerTextState extends State<_ThinkingShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.style?.color ?? context.oc.foregroundMuted;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final begin = -1.0 + _controller.value * 2.0;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(begin, 0),
              end: Alignment(begin + 1.0, 0),
              colors: [
                baseColor.withOpacity(0.58),
                context.oc.foreground,
                baseColor.withOpacity(0.58),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: Text(widget.text, style: widget.style),
    );
  }
}
