part of '../home_page.dart';

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
        if (toolName == 'todowrite') {
          return _TodoWriteToolPart(
            toolStatus: toolStatus,
            todos: _resolveTodoWriteTodos(toolState),
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
