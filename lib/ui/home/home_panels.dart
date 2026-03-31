part of '../home_page.dart';

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({required this.controller, required this.state});

  final AppController controller;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final request = state.permissions.first;
    final metadata = request.metadata;
    final preview = metadata['preview'] is Map
        ? Map<String, dynamic>.from(metadata['preview'] as Map)
        : null;
    final tool = metadata['tool'] as String?;
    final filePath =
        metadata['path'] as String? ?? metadata['filePath'] as String?;
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                l(context, '权限: ${request.permission}',
                    'Permission: ${request.permission}'),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(request.patterns.join(', '),
                style: Theme.of(context).textTheme.bodySmall),
            if (tool != null || filePath != null) ...[
              const SizedBox(height: 6),
              Text(
                [
                  if (tool != null) l(context, '工具: $tool', 'Tool: $tool'),
                  if (filePath != null)
                    l(context, '目标: $filePath', 'Target: $filePath'),
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (preview != null) ...[
              const SizedBox(height: 12),
              _PermissionPreviewCard(
                preview: preview,
                controller: controller,
                workspace: state.workspace,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CompactActionButton(
                  label: l(context, '允许一次', 'Allow once'),
                  onPressed: () => controller.replyPermission(
                      request.id, PermissionReply.once),
                ),
                _CompactActionButton(
                  label: l(context, '始终允许', 'Always allow'),
                  filled: true,
                  onPressed: () => controller.replyPermission(
                      request.id, PermissionReply.always),
                ),
                TextButton(
                  onPressed: () => controller.replyPermission(
                      request.id, PermissionReply.reject),
                  style: TextButton.styleFrom(
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                  ),
                  child: Text(l(context, '拒绝', 'Reject')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionPreviewCard extends StatelessWidget {
  const _PermissionPreviewCard({
    required this.preview,
    required this.controller,
    required this.workspace,
  });

  final Map<String, dynamic> preview;
  final AppController controller;
  final WorkspaceInfo? workspace;

  @override
  Widget build(BuildContext context) {
    final kind = preview['kind'] as String? ?? 'update';
    final path = preview['path'] as String? ?? '';
    final sourcePath = preview['sourcePath'] as String?;
    final diff = preview['preview'] as String? ?? '';
    final fullDiff = preview['fullPreview'] as String? ?? diff;
    final canOpen = workspace != null && path.isNotEmpty && kind != 'delete';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(
          background: const Color(0xFFF5F3FF), radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l(context, '待确认变更 · $kind', 'Pending Change · $kind'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(path, style: Theme.of(context).textTheme.bodySmall),
          if (sourcePath != null && sourcePath.isNotEmpty)
            Text(l(context, '来源: $sourcePath', 'From: $sourcePath'),
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (canOpen)
                _CompactActionButton(
                  label: l(context, '打开目标文件', 'Open target file'),
                  onPressed: () => _openFilePreview(
                    context,
                    controller: controller,
                    workspace: workspace!,
                    path: path,
                  ),
                ),
              _CompactActionButton(
                label: l(context, '更多上下文', 'More context'),
                onPressed: () => _openDiffPreviewSheet(
                  context,
                  title: l(context, '待确认变更', 'Pending Change'),
                  subtitle: path,
                  diff: fullDiff,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionPanel extends StatefulWidget {
  const _QuestionPanel({required this.controller, required this.state});

  final AppController controller;
  final AppState state;

  @override
  State<_QuestionPanel> createState() => _QuestionPanelState();
}

class _QuestionPanelState extends State<_QuestionPanel> {
  final Map<int, Set<String>> _selected = {};
  final Map<int, TextEditingController> _customControllers = {};

  @override
  void dispose() {
    for (final controller in _customControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.state.questions.first;
    return Card(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l(context, '问题', 'Question'),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            for (var i = 0; i < request.questions.length; i++) ...[
              _QuestionForm(
                info: request.questions[i],
                selected: _selected.putIfAbsent(i, () => <String>{}),
                customController: _customControllers.putIfAbsent(
                    i, () => TextEditingController()),
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                OutlinedButton(
                  onPressed: () =>
                      widget.controller.replyQuestion(request.id, const []),
                  child: Text(l(context, '忽略', 'Dismiss')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    final answers = <List<String>>[];
                    for (var i = 0; i < request.questions.length; i++) {
                      final info = request.questions[i];
                      final selected = _selected[i] ?? <String>{};
                      final current = selected.toList();
                      final custom = _customControllers[i]?.text.trim() ?? '';
                      if (info.custom && custom.isNotEmpty) {
                        current.add(custom);
                      }
                      answers.add(current);
                    }
                    await widget.controller.replyQuestion(request.id, answers);
                  },
                  child: Text(l(context, '提交', 'Submit')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionForm extends StatelessWidget {
  const _QuestionForm({
    required this.info,
    required this.selected,
    required this.customController,
    required this.onChanged,
  });

  final QuestionInfo info;
  final Set<String> selected;
  final TextEditingController customController;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(info.header, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(info.question),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: info.options.map((option) {
            final isSelected = selected.contains(option.label);
            return FilterChip(
              label: Text(option.label),
              selected: isSelected,
              onSelected: (value) {
                if (!info.multiple) {
                  selected
                    ..clear()
                    ..add(option.label);
                } else if (value) {
                  selected.add(option.label);
                } else {
                  selected.remove(option.label);
                }
                onChanged();
              },
            );
          }).toList(),
        ),
        if (info.custom) ...[
          const SizedBox(height: 8),
          TextField(
            controller: customController,
            decoration: InputDecoration(
              labelText: l(context, '自定义答案', 'Custom answer'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
        ],
      ],
    );
  }
}

class _TodoPanel extends StatelessWidget {
  const _TodoPanel({required this.todos});

  final List<TodoItem> todos;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l(context, '待办', 'Todos'),
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            for (final todo in todos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: todo.status == 'completed'
                            ? const Color(0xFF10B981)
                            : todo.status == 'in_progress'
                                ? const Color(0xFFF59E0B)
                                : todo.status == 'cancelled'
                                    ? const Color(0xFF94A3B8)
                                    : const Color(0xFF64748B),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${todoStatusText(context, todo.status)} - ${todo.content}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
