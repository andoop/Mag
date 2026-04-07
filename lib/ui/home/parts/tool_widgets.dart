part of '../../home_page.dart';

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

    final oc = context.oc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        color: isError
            ? (context.isDarkMode ? const Color(0xFF1F0A0A) : const Color(0xFFFFFBFB))
            : isRunning
                ? (context.isDarkMode ? const Color(0xFF1C1A0E) : const Color(0xFFFFFCF2))
                : oc.mutedPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: oc.softBorderColor),
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
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    color: oc.foreground,
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
                            ? oc.selectedFill
                            : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: exists
                              ? oc.accent.withOpacity(0.35)
                              : Colors.orange.shade200,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.insert_drive_file_outlined,
                            size: 14,
                            color: exists ? oc.accent : Colors.orange.shade800,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              path,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.25,
                                color: oc.text,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: oc.muted.withOpacity(0.9),
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

    final oc = context.oc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        color: isError
            ? (context.isDarkMode ? const Color(0xFF1F0A0A) : const Color(0xFFFFFBFB))
            : isRunning
                ? (context.isDarkMode ? const Color(0xFF1C1A0E) : const Color(0xFFFFFCF2))
                : oc.mutedPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: oc.softBorderColor),
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
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5,
                        color: oc.foreground,
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
                            ?.copyWith(color: oc.foregroundHint, height: 1.2),
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
    final oc = context.oc;
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
                  color: done ? oc.foregroundFaint : oc.foreground,
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

    final oc = context.oc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        color: isRunning
            ? (context.isDarkMode ? const Color(0xFF1C1A0E) : const Color(0xFFFFFCF2))
            : oc.mutedPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: oc.softBorderColor),
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
                Icon(Icons.chat_bubble_outline_rounded,
                    size: 16, color: oc.foregroundHint),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l(context, '问题', 'Questions'),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                          color: oc.foreground,
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
                              ?.copyWith(color: oc.foregroundHint, height: 1.2),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: oc.foregroundHint,
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
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: oc.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        line,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: oc.foregroundMuted,
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
                    ?.copyWith(color: oc.foregroundHint, height: 1.2),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

