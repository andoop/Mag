part of '../../home_page.dart';

// Reusable settings UI. Keep presentational widgets here; stateful behavior
// should stay in the shell or domain-specific settings_* action files.

class _SettingsMetaChip extends StatelessWidget {
  const _SettingsMetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            oc.composerOptionBg.withOpacity(context.isDarkMode ? 0.58 : 0.74),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: oc.softBorderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: oc.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: oc.foreground,
                letterSpacing: 0.02,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsActionButton extends StatelessWidget {
  const _SettingsActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final color = destructive ? Colors.redAccent : oc.foregroundMuted;
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        foregroundColor: color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: child,
    );
  }
}

class _SettingsHomeTile extends StatelessWidget {
  const _SettingsHomeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: oc.panelBackground,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            decoration: _settingsSurfaceDecoration(
              context,
              color: oc.panelBackground,
              radius: 20,
              elevated: true,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: oc.composerOptionBg
                        .withOpacity(context.isDarkMode ? 0.58 : 0.78),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: oc.softBorderColor),
                  ),
                  child: Icon(icon, size: 19, color: oc.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: oc.foreground,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: oc.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if ((trailing ?? '').isNotEmpty) ...[
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 130),
                    child: Text(
                      trailing!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: oc.foregroundMuted,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, size: 20, color: oc.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      decoration: _settingsSurfaceDecoration(
        context,
        color: oc.panelBackground,
        radius: 24,
        elevated: true,
      ),
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      oc.accent.withOpacity(context.isDarkMode ? 0.14 : 0.09),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color:
                        oc.accent.withOpacity(context.isDarkMode ? 0.26 : 0.14),
                  ),
                ),
                child: Icon(icon, size: 18, color: oc.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: oc.foreground,
                        letterSpacing: -0.05,
                      ),
                    ),
                    if (subtitle?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: oc.foregroundMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            action!,
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _McpToolPreviewTile extends StatelessWidget {
  const _McpToolPreviewTile({
    required this.tool,
    required this.onTap,
  });

  final McpToolDefinition tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final title =
        tool.title?.trim().isNotEmpty == true ? tool.title!.trim() : tool.name;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: oc.panelBackground
                .withOpacity(context.isDarkMode ? 0.44 : 0.70),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: oc.softBorderColor),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt_outlined, size: 17, color: oc.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: oc.foreground,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: oc.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _settingsSurfaceDecoration(
        context,
        color:
            oc.composerOptionBg.withOpacity(context.isDarkMode ? 0.50 : 0.68),
        radius: 16,
        elevated: false,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: oc.foreground,
              ),
            ),
          ),
          _SettingsMiniSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SettingsMiniSwitch extends StatelessWidget {
  const _SettingsMiniSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 42,
        height: 24,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value
              ? oc.accent.withOpacity(context.isDarkMode ? 0.82 : 0.78)
              : oc.muted.withOpacity(context.isDarkMode ? 0.24 : 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: value ? oc.accent.withOpacity(0.35) : oc.softBorderColor,
          ),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppVariableTile extends StatelessWidget {
  const _AppVariableTile({
    required this.variable,
    required this.onCopyName,
    required this.onReveal,
    required this.onDelete,
    required this.onAiAccessChanged,
  });

  final AppVariable variable;
  final VoidCallback onCopyName;
  final VoidCallback onReveal;
  final VoidCallback onDelete;
  final ValueChanged<bool> onAiAccessChanged;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: _settingsSurfaceDecoration(
        context,
        color:
            oc.composerOptionBg.withOpacity(context.isDarkMode ? 0.50 : 0.68),
        radius: 18,
        elevated: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: oc.panelBackground.withOpacity(0.86),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: oc.softBorderColor),
                ),
                child: Icon(
                  variable.secret ? Icons.lock_outline : Icons.notes_outlined,
                  size: 18,
                  color: oc.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      variable.name,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: oc.foreground,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _SettingsMetaChip(
                          icon: variable.secret
                              ? Icons.visibility_off_outlined
                              : Icons.text_fields_rounded,
                          label: variable.secret
                              ? l(context, '密钥', 'Secret')
                              : l(context, '普通变量', 'Plain variable'),
                        ),
                        _SettingsMetaChip(
                          icon: Icons.category_outlined,
                          label: variable.kind,
                        ),
                      ],
                    ),
                    if (variable.note?.isNotEmpty == true) ...[
                      const SizedBox(height: 6),
                      Text(
                        variable.note!,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: oc.foregroundMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SettingsToggleRow(
            label: l(context, '允许 AI 使用', 'Allow AI access'),
            value: variable.allowAiUse,
            onChanged: onAiAccessChanged,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _SettingsActionButton(
                onPressed: onCopyName,
                icon: Icons.copy_rounded,
                label: l(context, '复制名称', 'Copy name'),
              ),
              _SettingsActionButton(
                onPressed: onReveal,
                icon: Icons.visibility_outlined,
                label: l(context, '查看值', 'Reveal'),
              ),
              _SettingsActionButton(
                onPressed: onDelete,
                icon: Icons.delete_outline_rounded,
                label: l(context, '删除', 'Delete'),
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppVariableDraft {
  const _AppVariableDraft({
    required this.name,
    required this.value,
    required this.kind,
    required this.secret,
    required this.allowAiUse,
    this.note,
  });

  final String name;
  final String value;
  final String kind;
  final bool secret;
  final bool allowAiUse;
  final String? note;
}

class _AppVariableDialog extends StatefulWidget {
  const _AppVariableDialog();

  @override
  State<_AppVariableDialog> createState() => _AppVariableDialogState();
}

class _AppVariableDialogState extends State<_AppVariableDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String _kind = 'secret';
  bool _secret = true;
  bool _allowAiUse = false;
  bool _obscure = true;

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l(context, '添加变量', 'Add variable')),
      content: SizedBox(
        width: _dialogMaxWidth(context, maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l(context, '变量名', 'Variable name'),
                  hintText: 'OPENAI_API_KEY',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _kind,
                decoration: InputDecoration(
                  labelText: l(context, '类型', 'Type'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'secret',
                    child: Text(l(context, '密钥 / Token', 'Secret / token')),
                  ),
                  DropdownMenuItem(
                    value: 'api-key',
                    child: Text(l(context, 'AI API Key', 'AI API key')),
                  ),
                  DropdownMenuItem(
                    value: 'env',
                    child: Text(l(context, '环境变量', 'Environment variable')),
                  ),
                  DropdownMenuItem(
                    value: 'plain',
                    child: Text(l(context, '普通文本', 'Plain text')),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _kind = value;
                    _secret = value != 'plain';
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _valueController,
                obscureText: _secret && _obscure,
                decoration: InputDecoration(
                  labelText: l(context, '值', 'Value'),
                  suffixIcon: _secret
                      ? IconButton(
                          onPressed: () {
                            setState(() {
                              _obscure = !_obscure;
                            });
                          },
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l(context, '备注（可选）', 'Note (optional)'),
                  hintText: l(context, '例如：OpenAI 主账号',
                      'Example: OpenAI primary account'),
                ),
              ),
              const SizedBox(height: 8),
              _SettingsToggleRow(
                label: l(context, '允许 AI 使用', 'Allow AI access'),
                value: _allowAiUse,
                onChanged: (value) {
                  setState(() {
                    _allowAiUse = value;
                  });
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l(context, '取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _AppVariableDraft(
                name: _nameController.text,
                value: _valueController.text,
                kind: _kind,
                secret: _secret,
                allowAiUse: _allowAiUse,
                note: _noteController.text,
              ),
            );
          },
          child: Text(l(context, '保存', 'Save')),
        ),
      ],
    );
  }
}

class _RemoteCredentialDraft {
  const _RemoteCredentialDraft({
    required this.name,
    required this.host,
    required this.pathPrefix,
    required this.username,
    required this.secret,
    required this.sshKeyId,
  });

  final String name;
  final String host;
  final String pathPrefix;
  final String username;
  final String secret;
  final String? sshKeyId;
}

class _RemoteCredentialDialog extends StatefulWidget {
  const _RemoteCredentialDialog({
    required this.type,
    required this.gitSettings,
  });

  final String type;
  final GitSettings gitSettings;

  @override
  State<_RemoteCredentialDialog> createState() =>
      _RemoteCredentialDialogState();
}

class _RemoteCredentialDialogState extends State<_RemoteCredentialDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _pathController;
  late final TextEditingController _usernameController;
  late final TextEditingController _secretController;
  String? _selectedSshKeyId;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _hostController = TextEditingController();
    _pathController = TextEditingController();
    _usernameController = TextEditingController(
      text: widget.type == 'sshKey' ? 'git' : '',
    );
    _secretController = TextEditingController();
    _selectedSshKeyId = widget.gitSettings.defaultSshKey?.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _pathController.dispose();
    _usernameController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.type == 'sshKey'
            ? l(context, '新增 SSH 远程认证', 'Add SSH remote credential')
            : widget.type == 'httpsBasic'
                ? l(context, '新增 HTTPS 账号密码', 'Add HTTPS user/password')
                : l(context, '新增 HTTPS Token', 'Add HTTPS token'),
      ),
      content: SizedBox(
        width: _dialogMaxWidth(context, maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l(context, '名称', 'Name'),
                  hintText: l(
                    context,
                    '例如：GitHub 主账号',
                    'Example: GitHub primary account',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _hostController,
                decoration: InputDecoration(
                  labelText: l(context, '主机', 'Host'),
                  hintText: 'github.com',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pathController,
                decoration: InputDecoration(
                  labelText: l(
                    context,
                    '路径前缀（可选）',
                    'Path prefix (optional)',
                  ),
                  hintText: l(
                    context,
                    '/owner/repo.git 或 /owner',
                    '/owner/repo.git or /owner',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: l(context, '用户名', 'Username'),
                  hintText: widget.type == 'sshKey' ? 'git' : '',
                ),
              ),
              if (widget.type == 'sshKey') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedSshKeyId,
                  items: widget.gitSettings.sshKeys
                      .map(
                        (key) => DropdownMenuItem<String>(
                          value: key.id,
                          child: Text(key.name),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedSshKeyId = value;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: l(context, 'SSH Key', 'SSH key'),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _secretController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: widget.type == 'httpsBasic'
                        ? l(context, '密码', 'Password')
                        : l(context, 'Token', 'Token'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l(context, '取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _RemoteCredentialDraft(
                name: _nameController.text,
                host: _hostController.text,
                pathPrefix: _pathController.text,
                username: _usernameController.text,
                secret: _secretController.text,
                sshKeyId: _selectedSshKeyId,
              ),
            );
          },
          child: Text(l(context, '保存', 'Save')),
        ),
      ],
    );
  }
}
