part of '../../home_page.dart';

class _AppSettingsSheet extends StatefulWidget {
  const _AppSettingsSheet({
    required this.controller,
    required this.modelConfig,
  });

  final AppController controller;
  final ModelConfig modelConfig;

  @override
  State<_AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<_AppSettingsSheet> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _gitNameController;
  late final TextEditingController _gitEmailController;

  @override
  void initState() {
    super.initState();
    final connection = widget.modelConfig.currentConnection;
    final gitSettings =
        widget.controller.state.gitSettings ?? GitSettings.defaults();
    _baseUrlController = TextEditingController(text: connection?.baseUrl ?? '');
    _apiKeyController = TextEditingController(text: connection?.apiKey ?? '');
    _modelController = TextEditingController(text: widget.modelConfig.model);
    _gitNameController = TextEditingController(text: gitSettings.identity.name);
    _gitEmailController =
        TextEditingController(text: gitSettings.identity.email);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _gitNameController.dispose();
    _gitEmailController.dispose();
    super.dispose();
  }

  Future<void> _saveProviderSettings() async {
    final current = widget.modelConfig;
    final connection = current.currentConnection;
    if (connection == null) {
      return;
    }
    await widget.controller.connectProvider(
      connection.copyWith(
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        models: _modelController.text.trim().isEmpty
            ? connection.models
            : [_modelController.text.trim(), ...connection.models],
      ),
      currentModelId: _modelController.text.trim().isEmpty
          ? current.model
          : _modelController.text.trim(),
      select: true,
    );
  }

