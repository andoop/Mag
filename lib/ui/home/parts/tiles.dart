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
          isMaxSteps ? l(context, '已达最大步数', 'Max steps reached') : reason,
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
              ? (context.isDarkMode
                  ? const Color(0xFF422006)
                  : const Color(0xFFFEF3C7))
              : oc.userBubble,
        );
      case PartType.compaction:
        return _CompactionPartTile(
          summary: part.data['summary'] as String? ?? '',
          createdAt: message.createdAt,
          workspace: workspace,
          controller: controller,
          onInsertPromptReference: onInsertPromptReference,
          onSendPromptReference: onSendPromptReference,
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
          final footerMeta =
              showAssistantTextMeta && message.role == SessionRole.assistant
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
            showResponseCopy:
                showAssistantTextMeta && message.role == SessionRole.assistant,
          );
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: _panelDecoration(context,
              background: context.oc.composerOptionBg,
              radius: 14,
              elevated: false),
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
        final rawDisplayOutput = toolState['displayOutput'] as String?;
        final metadata = Map<String, dynamic>.from(
            toolState['metadata'] as Map? ?? const {});
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
              rawInputText: toolState['raw'] as String?,
              rawOutput: rawOutput,
              hasDisplayOutput: rawDisplayOutput != null,
              metadata: metadata,
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
          rawInputText: toolState['raw'] as String?,
          rawOutput: rawOutput,
          hasDisplayOutput: rawDisplayOutput != null,
          metadata: metadata,
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
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

