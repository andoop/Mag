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
    final oc = context.oc;
    final kind = preview['kind'] as String? ?? 'update';
    final path = preview['path'] as String? ?? '';
    final sourcePath = preview['sourcePath'] as String?;
    final diff = preview['preview'] as String? ?? '';
    final fullDiff = preview['fullPreview'] as String? ?? diff;
    final canOpen = workspace != null && path.isNotEmpty && kind != 'delete';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(context,
          background: oc.permissionPreviewBg, radius: 14, elevated: false),
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
  PageController? _pageController;
  int _pageIndex = 0;

  PageController get _pc {
    _pageController ??= PageController();
    return _pageController!;
  }

  @override
  void dispose() {
    _pageController?.dispose();
    for (final controller in _customControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _useWizard(QuestionRequest r) =>
      r.questions.length > 1 || r.questions.any((q) => q.multiple);

  bool _immediateSingle(QuestionRequest r) =>
      r.questions.length == 1 && !r.questions[0].multiple;

  List<List<String>> _collectAnswers(QuestionRequest request) {
    final answers = <List<String>>[];
    for (var i = 0; i < request.questions.length; i++) {
      final info = request.questions[i];
      final sel = _selected[i] ?? <String>{};
      final current = List<String>.from(sel);
      final custom = _customControllers[i]?.text.trim() ?? '';
      if (info.custom && custom.isNotEmpty) current.add(custom);
      answers.add(current);
    }
    return answers;
  }

  Future<void> _submit(QuestionRequest request) async {
    await widget.controller.replyQuestion(request.id, _collectAnswers(request));
  }

  Future<void> _dismiss(QuestionRequest request) async {
    await widget.controller.replyQuestion(request.id, const []);
  }

  Future<void> _wizardNext() async {
    await _pc.nextPage(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _wizardPrev() async {
    if (_pageIndex > 0) {
      await _pc.previousPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final request = widget.state.questions.first;
    final n = request.questions.length;
    final wizard = _useWizard(request);
    final immediate = _immediateSingle(request);
    final pageCount = wizard ? n + 1 : 1;
    final pageViewHeight =
        (MediaQuery.of(context).size.height * 0.40).clamp(240.0, 420.0);

    String subtitleText() {
      if (wizard) {
        return l(
          context,
          '逐题作答，最后一页核对后再提交。',
          'Answer step by step, then review and submit on the last page.',
        );
      }
      if (immediate) {
        if (request.questions[0].custom) {
          return l(
            context,
            '点选一项将立即提交；仅填自定义答案时请点「提交」。',
            'Tap an option to submit now, or fill custom and tap Submit.',
          );
        }
        return l(
          context,
          '点选一项即可提交。',
          'Tap an option to submit.',
        );
      }
      return l(
        context,
        '请选择题目标选项或填写自定义答案，完成后点「提交」。',
        'Choose options or enter a custom answer, then tap Submit.',
      );
    }

    Widget header() {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: oc.selectedFill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.help_outline_rounded,
                size: 22, color: oc.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l(context, '需要你的选择', 'Your input needed'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.25,
                    color: oc.text,
                  ),
                ),
                if (wizard) ...[
                  const SizedBox(height: 4),
                  Text(
                    l(
                      context,
                      '第 ${_pageIndex + 1} 步，共 $pageCount 步',
                      'Step ${_pageIndex + 1} of $pageCount',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: oc.accent,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  subtitleText(),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: oc.muted,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _dismiss(request),
            style: TextButton.styleFrom(
              foregroundColor: oc.muted,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(l(context, '忽略', 'Dismiss')),
          ),
        ],
      );
    }

    Widget reviewPage() {
      final none = l(context, '（未选择）', '(not answered)');
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l(context, '核对答案', 'Review'),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: oc.text,
              ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              Text(
                request.questions[i].question,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.35,
                  color: oc.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                () {
                  final parts = _collectAnswers(request)[i];
                  if (parts.isEmpty) return none;
                  return parts.join(', ');
                }(),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: oc.muted,
                ),
              ),
            ],
          ],
        ),
      );
    }

    final themeWrap = Theme(
      data: Theme.of(context).copyWith(
        radioTheme: RadioThemeData(
          fillColor: MaterialStateProperty.resolveWith((states) =>
              states.contains(MaterialState.selected)
                  ? oc.accent
                  : oc.muted),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: MaterialStateProperty.resolveWith((states) =>
              states.contains(MaterialState.selected) ? oc.accent : null),
          checkColor: MaterialStateProperty.all(Colors.white),
          side: BorderSide(color: oc.border, width: 1.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            header(),
            const SizedBox(height: 12),
            if (wizard) ...[
              SizedBox(
                height: pageViewHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: PageView.builder(
                    controller: _pc,
                    onPageChanged: (i) => setState(() => _pageIndex = i),
                    itemCount: pageCount,
                    itemBuilder: (context, pageIndex) {
                      if (pageIndex < n) {
                        final info = request.questions[pageIndex];
                        return SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(right: 4, bottom: 8),
                          child: _QuestionForm(
                            info: info,
                            selected:
                                _selected.putIfAbsent(pageIndex, () => <String>{}),
                            customController: _customControllers.putIfAbsent(
                                pageIndex, () => TextEditingController()),
                            onChanged: () => setState(() {}),
                            onAfterSingleChoice: !info.multiple
                                ? _wizardNext
                                : null,
                          ),
                        );
                      }
                      return reviewPage();
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_pageIndex > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _wizardPrev(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: oc.text,
                          side: BorderSide(color: oc.border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(l(context, '上一步', 'Back')),
                      ),
                    ),
                  if (_pageIndex > 0) const SizedBox(width: 10),
                  Expanded(
                    flex: _pageIndex > 0 ? 2 : 1,
                    child: FilledButton(
                      onPressed: () async {
                        if (_pageIndex < n) {
                          await _wizardNext();
                        } else {
                          await _submit(request);
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: oc.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        _pageIndex < n
                            ? l(context, '下一步', 'Next')
                            : l(context, '提交', 'Submit'),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              ...List.generate(n, (i) {
                final info = request.questions[i];
                return Padding(
                  padding: EdgeInsets.only(bottom: i < n - 1 ? 14 : 0),
                  child: _QuestionForm(
                    info: info,
                    selected: _selected.putIfAbsent(i, () => <String>{}),
                    customController:
                        _customControllers.putIfAbsent(i, () => TextEditingController()),
                    onChanged: () => setState(() {}),
                    onAfterSingleChoice: immediate
                        ? () => _submit(request)
                        : null,
                  ),
                );
              }),
              if (!immediate || request.questions[0].custom) ...[
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => _submit(request),
                  style: FilledButton.styleFrom(
                    backgroundColor: oc.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(l(context, '提交', 'Submit')),
                ),
              ],
            ],
          ],
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      decoration: _panelDecoration(context, radius: 14, elevated: true),
      clipBehavior: Clip.antiAlias,
      child: themeWrap,
    );
  }
}

class _QuestionForm extends StatelessWidget {
  const _QuestionForm({
    required this.info,
    required this.selected,
    required this.customController,
    required this.onChanged,
    this.onAfterSingleChoice,
  });

  final QuestionInfo info;
  final Set<String> selected;
  final TextEditingController customController;
  final VoidCallback onChanged;

  /// 单选题在选中一项后触发（OpenCode TUI：单 Tab 点选即提交；向导模式则进入下一页）。
  final VoidCallback? onAfterSingleChoice;

  void _notifyAfterSingleIfNeeded() {
    if (!info.multiple) {
      onAfterSingleChoice?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final hint = info.multiple
        ? l(context, '可多选', 'Select all that apply')
        : l(context, '选择一项', 'Select one answer');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (info.header.trim().isNotEmpty) ...[
          OcModelTag(label: info.header.trim()),
          const SizedBox(height: 8),
        ],
        Text(
          info.question,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: oc.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            color: oc.muted.withOpacity(0.95),
          ),
        ),
        const SizedBox(height: 12),
        ...info.options.map((option) {
          final isSelected = selected.contains(option.label);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (!info.multiple) {
                    selected
                      ..clear()
                      ..add(option.label);
                  } else if (isSelected) {
                    selected.remove(option.label);
                  } else {
                    selected.add(option.label);
                  }
                  onChanged();
                  _notifyAfterSingleIfNeeded();
                },
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? oc.selectedFill
                        : oc.optionDefaultBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? oc.accent.withOpacity(0.42)
                          : oc.border,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: info.multiple
                            ? SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: isSelected,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (_) {
                                    if (isSelected) {
                                      selected.remove(option.label);
                                    } else {
                                      selected.add(option.label);
                                    }
                                    onChanged();
                                  },
                                ),
                              )
                            : SizedBox(
                                width: 22,
                                height: 22,
                                child: Radio<String>(
                                  value: option.label,
                                  groupValue: selected.isEmpty
                                      ? null
                                      : selected.first,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (_) {
                                    selected
                                      ..clear()
                                      ..add(option.label);
                                    onChanged();
                                    _notifyAfterSingleIfNeeded();
                                  },
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.label,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                height: 1.3,
                                color: oc.text,
                              ),
                            ),
                            if (option.description.trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                option.description.trim(),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: oc.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
        if (info.custom) ...[
          const SizedBox(height: 8),
          TextField(
            controller: customController,
            minLines: 1,
            maxLines: 4,
            style: const TextStyle(fontSize: 14, height: 1.4),
            decoration: InputDecoration(
              hintText: l(context, '或输入自定义答案…', 'Or type a custom answer…'),
              filled: true,
              fillColor: oc.panelBackground,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: oc.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: oc.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: oc.accent, width: 1.4),
              ),
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