  Future<void> _saveGitIdentity() async {
    await widget.controller.saveGitIdentity(
      name: _gitNameController.text,
      email: _gitEmailController.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l(context, 'Git 身份已保存', 'Git identity saved'))),
    );
  }

  Future<void> _showGenerateKeyDialog() async {
    final nameController = TextEditingController();
    final commentController =
        TextEditingController(text: _gitEmailController.text.trim());
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(l(context, '生成 SSH Key', 'Generate SSH key')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l(
                      context,
                      '将生成 Ed25519 OpenSSH 密钥。',
                      'This generates an Ed25519 OpenSSH key.',
                    ),
                    style: TextStyle(fontSize: 12.5, color: context.oc.muted),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: l(context, '名称', 'Name'),
                    hintText:
                        l(context, '例如：GitHub Key', 'Example: GitHub Key'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentController,
                  decoration: InputDecoration(
                    labelText: l(context, '注释', 'Comment'),
                    hintText: l(context, '通常填邮箱', 'Usually your email'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l(context, '取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l(context, '生成', 'Generate')),
              ),
            ],
          );
        },
      );
      if (result != true) {
        return;
      }
      await widget.controller.generateGitSshKey(
        name: nameController.text.trim(),
        comment: commentController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l(context, 'SSH Key 已生成', 'SSH key generated'))),
      );
    } finally {
      nameController.dispose();
      commentController.dispose();
    }
  }

  Future<void> _showImportKeyDialog() async {
    final nameController = TextEditingController();
    final commentController = TextEditingController();
    final publicController = TextEditingController();
    final privateController = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(l(context, '导入 SSH Key', 'Import SSH key')),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: l(context, '名称', 'Name'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: commentController,
                      decoration: InputDecoration(
                        labelText: l(context, '注释（可选）', 'Comment (optional)'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: publicController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: l(
                          context,
                          '公钥（可选，ssh-ed25519）',
                          'Public key (optional, ssh-ed25519)',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: privateController,
                      minLines: 6,
                      maxLines: 10,
                      decoration: InputDecoration(
                        labelText: l(
                          context,
                          '私钥（仅 Ed25519 OpenSSH）',
                          'Private key (Ed25519 OpenSSH only)',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l(context, '取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l(context, '导入', 'Import')),
              ),
            ],
          );
        },
      );
      if (result != true) {
        return;
      }
      await widget.controller.importGitSshKey(
        name: nameController.text.trim(),
        privateKeyPem: privateController.text,
        publicKeyOpenSsh: publicController.text.trim(),
        comment: commentController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l(context, 'SSH Key 已导入', 'SSH key imported'))),
      );
    } finally {
      nameController.dispose();
      commentController.dispose();
      publicController.dispose();
      privateController.dispose();
    }
  }

  Future<void> _showPublicKeyDialog(GitSshKey key) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l(context, '公钥', 'Public key')),
          content: SizedBox(
            width: 520,
            child: SelectableText(key.publicKeyOpenSsh),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                    ClipboardData(text: key.publicKeyOpenSsh));
                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                      content: Text(l(context, '公钥已复制', 'Public key copied'))),
                );
              },
              child: Text(l(context, '复制', 'Copy')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l(context, '关闭', 'Close')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteKey(GitSshKey key) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l(context, '删除 SSH Key', 'Delete SSH key')),
          content: Text(
            l(
              context,
              '确定删除 `${key.name}` 吗？',
              'Delete `${key.name}`?',
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
        );
      },
    );
    if (ok != true) {
      return;
    }
    await widget.controller.deleteGitSshKey(key.id);
  }

  Future<void> _showRemoteCredentialDialog(String type) async {
    final gitSettings =
        widget.controller.state.gitSettings ?? GitSettings.defaults();
    final result = await showDialog<_RemoteCredentialDraft>(
      context: context,
      builder: (context) => _RemoteCredentialDialog(
        type: type,
        gitSettings: gitSettings,
      ),
    );
    if (result == null) {
      return;
    }
    try {
      await widget.controller.saveGitRemoteCredential(
        type: type,
        name: result.name.trim(),
        host: result.host.trim(),
        pathPrefix: result.pathPrefix.trim(),
        username: result.username.trim(),
        secret: result.secret,
        sshKeyId: result.sshKeyId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l(context, '远程认证已保存', 'Remote credential saved'),
          ),
        ),
      );
    } catch (_) {
      rethrow;
    }
  }

  Future<void> _confirmDeleteRemoteCredential(
    GitRemoteCredential credential,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l(context, '删除远程认证', 'Delete remote credential')),
          content: Text(
            l(
              context,
              '确定删除 `${credential.name}` 吗？',
              'Delete `${credential.name}`?',
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
        );
      },
    );
    if (ok != true) {
      return;
    }
    await widget.controller.deleteGitRemoteCredential(credential.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final oc = context.oc;
        final current = widget.modelConfig;
        final connection = current.currentConnection;
        final gitSettings =
            widget.controller.state.gitSettings ?? GitSettings.defaults();
        final themeLabel = context.isDarkMode
            ? l(context, '夜间模式', 'Dark mode')
            : l(context, '日间模式', 'Light mode');
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              12,
              0,
              12,
              MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: oc.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: oc.border),
                boxShadow: [
                  BoxShadow(
                    color: oc.shadow,
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _compactPickerHandle(context),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l(context, '设置', 'Settings'),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: oc.text,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, size: 20),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l(
                          context,
                          '模型连接、Git 身份和远程认证集中在这里管理。',
                          'Manage model connection, Git identity, and remote credentials here.',
                        ),
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: oc.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _SettingsMetaChip(
                            icon: context.isDarkMode
                                ? Icons.dark_mode_outlined
                                : Icons.light_mode_outlined,
                            label: themeLabel,
                          ),
                          _SettingsMetaChip(
                            icon: Icons.tune_rounded,
                            label: current.model,
                          ),
                          if (connection != null)
                            _SettingsMetaChip(
                              icon: Icons.link_rounded,
                              label: connection.name,
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (connection != null) ...[
                        _SettingsSectionCard(
                          icon: Icons.hub_outlined,
                          title: l(context, '模型连接', 'Model connection'),
                          subtitle: l(
                            context,
                            '当前 provider、接口地址和默认模型。',
                            'Current provider, endpoint, and default model.',
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _baseUrlController,
                                decoration: InputDecoration(
                                  labelText: l(context, 'Base URL', 'Base URL'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _apiKeyController,
                                obscureText: true,
                                decoration: InputDecoration(
                                  labelText: l(context, 'API Key', 'API Key'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _modelController,
                                decoration: InputDecoration(
                                  labelText: l(context, '模型', 'Model'),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton(
                                  onPressed: _saveProviderSettings,
                                  child: Text(
                                    l(context, '保存模型设置', 'Save model settings'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      _SettingsSectionCard(
                        icon: Icons.badge_outlined,
                        title: l(context, 'Git 身份', 'Git identity'),
                        subtitle: l(
                          context,
                          '提交作者信息会用于本地 Git 操作。',
                          'Commit author details used for local Git operations.',
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _gitNameController,
                              decoration: InputDecoration(
                                labelText:
                                    l(context, 'Git 用户名', 'Git user name'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _gitEmailController,
                              decoration: InputDecoration(
                                labelText: l(context, 'Git 邮箱', 'Git email'),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton(
                                onPressed: _saveGitIdentity,
                                child: Text(
                                  l(context, '保存 Git 身份', 'Save Git identity'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SettingsSectionCard(
                        icon: Icons.vpn_key_outlined,
                        title: l(context, 'SSH Keys', 'SSH keys'),
                        subtitle: l(
                          context,
                          '支持生成、导入和设置默认 SSH Key。',
                          'Generate, import, and manage your default SSH key.',
                        ),
                        action: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _showImportKeyDialog,
                              icon: const Icon(Icons.file_upload_outlined,
                                  size: 18),
                              label: Text(l(context, '导入', 'Import')),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _showGenerateKeyDialog,
                              icon: const Icon(Icons.auto_awesome_outlined,
                                  size: 18),
                              label: Text(l(context, '生成', 'Generate')),
                            ),
                          ],
                        ),
                        child: gitSettings.sshKeys.isEmpty
                            ? Text(
                                l(
                                  context,
                                  '还没有 SSH Key。当前仅支持 Ed25519 OpenSSH，可直接生成或导入现有私钥。',
                                  'No SSH keys yet. Only Ed25519 OpenSSH is supported now.',
                                ),
                                style:
                                    TextStyle(fontSize: 12.5, color: oc.muted),
                              )
                            : Column(
                                children: [
                                  for (final key in gitSettings.sshKeys) ...[
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 10),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: oc.border),
                                        borderRadius: BorderRadius.circular(14),
                                        color: oc.surface.withOpacity(0.55),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    key.name,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: oc.text,
                                                    ),
                                                  ),
                                                ),
                                                if (gitSettings
                                                        .defaultSshKey?.id ==
                                                    key.id)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: oc.tagGreen
                                                          .withOpacity(0.12),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              999),
                                                    ),
                                                    child: Text(
                                                      l(context, '默认',
                                                          'Default'),
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: oc.tagGreen,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '${key.algorithm}  ${key.fingerprint}',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: oc.muted,
                                              ),
                                            ),
                                            if (key.comment
                                                .trim()
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                key.comment,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: oc.muted,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 10),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                OutlinedButton(
                                                  onPressed: gitSettings
                                                              .defaultSshKey
                                                              ?.id ==
                                                          key.id
                                                      ? null
                                                      : () => widget.controller
                                                              .setDefaultGitSshKey(
                                                            key.id,
                                                          ),
                                                  child: Text(
                                                    l(
                                                      context,
                                                      '设为默认',
                                                      'Set default',
                                                    ),
                                                  ),
                                                ),
                                                OutlinedButton(
                                                  onPressed: () =>
                                                      _showPublicKeyDialog(key),
                                                  child: Text(
                                                    l(
                                                      context,
                                                      '查看公钥',
                                                      'View public key',
                                                    ),
                                                  ),
                                                ),
                                                OutlinedButton(
                                                  onPressed: () =>
                                                      _confirmDeleteKey(key),
                                                  child: Text(
                                                    l(context, '删除', 'Delete'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                      const SizedBox(height: 14),
                      _SettingsSectionCard(
                        icon: Icons.shield_outlined,
                        title: l(context, '远程认证', 'Remote credentials'),
                        subtitle: l(
                          context,
                          '按主机和路径前缀自动匹配远程仓库认证。',
                          'Credentials are matched automatically by host and path prefix.',
                        ),
                        action: PopupMenuButton<String>(
                          onSelected: _showRemoteCredentialDialog,
                          itemBuilder: (context) => [
                            PopupMenuItem<String>(
                              value: 'httpsToken',
                              child: Text(
                                l(context, '新增 HTTPS Token', 'Add HTTPS token'),
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'httpsBasic',
                              child: Text(
                                l(
                                  context,
                                  '新增 HTTPS 账号密码',
                                  'Add HTTPS user/password',
                                ),
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: 'sshKey',
                              child: Text(
                                l(context, '新增 SSH 绑定', 'Add SSH binding'),
                              ),
                            ),
                          ],
                          child: Container(
                            decoration: BoxDecoration(
                              color: oc.surface.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: oc.border),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add_circle_outline,
                                  size: 18,
                                  color: oc.text,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l(context, '新增认证', 'Add credential'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: oc.text,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        child: gitSettings.remoteCredentials.isEmpty
                            ? Text(
                                l(
                                  context,
                                  'SSH 远程如果没有单独配置，会回退到默认 SSH Key。',
                                  'SSH remotes fall back to the default SSH key when no explicit binding exists.',
                                ),
                                style:
                                    TextStyle(fontSize: 12.5, color: oc.muted),
                              )
                            : Column(
                                children: [
                                  for (final credential
                                      in gitSettings.remoteCredentials) ...[
                                    Builder(
                                      builder: (context) {
                                        final sshKey =
                                            credential.sshKeyId == null
                                                ? null
                                                : gitSettings.sshKeys
                                                    .where(
                                                      (item) =>
                                                          item.id ==
                                                          credential.sshKeyId,
                                                    )
                                                    .cast<GitSshKey?>()
                                                    .firstWhere(
                                                      (item) => item != null,
                                                      orElse: () => null,
                                                    );
                                        final typeLabel = credential.type ==
                                                'sshKey'
                                            ? 'SSH'
                                            : credential.type == 'httpsBasic'
                                                ? 'HTTPS Password'
                                                : 'HTTPS Token';
                                        final pathLabel =
                                            credential.pathPrefix.trim().isEmpty
                                                ? '/'
                                                : credential.pathPrefix;
                                        return Container(
                                          width: double.infinity,
                                          margin:
                                              const EdgeInsets.only(bottom: 10),
                                          decoration: BoxDecoration(
                                            border:
                                                Border.all(color: oc.border),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                            color: oc.surface.withOpacity(0.55),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  credential.name,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: oc.text,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '$typeLabel  ${credential.host}$pathLabel',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: oc.muted,
                                                  ),
                                                ),
                                                if (credential.username
                                                    .trim()
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${l(context, '用户名', 'Username')}: ${credential.username}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: oc.muted,
                                                    ),
                                                  ),
                                                ],
                                                if (sshKey != null) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${l(context, 'SSH Key', 'SSH key')}: ${sshKey.name}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: oc.muted,
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 10),
                                                OutlinedButton(
                                                  onPressed: () =>
                                                      _confirmDeleteRemoteCredential(
                                                    credential,
                                                  ),
                                                  child: Text(
                                                    l(context, '删除', 'Delete'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
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
          ),
        );
      },
    );
  }
}

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
        color: oc.panelBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: oc.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: oc.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: oc.text,
              ),
            ),
          ],
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
      decoration: BoxDecoration(
        color: oc.panelBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: oc.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: oc.surface.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: oc.border),
                ),
                child: Icon(icon, size: 18, color: oc.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: oc.text,
                      ),
                    ),
                    if (subtitle?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: oc.muted,
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
        width: 520,
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
