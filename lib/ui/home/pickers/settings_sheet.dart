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
    final gitSettings = widget.controller.state.gitSettings ?? GitSettings.defaults();
    _baseUrlController = TextEditingController(text: connection?.baseUrl ?? '');
    _apiKeyController = TextEditingController(text: connection?.apiKey ?? '');
    _modelController = TextEditingController(text: widget.modelConfig.model);
    _gitNameController = TextEditingController(text: gitSettings.identity.name);
    _gitEmailController = TextEditingController(text: gitSettings.identity.email);
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
      currentModelId:
          _modelController.text.trim().isEmpty ? current.model : _modelController.text.trim(),
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
    final commentController = TextEditingController(text: _gitEmailController.text.trim());
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(l(context, '生成 SSH Key', 'Generate SSH key')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: l(context, '名称', 'Name'),
                    hintText: l(context, '例如：GitHub Key', 'Example: GitHub Key'),
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
                        labelText: l(context, '公钥（可选）', 'Public key (optional)'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: privateController,
                      minLines: 6,
                      maxLines: 10,
                      decoration: InputDecoration(
                        labelText: l(context, '私钥 PEM', 'Private key PEM'),
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
                await Clipboard.setData(ClipboardData(text: key.publicKeyOpenSsh));
                if (!mounted) return;
                Navigator.of(context).pop();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text(l(context, '公钥已复制', 'Public key copied'))),
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
    final gitSettings = widget.controller.state.gitSettings ?? GitSettings.defaults();
    final nameController = TextEditingController();
    final hostController = TextEditingController();
    final pathController = TextEditingController();
    final usernameController = TextEditingController(
      text: type == 'sshKey' ? 'git' : '',
    );
    final secretController = TextEditingController();
    var selectedSshKeyId = gitSettings.defaultSshKey?.id;
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: Text(
                  type == 'sshKey'
                      ? l(context, '新增 SSH 远程认证', 'Add SSH remote credential')
                      : type == 'httpsBasic'
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
                          controller: nameController,
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
                          controller: hostController,
                          decoration: InputDecoration(
                            labelText: l(context, '主机', 'Host'),
                            hintText: 'github.com',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: pathController,
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
                          controller: usernameController,
                          decoration: InputDecoration(
                            labelText: l(context, '用户名', 'Username'),
                            hintText: type == 'sshKey' ? 'git' : '',
                          ),
                        ),
                        if (type == 'sshKey') ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: selectedSshKeyId,
                            items: gitSettings.sshKeys
                                .map(
                                  (key) => DropdownMenuItem<String>(
                                    value: key.id,
                                    child: Text(key.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                selectedSshKeyId = value;
                              });
                            },
                            decoration: InputDecoration(
                              labelText: l(context, 'SSH Key', 'SSH key'),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: secretController,
                            obscureText: true,
                            decoration: InputDecoration(
                              labelText: type == 'httpsBasic'
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
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l(context, '取消', 'Cancel')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(l(context, '保存', 'Save')),
                  ),
                ],
              );
            },
          );
        },
      );
      if (result != true) {
        return;
      }
      await widget.controller.saveGitRemoteCredential(
        type: type,
        name: nameController.text.trim(),
        host: hostController.text.trim(),
        pathPrefix: pathController.text.trim(),
        username: usernameController.text.trim(),
        secret: secretController.text,
        sshKeyId: selectedSshKeyId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l(context, '远程认证已保存', 'Remote credential saved'),
          ),
        ),
      );
    } finally {
      nameController.dispose();
      hostController.dispose();
      pathController.dispose();
      usernameController.dispose();
      secretController.dispose();
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
        final gitSettings = widget.controller.state.gitSettings ?? GitSettings.defaults();
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
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                      if (connection != null) ...[
                        _SettingsSectionTitle(
                          title: l(context, '模型连接', 'Model connection'),
                        ),
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
                            child: Text(l(context, '保存模型设置', 'Save model settings')),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      _SettingsSectionTitle(
                        title: l(context, 'Git 身份', 'Git identity'),
                      ),
                      TextField(
                        controller: _gitNameController,
                        decoration: InputDecoration(
                          labelText: l(context, 'Git 用户名', 'Git user name'),
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
                          child: Text(l(context, '保存 Git 身份', 'Save Git identity')),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _SettingsSectionTitle(
                              title: l(context, 'SSH Keys', 'SSH keys'),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _showImportKeyDialog,
                            icon: const Icon(Icons.file_upload_outlined, size: 18),
                            label: Text(l(context, '导入', 'Import')),
                          ),
                          TextButton.icon(
                            onPressed: _showGenerateKeyDialog,
                            icon: const Icon(Icons.vpn_key_outlined, size: 18),
                            label: Text(l(context, '生成', 'Generate')),
                          ),
                        ],
                      ),
                      if (gitSettings.sshKeys.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l(
                              context,
                              '还没有 SSH Key。你可以直接在这里生成，或者导入已有私钥。',
                              'No SSH keys yet. Generate one here or import an existing private key.',
                            ),
                            style: TextStyle(fontSize: 12.5, color: oc.muted),
                          ),
                        )
                      else
                        ...gitSettings.sshKeys.map((key) {
                          final isDefault = gitSettings.defaultSshKey?.id == key.id;
                          return Container(
                            margin: const EdgeInsets.only(top: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: oc.border),
                              borderRadius: BorderRadius.circular(14),
                              color: oc.panelBackground,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          key.name,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: oc.text,
                                          ),
                                        ),
                                      ),
                                      if (isDefault)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: oc.tagGreen.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            l(context, '默认', 'Default'),
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
                                    style: TextStyle(fontSize: 12, color: oc.muted),
                                  ),
                                  if (key.comment.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      key.comment,
                                      style: TextStyle(fontSize: 12, color: oc.muted),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton(
                                        onPressed: isDefault
                                            ? null
                                            : () => widget.controller.setDefaultGitSshKey(key.id),
                                        child: Text(l(context, '设为默认', 'Set default')),
                                      ),
                                      OutlinedButton(
                                        onPressed: () => _showPublicKeyDialog(key),
                                        child: Text(l(context, '查看公钥', 'View public key')),
                                      ),
                                      OutlinedButton(
                                        onPressed: () => _confirmDeleteKey(key),
                                        child: Text(l(context, '删除', 'Delete')),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _SettingsSectionTitle(
                              title: l(context, '远程认证', 'Remote credentials'),
                            ),
                          ),
                          PopupMenuButton<String>(
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
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Icon(Icons.add_circle_outline, size: 20),
                            ),
                          ),
                        ],
                      ),
                      if (gitSettings.remoteCredentials.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            l(
                              context,
                              '按主机和路径前缀自动匹配远程认证。SSH 远程如果没有单独配置，会回退到默认 SSH Key。',
                              'Remote credentials auto-match by host and path prefix. SSH remotes fall back to the default SSH key when no explicit binding exists.',
                            ),
                            style: TextStyle(fontSize: 12.5, color: oc.muted),
                          ),
                        )
                      else
                        ...gitSettings.remoteCredentials.map((credential) {
                          final sshKey = credential.sshKeyId == null
                              ? null
                              : gitSettings.sshKeys
                                  .where((item) => item.id == credential.sshKeyId)
                                  .cast<GitSshKey?>()
                                  .firstWhere(
                                    (item) => item != null,
                                    orElse: () => null,
                                  );
                          final typeLabel = credential.type == 'sshKey'
                              ? 'SSH'
                              : credential.type == 'httpsBasic'
                                  ? 'HTTPS Password'
                                  : 'HTTPS Token';
                          final pathLabel = credential.pathPrefix.trim().isEmpty
                              ? '/'
                              : credential.pathPrefix;
                          return Container(
                            margin: const EdgeInsets.only(top: 10),
                            decoration: BoxDecoration(
                              border: Border.all(color: oc.border),
                              borderRadius: BorderRadius.circular(14),
                              color: oc.panelBackground,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                    style: TextStyle(fontSize: 12, color: oc.muted),
                                  ),
                                  if (credential.username.trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${l(context, '用户名', 'Username')}: ${credential.username}',
                                      style: TextStyle(fontSize: 12, color: oc.muted),
                                    ),
                                  ],
                                  if (sshKey != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${l(context, 'SSH Key', 'SSH key')}: ${sshKey.name}',
                                      style: TextStyle(fontSize: 12, color: oc.muted),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton(
                                        onPressed: () =>
                                            _confirmDeleteRemoteCredential(credential),
                                        child: Text(l(context, '删除', 'Delete')),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
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

class _SettingsSectionTitle extends StatelessWidget {
  const _SettingsSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: context.oc.text,
        ),
      ),
    );
  }
}
