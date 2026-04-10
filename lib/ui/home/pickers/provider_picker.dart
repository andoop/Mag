part of '../../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _HomePageProviderPicker on _HomePageState {
  Future<void> _disconnectProviderFromPicker(
    BuildContext context,
    _ProviderPreset preset,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l(context, '断开 Provider', 'Disconnect provider')),
          content: Text(
            l(
              context,
              '确定断开 `${preset.name}` 吗？已保存的接口地址和 API Key 会一并移除。',
              'Disconnect `${preset.name}`? The saved endpoint and API key will be removed.',
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
    if (ok != true) return;
    await widget.controller.disconnectProvider(preset.id);
    if (!mounted) return;
    _showInfo(context, l(context, 'Provider 已断开', 'Provider disconnected'));
  }

  /// 选择要连接的 provider，而不是直接切当前 provider。
  Future<void> _openProviderPicker(BuildContext context) async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final oc = context.oc;
            final state = widget.controller.state;
            final current = state.modelConfig ?? ModelConfig.defaults();
            bool matchesPreset(_ProviderPreset item) {
              if (query.isEmpty) return true;
              final q = query;
              return item.name.toLowerCase().contains(q) ||
                  item.id.toLowerCase().contains(q) ||
                  item.baseUrl.toLowerCase().contains(q);
            }
            final sourceProviders = _allProviderPresets(state: state);
            final popularItems = sourceProviders
                .where((item) => item.popular && matchesPreset(item))
                .toList()
              ..sort((a, b) {
                final rankCompare =
                    _providerSortRank(a.id).compareTo(_providerSortRank(b.id));
                if (rankCompare != 0) return rankCompare;
                return a.name.toLowerCase().compareTo(b.name.toLowerCase());
              });
            final otherItems = sourceProviders
                .where(matchesPreset)
                .where((item) => !item.popular)
                .toList()
              ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
            return FractionallySizedBox(
              heightFactor: 0.7,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    MediaQuery.of(context).viewInsets.bottom + 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _compactPickerHandle(context),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l(context, '连接供应商', 'Connect provider'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                letterSpacing: -0.2,
                                color: oc.text,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        style: const TextStyle(fontSize: 13.5, height: 1.25),
                        onChanged: (value) {
                          query = value.trim().toLowerCase();
                          setModalState(() {});
                        },
                        decoration: _compactPickerSearchDecoration(
                          context,
                          hint: l(context, '过滤…', 'Filter…'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: popularItems.isEmpty && otherItems.isEmpty
                            ? Center(
                                child: Text(
                                  l(context, '没有匹配项', 'No matches'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: oc.muted,
                                  ),
                                ),
                              )
                            : ListView(
                                padding: EdgeInsets.zero,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: TextButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        _openCustomProviderSheet(this.context);
                                      },
                                      icon: const Icon(Icons.add_circle_outline),
                                      label: Text(
                                        l(context, '自定义 Provider', 'Custom Provider'),
                                      ),
                                    ),
                                  ),
                                  if (popularItems.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                                      child: Text(
                                        l(context, '热门', 'Popular'),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: oc.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                  ...popularItems.map(
                                    (item) => Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _ProviderListTile(
                                          item: item,
                                          selected: current.connectionFor(item.id) != null,
                                          onTap: () {
                                            Navigator.of(context).pop();
                                            _openConnectPresetProvider(this.context, item);
                                          },
                                          onDisconnect:
                                              current.connectionFor(item.id) == null
                                                  ? null
                                                  : () async {
                                                      await _disconnectProviderFromPicker(
                                                        this.context,
                                                        item,
                                                      );
                                                      if (!mounted) return;
                                                      setModalState(() {});
                                                    },
                                        ),
                                        Divider(
                                          height: 1,
                                          thickness: 1,
                                          color: oc.border,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (otherItems.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          4, 10, 4, 6),
                                      child: Text(
                                        l(context, '其他', 'Other'),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: oc.muted,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                    ...otherItems.map(
                                      (item) => Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _ProviderListTile(
                                            item: item,
                                            selected: current.connectionFor(item.id) != null,
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              _openConnectPresetProvider(
                                                  this.context, item);
                                            },
                                            onDisconnect:
                                                current.connectionFor(item.id) == null
                                                    ? null
                                                    : () async {
                                                        await _disconnectProviderFromPicker(
                                                          this.context,
                                                          item,
                                                        );
                                                        if (!mounted) return;
                                                        setModalState(() {});
                                                      },
                                          ),
                                          Divider(
                                            height: 1,
                                            thickness: 1,
                                            color: oc.border,
                                          ),
                                        ],
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
            );
          },
        );
      },
    );
  }

  Future<void> _openConnectPresetProvider(
    BuildContext context,
    _ProviderPreset preset,
  ) async {
    final state = widget.controller.state;
    final providerInfo = _providerInfoById(preset.id, state: state);
    final authEntry = _preferredProviderAuthMethod(state, preset.id);
    final authMethod = authEntry?.value;
    final authMethodIndex = authEntry?.key ?? 0;
    final authPrompt = _firstProviderAuthTextPrompt(authMethod);
    final authLabel =
        authPrompt?.message ?? authMethod?.label ?? l(context, 'API Key', 'API Key');
    final envSummary = providerInfo != null && providerInfo.env.isNotEmpty
        ? providerInfo.env.join(', ')
        : null;
    if (authMethod != null && authMethod.isOauth) {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: context.oc.pageBackground,
        barrierColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) => _ProviderOAuthSheet(
          controller: widget.controller,
          preset: preset,
          methodIndex: authMethodIndex,
          method: authMethod,
          envSummary: envSummary,
        ),
      );
      return;
    }
    final requiresSecret = authPrompt != null || preset.requiresApiKey;
    final apiKeyController = TextEditingController();
    final baseUrlController = TextEditingController(text: preset.baseUrl);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.oc.pageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final oc = context.oc;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            0,
            12,
            MediaQuery.of(sheetContext).viewInsets.bottom + 12,
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _compactPickerHandle(context),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l(context, '连接 ${preset.name}', 'Connect ${preset.name}'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: oc.text,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close, size: 20),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if ((preset.note ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        preset.note!,
                        style: TextStyle(fontSize: 12.5, color: oc.muted),
                      ),
                    ),
                  if (envSummary != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        l(
                          context,
                          '环境变量：$envSummary',
                          'Environment: $envSummary',
                        ),
                        style: TextStyle(fontSize: 12, color: oc.muted),
                      ),
                    ),
                  TextField(
                    controller: baseUrlController,
                    decoration: InputDecoration(
                      labelText: l(context, 'Base URL', 'Base URL'),
                    ),
                  ),
                  if (requiresSecret) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiKeyController,
                      autocorrect: false,
                      enableSuggestions: false,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: authLabel,
                        hintText: authPrompt?.placeholder,
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        l(
                          context,
                          '此供应商可直接连接，无需填写密钥。',
                          'This provider can connect without a key.',
                        ),
                        style: TextStyle(fontSize: 12, color: oc.muted),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      if (baseUrlController.text.trim().isEmpty) {
                        _showInfo(
                          context,
                          l(context, 'Base URL 不能为空', 'Base URL is required'),
                        );
                        return;
                      }
                      if (requiresSecret && apiKeyController.text.trim().isEmpty) {
                        _showInfo(
                          context,
                          l(
                            context,
                            '请先填写$authLabel',
                            'Please enter $authLabel',
                          ),
                        );
                        return;
                      }
                      try {
                        await _connectProviderPreset(
                          preset,
                          apiKey: apiKeyController.text.trim(),
                          overrideBaseUrl: baseUrlController.text.trim(),
                        );
                      } catch (error) {
                        if (!mounted) return;
                        _showInfo(sheetContext, error.toString());
                        return;
                      }
                      if (!mounted) return;
                      Navigator.of(sheetContext).pop();
                    },
                    icon: const Icon(Icons.link_rounded),
                    label: Text(l(context, '连接', 'Connect')),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCustomProviderSheet(BuildContext context) async {
    final providerId = TextEditingController();
    final providerName = TextEditingController();
    final baseUrl = TextEditingController();
    final apiKey = TextEditingController();
    final models = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.oc.pageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l(context, '自定义供应商', 'Custom Provider'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                TextField(
                  controller: providerId,
                  decoration: InputDecoration(
                    labelText: l(context, 'Provider ID', 'Provider ID'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: providerName,
                  decoration: InputDecoration(
                    labelText: l(context, '显示名称', 'Display name'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: baseUrl,
                  decoration: InputDecoration(
                    labelText: l(context, 'Base URL', 'Base URL'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: apiKey,
                  decoration: InputDecoration(
                    labelText: l(context, 'API Key', 'API Key'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: models,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: l(context, '模型列表（每行一个）', 'Models (one per line)'),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    final providerIdValue = providerId.text.trim();
                    final providerNameValue = providerName.text.trim();
                    final baseUrlValue = baseUrl.text.trim();
                    final ids = models.text
                        .split(RegExp(r'[\n,]'))
                        .map((item) => item.trim())
                        .where((item) => item.isNotEmpty)
                        .toList();
                    final current =
                        widget.controller.state.modelConfig ?? ModelConfig.defaults();
                    if (providerIdValue.isEmpty ||
                        !RegExp(r'^[a-z0-9][a-z0-9-_]*$').hasMatch(providerIdValue)) {
                      _showInfo(
                        context,
                        l(
                          context,
                          'Provider ID 需为小写字母/数字，可包含 - 或 _',
                          'Provider ID must use lowercase letters/numbers, with optional - or _',
                        ),
                      );
                      return;
                    }
                    if (current.connectionFor(providerIdValue) != null) {
                      _showInfo(
                        context,
                        l(context, '这个 Provider ID 已存在', 'This provider ID already exists'),
                      );
                      return;
                    }
                    if (providerNameValue.isEmpty || baseUrlValue.isEmpty) {
                      _showInfo(
                        context,
                        l(context, '名称和 Base URL 不能为空', 'Name and Base URL are required'),
                      );
                      return;
                    }
                    if (ids.isEmpty) {
                      _showInfo(
                        context,
                        l(context, '请至少填写一个模型 ID', 'Please add at least one model ID'),
                      );
                      return;
                    }
                    try {
                      await _connectCustomProvider(
                        providerId: providerIdValue,
                        name: providerNameValue,
                        baseUrl: baseUrlValue,
                        apiKey: apiKey.text.trim(),
                        models: ids,
                      );
                    } catch (error) {
                      if (!mounted) return;
                      _showInfo(sheetContext, error.toString());
                      return;
                    }
                    if (!mounted) return;
                    Navigator.of(sheetContext).pop();
                  },
                  icon: const Icon(Icons.add_link_rounded),
                  label: Text(l(context, '添加供应商', 'Add provider')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
