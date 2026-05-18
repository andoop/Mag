part of '../../home_page.dart';

enum _SettingsDestination {
  home,
  models,
  voice,
  variables,
  mcp,
  git,
}

_SettingsDestination _settingsDestinationFromId(String value) {
  switch (value.trim().toLowerCase()) {
    case 'home':
    case 'overview':
    case '':
      return _SettingsDestination.home;
    case 'models':
      return _SettingsDestination.models;
    case 'voice':
      return _SettingsDestination.voice;
    case 'variables':
      return _SettingsDestination.variables;
    case 'mcp':
      return _SettingsDestination.mcp;
    case 'git':
      return _SettingsDestination.git;
    default:
      return _SettingsDestination.home;
  }
}

double _dialogMaxWidth(
  BuildContext context, {
  required double maxWidth,
  double horizontalMargin = 40,
}) {
  final width = MediaQuery.of(context).size.width - horizontalMargin;
  if (width <= 0) {
    return maxWidth;
  }
  return width < maxWidth ? width : maxWidth;
}

BoxDecoration _settingsSurfaceDecoration(
  BuildContext context, {
  required Color color,
  double radius = 24,
  bool elevated = true,
  bool accent = false,
}) {
  final oc = context.oc;
  final dark = context.isDarkMode;
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color:
          accent ? oc.accent.withOpacity(dark ? 0.28 : 0.18) : oc.borderColor,
    ),
    boxShadow: elevated
        ? [
            BoxShadow(
              color: dark
                  ? Colors.black.withOpacity(0.28)
                  : Colors.black.withOpacity(0.06),
              blurRadius: 28,
              spreadRadius: -10,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(dark ? 0.03 : 0.72),
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ]
        : null,
  );
}

InputDecoration _settingsInputDecoration(
  BuildContext context, {
  required String label,
  String? hint,
  IconData? icon,
}) {
  final oc = context.oc;
  final radius = BorderRadius.circular(16);
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, size: 18),
    filled: true,
    fillColor:
        oc.composerOptionBg.withOpacity(context.isDarkMode ? 0.62 : 0.72),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: oc.softBorderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: oc.softBorderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: oc.accent.withOpacity(0.55)),
    ),
  );
}

Future<void> openAppSettingsSheet(
  BuildContext context, {
  required AppController controller,
  required ModelConfig modelConfig,
  String initialDestination = 'overview',
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) => _AppSettingsSheet(
        controller: controller,
        modelConfig: modelConfig,
        initialDestination: initialDestination,
      ),
    ),
  );
}

class _AppSettingsSheet extends StatefulWidget {
  const _AppSettingsSheet({
    required this.controller,
    required this.modelConfig,
    required this.initialDestination,
  });

  final AppController controller;
  final ModelConfig modelConfig;
  final String initialDestination;

  @override
  State<_AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<_AppSettingsSheet> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  late final TextEditingController _voiceQwenApiKeyController;
  late final TextEditingController _voiceQwenEndpointController;
  late final TextEditingController _voiceQwenModelController;
  late final TextEditingController _voiceDoubaoApiKeyController;
  late final TextEditingController _voiceDoubaoAppKeyController;
  late final TextEditingController _voiceDoubaoAccessKeyController;
  late final TextEditingController _voiceDoubaoResourceIdController;
  late final TextEditingController _voiceDoubaoEndpointController;
  late final TextEditingController _voiceLanguageController;
  late final TextEditingController _gitNameController;
  late final TextEditingController _gitEmailController;
  late _SettingsDestination _destination;
  String _mcpQuery = '';
  String _modelsQuery = '';
  bool _showAllMcpServers = false;
  bool _showAllSshKeys = false;
  bool _showAllRemoteCredentials = false;
  final Map<String, bool> _expandedModelProviders = <String, bool>{};
  final Map<String, bool> _expandedMcpToolLists = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _destination = _settingsDestinationFromId(widget.initialDestination);
    final connection = widget.modelConfig.currentConnection;
    final gitSettings =
        widget.controller.state.gitSettings ?? GitSettings.defaults();
    final voiceConfig = widget.controller.state.voiceConfig;
    _baseUrlController = TextEditingController(text: connection?.baseUrl ?? '');
    _apiKeyController = TextEditingController(text: connection?.apiKey ?? '');
    _modelController = TextEditingController(text: widget.modelConfig.model);
    _voiceQwenApiKeyController =
        TextEditingController(text: voiceConfig.qwen.apiKey);
    _voiceQwenEndpointController =
        TextEditingController(text: voiceConfig.qwen.endpoint);
    _voiceQwenModelController =
        TextEditingController(text: voiceConfig.qwen.model);
    _voiceDoubaoApiKeyController =
        TextEditingController(text: voiceConfig.doubao.apiKey);
    _voiceDoubaoAppKeyController =
        TextEditingController(text: voiceConfig.doubao.appKey);
    _voiceDoubaoAccessKeyController =
        TextEditingController(text: voiceConfig.doubao.accessKey);
    _voiceDoubaoResourceIdController =
        TextEditingController(text: voiceConfig.doubao.resourceId);
    _voiceDoubaoEndpointController =
        TextEditingController(text: voiceConfig.doubao.endpoint);
    _voiceLanguageController =
        TextEditingController(text: voiceConfig.language);
    _gitNameController = TextEditingController(text: gitSettings.identity.name);
    _gitEmailController =
        TextEditingController(text: gitSettings.identity.email);
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _voiceQwenApiKeyController.dispose();
    _voiceQwenEndpointController.dispose();
    _voiceQwenModelController.dispose();
    _voiceDoubaoApiKeyController.dispose();
    _voiceDoubaoAppKeyController.dispose();
    _voiceDoubaoAccessKeyController.dispose();
    _voiceDoubaoResourceIdController.dispose();
    _voiceDoubaoEndpointController.dispose();
    _voiceLanguageController.dispose();
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
    try {
      await widget.controller.discoverProviderModels(
        providerId: connection.id,
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        usePublicToken:
            connection.id == 'mag' && _apiKeyController.text.trim().isEmpty,
      );
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l(context, '模型设置已保存', 'Model settings saved'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    }
  }

