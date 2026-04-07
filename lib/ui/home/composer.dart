part of '../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _HomePageComposer on _HomePageState {
  Widget _buildComposerDock(
      BuildContext context, AppState state, bool isKeyboardOpen) {
    final oc = context.oc;
    final currentModel = state.modelConfig ?? ModelConfig.defaults();
    final currentModelChoice =
        _findModelChoice(
      currentModel.provider,
      currentModel.model,
      config: currentModel,
    );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: oc.pageBackground,
        border: Border(top: BorderSide(color: oc.softBorderColor)),
        boxShadow: [
          BoxShadow(
            color: oc.shadow,
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(
              12, isKeyboardOpen ? 4 : 8, 12, isKeyboardOpen ? 6 : 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.permissions.isNotEmpty || state.questions.isNotEmpty)
                Builder(
                  builder: (context) {
                    final h = MediaQuery.of(context).size.height;
                    final tall = state.questions.isNotEmpty;
                    final maxH = tall
                        ? (isKeyboardOpen ? h * 0.44 : h * 0.58)
                            .clamp(240.0, 560.0)
                        : (isKeyboardOpen ? 120.0 : 168.0);
                    return ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: maxH),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Column(
                          children: [
                            if (state.permissions.isNotEmpty)
                              _PermissionPanel(
                                  controller: widget.controller, state: state),
                            if (state.questions.isNotEmpty)
                              _QuestionPanel(
                                  controller: widget.controller, state: state),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              SizedBox(height: isKeyboardOpen ? 4 : 6),
              Container(
                decoration: BoxDecoration(
                  color: oc.panelBackground,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.fromBorderSide(
                      BorderSide(color: oc.borderColor)),
                  boxShadow: [
                    BoxShadow(
                      color: oc.shadow,
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: isKeyboardOpen
                          ? const SizedBox.shrink()
                          : Padding(
                              key: const ValueKey('composer-tools'),
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    _PromptTrayButton(
                                      icon: Icons.psychology_outlined,
                                      label: _selectedAgent ??
                                          state.session?.agent ??
                                          'build',
                                      onTap: () => _openAgentPicker(context),
                                    ),
                                    const SizedBox(width: 6),
                                    _PromptTrayButton(
                                      icon: Icons.auto_awesome_outlined,
                                      label: currentModelChoice?.name ??
                                          currentModel.model,
                                      onTap: () => _openModelChooser(context),
                                    ),
                                    const SizedBox(width: 6),
                                    _PromptTrayButton(
                                      icon: Icons.tune_outlined,
                                      label: l(context, '选项', 'Options'),
                                      onTap: () =>
                                          _openComposerOptionsSheet(context),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    Stack(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              10, isKeyboardOpen ? 2 : 3, 10, 8),
                          child: TextField(
                            controller: _promptController,
                            minLines: 1,
                            maxLines: isKeyboardOpen ? 4 : 3,
                            textInputAction: TextInputAction.newline,
                            style: const TextStyle(fontSize: 14, height: 1.32),
                            decoration: InputDecoration(
                              hintText: l(context, '问我关于这个工作区的任何事',
                                  'Ask anything about this workspace'),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.fromLTRB(
                                  38, isKeyboardOpen ? 7 : 8, 86, 11),
                              hintStyle: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: oc.foregroundHint),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _CompactIconButton(
                            tooltip: l(context, '附件', 'Attach'),
                            onPressed: () => _showInfo(
                                context,
                                l(context, '移动端附件入口下一步接入',
                                    'Attachment support on mobile is coming next.')),
                            icon: Icons.add,
                          ),
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (state.session != null) ...[
                                _ContextRingButton(
                                  ratio: _contextUsageRatio(
                                      state.session, currentModel.model),
                                  compacted: state.session?.hasSummary == true,
                                  onPressed: () => _openContextStatsSheet(
                                    context,
                                    session: state.session,
                                    model: currentModel.model,
                                    onInitializeMemory: state.isBusy
                                        ? null
                                        : widget
                                            .controller.initializeProjectMemory,
                                    onCompactSession: state.isBusy
                                        ? null
                                        : widget.controller.compactSession,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              state.isBusy
                                  ? FilledButton(
                                      style: FilledButton.styleFrom(
                                        shape: const CircleBorder(),
                                        padding: const EdgeInsets.all(0),
                                        minimumSize: const Size(36, 36),
                                        fixedSize: const Size(36, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: Colors.red.shade500,
                                        elevation: 0,
                                      ),
                                      onPressed: () =>
                                          widget.controller.cancelPrompt(),
                                      child: const Icon(Icons.stop,
                                          color: Colors.white, size: 16),
                                    )
                                  : FilledButton(
                                      style: FilledButton.styleFrom(
                                        shape: const CircleBorder(),
                                        padding: const EdgeInsets.all(0),
                                        minimumSize: const Size(36, 36),
                                        fixedSize: const Size(36, 36),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        backgroundColor: oc.sendButtonBg,
                                        foregroundColor: oc.sendButtonFg,
                                        elevation: 0,
                                      ),
                                      onPressed: () async {
                                        final text =
                                            _promptController.text.trim();
                                        if (text.isEmpty) return;
                                        MessageFormat? format;
                                        if (_structuredOutputEnabled) {
                                          try {
                                            final decoded = jsonDecode(
                                                _schemaController.text.trim());
                                            format = MessageFormat.jsonSchema(
                                              schema: Map<String, dynamic>.from(
                                                  decoded as Map),
                                            );
                                          } catch (_) {
                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                    content: Text(l(
                                                        context,
                                                        'Schema 不是合法 JSON 对象',
                                                        'Schema is not a valid JSON object'))),
                                              );
                                            }
                                            return;
                                          }
                                        }
                                        _promptController.clear();
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        await widget.controller.sendPrompt(
                                          text,
                                          agent: _selectedAgent ??
                                              state.session?.agent,
                                          format: format,
                                        );
                                      },
                                      child: const Icon(Icons.arrow_upward,
                                          size: 16),
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSchemaEditor(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l(context, '结构化输出 Schema', 'Structured Output Schema'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _structuredSchemaTemplates.keys
                    .map(
                      (key) => ChoiceChip(
                        label: Text(_schemaTemplateLabels[key] ?? key),
                        selected: _selectedSchemaTemplate == key,
                        onSelected: (_) {
                          setState(() {
                            _selectedSchemaTemplate = key;
                            _schemaController.text =
                                const JsonEncoder.withIndent('  ')
                                    .convert(_structuredSchemaTemplates[key]);
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _schemaController,
                minLines: 10,
                maxLines: 18,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: l(context, '输入 JSON Schema', 'Enter JSON Schema'),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  try {
                    final decoded = jsonDecode(_schemaController.text.trim());
                    Map<String, dynamic>.from(decoded as Map);
                    Navigator.of(context).pop();
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(l(context, 'Schema 必须是合法 JSON 对象',
                              'Schema must be a valid JSON object'))),
                    );
                  }
                },
                child: Text(l(context, '完成', 'Done')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openComposerOptionsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 0.38,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l(context, '选项', 'Options'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ComposerOptionTile(
                    icon: Icons.tune_outlined,
                    title: _structuredOutputEnabled
                        ? l(context, '关闭结构化输出', 'Disable Structured Output')
                        : l(context, '开启结构化输出', 'Enable Structured Output'),
                    subtitle: l(
                      context,
                      '控制是否按 Schema 输出',
                      'Toggle schema-based structured output',
                    ),
                    trailing: _structuredOutputEnabled
                        ? Icon(Icons.check_circle,
                            size: 18, color: context.oc.accent)
                        : null,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      setState(() {
                        _structuredOutputEnabled = !_structuredOutputEnabled;
                      });
                    },
                  ),
                  if (_structuredOutputEnabled)
                    _ComposerOptionTile(
                      icon: Icons.data_object,
                      title: l(context, '编辑 Schema', 'Edit Schema'),
                      subtitle: l(
                        context,
                        '配置结构化输出格式',
                        'Configure structured output schema',
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _openSchemaEditor(context);
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openContextStatsSheet(
    BuildContext context, {
    required SessionInfo? session,
    required String model,
    required VoidCallback? onInitializeMemory,
    required VoidCallback? onCompactSession,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.58,
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
                            l(context, '上下文', 'Context'),
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _contextUsageLabel(session, model),
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: context.oc.foregroundMuted),
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
                const SizedBox(height: 10),
                _ContextStatsCard(
                  session: session,
                  model: model,
                  onInitializeMemory: onInitializeMemory,
                  onCompactSession: onCompactSession,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptTrayButton extends StatelessWidget {
  const _PromptTrayButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: oc.panelBackground,
        side: BorderSide(color: oc.borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: oc.foreground),
          const SizedBox(width: 6),
          Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: oc.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerOptionTile extends StatelessWidget {
  const _ComposerOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: oc.composerOptionBg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.fromBorderSide(
                BorderSide(color: oc.borderColor),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: oc.panelBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.fromBorderSide(
                      BorderSide(color: oc.borderColor),
                    ),
                  ),
                  child: Icon(icon, size: 17, color: oc.foreground),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: oc.foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.3,
                          color: oc.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: oc.foregroundFaint,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
