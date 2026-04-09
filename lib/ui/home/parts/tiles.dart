part of '../../home_page.dart';

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
    final oc = context.oc;
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
        final reason = (part.data['reason'] as String?) ?? 'stop';
        final isMaxSteps = reason == 'max_steps';
        final tokenMap =
            Map<String, dynamic>.from(part.data['tokens'] as Map? ?? const {});
        final cacheMap =
            Map<String, dynamic>.from(tokenMap['cache'] as Map? ?? const {});
        final detailParts = <String>[
          isMaxSteps
              ? l(context, '已达最大步数', 'Max steps reached')
              : reason,
          if (((tokenMap['input'] as num?)?.toInt() ?? 0) > 0)
            '${l(context, '输入', 'Input')} ${formatTokenCount((tokenMap['input'] as num?)?.toInt() ?? 0)}',
          if (((tokenMap['output'] as num?)?.toInt() ?? 0) > 0)
            '${l(context, '输出', 'Output')} ${formatTokenCount((tokenMap['output'] as num?)?.toInt() ?? 0)}',
          if (((cacheMap['read'] as num?)?.toInt() ?? 0) > 0)
            '${l(context, '缓存读', 'Cache read')} ${formatTokenCount((cacheMap['read'] as num?)?.toInt() ?? 0)}',
        ];
        return _StatusPartTile(
          label: isMaxSteps
              ? l(context, '⚠️ 步数上限', '⚠️ Step Limit')
              : l(context, '步骤完成', 'Step Complete'),
          detail: detailParts.join(' · '),
          color: isMaxSteps
              ? (context.isDarkMode ? const Color(0xFF422006) : const Color(0xFFFEF3C7))
              : oc.userBubble,
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
            streaming: streamAssistantContent,
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
          decoration: _panelDecoration(context,
              background: context.oc.composerOptionBg, radius: 14, elevated: false),
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
        final rawInput =
            Map<String, dynamic>.from(toolState['input'] as Map? ?? const {});
        final rawOutput = toolState['output'] as String?;
        final attachments = (toolState['attachments'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        final toolName = part.data['tool'] as String? ?? '';
        final toolTitle = toolState['title'] as String?;
        final toolStatus = toolState['status'] as String? ?? 'pending';
        final callId = part.data['callID'] as String?;
        if (toolName == 'todowrite') {
          return _TodoWriteToolPart(
            toolStatus: toolStatus,
            todos: _resolveTodoWriteTodos(toolState),
            rawInput: rawInput,
            rawOutput: rawOutput,
            callId: callId,
          );
        }
        if (toolName == 'fileref') {
          final metadata =
              Map<String, dynamic>.from(toolState['metadata'] as Map? ?? const {});
          List<Map<String, dynamic>> refs;
          final metaRefs = metadata['refs'];
          if (metaRefs is List) {
            refs = metaRefs
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          } else {
            final ir = rawInput['refs'];
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
            rawInput: rawInput,
            rawOutput: rawOutput,
            callId: callId,
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
              callId: callId,
              rawInput: rawInput,
              rawOutput: rawOutput,
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
            rawInput: rawInput,
            rawOutput: rawOutput,
            callId: callId,
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
          callId: callId,
          rawInput: rawInput,
          rawOutput: rawOutput,
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

class _ToolPartTile extends StatefulWidget {
  const _ToolPartTile({
    required this.toolName,
    required this.toolTitle,
    required this.status,
    required this.callId,
    required this.rawInput,
    required this.rawOutput,
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
  final String? callId;
  final JsonMap rawInput;
  final String? rawOutput;
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

  String? _diffStatSuffix() {
    if (widget.status == 'error') return null;
    const names = {'edit', 'write', 'apply_patch'};
    if (!names.contains(widget.toolName)) return null;
    for (final a in widget.attachments) {
      if (a['type'] != 'diff_preview') continue;
      final add = a['additions'] as int?;
      final del = a['deletions'] as int?;
      if (add == null || del == null) return null;
      if (add == 0 && del == 0) return null;
      return '+$add −$del';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.status == 'running' || widget.status == 'pending';
    final isError = widget.status == 'error';
    final label = widget.toolTitle ?? widget.toolName;
    final expanded = _expanded ?? _defaultExpanded();
    final collapsedSummary = widget.output?.split('\n').first.trim();
    final diffSuffix = _diffStatSuffix();
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
                        '${widget.toolName} · ${_toolStatusLabel(context, widget.status)}'
                        '${diffSuffix != null ? ' · $diffSuffix' : ''}',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                          color: oc.foreground,
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
                            ?.copyWith(color: oc.foregroundHint, height: 1.2),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _CompactIconButton(
                  icon: Icons.data_object_outlined,
                  tooltip: l(context, '查看原始调用', 'View raw call'),
                  small: true,
                  quiet: true,
                  onPressed: () => _openRawToolCallSheet(
                    context,
                    toolName: widget.toolName,
                    callId: widget.callId,
                    rawInput: widget.rawInput,
                    rawOutput: widget.rawOutput,
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
          if (expanded &&
              widget.output != null &&
              widget.output!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: oc.shadow,
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
        border: Border.all(color: context.oc.softBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.oc.foregroundMuted,
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