/// `metadata.answers`：与题目顺序对应的标签数组列表。
List<List<String>> _resolveQuestionToolAnswers(Map<String, dynamic> toolState) {
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
    required this.rawInputText,
    required this.rawOutput,
    required this.hasDisplayOutput,
    required this.metadata,
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
  final String? rawInputText;
  final String? rawOutput;
  final bool hasDisplayOutput;
  final Map<String, dynamic> metadata;
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

  Map<String, dynamic>? _firstAttachmentOfType(String type) {
    for (final item in widget.attachments) {
      if (item['type'] == type) return item;
    }
    return null;
  }

  String _entryKindLabel(BuildContext context, bool isDirectory) {
    return isDirectory
        ? l(context, '目录', 'directory')
        : l(context, '文件', 'file');
  }

  String? _localizedRunningPhaseSummary(BuildContext context) {
    final phase = (widget.metadata['phase'] as String?) ?? '';
    if (phase.isEmpty) return null;
    final path = (widget.metadata['path'] as String?) ??
        (widget.rawInput['filePath'] as String?) ??
        (widget.rawInput['path'] as String?) ??
        (widget.rawInput['url'] as String?) ??
        (widget.rawInput['pattern'] as String?);
    final newPath = (widget.metadata['newPath'] as String?) ??
        (widget.rawInput['toPath'] as String?) ??
        (widget.rawInput['newName'] as String?);
    final isDirectory = widget.metadata['isDirectory'] == true;
    final objectKind = _entryKindLabel(context, isDirectory);
    switch (phase) {
      case 'reading':
        if (path == null || path.isEmpty) return null;
        return l(context, '正在读取 $path', 'Reading $path');
      case 'fetching':
        if (path == null || path.isEmpty) return null;
        return l(context, '正在抓取 $path', 'Fetching $path');
      case 'opening':
        if (path == null || path.isEmpty) return null;
        return l(context, '正在打开 $path', 'Opening $path');
      case 'scanning':
        if (widget.toolName == 'list') {
          final target = path == null || path.isEmpty ? '.' : path;
          return l(context, '正在列出 $target', 'Listing $target');
        }
        if (path == null || path.isEmpty) return null;
        return l(context, '正在搜索 $path', 'Searching $path');
      case 'inspecting':
        final target = path == null || path.isEmpty ? '.' : path;
        return l(context, '正在查看信息 $target', 'Inspecting $target');
      case 'awaiting_approval':
        if (widget.toolName == 'apply_patch') {
          return l(context, '等待批准应用补丁', 'Waiting approval to apply patch');
        }
        if (widget.toolName == 'delete' && path != null && path.isNotEmpty) {
          return l(context, '等待批准删除$objectKind $path',
              'Waiting approval to delete $objectKind $path');
        }
        if ((widget.toolName == 'rename' ||
                widget.toolName == 'move' ||
                widget.toolName == 'copy') &&
            path != null &&
            path.isNotEmpty &&
            newPath != null &&
            newPath.isNotEmpty) {
          final verbZh = widget.toolName == 'rename'
              ? '重命名'
              : widget.toolName == 'move'
                  ? '移动'
                  : '复制';
          final verbEn = widget.toolName == 'rename'
              ? 'rename'
              : widget.toolName == 'move'
                  ? 'move'
                  : 'copy';
          return l(context, '等待批准$verbZh$objectKind $path -> $newPath',
              'Waiting approval to $verbEn $objectKind $path -> $newPath');
        }
        if (path == null || path.isEmpty) {
          return l(context, '等待批准执行', 'Waiting for approval');
        }
        return l(context, '等待批准修改 $path', 'Waiting approval for $path');
      case 'applying':
        if (widget.toolName == 'apply_patch') {
          return l(context, '正在应用补丁', 'Applying patch');
        }
        if (path == null || path.isEmpty) {
          return l(context, '正在应用更改', 'Applying changes');
        }
        return l(context, '正在应用更改 $path', 'Applying changes to $path');
      case 'awaiting_input':
        return l(context, '等待用户输入', 'Waiting for user input');
      case 'processing':
        return l(context, '正在整理结果', 'Processing results');
      case 'preparing':
        if (widget.toolName == 'apply_patch') {
          return l(context, '正在准备补丁预览', 'Preparing patch preview');
        }
        if (path == null || path.isEmpty) {
          return l(context, '正在准备更改', 'Preparing changes');
        }
        return l(context, '正在准备更改 $path', 'Preparing changes for $path');
      case 'executing':
        final command =
            ((widget.metadata['command'] as String?) ?? widget.toolName).trim();
        return l(context, '正在执行 $command', 'Running $command');
      default:
        return null;
    }
  }

  String? _localizedFileOpSummary(BuildContext context) {
    final isDirectory = widget.metadata['isDirectory'] == true;
    final objectKind = _entryKindLabel(context, isDirectory);
    final isRunning = widget.status == 'running' || widget.status == 'pending';
    final path = (widget.metadata['path'] as String?) ??
        (widget.rawInput['filePath'] as String?) ??
        (widget.rawInput['path'] as String?) ??
        (widget.rawInput['toPath'] as String?);
    final from = (widget.metadata['from'] as String?) ??
        (widget.rawInput['fromPath'] as String?) ??
        (widget.rawInput['filePath'] as String?) ??
        (widget.rawInput['path'] as String?);
    switch (widget.toolName) {
      case 'delete':
        if (path == null || path.isEmpty) return null;
        if (isRunning) {
          return l(context, '准备删除$objectKind $path',
              'Preparing to delete $objectKind $path');
        }
        return l(context, '已删除$objectKind $path', 'Deleted $objectKind $path');
      case 'rename':
        if (from == null || from.isEmpty || path == null || path.isEmpty) {
          return null;
        }
        if (isRunning) {
          return l(context, '准备重命名$objectKind $from -> $path',
              'Preparing to rename $objectKind $from -> $path');
        }
        return l(context, '已重命名$objectKind $from -> $path',
            'Renamed $objectKind $from -> $path');
      case 'move':
        if (from == null || from.isEmpty || path == null || path.isEmpty) {
          return null;
        }
        if (isRunning) {
          return l(context, '准备移动$objectKind $from -> $path',
              'Preparing to move $objectKind $from -> $path');
        }
        return l(context, '已移动$objectKind $from -> $path',
            'Moved $objectKind $from -> $path');
      case 'copy':
        if (from == null || from.isEmpty || path == null || path.isEmpty) {
          return null;
        }
        if (isRunning) {
          return l(context, '准备复制$objectKind $from -> $path',
              'Preparing to copy $objectKind $from -> $path');
        }
        return l(context, '已复制$objectKind $from -> $path',
            'Copied $objectKind $from -> $path');
      default:
        return null;
    }
  }

  String? _localizedToolSummary(BuildContext context) {
    final isRunning = widget.status == 'running' || widget.status == 'pending';
    if (isRunning) {
      final phaseSummary = _localizedRunningPhaseSummary(context);
      if (phaseSummary != null) return phaseSummary;
    }
    final fileOpSummary = _localizedFileOpSummary(context);
    if (fileOpSummary != null) return fileOpSummary;

    switch (widget.toolName) {
      case 'read':
        final path = (widget.metadata['path'] as String?) ??
            (widget.rawInput['filePath'] as String?) ??
            (widget.rawInput['path'] as String?) ??
            '.';
        if (isRunning) {
          return l(context, '正在读取 $path', 'Reading $path');
        }
        final kind = widget.metadata['kind'] as String?;
        if (kind == 'directory') {
          return l(context, '已列出目录 $path', 'Listed directory $path');
        }
        if (kind == 'attachment') {
          return l(context, '已读取附件 $path', 'Read attachment $path');
        }
        if (kind == 'file') {
          final preview = _firstAttachmentOfType('text_preview');
          final startLine = preview?['startLine'] as int?;
          final endLine = preview?['endLine'] as int?;
          final lineCount = preview?['lineCount'] as int? ??
              widget.metadata['lineCount'] as int?;
          if (startLine != null && endLine != null && lineCount != null) {
            if (lineCount == 0) {
              return l(context, '已读取文件 $path · 空文件', 'Read $path · empty file');
            }
            return l(
                context,
                '已读取文件 $path · 第 $startLine-$endLine 行 / 共 $lineCount 行',
                'Read $path · lines $startLine-$endLine / $lineCount');
          }
          return l(context, '已读取文件 $path', 'Read file $path');
        }
        return null;
      case 'write':
        final path = (widget.metadata['path'] as String?) ??
            (widget.rawInput['filePath'] as String?) ??
            (widget.rawInput['path'] as String?);
        if (path == null || path.isEmpty) return null;
        if (isRunning) {
          return l(context, '准备写入文件 $path', 'Preparing write to $path');
        }
        return l(context, '已写入文件 $path', 'Wrote file $path');
      case 'edit':
        final path = (widget.metadata['path'] as String?) ??
            (widget.rawInput['filePath'] as String?) ??
            (widget.rawInput['path'] as String?);
        if (path == null || path.isEmpty) return null;
        if (isRunning) {
          return l(context, '准备更新文件 $path', 'Preparing edit for $path');
        }
        return l(context, '已更新文件 $path', 'Updated file $path');
      case 'apply_patch':
        final files = widget.metadata['files'];
        final count = files is List ? files.length : null;
        if (isRunning) {
          return l(context, '准备应用补丁', 'Preparing patch');
        }
        if (count == null) return l(context, '已应用补丁', 'Applied patch');
        return l(
            context, '已应用补丁 · $count 个文件', 'Applied patch · $count file(s)');
      case 'grep':
        final pattern = (widget.rawInput['pattern'] as String?) ?? '';
        if (isRunning) {
          return l(context, '正在搜索 $pattern', 'Searching $pattern');
        }
        final count = (widget.metadata['count'] as int?) ??
            (widget.metadata['matches'] as int?) ??
            0;
        final truncated = widget.metadata['truncated'] == true;
        if (count == 0) {
          return l(context, '搜索 $pattern · 0 个匹配', 'Grep $pattern · 0 matches');
        }
        return l(context, '搜索 $pattern · $count${truncated ? '+' : ''} 个匹配',
            'Grep $pattern · $count${truncated ? '+' : ''} matches');
      case 'list':
        final path = (widget.rawInput['path'] as String?)?.trim();
        final resolvedPath = (path == null || path.isEmpty) ? '.' : path;
        if (isRunning) {
          return l(context, '正在列出 $resolvedPath', 'Listing $resolvedPath');
        }
        final count = (widget.metadata['count'] as int?) ?? 0;
        final truncated = widget.metadata['truncated'] == true;
        return l(
            context,
            '已列出 $resolvedPath · $count${truncated ? '+' : ''} 个文件',
            'Listed $resolvedPath · $count${truncated ? '+' : ''} files');
      case 'glob':
        final pattern = (widget.rawInput['pattern'] as String?) ?? '*';
        if (isRunning) {
          return l(context, '正在通配搜索 $pattern', 'Searching glob $pattern');
        }
        final count = (widget.metadata['count'] as int?) ?? 0;
        final truncated = widget.metadata['truncated'] == true;
        return l(context, '通配搜索 $pattern · $count${truncated ? '+' : ''} 个匹配',
            'Glob $pattern · $count${truncated ? '+' : ''} matches');
      case 'stat':
        final path = (widget.metadata['path'] as String?) ??
            (widget.rawInput['filePath'] as String?) ??
            (widget.rawInput['path'] as String?) ??
            '.';
        if (isRunning) {
          return l(context, '正在查看信息 $path', 'Inspecting $path');
        }
        final isDirectory = widget.metadata['isDirectory'] == true;
        final kind = _entryKindLabel(context, isDirectory);
        return l(context, '查看$kind信息 $path', 'Stat $kind $path');
      case 'webfetch':
        final attachment = _firstAttachmentOfType('webpage');
        final url = (attachment?['url'] as String?) ??
            (widget.rawInput['url'] as String?);
        final statusCode = widget.metadata['statusCode'];
        final contentType = widget.metadata['contentType'];
        if (url == null || url.isEmpty) return null;
        if (isRunning) {
          return l(context, '正在抓取 $url', 'Fetching $url');
        }
        return l(context, '已抓取 $url · $statusCode · $contentType',
            'Fetched $url · $statusCode · $contentType');
      case 'browser':
        final path = widget.metadata['path'] as String?;
        if (path == null || path.isEmpty) return null;
        return l(context, '已打开页面 $path', 'Opened page $path');
      case 'skill':
        final name = (widget.rawInput['name'] as String?) ?? '';
        if (name.isEmpty) return l(context, '已读取内置技能', 'Loaded built-in skill');
        return l(context, '已读取内置技能 $name', 'Loaded built-in skill $name');
      case 'invalid':
        final tool = (widget.rawInput['tool'] as String?) ?? 'unknown';
        return l(context, '无效工具调用 $tool', 'Invalid tool call $tool');
      case 'plan_exit':
        return l(context, '准备切换到 build 模式', 'Switching to build mode');
      case 'task':
        final taskSessionId = widget.metadata['taskSessionId'] as String?;
        if (taskSessionId == null || taskSessionId.isEmpty) {
          return l(context, '子任务已完成', 'Subtask completed');
        }
        return l(context, '子任务已完成 · $taskSessionId',
            'Subtask completed · $taskSessionId');
      case 'git':
        return _localizedGitSummary(context);
      default:
        return null;
    }
  }

  String? _localizedGitSummary(BuildContext context) {
    final title = widget.toolTitle ?? '';
    final isRunning = widget.status == 'running' || widget.status == 'pending';
    if (isRunning) {
      final phase = (widget.metadata['phase'] as String?) ?? '';
      if (phase == 'awaiting_approval') {
        return l(context, '等待 Git 操作授权', 'Waiting for git approval');
      }
      final command = ((widget.metadata['command'] as String?) ?? 'git').trim();
      return l(context, '正在执行 git $command', 'Running git $command');
    }
    if (title == 'git init') {
      final workDir = widget.metadata['workDir'] as String?;
      if (workDir == null || workDir.isEmpty) return null;
      return l(context, '已初始化 Git 仓库 $workDir',
          'Initialized git repository at $workDir');
    }
    if (title == 'git clone') {
      final path = widget.metadata['path'] as String?;
      final defaultBranch = widget.metadata['defaultBranch'] as String?;
      if (path == null || path.isEmpty) return null;
      if (defaultBranch != null && defaultBranch.isNotEmpty) {
        return l(context, '已克隆到 $path · 分支 $defaultBranch',
            'Cloned into $path · branch $defaultBranch');
      }
      return l(context, '已克隆到 $path', 'Cloned into $path');
    }
    if (title == 'git status') {
      final clean = widget.metadata['clean'] == true;
      if (clean) return l(context, '工作区干净', 'Working tree clean');
      final staged = widget.metadata['staged'] ?? 0;
      final unstaged = widget.metadata['unstaged'] ?? 0;
      final untracked = widget.metadata['untracked'] ?? 0;
      return l(context, '$staged 个已暂存，$unstaged 个未暂存，$untracked 个未跟踪',
          '$staged staged, $unstaged unstaged, $untracked untracked');
    }
    if (title == 'git commit') {
      final hash = (widget.metadata['hash'] as String?) ?? '';
      if (hash.isEmpty) return null;
      final shortHash = hash.length > 8 ? hash.substring(0, 8) : hash;
      final amend = widget.rawInput['amend'] == true;
      return amend
          ? l(context, '已修订提交 $shortHash', 'Amended $shortHash')
          : l(context, '已创建提交 $shortHash', 'Created $shortHash');
    }
    if (title == 'git log') {
      final count = widget.metadata['count'];
      if (count == null) return null;
      return l(context, '$count 条提交记录', '$count commit(s)');
    }
    if (title == 'git show') {
      final hash = (widget.metadata['hash'] as String?) ?? '';
      if (hash.isEmpty) return null;
      final shortHash = hash.length > 8 ? hash.substring(0, 8) : hash;
      return l(context, '查看提交 $shortHash', 'Show commit $shortHash');
    }
    if (title == 'git add .') {
      return l(context, '已暂存全部更改', 'Staged all changes');
    }
    if (title == 'git add') {
      final paths = widget.metadata['paths'];
      if (paths is List) {
        return l(context, '已暂存 ${paths.length} 个路径',
            'Staged ${paths.length} path(s)');
      }
    }
    if (title == 'git restore') {
      final paths = widget.metadata['paths'];
      if (paths is List) {
        return l(context, '已恢复 ${paths.length} 个路径',
            'Restored ${paths.length} path(s)');
      }
    }
    if (title == 'git reset') {
      final paths = widget.metadata['paths'];
      if (paths is List && paths.isNotEmpty) {
        return l(context, '已重置 ${paths.length} 个路径',
            'Reset ${paths.length} path(s)');
      }
      final target = (widget.metadata['target'] as String?) ?? '';
      final mode = (widget.metadata['mode'] as String?) ?? '';
      if (target.isNotEmpty) {
        return mode.isEmpty
            ? l(context, '已重置到 $target', 'Reset to $target')
            : l(context, '已 $mode 重置到 $target', 'Reset $mode to $target');
      }
    }
    if (title == 'git branch') {
      final action = ((widget.rawInput['action'] as String?) ?? 'list')
          .trim()
          .toLowerCase();
      final name = (widget.rawInput['name'] as String?) ?? '';
      if (action.isEmpty || action == 'list') {
        final branches = widget.metadata['branches'];
        if (branches is List) {
          return l(context, '${branches.length} 个分支',
              '${branches.length} branch(es)');
        }
      }
      if (action == 'create' && name.isNotEmpty) {
        final startPoint = (widget.rawInput['startPoint'] as String?) ?? '';
        return startPoint.isEmpty
            ? l(context, '已创建分支 $name', 'Created branch $name')
            : l(context, '已创建分支 $name · 基于 $startPoint',
                'Created branch $name at $startPoint');
      }
      if (action == 'delete' && name.isNotEmpty) {
        final force = widget.rawInput['force'] == true;
        return force
            ? l(context, '已强制删除分支 $name', 'Force deleted branch $name')
            : l(context, '已删除分支 $name', 'Deleted branch $name');
      }
    }
    if (title == 'git checkout -b') {
      final target = (widget.rawInput['target'] as String?) ?? '';
      if (target.isEmpty) return null;
      return l(context, '已创建并切换到分支 $target',
          'Created and switched to branch $target');
    }
    if (title == 'git checkout') {
      final target = (widget.rawInput['target'] as String?) ?? '';
      if (target.isEmpty) return null;
      return l(context, '已切换到 $target', 'Switched to $target');
    }
    if (title == 'git merge') {
      final action = (widget.metadata['action'] as String?) ??
          ((widget.rawInput['action'] as String?) ?? 'start');
      if (action == 'abort') {
        return l(context, '已中止合并', 'Aborted merge');
      }
      if (action == 'continue') {
        return l(context, '已继续合并', 'Continued merge');
      }
      final conflicts = widget.metadata['conflicts'];
      if (conflicts is List && conflicts.isNotEmpty) {
        return l(context, '合并发生冲突 · ${conflicts.length} 个文件',
            'Merge conflicts · ${conflicts.length} file(s)');
      }
      final branch = (widget.rawInput['branch'] as String?) ?? '';
      final mergeCommit = widget.metadata['mergeCommit'] as String?;
      if (mergeCommit != null && mergeCommit.isNotEmpty) {
        final shortHash =
            mergeCommit.length > 8 ? mergeCommit.substring(0, 8) : mergeCommit;
        return branch.isEmpty
            ? l(context, '已完成合并 $shortHash', 'Merged $shortHash')
            : l(context, '已合并 $branch · $shortHash',
                'Merged $branch · $shortHash');
      }
      if (branch.isNotEmpty) {
        return l(context, '已合并 $branch', 'Merged $branch');
      }
    }
    if (title == 'git fetch') {
      final updatedRefs = widget.metadata['updatedRefs'];
      final count = updatedRefs is List ? updatedRefs.length : 0;
      if (count == 0) {
        return l(
            context, '抓取完成，引用无更新', 'Fetched successfully, no refs updated');
      }
      return l(context, '已抓取 $count 个引用', 'Fetched $count ref(s)');
    }
    if (title == 'git pull') {
      final useRebase = widget.rawInput['rebase'] == true;
      final mergeCommit = widget.metadata['mergeCommit'] as String?;
      final newHead = widget.metadata['newHead'] as String?;
      if (useRebase) {
        if (newHead != null && newHead.isNotEmpty) {
          final shortHash =
              newHead.length > 8 ? newHead.substring(0, 8) : newHead;
          return l(context, '拉取并变基完成 · $shortHash',
              'Pulled and rebased · $shortHash');
        }
        return l(context, '拉取并变基完成', 'Pulled and rebased successfully');
      }
      if (mergeCommit != null && mergeCommit.isNotEmpty) {
        final shortHash =
            mergeCommit.length > 8 ? mergeCommit.substring(0, 8) : mergeCommit;
        return l(
            context, '拉取并合并完成 · $shortHash', 'Pulled and merged · $shortHash');
      }
      return l(context, '拉取并合并完成', 'Pulled and merged successfully');
    }
    if (title == 'git push') {
      final pushedRefs = widget.metadata['pushedRefs'];
      if (pushedRefs is List && pushedRefs.isNotEmpty) {
        return l(context, '已推送 ${pushedRefs.length} 个引用',
            'Pushed ${pushedRefs.length} ref(s)');
      }
      return l(context, '推送完成', 'Pushed successfully');
    }
    if (title == 'git cherry-pick') {
      final action = (widget.metadata['action'] as String?) ??
          ((widget.rawInput['action'] as String?) ?? 'start');
      if (action == 'abort') {
        return l(context, '已中止拣选', 'Aborted cherry-pick');
      }
      if (action == 'continue') {
        return l(context, '已继续拣选', 'Continued cherry-pick');
      }
      final conflicts = widget.metadata['conflicts'];
      if (conflicts is List && conflicts.isNotEmpty) {
        return l(context, '拣选发生冲突 · ${conflicts.length} 个文件',
            'Cherry-pick conflicts · ${conflicts.length} file(s)');
      }
      final ref = (widget.rawInput['ref'] as String?) ?? '';
      final newHead = widget.metadata['newHead'] as String?;
      if (newHead != null && newHead.isNotEmpty) {
        final shortHash =
            newHead.length > 8 ? newHead.substring(0, 8) : newHead;
        return ref.isEmpty
            ? l(context, '拣选完成 · $shortHash', 'Cherry-picked · $shortHash')
            : l(context, '已拣选 $ref · $shortHash',
                'Cherry-picked $ref · $shortHash');
      }
      if (ref.isNotEmpty) {
        return l(context, '已拣选 $ref', 'Cherry-picked $ref');
      }
    }
    if (title == 'git rebase') {
      final action = (widget.metadata['action'] as String?) ??
          ((widget.rawInput['action'] as String?) ?? 'start');
      if (action == 'abort') {
        return l(context, '已中止变基', 'Aborted rebase');
      }
      if (action == 'continue') {
        return l(context, '已继续变基', 'Continued rebase');
      }
      if (action == 'skip') {
        return l(context, '已跳过当前提交', 'Skipped current commit');
      }
      final conflicts = widget.metadata['conflicts'];
      if (conflicts is List && conflicts.isNotEmpty) {
        return l(context, '变基发生冲突 · ${conflicts.length} 个文件',
            'Rebase conflicts · ${conflicts.length} file(s)');
      }
      final ref = (widget.rawInput['ref'] as String?) ?? '';
      final newHead = widget.metadata['newHead'] as String?;
      if (newHead != null && newHead.isNotEmpty) {
        final shortHash =
            newHead.length > 8 ? newHead.substring(0, 8) : newHead;
        return ref.isEmpty
            ? l(context, '变基完成 · $shortHash', 'Rebased · $shortHash')
            : l(context, '已变基到 $ref · $shortHash',
                'Rebased onto $ref · $shortHash');
      }
      if (ref.isNotEmpty) {
        return l(context, '已变基到 $ref', 'Rebased onto $ref');
      }
    }
    if (title == 'git config') {
      final action = (widget.metadata['action'] as String?) ?? '';
      final section = (widget.metadata['section'] as String?) ?? '';
      final key = (widget.metadata['key'] as String?) ?? '';
      final label = [section, key].where((part) => part.isNotEmpty).join('.');
      if (action == 'set' && label.isNotEmpty) {
        return l(context, '已更新配置 $label', 'Updated config $label');
      }
      if (action == 'get' && label.isNotEmpty) {
        return l(context, '已读取配置 $label', 'Read config $label');
      }
    }
    if (title == 'git remote-url') {
      final remote = (widget.metadata['remote'] as String?) ?? '';
      if (remote.isNotEmpty) {
        return l(context, '已读取远程 $remote', 'Read remote $remote');
      }
    }
    if (title == 'git remote') {
      final action = (widget.metadata['action'] as String?) ?? '';
      final remote = (widget.metadata['remote'] as String?) ?? '';
      if (action == 'list') {
        final count = widget.metadata['count'];
        if (count != null) {
          return l(context, '$count 个远程', '$count remote(s)');
        }
      }
      if (remote.isNotEmpty) {
        if (action == 'add') {
          return l(context, '已添加远程 $remote', 'Added remote $remote');
        }
        if (action == 'set-url') {
          return l(context, '已更新远程 $remote', 'Updated remote $remote');
        }
        if (action == 'remove') {
          return l(context, '已删除远程 $remote', 'Removed remote $remote');
        }
        if (action == 'get-url') {
          return l(context, '已读取远程 $remote', 'Read remote $remote');
        }
      }
      final oldName = (widget.metadata['oldName'] as String?) ?? '';
      final newName = (widget.metadata['newName'] as String?) ?? '';
      if (action == 'rename' && oldName.isNotEmpty && newName.isNotEmpty) {
        return l(context, '已重命名远程 $oldName -> $newName',
            'Renamed remote $oldName -> $newName');
      }
    }
    return null;
  }

  String _localizedToolLabel(BuildContext context) {
    final title = widget.toolTitle;
    switch (title) {
      case 'Apply Patch':
        return l(context, '应用补丁', 'Apply Patch');
      case 'WebFetch':
        return l(context, '网页抓取', 'WebFetch');
      case 'Browser':
        return l(context, '页面预览', 'Browser');
      case 'Skill':
        return l(context, '内置技能', 'Skill');
      case 'Invalid':
        return l(context, '无效调用', 'Invalid');
      case 'Plan Exit':
        return l(context, '退出计划模式', 'Plan Exit');
    }

    switch (widget.toolName) {
      case 'list':
        return l(context, '文件列表', 'File List');
      case 'glob':
        return l(context, '通配搜索', 'Glob Search');
      case 'grep':
        return l(context, '文本搜索', 'Text Search');
      case 'stat':
        return l(context, '文件信息', 'File Info');
      case 'read':
        return l(context, '读取文件', 'Read File');
      case 'write':
        return l(context, '写入文件', 'Write File');
      case 'edit':
        return l(context, '编辑文件', 'Edit File');
      case 'apply_patch':
        return l(context, '应用补丁', 'Apply Patch');
      case 'webfetch':
        return l(context, '网页抓取', 'WebFetch');
      case 'browser':
        return l(context, '页面预览', 'Browser');
      case 'skill':
        return l(context, '内置技能', 'Skill');
      case 'invalid':
        return l(context, '无效调用', 'Invalid');
      case 'plan_exit':
        return l(context, '退出计划模式', 'Plan Exit');
      default:
        return title ?? widget.toolName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = widget.status == 'running' || widget.status == 'pending';
    final isError = widget.status == 'error';
    final label = _localizedToolLabel(context);
    final expanded = _expanded ?? _defaultExpanded();
    final localizedSummary = _localizedToolSummary(context);
    final collapsedOutput = localizedSummary ?? widget.output;
    final expandedOutput = widget.hasDisplayOutput
        ? (localizedSummary ?? widget.output)
        : widget.output;
    final collapsedSummary = collapsedOutput?.split('\n').first.trim();
    final diffSuffix = _diffStatSuffix();
    final oc = context.oc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
      decoration: BoxDecoration(
        color: isError
            ? (context.isDarkMode
                ? const Color(0xFF1F0A0A)
                : const Color(0xFFFFFBFB))
            : isRunning
                ? (context.isDarkMode
                    ? const Color(0xFF1C1A0E)
                    : const Color(0xFFFFFCF2))
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
                            : (localizedSummary ?? label),
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
                    rawInputText: widget.rawInputText,
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
              expandedOutput != null &&
              expandedOutput.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: oc.shadow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                expandedOutput,
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
    this.trailing,
  });

  final String label;
  final String detail;
  final Color color;
  final Widget? trailing;

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
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: context.oc.foregroundMuted,
                      ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
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

class _CompactionPartTile extends StatelessWidget {
  const _CompactionPartTile({
    required this.summary,
    required this.createdAt,
    required this.workspace,
    required this.controller,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final String summary;
  final int createdAt;
  final WorkspaceInfo? workspace;
  final AppController controller;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final trimmed = summary.trim();
    final background =
        context.isDarkMode ? const Color(0xFF2A2412) : const Color(0xFFFFFBEB);
    final detail = <String>[
      l(
        context,
        '已生成续聊摘要，后续上下文将从摘要继续。',
        'A continuation summary was generated and future context will continue from it.',
      ),
      '${_formatCompactionTimestamp(createdAt)} · ${_formatCompactionSummaryLength(context, trimmed)}',
    ].join('\n');
    return _StatusPartTile(
      label: l(context, '上下文已压缩', 'Context Compacted'),
      detail: detail,
      color: background,
      trailing: trimmed.isEmpty
          ? null
          : _CompactActionButton(
              onPressed: () => _openCompactionSummarySheet(
                context,
                summary: trimmed,
                workspace: workspace,
                controller: controller,
                onInsertPromptReference: onInsertPromptReference,
                onSendPromptReference: onSendPromptReference,
              ),
              icon: Icons.description_outlined,
              label: l(context, '查看摘要', 'View summary'),
            ),
    );
  }
}

String _formatCompactionTimestamp(int createdAt) {
  final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

String _formatCompactionSummaryLength(BuildContext context, String summary) {
  final count = summary.characters.length;
  if (count >= 1000) {
    final short = (count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1);
    return l(context, '$short 千字', '${short}k chars');
  }
  return l(context, '$count 字', '$count chars');
}

Future<void> _openCompactionSummarySheet(
  BuildContext context, {
  required String summary,
  required WorkspaceInfo? workspace,
  required AppController controller,
  required ValueChanged<String> onInsertPromptReference,
  required PromptReferenceAction onSendPromptReference,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.88,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l(context, '会话摘要', 'Session Summary'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
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
                  decoration: _panelDecoration(context,
                      background: context.oc.shadow,
                      radius: 14,
                      elevated: false),
                  child: SingleChildScrollView(
                    child: _StreamingMarkdownText(
                      text: summary,
                      streaming: false,
                      workspace: workspace,
                      controller: controller,
                      onInsertPromptReference: onInsertPromptReference,
                      onSendPromptReference: onSendPromptReference,
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
