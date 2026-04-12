part of '../../home_page.dart';

Future<void> _openSkillsBrowser(
  BuildContext context, {
  required AppController controller,
  required WorkspaceInfo workspace,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _SkillsBrowserSheet(
        controller: controller,
        workspace: workspace,
      ),
    ),
  );
}

class _SkillsBrowserSheet extends StatefulWidget {
  const _SkillsBrowserSheet({
    required this.controller,
    required this.workspace,
  });

  final AppController controller;
  final WorkspaceInfo workspace;

  @override
  State<_SkillsBrowserSheet> createState() => _SkillsBrowserSheetState();
}

class _SkillsBrowserSheetState extends State<_SkillsBrowserSheet> {
  late Future<List<_LoadedSkillDebugEntry>> _future = _load();

  Future<List<_LoadedSkillDebugEntry>> _load() async {
    final registry = SkillRegistry.instance;
    final skills = await registry.all(widget.workspace);
    final entries = <_LoadedSkillDebugEntry>[];
    for (final skill in skills) {
      final files = await registry.sampleFiles(widget.workspace, skill);
      entries.add(_LoadedSkillDebugEntry(skill: skill, files: files));
    }
    return entries;
  }

  Future<void> _refresh() async {
    SkillRegistry.instance.invalidateWorkspace(widget.workspace.treeUri);
    setState(() {
      _future = _load();
    });
  }

  void _copyText(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return DecoratedBox(
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
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l(context, 'Skills', 'Skills'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: oc.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.workspace.name,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: oc.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _refresh,
                  tooltip: l(context, '刷新', 'Refresh'),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              l(
                context,
                '浏览当前工作区内发现到的 skills，便于核对名称、位置、正文和采样文件。',
                'Browse skills discovered in the current workspace, including name, location, content, and sampled files.',
              ),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: oc.muted,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<_LoadedSkillDebugEntry>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        snapshot.error.toString(),
                        style: TextStyle(color: oc.text),
                      ),
                    ),
                  );
                }
                final entries = snapshot.data ?? const [];
                if (entries.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 28,
                            color: oc.muted,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l(
                              context,
                              '当前工作区还没有发现可用 skills。',
                              'No skills were discovered in this workspace yet.',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: oc.text,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '.claude/skills  .agents/skills  .opencode/skill  .opencode/skills',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: oc.muted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final skill = entry.skill;
                    return Container(
                      decoration: BoxDecoration(
                        color: oc.panelBackground,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: oc.border),
                      ),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          dividerColor: Colors.transparent,
                        ),
                        child: ExpansionTile(
                          tilePadding:
                              const EdgeInsets.fromLTRB(14, 10, 10, 10),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          leading: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: oc.surface.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: oc.border),
                            ),
                            child: Icon(
                              Icons.auto_awesome_outlined,
                              size: 18,
                              color: oc.accent,
                            ),
                          ),
                          title: Text(
                            skill.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: oc.text,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              skill.description,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: oc.muted,
                              ),
                            ),
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                onPressed: () => _copyText(
                                  context,
                                  skill.name,
                                  l(context, 'Skill 名称已复制', 'Skill name copied'),
                                ),
                                tooltip:
                                    l(context, '复制 skill 名称', 'Copy skill name'),
                                icon: const Icon(Icons.copy_all_outlined,
                                    size: 18),
                              ),
                              IconButton(
                                onPressed: () => _copyText(
                                  context,
                                  skill.location,
                                  l(context, 'Skill 位置已复制',
                                      'Skill location copied'),
                                ),
                                tooltip:
                                    l(context, '复制 skill 位置', 'Copy skill location'),
                                icon: const Icon(Icons.link_outlined, size: 18),
                              ),
                            ],
                          ),
                          children: [
                            _SkillDetailBlock(
                              label: l(context, '位置', 'Location'),
                              child: SelectableText(
                                skill.location,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: oc.text,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _SkillDetailBlock(
                              label: l(context, '基目录', 'Base directory'),
                              child: SelectableText(
                                skill.directory,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: oc.text,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _SkillDetailBlock(
                              label: l(context, '正文', 'Content'),
                              child: SelectableText(
                                skill.content.trim(),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: oc.text,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _SkillDetailBlock(
                              label: l(context, '采样文件', 'Sampled files'),
                              child: entry.files.isEmpty
                                  ? Text(
                                      l(context, '无', 'None'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: oc.muted,
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final file in entry.files) ...[
                                          SelectableText(
                                            file,
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.35,
                                              color: oc.text,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                        ],
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadedSkillDebugEntry {
  const _LoadedSkillDebugEntry({
    required this.skill,
    required this.files,
  });

  final SkillInfo skill;
  final List<String> files;
}

class _SkillDetailBlock extends StatelessWidget {
  const _SkillDetailBlock({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: oc.muted,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: oc.surface.withOpacity(0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: oc.border),
          ),
          child: child,
        ),
      ],
    );
  }
}
