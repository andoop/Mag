part of '../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _HomePagePickers on _HomePageState {
  Future<void> _openSessionPicker(BuildContext context) async {
    final state = widget.controller.state;
    if (state.sessions.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.72,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l(context, '会话', 'Sessions'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: state.sessions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = state.sessions[index];
                        final selected = item.id == state.session?.id;
                        final currentModel = state.modelConfig?.model ??
                            ModelConfig.defaults().model;
                        final ratio = _contextUsageRatio(item, currentModel);
                        final percent = (ratio * 100).round();
                        return ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          tileColor: selected
                              ? Colors.blue.shade50
                              : Colors.grey.shade50,
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.agent} · ${_contextUsageLabel(item, currentModel)} · $percent%',
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle_outline)
                              : null,
                          onTap: () async {
                            _stickToBottom = true;
                            Navigator.of(context).pop();
                            await widget.controller.switchSession(item);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAgentPicker(BuildContext context) async {
    final state = widget.controller.state;
    if (state.agents.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l(context, 'Agents', 'Agents'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...state.agents.map((agent) {
                  final selected =
                      (_selectedAgent ?? state.session?.agent ?? 'build') ==
                          agent.name;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      tileColor:
                          selected ? Colors.blue.shade50 : Colors.grey.shade50,
                      title: Text(agent.name),
                      subtitle: agent.description.isEmpty
                          ? null
                          : Text(agent.description),
                      trailing: selected
                          ? const Icon(Icons.check_circle_outline)
                          : null,
                      onTap: () {
                        setState(() {
                          _selectedAgent = agent.name;
                        });
                        Navigator.of(context).pop();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSettings(BuildContext context, ModelConfig? config) async {
    final current = config ?? ModelConfig.defaults();
    final baseUrl = TextEditingController(text: current.baseUrl);
    final apiKey = TextEditingController(text: current.apiKey);
    final model = TextEditingController(text: current.model);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: baseUrl,
                  decoration: InputDecoration(
                      labelText: l(context, 'Base URL', 'Base URL'))),
              const SizedBox(height: 12),
              TextField(
                  controller: apiKey,
                  decoration: InputDecoration(
                      labelText: l(context, 'API Key', 'API Key'))),
              const SizedBox(height: 12),
              TextField(
                  controller: model,
                  decoration:
                      InputDecoration(labelText: l(context, '模型', 'Model'))),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  await widget.controller.saveModelConfig(
                    ModelConfig(
                      baseUrl: baseUrl.text.trim(),
                      apiKey: apiKey.text.trim(),
                      model: model.text.trim(),
                      provider: current.provider,
                    ),
                  );
                  if (mounted) Navigator.of(context).pop();
                },
                child: Text(l(context, '保存', 'Save')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openProviderPicker(BuildContext context) async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final state = widget.controller.state;
            final current = state.modelConfig ?? ModelConfig.defaults();
            final items = _providerPresets.where((item) {
              if (query.isEmpty) return true;
              return item.name.toLowerCase().contains(query) ||
                  item.id.toLowerCase().contains(query) ||
                  (item.note?.toLowerCase().contains(query) ?? false);
            }).toList()
              ..sort((a, b) {
                final aCurrent = a.id == current.provider;
                final bCurrent = b.id == current.provider;
                if (aCurrent != bCurrent) return aCurrent ? -1 : 1;
                if (a.recommended && !b.recommended) return -1;
                if (!a.recommended && b.recommended) return 1;
                if (a.popular && !b.popular) return -1;
                if (!a.popular && b.popular) return 1;
                return a.name.compareTo(b.name);
              });
            final popular = items.where((item) => item.popular).toList();
            final other = items.where((item) => !item.popular).toList();
            final currentProvider = _providerById(current.provider);
            return FractionallySizedBox(
              heightFactor: 0.9,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16,
                      MediaQuery.of(context).viewInsets.bottom + 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l(context, 'Providers', 'Providers'),
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        l(context, '像 Mag 一样把 provider 作为模型管理入口来切换。',
                            'Manage providers as the entry point for model selection, similar to Mag.'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (value) {
                          query = value.trim().toLowerCase();
                          setModalState(() {});
                        },
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText:
                              l(context, '搜索 provider', 'Search provider'),
                          prefixIcon: const Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          children: [
                            if (currentProvider != null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l(context, '当前', 'Current'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    Text(
                                      currentProvider.name,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${modelCountText(context, _providerModelCount(currentProvider.id))} · ${_providerAvailabilityLabel(context, currentProvider)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            if (popular.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(l(context, '热门', 'Popular'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...popular.map((item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _ProviderListTile(
                                      item: item,
                                      selected: item.id == current.provider,
                                      modelCount: _providerModelCount(item.id),
                                      availability: _providerAvailabilityLabel(
                                          context, item),
                                      description: _providerNote(context, item),
                                      onTap: () => _selectProvider(item),
                                    ),
                                  )),
                            ],
                            if (other.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(l(context, '所有 Providers', 'All Providers'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...other.map((item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: _ProviderListTile(
                                      item: item,
                                      selected: item.id == current.provider,
                                      modelCount: _providerModelCount(item.id),
                                      availability: _providerAvailabilityLabel(
                                          context, item),
                                      description: _providerNote(context, item),
                                      onTap: () => _selectProvider(item),
                                    ),
                                  )),
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

  Future<void> _openModelPicker(BuildContext context) async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final state = widget.controller.state;
            final current = state.modelConfig ?? ModelConfig.defaults();
            final currentChoice =
                _findModelChoice(current.provider, current.model);
            final filteredRecent = _recentModelChoices(state)
                .where((item) => _matchesModelQuery(item, query))
                .toList();
            final recentKeys = filteredRecent
                .map((item) => _modelKey(item.providerId, item.id))
                .toSet();
            final filteredSuggested = _suggestedModelChoices(state)
                .where((item) => _matchesModelQuery(item, query))
                .where((item) =>
                    !recentKeys.contains(_modelKey(item.providerId, item.id)))
                .toList();
            final allModels = _modelCatalog
                .where((item) => _matchesModelQuery(item, query))
                .toList()
              ..sort((a, b) => _compareModelChoices(a, b, state));
            final promotedKeys = <String>{
              _modelKey(current.provider, current.model),
              if (query.isEmpty)
                ...filteredRecent
                    .map((item) => _modelKey(item.providerId, item.id)),
              if (query.isEmpty)
                ...filteredSuggested
                    .map((item) => _modelKey(item.providerId, item.id)),
            };
            final visibleModels = query.isEmpty
                ? allModels
                    .where((item) => !promotedKeys
                        .contains(_modelKey(item.providerId, item.id)))
                    .toList()
                : allModels;
            final popularProviders =
                _providerPresets.where((item) => item.popular).take(4).toList();
            return FractionallySizedBox(
              heightFactor: 0.92,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16,
                      MediaQuery.of(context).viewInsets.bottom + 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l(context, '模型', 'Models'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(
                                  l(
                                      context,
                                      '按 Mag 的单列表思路展示最近使用、推荐项和完整模型列表。',
                                      'Show recent, suggested, and the full model catalog in a single Mag-style list.'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _openProviderPicker(this.context);
                            },
                            icon: const Icon(Icons.hub_outlined),
                            label: Text(l(context, 'Provider', 'Provider')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (value) {
                          query = value.trim().toLowerCase();
                          setModalState(() {});
                        },
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: l(context, '搜索模型或 provider',
                              'Search model or provider'),
                          prefixIcon: const Icon(Icons.search),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l(context, '当前', 'Current'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 8),
                                  Text(
                                    currentChoice?.name ?? current.model,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${_providerLabel(current.provider)} · ${current.model}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  if (!_hasPaidProvider(state)) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      l(
                                          context,
                                          '当前还没有付费 provider，免费模型会优先排在前面。',
                                          'No paid provider is configured yet, so free models are prioritized first.'),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (query.isEmpty && filteredRecent.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Text(l(context, '最近使用', 'Recent'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...filteredRecent.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ModelListTile(
                                    item: item,
                                    selected:
                                        current.provider == item.providerId &&
                                            current.model == item.id,
                                    onTap: () => _selectModel(item),
                                  ),
                                ),
                              ),
                            ],
                            if (query.isEmpty &&
                                filteredSuggested.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(l(context, '推荐', 'Suggested'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              ...filteredSuggested.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ModelListTile(
                                    item: item,
                                    selected:
                                        current.provider == item.providerId &&
                                            current.model == item.id,
                                    onTap: () => _selectModel(item),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              query.isEmpty
                                  ? l(context, '所有模型', 'All Models')
                                  : l(context, '结果', 'Results'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            if (visibleModels.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Text(l(context, '没有找到匹配的模型',
                                    'No matching models found')),
                              )
                            else
                              ...visibleModels.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _ModelListTile(
                                    item: item,
                                    selected:
                                        current.provider == item.providerId &&
                                            current.model == item.id,
                                    onTap: () => _selectModel(item),
                                  ),
                                ),
                              ),
                            if (query.isEmpty && !_hasPaidProvider(state)) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        l(context, '连接更多 Providers',
                                            'Connect More Providers'),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 8),
                                    ...popularProviders.map(
                                      (item) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8),
                                        child: ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 2),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          tileColor: Colors.white,
                                          title: Row(
                                            children: [
                                              Expanded(child: Text(item.name)),
                                              if (item.recommended)
                                                _TinyTag(
                                                  label: 'Recommended',
                                                  color: Colors.green.shade100,
                                                ),
                                            ],
                                          ),
                                          subtitle:
                                              Text(item.note ?? item.baseUrl),
                                          onTap: () async {
                                            Navigator.of(context).pop();
                                            await _selectProvider(item);
                                            if (!mounted) return;
                                            if (item.requiresApiKey) {
                                              _openSettings(
                                                  this.context,
                                                  widget.controller.state
                                                      .modelConfig);
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          _openProviderPicker(this.context);
                                        },
                                        icon: const Icon(
                                            Icons.grid_view_outlined),
                                        label: Text(l(context, '查看全部 providers',
                                            'View all providers')),
                                      ),
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
}
