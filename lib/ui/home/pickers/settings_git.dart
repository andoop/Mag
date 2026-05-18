part of '../../home_page.dart';

// Git-specific settings actions: identity is saved in the shell; SSH keys and
// remote credential dialogs live here.

extension _AppSettingsGitActions on _AppSettingsSheetState {
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
              width: _dialogMaxWidth(context, maxWidth: 520),
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
            width: _dialogMaxWidth(context, maxWidth: 520),
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
}
