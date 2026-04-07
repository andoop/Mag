part of '../../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _HomePageModelPicker on _HomePageState {

  Future<void> _openManageModelsSheet(BuildContext context) async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.oc.pageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final oc = sheetContext.oc;
            final state = widget.controller.state;
            final config = state.modelConfig ?? ModelConfig.defaults();
            final connectedProviders =
                _connectedProviderPresets(config, state: state);
            final grouped = <_ProviderPreset, List<_ModelChoice>>{};
            for (final provider in connectedProviders) {
              final matches = _modelsForProvider(
                provider.id,
                config: config,
                state: state,
              )
                  .where((item) => _matchesModelQuery(item, query))
                  .toList();
              if (matches.isNotEmpty) {
                grouped[provider] = matches;
              }
            }
            return FractionallySizedBox(
              heightFactor: 0.72,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    MediaQuery.of(sheetContext).viewInsets.bottom + 8,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _compactPickerHandle(sheetContext),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l(context, '模型管理', 'Manage Models'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: oc.text,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                icon: const Icon(Icons.close, size: 20),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          child: TextField(
                            onChanged: (value) {
                              query = value.trim().toLowerCase();
                              setModalState(() {});
                            },
                            decoration: _compactPickerSearchDecoration(
                              context,
                              hint: l(context, '过滤模型…', 'Filter models…'),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            children: grouped.entries.map((entry) {
                            final provider = entry.key;
                            final models = entry.value;
                            final allVisible = models.every(
                              (item) => _isModelVisible(config, item),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          provider.name,
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: oc.text,
                                          ),
                                        ),
                                      ),
                                      Switch.adaptive(
                                        value: allVisible,
                                        onChanged: (value) async {
                                          for (final item in models) {
                                            await widget.controller.setModelVisibility(
                                              providerId: item.providerId,
                                              modelId: item.id,
                                              visible: value,
                                            );
                                          }
                                          if (!mounted) return;
                                          setModalState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: oc.panelBackground,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: oc.border),
                                    ),
                                    child: Column(
                                      children: models.map((item) {
                                        final visible = _isModelVisible(config, item);
                                        return SwitchListTile.adaptive(
                                          value: visible,
                                          dense: true,
                                          contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          title: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.name,
                                                  style: const TextStyle(
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                              if (_modelChoiceIsFree(item)) ...[
                                                const SizedBox(width: 6),
                                                OcModelTag(
                                                  label: l(context, '免费', 'Free'),
                                                ),
                                              ],
                                              if (_modelChoiceIsLatest(item)) ...[
                                                const SizedBox(width: 6),
                                                OcModelTag(
                                                  label:
                                                      l(context, '最新', 'Latest'),
                                                ),
                                              ],
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(top: 4),
                                            child: Text(
                                              item.id,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: oc.muted,
                                              ),
                                            ),
                                          ),
                                          onChanged: (value) async {
                                            await widget.controller.setModelVisibility(
                                              providerId: item.providerId,
                                              modelId: item.id,
                                              visible: value,
                                            );
                                            if (!mounted) return;
                                            setModalState(() {});
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
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
      },
    );
  }

  /// 分组模型列表，右上保留 `+` 与管理入口。
  Future<void> _openModelPicker(BuildContext context) async {
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.oc.pageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final oc = context.oc;
            final state = widget.controller.state;
            final current = state.modelConfig ?? ModelConfig.defaults();
            final visible = _visibleModelChoices(state);
            final filtered = visible
                .where((item) => _matchesModelQuery(item, query))
                .toList()
              ..sort((a, b) => _compareModelChoices(a, b, state));
            final grouped = <String, List<_ModelChoice>>{};
            for (final item in filtered) {
              grouped.putIfAbsent(item.providerId, () => []).add(item);
            }
            return FractionallySizedBox(
              heightFactor: 0.64,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    MediaQuery.of(context).viewInsets.bottom + 8,
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _compactPickerHandle(context),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l(context, '模型', 'Models'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    letterSpacing: -0.2,
                                    color: oc.text,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: l(
                                    context, '连接供应商', 'Connect provider'),
                                icon: const Icon(Icons.add, size: 20),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _openProviderPicker(this.context);
                                },
                              ),
                              IconButton(
                                tooltip:
                                    l(context, '模型管理', 'Manage models'),
                                icon: const Icon(Icons.tune_rounded, size: 20),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  _openManageModelsSheet(this.context);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                          child: TextField(
                            style: const TextStyle(
                                fontSize: 13.5, height: 1.25),
                            onChanged: (value) {
                              query = value.trim().toLowerCase();
                              setModalState(() {});
                            },
                            decoration: _compactPickerSearchDecoration(
                              context,
                              hint: l(context, '过滤模型…', 'Filter models…'),
                            ),
                          ),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    child: Text(
                                      visible.isEmpty
                                          ? l(
                                              context,
                                              '还没有可见模型，请先连接供应商或在模型管理中开启模型。',
                                              'No visible models yet. Connect a provider or enable models in Manage Models.',
                                            )
                                          : l(context, '没有匹配的模型',
                                              'No matching models'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: oc.muted,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 0, 12, 12),
                                  children: grouped.entries.map((entry) {
                                    final providerId = entry.key;
                                    final items = entry.value;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                4, 4, 4, 6),
                                            child: Text(
                                              _providerLabel(
                                                providerId,
                                                config: current,
                                                state: state,
                                              ),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: oc.muted,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: oc.panelBackground,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: oc.border),
                                            ),
                                            child: Column(
                                              children: [
                                                for (var i = 0;
                                                    i < items.length;
                                                    i++) ...[
                                                  _ModelListTile(
                                                    item: items[i],
                                                    selected: current
                                                                .provider ==
                                                            items[i]
                                                                .providerId &&
                                                        current.model ==
                                                            items[i].id,
                                                    onTap: () => _selectModel(
                                                        items[i]),
                                                  ),
                                                  if (i != items.length - 1)
                                                    Divider(
                                                      height: 1,
                                                      thickness: 1,
                                                      color: oc.border,
                                                    ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
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
      },
    );
  }
}
