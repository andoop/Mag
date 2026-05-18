// Mutable navigation/filter state is updated from settings_* extension parts.
// ignore_for_file: prefer_final_fields

part of '../../home_page.dart';

// AI map for settings:
// - settings_sheet.dart: route shell, shared form helpers, settings home, page layout.
// - settings_mcp.dart: MCP server/tool/resource/prompt actions and dialogs.
// - settings_git.dart: SSH key and remote credential actions.
// - settings_variables.dart: variable CRUD actions.
// - settings_widgets.dart: reusable setting tiles, switches, and small dialogs.

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
