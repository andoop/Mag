part of '../../home_page.dart';

// MCP-specific settings actions. Keep server/tool/resource/prompt dialogs here
// so general settings navigation remains easy to scan.

extension _AppSettingsMcpActions on _AppSettingsSheetState {
  Future<void> _showMcpServerDialog([McpServerConfig? existing]) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final urlController = TextEditingController(text: existing?.url ?? '');
    final tokenController = TextEditingController(
      text: existing?.auth?.accessToken ?? '',
    );
    final authEndpointController = TextEditingController(
      text: existing?.oauth?.authorizationEndpoint ?? '',
    );
    final tokenEndpointController = TextEditingController(
      text: existing?.oauth?.tokenEndpoint ?? '',
    );
    final clientIdController = TextEditingController(
      text: existing?.oauth?.clientId ?? '',
    );
    final scopeController = TextEditingController(
      text: existing?.oauth?.scope ?? '',
    );
    final redirectUriController = TextEditingController(
      text: existing?.oauth?.redirectUri ?? 'urn:ietf:wg:oauth:2.0:oob',
    );
    var enabled = existing?.enabled ?? true;
    var authMode = existing?.oauth != null
        ? 'oauth'
        : (existing?.auth?.hasCredentials ?? false)
            ? 'bearer'
            : 'none';
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(
                  existing == null
                      ? l(context, '添加 MCP Server', 'Add MCP server')
                      : l(context, '编辑 MCP Server', 'Edit MCP server'),
                ),
                content: SizedBox(
                  width: _dialogMaxWidth(context, maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: l(context, '名称', 'Name'),
                          hintText: l(
                              context, '例如：GitHub MCP', 'Example: GitHub MCP'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: urlController,
                        decoration: InputDecoration(
                          labelText: l(context, 'HTTP URL', 'HTTP URL'),
                          hintText: 'https://example.com/mcp',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: tokenController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l(context, 'Bearer Token（可选）',
                              'Bearer token (optional)'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: authMode,
                        decoration: InputDecoration(
                          labelText: l(context, '认证方式', 'Authentication mode'),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'none', child: Text('None')),
                          DropdownMenuItem(
                              value: 'bearer', child: Text('Bearer token')),
                          DropdownMenuItem(
                              value: 'oauth', child: Text('OAuth / PKCE')),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            authMode = value ?? 'none';
                          });
                        },
                      ),
                      if (authMode == 'oauth') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: authEndpointController,
                          decoration: InputDecoration(
                            labelText:
                                l(context, '授权端点', 'Authorization endpoint'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: tokenEndpointController,
                          decoration: InputDecoration(
                            labelText: l(context, 'Token 端点', 'Token endpoint'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: clientIdController,
                          decoration: InputDecoration(
                            labelText: l(context, 'Client ID', 'Client ID'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: scopeController,
                          decoration: InputDecoration(
                            labelText: l(context, 'Scopes（空格分隔）',
                                'Scopes (space-separated)'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: redirectUriController,
                          decoration: InputDecoration(
                            labelText:
                                l(context, 'Redirect URI', 'Redirect URI'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: enabled,
                        contentPadding: EdgeInsets.zero,
                        title: Text(l(context, '启用', 'Enabled')),
                        onChanged: (value) {
                          setDialogState(() {
                            enabled = value;
                          });
                        },
                      ),
                    ],
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
      if (result != true) return;
      final name = nameController.text.trim();
      final url = urlController.text.trim();
      if (name.isEmpty || url.isEmpty) {
        if (!mounted) return;
        _showInfo(
          context,
          l(context, '名称和 URL 不能为空。', 'Name and URL are required.'),
        );
        return;
      }
      await widget.controller.saveMcpServer(
        McpServerConfig(
          id: existing?.id ?? newId('mcp'),
          name: name,
          url: url,
          enabled: enabled,
          headers: existing?.headers ?? const {},
          timeoutMs: existing?.timeoutMs ?? 30000,
          auth: authMode == 'bearer'
              ? (tokenController.text.trim().isEmpty
                  ? null
                  : McpAuthState(
                      type: 'bearer',
                      accessToken: tokenController.text.trim(),
                      tokenType: 'Bearer',
                    ))
              : authMode == 'oauth'
                  ? existing?.auth
                  : null,
          oauth: authMode == 'oauth'
              ? McpOAuthConfig(
                  authorizationEndpoint: authEndpointController.text.trim(),
                  tokenEndpoint: tokenEndpointController.text.trim(),
                  clientId: clientIdController.text.trim(),
                  scope: scopeController.text.trim().isEmpty
                      ? null
                      : scopeController.text.trim(),
                  redirectUri: redirectUriController.text.trim().isEmpty
                      ? 'urn:ietf:wg:oauth:2.0:oob'
                      : redirectUriController.text.trim(),
                  pendingCodeVerifier: existing?.oauth?.pendingCodeVerifier,
                  pendingState: existing?.oauth?.pendingState,
                )
              : null,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing == null
                ? l(context, 'MCP Server 已添加', 'MCP server added')
                : l(context, 'MCP Server 已更新', 'MCP server updated'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    } finally {
      nameController.dispose();
      urlController.dispose();
      tokenController.dispose();
      authEndpointController.dispose();
      tokenEndpointController.dispose();
      clientIdController.dispose();
      scopeController.dispose();
      redirectUriController.dispose();
    }
  }

  Future<void> _refreshMcpServer(String serverId) async {
    try {
      await widget.controller.refreshMcpServer(serverId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l(context, 'MCP 已刷新', 'MCP refreshed'))),
      );
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    }
  }

  Future<void> _setMcpServerEnabled(
      McpServerConfig server, bool enabled) async {
    try {
      await widget.controller.saveMcpServer(server.copyWith(enabled: enabled));
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    }
  }

  Future<void> _deleteMcpServer(McpServerConfig server) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l(context, '删除 MCP Server', 'Delete MCP server')),
        content: Text(
          l(
            context,
            '确定删除 `${server.name}` 吗？',
            'Delete `${server.name}`?',
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
    try {
      await widget.controller.deleteMcpServer(server.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l(context, 'MCP Server 已删除', 'MCP server deleted'))),
      );
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    }
  }

  Future<void> _showMcpOAuthSheet(McpServerConfig server) async {
    final codeController = TextEditingController();
    McpOAuthAuthorization? authorization;
    WebViewController? webViewController;

    void captureCode(String? rawUrl) {
      if (rawUrl == null || rawUrl.isEmpty) return;
      try {
        final uri = Uri.parse(rawUrl);
        final code = uri.queryParameters['code'] ?? '';
        if (code.isNotEmpty) {
          codeController.text = code;
        }
      } catch (_) {}
    }

    try {
      authorization = await widget.controller.authorizeMcpOAuth(server.id);
      if (!mounted) return;
      webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              captureCode(request.url);
              return NavigationDecision.navigate;
            },
            onPageStarted: captureCode,
            onPageFinished: captureCode,
          ),
        )
        ..loadRequest(Uri.parse(authorization.url));
      await showDialog<void>(
        context: context,
        builder: (context) {
          final dialogHeight = MediaQuery.of(context).size.height * 0.72;
          return AlertDialog(
            title:
                Text(l(context, '连接 ${server.name}', 'Connect ${server.name}')),
            content: SizedBox(
              width: _dialogMaxWidth(context, maxWidth: 760),
              height: dialogHeight.clamp(420.0, 620.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    authorization!.instructions,
                    style: TextStyle(fontSize: 12.5, color: context.oc.muted),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                      child: WebViewWidget(controller: webViewController!)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    decoration: InputDecoration(
                      labelText: l(
                          context, 'Authorization Code', 'Authorization code'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l(context, '取消', 'Cancel')),
              ),
              FilledButton(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final messenger = ScaffoldMessenger.of(context);
                  final successText =
                      l(context, 'MCP OAuth 已连接', 'MCP OAuth connected');
                  try {
                    await widget.controller.callbackMcpOAuth(
                      serverId: server.id,
                      code: codeController.text.trim(),
                    );
                    if (!mounted) return;
                    navigator.pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(successText),
                      ),
                    );
                  } catch (error) {
                    if (!mounted) return;
                    _showInfo(this.context, error.toString());
                  }
                },
                child: Text(l(context, '完成连接', 'Complete connection')),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    } finally {
      codeController.dispose();
    }
  }

  Future<void> _showMcpResourcesBrowser() async {
    final resources = widget.controller.state.mcpResources;
    if (resources.isEmpty) {
      _showInfo(
        context,
        l(context, '当前没有可用的 MCP resources。',
            'No MCP resources are available yet.'),
      );
      return;
    }
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = resources.where((item) {
              if (query.trim().isEmpty) return true;
              final q = query.trim().toLowerCase();
              return item.name.toLowerCase().contains(q) ||
                  item.serverId.toLowerCase().contains(q) ||
                  item.uri.toLowerCase().contains(q);
            }).toList();
            return AlertDialog(
              title: Text(l(context, 'MCP Resources', 'MCP resources')),
              content: SizedBox(
                width: _dialogMaxWidth(context, maxWidth: 720),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      onChanged: (value) {
                        query = value;
                        setDialogState(() {});
                      },
                      decoration: _compactPickerSearchDecoration(
                        context,
                        hint: l(context, '过滤 resources…', 'Filter resources…'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                l(context, '没有匹配的 resources。',
                                    'No matching resources.'),
                                style: TextStyle(
                                    fontSize: 12.5, color: context.oc.muted),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(item.name),
                                  subtitle:
                                      Text('${item.serverId}\n${item.uri}'),
                                  isThreeLine: true,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () async {
                                    final hostContext = this.context;
                                    try {
                                      final contents = await widget.controller
                                          .readMcpResource(
                                        serverId: item.serverId,
                                        uri: item.uri,
                                      );
                                      if (!mounted) return;
                                      await showDialog<void>(
                                        context: hostContext,
                                        builder: (context) => AlertDialog(
                                          title: Text(item.name),
                                          content: SizedBox(
                                            width: _dialogMaxWidth(context,
                                                maxWidth: 760),
                                            child: SingleChildScrollView(
                                              child: SelectableText(
                                                contents
                                                    .map((e) =>
                                                        e.text ??
                                                        const JsonEncoder
                                                                    .withIndent(
                                                                '  ')
                                                            .convert(
                                                                e.toJson()))
                                                    .join('\n\n'),
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                              child: Text(
                                                  l(context, '关闭', 'Close')),
                                            ),
                                          ],
                                        ),
                                      );
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      _showInfo(context, error.toString());
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l(context, '关闭', 'Close')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMcpToolsBrowser() async {
    final tools = widget.controller.state.mcpTools;
    if (tools.isEmpty) {
      _showInfo(
        context,
        l(context, '当前没有可用的 MCP tools。', 'No MCP tools are available yet.'),
      );
      return;
    }
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = tools.where((item) {
              if (query.trim().isEmpty) return true;
              final q = query.trim().toLowerCase();
              return item.name.toLowerCase().contains(q) ||
                  item.qualifiedName.toLowerCase().contains(q) ||
                  item.serverId.toLowerCase().contains(q) ||
                  item.description.toLowerCase().contains(q) ||
                  (item.title ?? '').toLowerCase().contains(q);
            }).toList();
            return AlertDialog(
              title: Text(l(context, 'MCP Tools', 'MCP tools')),
              content: SizedBox(
                width: _dialogMaxWidth(context, maxWidth: 760),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      onChanged: (value) {
                        query = value;
                        setDialogState(() {});
                      },
                      decoration: _compactPickerSearchDecoration(
                        context,
                        hint: l(context, '搜索 tools…', 'Search tools…'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                l(context, '没有匹配的 tools。',
                                    'No matching tools.'),
                                style: TextStyle(
                                    fontSize: 12.5, color: context.oc.muted),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  title: Text(item.title?.isNotEmpty == true
                                      ? item.title!
                                      : item.name),
                                  subtitle: Text(item.serverId),
                                  trailing:
                                      const Icon(Icons.chevron_right_rounded),
                                  onTap: () => _showMcpToolDetails(item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l(context, '关闭', 'Close')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMcpToolDetails(McpToolDefinition tool) async {
    final schemaText = tool.inputSchema.isEmpty
        ? ''
        : const JsonEncoder.withIndent('  ').convert(tool.inputSchema);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tool.title?.trim().isNotEmpty == true
            ? tool.title!.trim()
            : tool.name),
        content: SizedBox(
          width: _dialogMaxWidth(context, maxWidth: 680),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  tool.qualifiedName,
                  style: TextStyle(fontSize: 12, color: context.oc.muted),
                ),
                if (tool.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SelectableText(tool.description.trim()),
                ],
                if (schemaText.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    l(context, '参数', 'Parameters'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(schemaText),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l(context, '关闭', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showMcpPromptsBrowser() async {
    final prompts = widget.controller.state.mcpPrompts;
    if (prompts.isEmpty) {
      _showInfo(
        context,
        l(context, '当前没有可用的 MCP prompts。', 'No MCP prompts are available yet.'),
      );
      return;
    }
    var query = '';
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = prompts.where((item) {
              if (query.trim().isEmpty) return true;
              final q = query.trim().toLowerCase();
              return item.name.toLowerCase().contains(q) ||
                  item.serverId.toLowerCase().contains(q) ||
                  (item.description ?? '').toLowerCase().contains(q);
            }).toList();
            return AlertDialog(
              title: Text(l(context, 'MCP Prompts', 'MCP prompts')),
              content: SizedBox(
                width: _dialogMaxWidth(context, maxWidth: 720),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      onChanged: (value) {
                        query = value;
                        setDialogState(() {});
                      },
                      decoration: _compactPickerSearchDecoration(
                        context,
                        hint: l(context, '过滤 prompts…', 'Filter prompts…'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                l(context, '没有匹配的 prompts。',
                                    'No matching prompts.'),
                                style: TextStyle(
                                    fontSize: 12.5, color: context.oc.muted),
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(item.name),
                                  subtitle: Text([
                                    item.serverId,
                                    if ((item.description ?? '').isNotEmpty)
                                      item.description!,
                                  ].join('\n')),
                                  isThreeLine:
                                      (item.description ?? '').isNotEmpty,
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () => _showMcpPromptRunDialog(item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l(context, '关闭', 'Close')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMcpPromptRunDialog(McpPromptDefinition prompt) async {
    final controllers = <String, TextEditingController>{
      for (final arg in prompt.arguments) arg.name: TextEditingController(),
    };
    try {
      final run = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(prompt.name),
          content: SizedBox(
            width: _dialogMaxWidth(context, maxWidth: 560),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((prompt.description ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        prompt.description!,
                        style:
                            TextStyle(fontSize: 12.5, color: context.oc.muted),
                      ),
                    ),
                  for (final arg in prompt.arguments) ...[
                    TextField(
                      controller: controllers[arg.name],
                      decoration: InputDecoration(
                        labelText: arg.name,
                        hintText: arg.description,
                      ),
                    ),
                    const SizedBox(height: 12),
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
              child: Text(l(context, '获取 Prompt', 'Get prompt')),
            ),
          ],
        ),
      );
      if (run != true) return;
      final arguments = <String, String>{};
      for (final arg in prompt.arguments) {
        final value = controllers[arg.name]!.text.trim();
        if (value.isNotEmpty) arguments[arg.name] = value;
      }
      final messages = await widget.controller.getMcpPrompt(
        serverId: prompt.serverId,
        promptName: prompt.name,
        arguments: arguments,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(prompt.name),
          content: SizedBox(
            width: _dialogMaxWidth(context, maxWidth: 760),
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ')
                    .convert(messages.map((e) => e.toJson()).toList()),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l(context, '关闭', 'Close')),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }
}