  Future<void> _refreshProviderCatalog() async {
    final current = widget.modelConfig;
    final connection = current.currentConnection;
    if (connection == null) {
      return;
    }
    try {
      await widget.controller.discoverProviderModels(
        providerId: connection.id,
        baseUrl: _baseUrlController.text.trim().isEmpty
            ? connection.baseUrl
            : _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        usePublicToken:
            connection.id == 'mag' && _apiKeyController.text.trim().isEmpty,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l(context, '模型目录已刷新', 'Model catalog refreshed'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    }
  }

  Future<void> _saveVoiceSettings({
    bool? enabled,
    VoiceRealtimeProvider? provider,
    bool? serverVad,
  }) async {
    final current = widget.controller.state.voiceConfig;
    final next = current.copyWith(
      enabled: enabled ?? current.enabled,
      provider: provider ?? current.provider,
      language: _voiceLanguageController.text.trim().isEmpty
          ? 'zh'
          : _voiceLanguageController.text.trim(),
      serverVad: serverVad ?? current.serverVad,
      qwen: current.qwen.copyWith(
        apiKey: _voiceQwenApiKeyController.text.trim(),
        endpoint: _voiceQwenEndpointController.text.trim().isEmpty
            ? const QwenVoiceConfig().endpoint
            : _voiceQwenEndpointController.text.trim(),
        model: _voiceQwenModelController.text.trim().isEmpty
            ? const QwenVoiceConfig().model
            : _voiceQwenModelController.text.trim(),
      ),
      doubao: current.doubao.copyWith(
        apiKey: _voiceDoubaoApiKeyController.text.trim(),
        appKey: _voiceDoubaoAppKeyController.text.trim(),
        accessKey: _voiceDoubaoAccessKeyController.text.trim(),
        resourceId: _voiceDoubaoResourceIdController.text.trim().isEmpty
            ? const DoubaoVoiceConfig().resourceId
            : _voiceDoubaoResourceIdController.text.trim(),
        endpoint: _voiceDoubaoEndpointController.text.trim().isEmpty
            ? const DoubaoVoiceConfig().endpoint
            : _voiceDoubaoEndpointController.text.trim(),
      ),
    );
    try {
      await widget.controller.saveVoiceConfig(next);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l(context, '语音输入设置已保存', 'Voice input settings saved')),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    }
  }

  Future<void> _disconnectCurrentProvider() async {
    final connection = widget.modelConfig.currentConnection;
    if (connection == null) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l(context, '断开 Provider', 'Disconnect provider')),
          content: Text(
            l(
              context,
              '确定断开 `${connection.name}` 吗？已保存的接口地址和 API Key 会一并移除。',
              'Disconnect `${connection.name}`? The saved endpoint and API key will be removed.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l(context, '取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l(context, '断开', 'Disconnect')),
            ),
          ],
        );
      },
    );
    if (ok != true) {
      return;
    }
    if (!mounted) return;
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      final navigator = Navigator.of(context);
      final successMessage =
          l(context, 'Provider 已断开', 'Provider disconnected');
      await widget.controller.disconnectProvider(connection.id);
      if (!mounted) return;
      _showInfoWithMessenger(
        messenger,
        successMessage,
      );
      navigator.pop();
    } catch (error) {
      if (!mounted) return;
      _showInfo(context, error.toString());
    }
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

  Future<void> _showSkillsBrowser() async {
    final workspace = widget.controller.state.workspace;
    if (workspace == null) {
      _showInfo(
        context,
        l(
          context,
          '请先打开一个工作区，再查看 skills。',
          'Open a workspace before browsing skills.',
        ),
      );
      return;
    }
    await _openSkillsBrowser(
      context,
      controller: widget.controller,
      workspace: workspace,
    );
  }

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

  Future<bool> _handleSystemBack() async {
    if (_destination == _SettingsDestination.home) {
      return true;
    }
    setState(() {
      _destination = _SettingsDestination.home;
    });
    return false;
  }

  String _destinationLabel(
      BuildContext context, _SettingsDestination destination) {
    switch (destination) {
      case _SettingsDestination.home:
        return l(context, '设置', 'Settings');
      case _SettingsDestination.models:
        return l(context, '模型', 'Models');
      case _SettingsDestination.voice:
        return l(context, '语音', 'Voice');
      case _SettingsDestination.variables:
        return l(context, '变量', 'Variables');
      case _SettingsDestination.mcp:
        return 'MCP';
      case _SettingsDestination.git:
        return 'Git';
    }
  }

  Widget _buildSettingsBody(
    BuildContext context, {
    required Widget child,
  }) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      children: [child],
    );
  }

  bool _matchesSettingsModelQuery(_ModelChoice item, String query) {
    if (query.trim().isEmpty) return true;
    final normalized = query.trim().toLowerCase();
    final providerLabel = _providerLabel(
      item.providerId,
      config: widget.controller.state.modelConfig,
      state: widget.controller.state,
    ).toLowerCase();
    return item.name.toLowerCase().contains(normalized) ||
        item.id.toLowerCase().contains(normalized) ||
        item.providerId.toLowerCase().contains(normalized) ||
        providerLabel.contains(normalized);
  }

  Future<void> _setProviderModelsVisibility(
    _ProviderModelGroup group,
    bool visible,
  ) async {
    for (final item in group.models) {
      await widget.controller.setModelVisibility(
        providerId: item.providerId,
        modelId: item.id,
        visible: visible,
      );
    }
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildSettingsHomePage(
    BuildContext context, {
    required ModelConfig current,
    required ProviderConnection? connection,
    required GitSettings gitSettings,
  }) {
    final state = widget.controller.state;
    final voice = state.voiceConfig;
    final mcpServers = state.mcpServers;
    final connectedMcp =
        state.mcpStatuses.values.where((item) => item.connected).length;
    final allModelGroups = _connectedModelGroups(current, state: state);
    final totalModels =
        allModelGroups.fold<int>(0, (sum, group) => sum + group.models.length);
    final visibleModels = allModelGroups.fold<int>(
      0,
      (sum, group) =>
          sum +
          group.models.where((item) => _isModelVisible(current, item)).length,
    );
    final variables = state.appVariables;
    final aiVariables = variables.where((item) => item.allowAiUse).length;
    final credentialCount =
        gitSettings.sshKeys.length + gitSettings.remoteCredentials.length;
    final workspace = state.workspace;

    void open(_SettingsDestination destination) {
      setState(() {
        _destination = destination;
      });
    }

    return _buildSettingsBody(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsHomeTile(
            icon: Icons.hub_outlined,
            title: l(context, '模型', 'Models'),
            subtitle: connection == null
                ? l(context, '未连接 Provider', 'No provider connected')
                : '${connection.name} · ${current.model}',
            trailing:
                '$visibleModels/$totalModels ${l(context, '可用', 'available')}',
            onTap: () => open(_SettingsDestination.models),
          ),
          _SettingsHomeTile(
            icon: Icons.mic_none_rounded,
            title: l(context, '语音', 'Voice'),
            subtitle: voice.enabled
                ? '${voice.providerId} · ${voice.language}'
                : l(context, '关闭', 'Off'),
            trailing: voice.selectedProviderConfigured
                ? l(context, '已配置', 'Configured')
                : l(context, '未配置', 'Not set'),
            onTap: () => open(_SettingsDestination.voice),
          ),
          _SettingsHomeTile(
            icon: Icons.extension_outlined,
            title: 'MCP',
            subtitle: '$connectedMcp/${mcpServers.length} servers',
            trailing:
                '${state.mcpTools.length} tools · ${state.mcpResources.length} resources',
            onTap: () => open(_SettingsDestination.mcp),
          ),
          _SettingsHomeTile(
            icon: Icons.key_outlined,
            title: l(context, '变量与密钥', 'Variables & secrets'),
            subtitle:
                '${variables.length} ${l(context, '项', 'items')} · $aiVariables AI',
            trailing: variables.isEmpty ? l(context, '空', 'Empty') : null,
            onTap: () => open(_SettingsDestination.variables),
          ),
          _SettingsHomeTile(
            icon: Icons.source_outlined,
            title: 'Git',
            subtitle: gitSettings.identity.name.trim().isEmpty
                ? l(context, '未设置身份', 'No identity')
                : '${gitSettings.identity.name} · ${gitSettings.identity.email}',
            trailing: '$credentialCount ${l(context, '凭据', 'credentials')}',
            onTap: () => open(_SettingsDestination.git),
          ),
          _SettingsHomeTile(
            icon: Icons.auto_awesome_outlined,
            title: 'Skills',
            subtitle: workspace == null
                ? l(context, '未打开工作区', 'No workspace')
                : workspace.name,
            trailing: l(context, '浏览', 'Browse'),
            onTap: _showSkillsBrowser,
          ),
        ],
      ),
    );
  }

  Widget _buildModelsPage(
    BuildContext context, {
    required ModelConfig current,
    required ProviderConnection? connection,
  }) {
    final state = widget.controller.state;
    final allGroups = _connectedModelGroups(
      current,
      state: state,
    )
        .map((group) {
          final matches = group.models
              .where((item) => _matchesSettingsModelQuery(item, _modelsQuery))
              .toList();
          return _ProviderModelGroup(
            provider: group.provider,
            models: matches,
          );
        })
        .where((group) => group.models.isNotEmpty)
        .toList();
    var visibleModelCount = 0;
    var totalModelCount = 0;
    for (final group in allGroups) {
      totalModelCount += group.models.length;
      visibleModelCount +=
          group.models.where((item) => _isModelVisible(current, item)).length;
      _expandedModelProviders.putIfAbsent(group.provider.id, () => false);
    }
    return _buildSettingsBody(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsSectionCard(
            icon: Icons.hub_outlined,
            title: l(context, '模型连接', 'Model connection'),
            child: connection == null
                ? Text(
                    l(
                      context,
                      '还没有连接 provider。',
                      'No provider connected.',
                    ),
                    style: TextStyle(fontSize: 12.5, color: context.oc.muted),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _baseUrlController,
                        decoration: _settingsInputDecoration(
                          context,
                          label: l(context, 'Base URL', 'Base URL'),
                          icon: Icons.link_rounded,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _apiKeyController,
                        obscureText: true,
                        decoration: _settingsInputDecoration(
                          context,
                          label: l(context, 'API Key', 'API Key'),
                          icon: Icons.key_rounded,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _modelController,
                        decoration: _settingsInputDecoration(
                          context,
                          label: l(context, '模型', 'Model'),
                          icon: Icons.auto_awesome_rounded,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _SettingsActionButton(
                            onPressed: _refreshProviderCatalog,
                            icon: Icons.refresh_rounded,
                            label: l(context, '刷新模型目录', 'Refresh catalog'),
                          ),
                          _SettingsActionButton(
                            onPressed: _disconnectCurrentProvider,
                            icon: Icons.link_off_rounded,
                            label: l(context, '断开', 'Disconnect'),
                          ),
                          _SettingsActionButton(
                            onPressed: _saveProviderSettings,
                            icon: Icons.check_rounded,
                            label: l(context, '保存', 'Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          _SettingsSectionCard(
            icon: Icons.tune_rounded,
            title:
                '$visibleModelCount/$totalModelCount ${l(context, '可用模型', 'available models')}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  onChanged: (value) {
                    setState(() {
                      _modelsQuery = value;
                    });
                  },
                  decoration: _compactPickerSearchDecoration(
                    context,
                    hint: l(context, '过滤模型…', 'Filter models…'),
                  ),
                ),
                const SizedBox(height: 12),
                if (allGroups.isEmpty)
                  Text(
                    _modelsQuery.trim().isEmpty
                        ? l(
                            context,
                            '还没有可管理的模型。先连接 provider 或刷新当前模型目录。',
                            'No models available yet. Connect a provider or refresh the current catalog first.',
                          )
                        : l(context, '没有匹配的模型。', 'No matching models.'),
                    style: TextStyle(fontSize: 12.5, color: context.oc.muted),
                  )
                else
                  Column(
                    children: allGroups.map((group) {
                      final provider = group.provider;
                      final models = group.models;
                      final providerId = provider.id;
                      final expanded = _modelsQuery.trim().isNotEmpty ||
                          (_expandedModelProviders[providerId] ?? false);
                      final visibleCount = models
                          .where((item) => _isModelVisible(current, item))
                          .length;
                      final allVisible = visibleCount == models.length;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          decoration: _settingsSurfaceDecoration(
                            context,
                            color: context.oc.composerOptionBg
                                .withOpacity(context.isDarkMode ? 0.50 : 0.68),
                            radius: 18,
                            elevated: false,
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(18),
                                ),
                                onTap: () {
                                  if (_modelsQuery.trim().isNotEmpty) return;
                                  setState(() {
                                    _expandedModelProviders[providerId] =
                                        !expanded;
                                  });
                                },
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(13, 11, 13, 11),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              provider.name,
                                              style: TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                                color: context.oc.foreground,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '$visibleCount / ${models.length} ${l(context, '可见模型', 'visible models')}',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color:
                                                    context.oc.foregroundMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      _SettingsMiniSwitch(
                                        value: allVisible,
                                        onChanged: (value) =>
                                            _setProviderModelsVisibility(
                                                group, value),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        expanded
                                            ? Icons.expand_less_rounded
                                            : Icons.expand_more_rounded,
                                        size: 18,
                                        color: context.oc.muted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (expanded) ...[
                                Divider(
                                    height: 1,
                                    color: context.oc.softBorderColor),
                                for (var i = 0; i < models.length; i++) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 9,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  models[i].name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              if (_modelChoiceIsFree(
                                                  models[i])) ...[
                                                const SizedBox(width: 6),
                                                OcModelTag(
                                                  label:
                                                      l(context, '免费', 'Free'),
                                                ),
                                              ],
                                              if (_modelChoiceIsLatest(
                                                  models[i])) ...[
                                                const SizedBox(width: 6),
                                                OcModelTag(
                                                  label: l(
                                                      context, '最新', 'Latest'),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        _SettingsMiniSwitch(
                                          value: _isModelVisible(
                                              current, models[i]),
                                          onChanged: (value) async {
                                            await widget.controller
                                                .setModelVisibility(
                                              providerId: models[i].providerId,
                                              modelId: models[i].id,
                                              visible: value,
                                            );
                                            if (!mounted) return;
                                            setState(() {});
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (i != models.length - 1)
                                    Divider(
                                        height: 1, color: context.oc.border),
                                ],
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoicePage(BuildContext context) {
    final config = widget.controller.state.voiceConfig;
    final selectedProvider = config.provider;
    return _buildSettingsBody(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsSectionCard(
            icon: Icons.mic_none_rounded,
            title: l(context, '语音输入', 'Voice input'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsToggleRow(
                  label: l(context, '启用', 'Enabled'),
                  value: config.enabled,
                  onChanged: (value) => _saveVoiceSettings(enabled: value),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<VoiceRealtimeProvider>(
                  value: selectedProvider,
                  decoration: _settingsInputDecoration(
                    context,
                    label: l(context, '语音 Provider', 'Voice provider'),
                    icon: Icons.cloud_outlined,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: VoiceRealtimeProvider.qwen,
                      child: Text(
                          l(context, 'Qwen ASR Realtime', 'Qwen ASR Realtime')),
                    ),
                    DropdownMenuItem(
                      value: VoiceRealtimeProvider.doubao,
                      child:
                          Text(l(context, '豆包 / 火山引擎', 'Doubao / Volcengine')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    _saveVoiceSettings(provider: value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _voiceLanguageController,
                  decoration: _settingsInputDecoration(
                    context,
                    label: l(context, '语言', 'Language'),
                    hint: 'zh',
                    icon: Icons.translate_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                _SettingsToggleRow(
                  label: 'Server VAD',
                  value: config.serverVad,
                  onChanged: (value) => _saveVoiceSettings(serverVad: value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (selectedProvider == VoiceRealtimeProvider.qwen)
            _SettingsSectionCard(
              icon: Icons.auto_awesome_outlined,
              title: l(context, 'Qwen ASR', 'Qwen ASR'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _voiceQwenApiKeyController,
                    obscureText: true,
                    decoration: _settingsInputDecoration(
                      context,
                      label: 'DashScope API Key',
                      icon: Icons.key_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _voiceQwenEndpointController,
                    decoration: _settingsInputDecoration(
                      context,
                      label: 'Endpoint',
                      icon: Icons.link_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _voiceQwenModelController,
                    decoration: _settingsInputDecoration(
                      context,
                      label: l(context, '模型', 'Model'),
                      icon: Icons.memory_rounded,
                    ),
                  ),
                ],
              ),
            )
          else
            _SettingsSectionCard(
              icon: Icons.graphic_eq_rounded,
              title: l(context, '豆包语音', 'Doubao voice'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _voiceDoubaoApiKeyController,
                    obscureText: true,
                    decoration: _settingsInputDecoration(
                      context,
                      label: 'X-Api-Key',
                      icon: Icons.key_rounded,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _voiceDoubaoAppKeyController,
                    obscureText: true,
                    decoration: _settingsInputDecoration(
                      context,
                      label: 'X-Api-App-Key',
                      icon: Icons.badge_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _voiceDoubaoAccessKeyController,
                    obscureText: true,
                    decoration: _settingsInputDecoration(
                      context,
                      label: 'X-Api-Access-Key',
                      icon: Icons.vpn_key_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _voiceDoubaoResourceIdController,
                    decoration: _settingsInputDecoration(
                      context,
                      label: 'X-Api-Resource-Id',
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _voiceDoubaoEndpointController,
                    decoration: _settingsInputDecoration(
                      context,
                      label: 'Endpoint',
                      icon: Icons.link_rounded,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: _SettingsActionButton(
              onPressed: () => _saveVoiceSettings(),
              icon: Icons.check_rounded,
              label: l(context, '保存', 'Save'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariablesPage(BuildContext context) {
    final variables = widget.controller.state.appVariables;
    final aiEnabledCount = variables.where((item) => item.allowAiUse).length;
    return _buildSettingsBody(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsSectionCard(
            icon: Icons.key_outlined,
            title: l(context, '变量与密钥', 'Variables & secrets'),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SettingsMetaChip(
                  icon: Icons.inventory_2_outlined,
                  label: '${variables.length} ${l(context, '项', 'items')}',
                ),
                _SettingsMetaChip(
                  icon: Icons.smart_toy_outlined,
                  label:
                      '$aiEnabledCount ${l(context, '允许 AI 使用', 'AI-enabled')}',
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SettingsActionButton(
                  onPressed: _showAppVariableDialog,
                  icon: Icons.add_rounded,
                  label: l(context, '添加变量', 'Add variable'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SettingsSectionCard(
            icon: Icons.list_alt_outlined,
            title: l(context, '已保存', 'Saved'),
            child: variables.isEmpty
                ? Text(
                    l(
                      context,
                      '还没有变量。',
                      'No variables yet.',
                    ),
                    style: TextStyle(fontSize: 12.5, color: context.oc.muted),
                  )
                : Column(
                    children: [
                      for (final variable in variables) ...[
                        _AppVariableTile(
                          variable: variable,
                          onCopyName: () => _copyVariableName(variable),
                          onReveal: () => _showVariableValue(variable),
                          onDelete: () => _deleteAppVariable(variable),
                          onAiAccessChanged: (value) =>
                              widget.controller.setAppVariableAiAccess(
                            variable.id,
                            value,
                          ),
                        ),
                        if (variable != variables.last)
                          const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMcpPage(BuildContext context) {
    final oc = context.oc;
    final servers = widget.controller.state.mcpServers;
    final statuses = widget.controller.state.mcpStatuses;
    final tools = widget.controller.state.mcpTools;
    final resources = widget.controller.state.mcpResources;
    final prompts = widget.controller.state.mcpPrompts;
    final connectedCount =
        statuses.values.where((item) => item.connected).length;
    final filteredServers = servers.where((server) {
      if (_mcpQuery.trim().isEmpty) return true;
      final q = _mcpQuery.trim().toLowerCase();
      return server.name.toLowerCase().contains(q) ||
          server.url.toLowerCase().contains(q) ||
          server.id.toLowerCase().contains(q) ||
          tools.where((tool) => tool.serverId == server.id).any((tool) =>
              tool.name.toLowerCase().contains(q) ||
              tool.description.toLowerCase().contains(q) ||
              (tool.title ?? '').toLowerCase().contains(q));
    }).toList();
    final visibleServers = _showAllMcpServers || filteredServers.length <= 3
        ? filteredServers
        : filteredServers.take(3).toList();
    return _buildSettingsBody(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SettingsSectionCard(
            icon: Icons.extension_outlined,
            title: 'MCP',
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SettingsActionButton(
                  onPressed: () => _showMcpServerDialog(),
                  icon: Icons.add_link_outlined,
                  label: l(context, '添加 Server', 'Add server'),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SettingsMetaChip(
                      icon: Icons.cloud_done_outlined,
                      label: '$connectedCount/${servers.length} servers',
                    ),
                    _SettingsMetaChip(
                      icon: Icons.build_circle_outlined,
                      label: '${tools.length} tools',
                    ),
                    _SettingsMetaChip(
                      icon: Icons.inventory_2_outlined,
                      label: '${resources.length} resources',
                    ),
                    _SettingsMetaChip(
                      icon: Icons.text_snippet_outlined,
                      label: '${prompts.length} prompts',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SettingsActionButton(
                      onPressed: _showMcpToolsBrowser,
                      label: 'Tools',
                    ),
                    _SettingsActionButton(
                      onPressed: _showMcpResourcesBrowser,
                      label: 'Resources',
                    ),
                    _SettingsActionButton(
                      onPressed: _showMcpPromptsBrowser,
                      label: 'Prompts',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  onChanged: (value) {
                    setState(() {
                      _mcpQuery = value;
                      _showAllMcpServers = false;
                    });
                  },
                  decoration: _compactPickerSearchDecoration(
                    context,
                    hint: l(context, '搜索 server 或 tool…',
                        'Search servers or tools…'),
                  ),
                ),
                const SizedBox(height: 12),
                if (servers.isEmpty)
                  Text(
                    l(
                      context,
                      '还没有 MCP server。',
                      'No MCP servers yet.',
                    ),
                    style: TextStyle(fontSize: 12.5, color: oc.muted),
                  )
                else if (filteredServers.isEmpty)
                  Text(
                    l(context, '没有匹配的 MCP server。', 'No matching MCP servers.'),
                    style: TextStyle(fontSize: 12.5, color: oc.muted),
                  )
                else ...[
                  for (final server in visibleServers) ...[
                    _buildMcpServerCard(context, server, statuses[server.id]),
                    if (server != visibleServers.last)
                      const SizedBox(height: 10),
                  ],
                  if (filteredServers.length > visibleServers.length) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _SettingsActionButton(
                        onPressed: () {
                          setState(() {
                            _showAllMcpServers = true;
                          });
                        },
                        icon: Icons.expand_more_rounded,
                        label: l(
                          context,
                          '查看全部 ${filteredServers.length} 个 server',
                          'Show all ${filteredServers.length} servers',
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGitPage(BuildContext context,
      {required GitSettings gitSettings}) {
    final sshKeys = _showAllSshKeys || gitSettings.sshKeys.length <= 2
        ? gitSettings.sshKeys
        : gitSettings.sshKeys.take(2).toList();
    final remoteCredentials =
        _showAllRemoteCredentials || gitSettings.remoteCredentials.length <= 2
            ? gitSettings.remoteCredentials
            : gitSettings.remoteCredentials.take(2).toList();
    return _buildSettingsBody(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  decoration: _settingsInputDecoration(
                    context,
                    label: l(context, 'Git 用户名', 'Git user name'),
                    icon: Icons.person_outline_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _gitEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _settingsInputDecoration(
                    context,
                    label: l(context, 'Git 邮箱', 'Git email'),
                    icon: Icons.alternate_email_rounded,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: _SettingsActionButton(
                    onPressed: _saveGitIdentity,
                    icon: Icons.check_rounded,
                    label: l(context, '保存 Git 身份', 'Save Git identity'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildGitSshSection(context, gitSettings, sshKeys),
          const SizedBox(height: 14),
          _buildRemoteCredentialSection(
              context, gitSettings, remoteCredentials),
        ],
      ),
    );
  }

  Widget _buildCurrentDestinationPage(
    BuildContext context, {
    required ModelConfig current,
    required ProviderConnection? connection,
    required GitSettings gitSettings,
  }) {
    switch (_destination) {
      case _SettingsDestination.home:
        return _buildSettingsHomePage(
          context,
          current: current,
          connection: connection,
          gitSettings: gitSettings,
        );
      case _SettingsDestination.models:
        return _buildModelsPage(
          context,
          current: current,
          connection: connection,
        );
      case _SettingsDestination.voice:
        return _buildVoicePage(context);
      case _SettingsDestination.variables:
        return _buildVariablesPage(context);
      case _SettingsDestination.mcp:
        return _buildMcpPage(context);
      case _SettingsDestination.git:
        return _buildGitPage(
          context,
          gitSettings: gitSettings,
        );
    }
  }

  Widget _buildMcpServerCard(
    BuildContext context,
    McpServerConfig server,
    McpServerStatus? status,
  ) {
    final oc = context.oc;
    final healthy = status?.connected ?? false;
    final tools = widget.controller.state.mcpTools
        .where((item) => item.serverId == server.id)
        .toList();
    final resources = widget.controller.state.mcpResources
        .where((item) => item.serverId == server.id)
        .toList();
    final prompts = widget.controller.state.mcpPrompts
        .where((item) => item.serverId == server.id)
        .toList();
    final toolsExpanded = _expandedMcpToolLists[server.id] ?? false;
    final authLabel = server.oauth != null
        ? (server.hasAuth ? 'OAuth' : l(context, 'OAuth 未连接', 'OAuth pending'))
        : server.hasAuth
            ? 'Bearer'
            : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 13),
      decoration: _settingsSurfaceDecoration(
        context,
        color:
            oc.composerOptionBg.withOpacity(context.isDarkMode ? 0.50 : 0.68),
        radius: 18,
        elevated: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: oc.foreground,
                      ),
                    ),
                    if ((status?.error ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        status!.error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
              _SettingsMiniSwitch(
                value: server.enabled,
                onChanged: (value) => _setMcpServerEnabled(server, value),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: healthy
                    ? l(context, '已连接', 'Connected')
                    : l(context, '未连接', 'Disconnected'),
                child: Icon(
                  healthy
                      ? Icons.check_circle_outline
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: healthy ? Colors.green : oc.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (authLabel.isNotEmpty)
                _SettingsMetaChip(
                  icon: Icons.lock_outline,
                  label: authLabel,
                ),
              _SettingsMetaChip(
                icon: Icons.build_circle_outlined,
                label:
                    '${tools.isEmpty ? (status?.toolCount ?? 0) : tools.length} tools',
              ),
              _SettingsMetaChip(
                icon: Icons.inventory_2_outlined,
                label:
                    '${resources.isEmpty ? (status?.resourceCount ?? 0) : resources.length} resources',
              ),
              _SettingsMetaChip(
                icon: Icons.text_snippet_outlined,
                label:
                    '${prompts.isEmpty ? (status?.promptCount ?? 0) : prompts.length} prompts',
              ),
            ],
          ),
          if (tools.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _expandedMcpToolLists[server.id] = !toolsExpanded;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.build_circle_outlined,
                        size: 17, color: oc.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l(context, '工具列表', 'Tool list'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: oc.foreground,
                        ),
                      ),
                    ),
                    Icon(
                      toolsExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: oc.muted,
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (toolsExpanded) ...[
            const SizedBox(height: 8),
            Column(
              children: [
                for (final tool in tools) ...[
                  _McpToolPreviewTile(
                    tool: tool,
                    onTap: () => _showMcpToolDetails(tool),
                  ),
                  if (tool != tools.last) const SizedBox(height: 8),
                ],
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SettingsActionButton(
                onPressed: () => _showMcpServerDialog(server),
                icon: Icons.edit_outlined,
                label: l(context, '编辑', 'Edit'),
              ),
              _SettingsActionButton(
                onPressed: () => _refreshMcpServer(server.id),
                icon: Icons.refresh_rounded,
                label: l(context, '刷新', 'Refresh'),
              ),
              if (server.oauth != null)
                _SettingsActionButton(
                  onPressed: () => _showMcpOAuthSheet(server),
                  icon: Icons.lock_open_outlined,
                  label: server.hasAuth
                      ? l(context, '重连 OAuth', 'Reconnect OAuth')
                      : l(context, '连接 OAuth', 'Connect OAuth'),
                ),
              _SettingsActionButton(
                onPressed: () => _deleteMcpServer(server),
                icon: Icons.delete_outline,
                label: l(context, '删除', 'Delete'),
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGitSshSection(
    BuildContext context,
    GitSettings gitSettings,
    List<GitSshKey> visibleKeys,
  ) {
    final oc = context.oc;
    return _SettingsSectionCard(
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
          _SettingsActionButton(
            onPressed: _showImportKeyDialog,
            icon: Icons.file_upload_outlined,
            label: l(context, '导入', 'Import'),
          ),
          _SettingsActionButton(
            onPressed: _showGenerateKeyDialog,
            icon: Icons.auto_awesome_outlined,
            label: l(context, '生成', 'Generate'),
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
              style: TextStyle(fontSize: 12.5, color: oc.muted),
            )
          : Column(
              children: [
                for (final key in visibleKeys) ...[
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: _settingsSurfaceDecoration(
                      context,
                      color: oc.composerOptionBg
                          .withOpacity(context.isDarkMode ? 0.50 : 0.68),
                      radius: 18,
                      elevated: false,
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
                                    color: oc.foreground,
                                  ),
                                ),
                              ),
                              if (gitSettings.defaultSshKey?.id == key.id)
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
                            style: TextStyle(
                                fontSize: 12, color: oc.foregroundMuted),
                          ),
                          if (key.comment.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              key.comment,
                              style: TextStyle(
                                  fontSize: 12, color: oc.foregroundMuted),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _SettingsActionButton(
                                onPressed:
                                    gitSettings.defaultSshKey?.id == key.id
                                        ? null
                                        : () => widget.controller
                                            .setDefaultGitSshKey(key.id),
                                label: l(context, '设为默认', 'Set default'),
                              ),
                              _SettingsActionButton(
                                onPressed: () => _showPublicKeyDialog(key),
                                label: l(context, '查看公钥', 'View public key'),
                              ),
                              _SettingsActionButton(
                                onPressed: () => _confirmDeleteKey(key),
                                label: l(context, '删除', 'Delete'),
                                destructive: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (gitSettings.sshKeys.length > visibleKeys.length)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _SettingsActionButton(
                      onPressed: () {
                        setState(() {
                          _showAllSshKeys = true;
                        });
                      },
                      icon: Icons.expand_more_rounded,
                      label: l(
                        context,
                        '查看全部 ${gitSettings.sshKeys.length} 个 SSH Key',
                        'Show all ${gitSettings.sshKeys.length} SSH keys',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildRemoteCredentialSection(
    BuildContext context,
    GitSettings gitSettings,
    List<GitRemoteCredential> visibleCredentials,
  ) {
    final oc = context.oc;
    return _SettingsSectionCard(
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
            child: Text(l(context, '新增 HTTPS Token', 'Add HTTPS token')),
          ),
          PopupMenuItem<String>(
            value: 'httpsBasic',
            child: Text(l(context, '新增 HTTPS 账号密码', 'Add HTTPS user/password')),
          ),
          PopupMenuItem<String>(
            value: 'sshKey',
            child: Text(l(context, '新增 SSH 绑定', 'Add SSH binding')),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_circle_outline,
                  size: 15, color: oc.foregroundMuted),
              const SizedBox(width: 5),
              Text(
                l(context, '新增认证', 'Add credential'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: oc.foregroundMuted,
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
              style: TextStyle(fontSize: 12.5, color: oc.foregroundMuted),
            )
          : Column(
              children: [
                for (final credential in visibleCredentials) ...[
                  Builder(
                    builder: (context) {
                      final sshKey = credential.sshKeyId == null
                          ? null
                          : gitSettings.sshKeys
                              .where((item) => item.id == credential.sshKeyId)
                              .cast<GitSshKey?>()
                              .firstWhere((item) => item != null,
                                  orElse: () => null);
                      final typeLabel = credential.type == 'sshKey'
                          ? 'SSH'
                          : credential.type == 'httpsBasic'
                              ? 'HTTPS Password'
                              : 'HTTPS Token';
                      final pathLabel = credential.pathPrefix.trim().isEmpty
                          ? '/'
                          : credential.pathPrefix;
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: _settingsSurfaceDecoration(
                          context,
                          color: oc.composerOptionBg
                              .withOpacity(context.isDarkMode ? 0.50 : 0.68),
                          radius: 18,
                          elevated: false,
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
                                  color: oc.foreground,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$typeLabel  ${credential.host}$pathLabel',
                                style: TextStyle(
                                    fontSize: 12, color: oc.foregroundMuted),
                              ),
                              if (credential.username.trim().isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${l(context, '用户名', 'Username')}: ${credential.username}',
                                  style: TextStyle(
                                      fontSize: 12, color: oc.foregroundMuted),
                                ),
                              ],
                              if (sshKey != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${l(context, 'SSH Key', 'SSH key')}: ${sshKey.name}',
                                  style: TextStyle(
                                      fontSize: 12, color: oc.foregroundMuted),
                                ),
                              ],
                              const SizedBox(height: 10),
                              _SettingsActionButton(
                                onPressed: () =>
                                    _confirmDeleteRemoteCredential(credential),
                                label: l(context, '删除', 'Delete'),
                                destructive: true,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
                if (gitSettings.remoteCredentials.length >
                    visibleCredentials.length)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _SettingsActionButton(
                      onPressed: () {
                        setState(() {
                          _showAllRemoteCredentials = true;
                        });
                      },
                      icon: Icons.expand_more_rounded,
                      label: l(
                        context,
                        '查看全部 ${gitSettings.remoteCredentials.length} 条认证',
                        'Show all ${gitSettings.remoteCredentials.length} credentials',
                      ),
                    ),
                  ),
              ],
            ),
    );
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
        final onHome = _destination == _SettingsDestination.home;
        return WillPopScope(
          onWillPop: _handleSystemBack,
          child: Scaffold(
            backgroundColor: oc.surface,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () {
                              if (onHome) {
                                Navigator.of(context).pop();
                                return;
                              }
                              setState(() {
                                _destination = _SettingsDestination.home;
                              });
                            },
                            icon: Icon(
                              onHome
                                  ? Icons.close_rounded
                                  : Icons.arrow_back_rounded,
                              size: 20,
                            ),
                            visualDensity: VisualDensity.compact,
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _destinationLabel(context, _destination),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.2,
                                        color: oc.foreground,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                          key: ValueKey(_destination),
                          child: _buildCurrentDestinationPage(
                            context,
                            current: current,
                            connection: connection,
                            gitSettings: gitSettings,
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
