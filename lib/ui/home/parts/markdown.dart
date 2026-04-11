part of '../../home_page.dart';

class _StreamingMarkdownText extends StatefulWidget {
  const _StreamingMarkdownText({
    required this.text,
    this.streaming = false,
    this.workspace,
    this.controller,
    this.onInsertPromptReference,
    this.onSendPromptReference,
    this.footerMeta,
    this.showResponseCopy = false,
  });

  final String text;
  final bool streaming;
  final WorkspaceInfo? workspace;
  final AppController? controller;
  final ValueChanged<String>? onInsertPromptReference;
  final PromptReferenceAction? onSendPromptReference;
  final String? footerMeta;
  final bool showResponseCopy;

  @override
  State<_StreamingMarkdownText> createState() => _StreamingMarkdownTextState();
}

class _StreamingMarkdownTextState extends State<_StreamingMarkdownText> {
  String _stableText = '';
  Widget? _stableWidget;

  String _completeText = '';
  Widget? _completeWidget;
  int? _cachedThemeKey;

  void _invalidateCachedMarkdown() {
    _stableText = '';
    _stableWidget = null;
    _completeText = '';
    _completeWidget = null;
  }

  /// Find the last paragraph boundary (\n\n) that is NOT inside a code fence.
  int _safeSplitPoint(String text) {
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

  String _normalize(String raw) {
    return _normalizeStreamingMarkdown(raw);
  }

  MarkdownBody _md(BuildContext context, String data) {
    return MarkdownBody(
      data: data,
      selectable: false,
      softLineBreak: true,
      shrinkWrap: true,
      builders: {'pre': _MarkdownCodeBlockBuilder()},
      styleSheet: _kMarkdownStyle(context),
      onTapLink: (_, href, __) => _onMdLinkTap(context, href),
    );
  }

  void _onMdLinkTap(BuildContext context, String? href) {
    if (href == null || href.isEmpty) return;
    _showInfo(
      context,
      l(context, '链接暂未接入外部打开: $href',
          'External link opening is not wired yet: $href'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeKey = context.themeCacheKey;
    if (_cachedThemeKey != themeKey) {
      _cachedThemeKey = themeKey;
      _invalidateCachedMarkdown();
    }
    if (widget.streaming) {
      return _buildStreaming(context);
    }
    return _buildComplete(context);
  }

  Widget _buildStreaming(BuildContext context) {
    final text = widget.text;
    final splitAt = _safeSplitPoint(text);
    final stableText = splitAt > 0 ? text.substring(0, splitAt) : '';
    final activeText = text.substring(splitAt);

    if (stableText != _stableText) {
      _stableText = stableText;
      _stableWidget =
          stableText.isEmpty ? null : _md(context, _normalize(stableText));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _stableWidget ?? const SizedBox.shrink(),
        if (activeText.isNotEmpty) _md(context, _normalize(activeText)),
      ],
    );
  }

  Widget _buildComplete(BuildContext context) {
    final text = widget.text;
    if (text != _completeText || _completeWidget == null) {
      _completeText = text;
      _stableText = '';
      _stableWidget = null;
      _completeWidget = _md(context, _normalize(text));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _completeWidget!,
        if (widget.showResponseCopy)
          _AssistantTextFooter(
            plainText: widget.text,
            metaLine: widget.footerMeta,
          ),
      ],
    );
  }
}

MarkdownStyleSheet _kMarkdownStyle(BuildContext context) {
  final oc = context.oc;
  final dark = context.isDarkMode;
  final blockBackground =
      dark ? const Color(0xFF151821) : const Color(0xFFF8FAFC);
  final blockquoteBackground =
      dark ? const Color(0xFF161A24) : const Color(0xFFF6F8FB);
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    blockSpacing: 10,
    p: TextStyle(fontSize: 15, height: 1.5, color: oc.foreground),
    a: TextStyle(
      fontSize: 15,
      height: 1.5,
      color: oc.accent,
      decoration: TextDecoration.none,
      fontWeight: FontWeight.w500,
    ),
    strong: TextStyle(
      fontWeight: FontWeight.w700,
      color: oc.foreground,
    ),
    em: TextStyle(
      fontStyle: FontStyle.italic,
      color: oc.foreground,
    ),
    code: TextStyle(
      fontFamily: 'monospace',
      fontSize: 13,
      height: 1.45,
      color: dark ? const Color(0xFFE06C75) : Colors.red.shade900,
      backgroundColor: blockBackground,
    ),
    codeblockDecoration: BoxDecoration(
      color: blockBackground,
      borderRadius: BorderRadius.circular(10),
      border: Border.fromBorderSide(BorderSide(color: oc.borderColor)),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquoteDecoration: BoxDecoration(
      color: blockquoteBackground,
      borderRadius: BorderRadius.circular(10),
      border: Border(
        left: BorderSide(color: oc.border, width: 3),
      ),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    listIndent: 22,
    listBullet: TextStyle(fontSize: 14, height: 1.45, color: oc.foreground),
    h1: TextStyle(
      fontSize: 21,
      height: 1.28,
      fontWeight: FontWeight.w700,
      color: oc.foreground,
    ),
    h2: TextStyle(
      fontSize: 18,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: oc.foreground,
    ),
    h3: TextStyle(
      fontSize: 16,
      height: 1.32,
      fontWeight: FontWeight.w700,
      color: oc.foreground,
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: oc.progressBg),
      ),
    ),
  );
}

