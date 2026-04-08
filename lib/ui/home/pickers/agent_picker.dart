part of '../../home_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _HomePageAgentPicker on _HomePageState {

  Future<void> _openAgentPicker(BuildContext context) async {
    final state = widget.controller.state;
    if (state.agents.isEmpty) return;
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
                              l(context, 'Agents', 'Agents'),
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
                                '主会话与子代理角色',
                                'Primary & subagent roles',
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
                SizedBox(
                  height: (MediaQuery.of(context).size.height * 0.5)
                      .clamp(220.0, 520.0),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: state.agents.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final agent = state.agents[index];
                      final selected =
                          (_selectedAgent ?? state.session?.agent ?? 'build') ==
                              agent.name;
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            setState(() {
                              _selectedAgent = agent.name;
                            });
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: selected
                                  ? oc.selectedFill
                                  : oc.bgDeep,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selected
                                    ? oc.accent.withOpacity(0.45)
                                    : oc.border,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: oc.panelBackground,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: oc.border),
                                  ),
                                  child: Icon(
                                    Icons.smart_toy_outlined,
                                    color: selected ? oc.accent : oc.muted,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              agent.name,
                                              style: TextStyle(
                                                color: oc.text,
                                                fontSize: 15,
                                                fontWeight: selected
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          if (selected)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: oc.accent.withOpacity(0.22),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                l(context, '当前', 'Active'),
                                                style: TextStyle(
                                                  color: oc.accent,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (agent.description.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          agent.localizedDescription(
                                              zh: isZhLocale(context)),
                                          style: TextStyle(
                                            color: oc.muted,
                                            fontSize: 12.5,
                                            height: 1.35,
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
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSettings(BuildContext context, ModelConfig? config) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.oc.pageBackground,
      barrierColor: Colors.transparent,
      builder: (context) => _AppSettingsSheet(
        controller: widget.controller,
        modelConfig: config ?? ModelConfig.defaults(),
      ),
    );
  }
}
