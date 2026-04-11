part of '../../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _HomePageVariantPicker on _HomePageState {
  String _currentVariantModelKey(AppState state) {
    final config = state.modelConfig ?? ModelConfig.defaults();
    return '${config.provider}/${config.model}';
  }

  int _variantSortRank(String value) {
    const order = [
      'default',
      'none',
      'minimal',
      'low',
      'medium',
      'high',
      'max',
      'xhigh',
    ];
    final index = order.indexOf(value.toLowerCase());
    return index >= 0 ? index : order.length;
  }

  List<String> _currentPromptVariantOptions(AppState state) {
    final variants =
        (state.modelConfig?.currentModelVariants ?? const <String, JsonMap>{})
            .keys
            .toList();
    variants.sort((a, b) {
      final rank = _variantSortRank(a).compareTo(_variantSortRank(b));
      if (rank != 0) return rank;
      return a.compareTo(b);
    });
    return variants;
  }

  String? _latestUserVariantForState(AppState state) {
    final options = _currentPromptVariantOptions(state).toSet();
    if (options.isEmpty) return null;
    for (var i = state.messages.length - 1; i >= 0; i--) {
      final message = state.messages[i].message;
      if (message.role != SessionRole.user) continue;
      final value = message.variant?.trim();
      if (value != null && value.isNotEmpty && options.contains(value)) {
        return value;
      }
    }
    return null;
  }

  bool _syncPromptVariantSelection(AppState state, {bool force = false}) {
    final options = _currentPromptVariantOptions(state).toSet();
    final previous = _selectedVariant;
    if (options.isEmpty) {
      _selectedVariant = null;
      return previous != _selectedVariant;
    }
    final latest = _latestUserVariantForState(state);
    if (force || !_selectedVariantDirty) {
      _selectedVariant = latest ??
          (options.contains(_selectedVariant) ? _selectedVariant : null);
      return previous != _selectedVariant;
    }
    if (_selectedVariant != null && !options.contains(_selectedVariant)) {
      _selectedVariant = null;
      _selectedVariantDirty = false;
      return previous != _selectedVariant;
    }
    return false;
  }

  String? _effectiveSelectedVariant(AppState state) {
    final value = _selectedVariant?.trim();
    if (value == null || value.isEmpty) return null;
    return _currentPromptVariantOptions(state).contains(value) ? value : null;
  }

  String _variantTrayLabel(BuildContext context, AppState state) {
    final current = _effectiveSelectedVariant(state);
    return current ?? l(context, '默认', 'Default');
  }

  Future<void> _openVariantPicker(BuildContext context) async {
    final state = widget.controller.state;
    final variants = _currentPromptVariantOptions(state);
    if (variants.isEmpty) return;
    final current = _effectiveSelectedVariant(state);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.oc.pageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final oc = context.oc;
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 12,
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
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ocSheetDragHandle(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l(context, 'Variant', 'Variant'),
                              style: TextStyle(
                                color: oc.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l(
                                context,
                                '模型推理强度 / provider-specific 变体',
                                'Model reasoning effort / provider-specific variant',
                              ),
                              style: TextStyle(
                                color: oc.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close_rounded, color: oc.muted),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    children: [
                      _VariantPickerTile(
                        title: l(context, '默认', 'Default'),
                        subtitle: l(
                          context,
                          '使用模型默认请求参数',
                          'Use the model default request options',
                        ),
                        selected: current == null,
                        onTap: () {
                          setState(() {
                            _selectedVariant = null;
                            _selectedVariantDirty = true;
                          });
                          Navigator.of(context).pop();
                        },
                      ),
                      for (final variant in variants)
                        _VariantPickerTile(
                          title: variant,
                          subtitle: l(
                            context,
                            '覆盖当前消息的模型请求选项',
                            'Override request options for the current message',
                          ),
                          selected: current == variant,
                          onTap: () {
                            setState(() {
                              _selectedVariant = variant;
                              _selectedVariantDirty = true;
                            });
                            Navigator.of(context).pop();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VariantPickerTile extends StatelessWidget {
  const _VariantPickerTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? oc.selectedFill : oc.bgDeep,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? oc.accent.withOpacity(0.45) : oc.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: oc.text,
                          fontSize: 15,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: oc.muted,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: oc.accent, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
