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

/// 项目首页：最近项目与打开工作区（路径由系统沙盒 / 文件选择器与原生桥提供）。
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
                        onOpen: () => widget.controller.pickAndOpenProject(),
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
                              onPressed: () =>
                                  widget.controller.pickAndOpenProject(),
                              icon: const Icon(Icons.folder_open_rounded, size: 18),
                              label: Text(l(context, '打开项目', 'Open project')),
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
                                            times[w.treeUri] ?? w.createdAt,
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: oc.muted,
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

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onOpen});

  final VoidCallback onOpen;

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
              '选择一个文件夹作为工作区，访问权限由系统文件选择器授权。',
              'Pick a folder as your workspace. Access is granted through the system file picker.',
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
            onPressed: onOpen,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(l(context, '打开项目', 'Open project')),
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
