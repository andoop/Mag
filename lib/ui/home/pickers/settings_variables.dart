part of '../../home_page.dart';

// Variable-specific settings actions. The tile/dialog widgets are in
// settings_widgets.dart.

extension _AppSettingsVariableActions on _AppSettingsSheetState {
  Future<void> _showAppVariableDialog() async {
    final draft = await showDialog<_AppVariableDraft>(
      context: context,
      builder: (context) => const _AppVariableDialog(),
    );
    if (draft == null) return;
    try {
      await widget.controller.saveAppVariable(
        name: draft.name,
        value: draft.value,
        kind: draft.kind,
        secret: draft.secret,
        allowAiUse: draft.allowAiUse,
        note: draft.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l(context, '变量已保存', 'Variable saved'))),
      );
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    }
  }

  Future<void> _copyVariableName(AppVariable variable) async {
    await Clipboard.setData(ClipboardData(text: variable.name));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l(context, '变量名已复制', 'Variable name copied'))),
    );
  }

  Future<void> _showVariableValue(AppVariable variable) async {
    final value = await widget.controller.readAppVariableValue(variable.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(variable.name),
        content: SelectableText(
          value?.isNotEmpty == true
              ? value!
              : l(context, '未找到保存的值。', 'No saved value found.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l(context, '关闭', 'Close')),
          ),
          if (value?.isNotEmpty == true)
            FilledButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value!));
                Navigator.of(context).pop();
              },
              child: Text(l(context, '复制值', 'Copy value')),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteAppVariable(AppVariable variable) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l(context, '删除变量', 'Delete variable')),
        content: Text(
          l(
            context,
            '确定删除 `${variable.name}` 吗？保存的值也会从安全存储中移除。',
            'Delete `${variable.name}`? The stored value will also be removed from secure storage.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l(context, '取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l(context, '删除', 'Delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.deleteAppVariable(variable.id);
  }
}
