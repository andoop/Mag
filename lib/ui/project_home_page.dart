import 'package:flutter/material.dart';

import '../core/models.dart';
import '../store/app_controller.dart';
import '../store/project_recents_store.dart';
import 'i18n.dart';
import 'oc_theme.dart';

class _RecentProjectsLoad {
  _RecentProjectsLoad({required this.list, required this.times});

  final List<WorkspaceInfo> list;
  final Map<String, int> times;
}

/// 项目首页：展示应用沙盒中的项目列表，并支持创建新项目。
class ProjectHomePage extends StatefulWidget {
  const ProjectHomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProjectHomePage> createState() => _ProjectHomePageState();
}

class _ProjectHomePageState extends State<ProjectHomePage> {
  late Future<_RecentProjectsLoad> _recentFuture;

  @override
  void initState() {
    super.initState();
    _recentFuture = _loadRecents();
  }

  Future<_RecentProjectsLoad> _loadRecents() async {
    final list = await widget.controller.workspacesForHome();
    final times = await ProjectRecentsStore.lastOpenedMap();
    return _RecentProjectsLoad(list: list, times: times);
  }

  Future<void> _showCreateProjectDialog() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ProjectNameDialog(
        title: l(context, '新建项目', 'New project'),
        hintText: l(context, '输入项目名称', 'Enter project name'),
        confirmText: l(context, '创建', 'Create'),
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    await widget.controller.createAndOpenProject(result);
  }

  Future<void> _refreshProjects() async {
    if (!mounted) return;
    setState(() {
      _recentFuture = _loadRecents();
    });
  }

  Future<void> _showRenameProjectDialog(WorkspaceInfo workspace) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ProjectNameDialog(
        title: l(context, '重命名项目', 'Rename project'),
        hintText: l(context, '输入新的项目名称', 'Enter a new project name'),
        confirmText: l(context, '保存', 'Save'),
        initialValue: workspace.name,
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    await widget.controller.renameProject(workspace, result);
    await _refreshProjects();
  }

  Future<void> _confirmDeleteProject(WorkspaceInfo workspace) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l(context, '删除项目', 'Delete project')),
        content: Text(
          l(
            context,
            '确定删除 `${workspace.name}` 吗？项目目录和对应会话都会被删除。',
            'Delete `${workspace.name}`? The project folder and related sessions will be removed.',
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
    if (ok != true || !mounted) {
      return;
    }
    await widget.controller.deleteProject(workspace);
    await _refreshProjects();
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
      backgroundColor: oc.pageBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: l(context, '切换主题', 'Toggle theme'),
                    onPressed: () => widget.controller.toggleThemeMode(),
                    icon: Icon(
                      context.isDarkMode
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                    ),
                  ),
                ],
              ),
              Text(
                l(context, 'Mag', 'Mag'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.2,
                  color: oc.text.withOpacity(0.12),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l(context, '本地 AI 工作区', 'Local AI workspace'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: oc.muted,
                ),
              ),
              if (widget.controller.state.serverUri != null) ...[
                const SizedBox(height: 6),
                Text(
                  widget.controller.state.serverUri.toString(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: oc.muted.withOpacity(0.85),
                  ),
                ),
              ],
              const SizedBox(height: 36),
              Expanded(
                child: FutureBuilder<_RecentProjectsLoad>(
                  future: _recentFuture,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              l(context, '项目列表加载失败', 'Failed to load projects'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: oc.muted,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () {
                                setState(() {
                                  _recentFuture = _loadRecents();
                                });
                              },
                              child: Text(l(context, '重试', 'Retry')),
                            ),
                          ],
                        ),
                      );
                    }
                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) {
                      return Center(
                        child: Text(
                          l(context, '加载中…', 'Loading…'),
                          style: TextStyle(color: oc.muted, fontSize: 13),
                        ),
                      );
                    }
                    final data = snap.data;
                    final list = data?.list ?? const <WorkspaceInfo>[];
                    final times = data?.times ?? const <String, int>{};
                    if (list.isEmpty) {
                      return _EmptyProjects(
                        onCreate: _showCreateProjectDialog,
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l(context, '最近项目', 'Recent projects'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: oc.text,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _showCreateProjectDialog,
                              icon: const Icon(Icons.create_new_folder_rounded, size: 18),
                              label: Text(l(context, '新建项目', 'New project')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final w = list[i];
                              return Material(
                                color: oc.panelBackground,
                                borderRadius: BorderRadius.circular(14),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: () =>
                                      widget.controller.openSavedProject(w),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 14,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _displayPath(context, w.name),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: oc.text,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          _relativeTime(
                                            context,
                                            times[w.id] ?? w.createdAt,
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: oc.muted,
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          tooltip: l(context, '项目操作', 'Project actions'),
                                          onSelected: (value) async {
                                            if (value == 'rename') {
                                              await _showRenameProjectDialog(w);
                                            } else if (value == 'delete') {
                                              await _confirmDeleteProject(w);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            PopupMenuItem<String>(
                                              value: 'rename',
                                              child: Text(
                                                l(context, '重命名', 'Rename'),
                                              ),
                                            ),
                                            PopupMenuItem<String>(
                                              value: 'delete',
                                              child: Text(
                                                l(context, '删除', 'Delete'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (widget.controller.state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    widget.controller.state.error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  String _displayPath(BuildContext context, String name) {
    if (name.isEmpty) {
      return l(context, '未命名工作区', 'Untitled workspace');
    }
    return name;
  }

  String _relativeTime(BuildContext context, int createdAt) {
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final now = DateTime.now();
    var diff = now.difference(dt);
    if (diff.isNegative) diff = Duration.zero;
    if (diff.inSeconds < 45) {
      return l(context, '刚刚', 'just now');
    }
    if (diff.inMinutes < 60) {
      return l(context, '${diff.inMinutes} 分钟前', '${diff.inMinutes}m ago');
    }
    if (diff.inHours < 24) {
      return l(context, '${diff.inHours} 小时前', '${diff.inHours}h ago');
    }
    if (diff.inDays < 7) {
      return l(context, '${diff.inDays} 天前', '${diff.inDays}d ago');
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

class _ProjectNameDialog extends StatefulWidget {
  const _ProjectNameDialog({
    required this.title,
    required this.hintText,
    required this.confirmText,
    this.initialValue = '',
  });

  final String title;
  final String hintText;
  final String confirmText;
  final String initialValue;

  @override
  State<_ProjectNameDialog> createState() => _ProjectNameDialogState();
}

class _ProjectNameDialogState extends State<_ProjectNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hintText,
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l(context, '取消', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_rounded,
            size: 48,
            color: oc.text.withOpacity(0.2),
          ),
          const SizedBox(height: 16),
          Text(
            l(context, '尚无项目', 'No projects yet'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: oc.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l(
              context,
              '项目将保存在应用自己的沙盒目录中，后续文件编辑与 Git 都只在这里运行。',
              'Projects live inside the app sandbox so file editing and Git always run there.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: oc.muted,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.create_new_folder_rounded, size: 20),
            label: Text(l(context, '新建项目', 'New project')),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              backgroundColor: oc.sendButtonBg,
              foregroundColor: oc.sendButtonFg,
            ),
          ),
        ],
      ),
    );
  }
}