Map<String, TextStyle> _codeHighlightTheme(BuildContext context) =>
    context.isDarkMode ? atomOneDarkTheme : githubTheme;

class _MarkdownCodeBlockBuilder extends MarkdownElementBuilder {
  /// `flutter_markdown` block `pre` never calls [visitElementAfter] on custom
  /// builders; it only delegates [visitText] to the `pre` builder. Returning null
  /// there skips the default pre renderer and leaves `_inlines` non-empty →
  /// assert `_inlines.isEmpty` in `MarkdownBuilder.build`.
  String _fenceLanguage = '';

  @override
  void visitElementBefore(md.Element element) {
    if (element.tag == 'pre') {
      _fenceLanguage = '';
    } else if (element.tag == 'code') {
      final className = element.attributes['class'] ?? '';
      if (className.startsWith('language-')) {
        _fenceLanguage = _normalizeMarkdownLanguage(
          className.substring('language-'.length),
        );
      }
    }
  }

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    final code = text.text.replaceAll(RegExp(r'\n$'), '');
    if (code.isEmpty) {
      return const SizedBox.shrink();
    }
    final lang = _fenceLanguage;
    _fenceLanguage = '';
    return _MarkdownCodeBlock(
      code: code,
      language: lang,
      wrappedByMarkdownPre: true,
    );
  }
}

class _MarkdownCodeBlock extends StatelessWidget {
  const _MarkdownCodeBlock({
    required this.code,
    required this.language,
    this.wrappedByMarkdownPre = false,
  });

  final String code;
  final String language;

  /// When true, [MarkdownBody] already wraps `pre` in [MarkdownStyleSheet.codeblockDecoration].
  final bool wrappedByMarkdownPre;

  @override
  Widget build(BuildContext context) {
    final codeBackground =
        context.isDarkMode ? const Color(0xFF151821) : const Color(0xFFF8FAFC);
    final headerBackground =
        context.isDarkMode ? const Color(0xFF202431) : const Color(0xFFEFF3F8);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.of(context).size.width;
        final frameWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        final inner = SizedBox(
          width: frameWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                decoration: BoxDecoration(
                  color: headerBackground,
                  border: Border(
                    bottom: BorderSide(color: context.oc.borderColor),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.isDarkMode
                            ? const Color(0xFF2D3748)
                            : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        language.isEmpty ? 'text' : language,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 10.5,
                              color: context.oc.foreground,
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
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: frameWidth),
                  child: ColoredBox(
                    color: codeBackground,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: HighlightView(
                        code,
                        language: language,
                        theme: _codeHighlightTheme(context),
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        if (wrappedByMarkdownPre) {
          return inner;
        }
        return Container(
          width: frameWidth,
          decoration: BoxDecoration(
            color: codeBackground,
            borderRadius: BorderRadius.circular(10),
            border: Border.fromBorderSide(
                BorderSide(color: context.oc.borderColor)),
          ),
          child: inner,
        );
      },
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
