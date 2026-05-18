import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../platform/floating_window_bridge.dart';
import '../store/app_controller.dart';
import '../store/project_recents_store.dart';
import 'home_page.dart';
import 'i18n.dart';
import 'oc_theme.dart';

const double _kHomeCollapseScrollRange = 96;
const double _kHomeExpandedHeight = 202;
const double _kProjectListGap = 6;

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
  final ScrollController _projectListController = ScrollController();
  double _homeCollapseT = 0;

  @override
  void initState() {
    super.initState();
    _recentFuture = _loadRecents();
    _projectListController.addListener(_syncHomeCollapse);
  }

  @override
  void dispose() {
    _projectListController.removeListener(_syncHomeCollapse);
    _projectListController.dispose();
    super.dispose();
  }

  double _ease(double t) {
    return Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
  }

  double _fadeIn(double start, double end) {
    return _ease((_homeCollapseT - start) / (end - start));
  }

  double _fadeOut(double start, double end) {
    return 1 - _fadeIn(start, end);
  }

  void _syncHomeCollapse() {
    if (!_projectListController.hasClients) return;
    final position = _projectListController.position;
    final next = (position.pixels / _kHomeCollapseScrollRange).clamp(0.0, 1.0);
    if ((next - _homeCollapseT).abs() < 0.01) return;
    setState(() => _homeCollapseT = next);
  }

  Future<_RecentProjectsLoad> _loadRecents() async {
    final list = await widget.controller.workspacesForHome();
    final times = await ProjectRecentsStore.lastOpenedMap();
    final sorted = [...list]..sort((a, b) {
        final aTime = times[a.id] ?? a.createdAt;
        final bTime = times[b.id] ?? b.createdAt;
        return bTime.compareTo(aTime);
      });
    return _RecentProjectsLoad(list: sorted, times: times);
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
    await _requestNotificationPermissionAfterProjectEnter();
  }

  Future<void> _requestNotificationPermissionAfterProjectEnter() async {
    // Delay until the navigation from the project list to the agent page has
    // settled; native side already creates notification channels up front.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await FloatingWindowBridge.requestNotificationPermission();
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
    final overlayStyle = context.isDarkMode
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: oc.pageBackground,
            systemNavigationBarColor: oc.pageBackground,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: oc.pageBackground,
            systemNavigationBarColor: oc.pageBackground,
          );
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: Scaffold(
            backgroundColor: oc.pageBackground,
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Stack(
                  children: [
                    FutureBuilder<_RecentProjectsLoad>(
                      future: _recentFuture,
                      builder: (context, snap) {
                        final data = snap.data;
                        final list = data?.list ?? const <WorkspaceInfo>[];
                        final times = data?.times ?? const <String, int>{};
                        return CustomScrollView(
                          controller: _projectListController,
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            SliverAppBar(
                              automaticallyImplyLeading: false,
                              pinned: true,
                              elevation: 0,
                              scrolledUnderElevation: 0,
                              backgroundColor: oc.pageBackground,
                              surfaceTintColor: Colors.transparent,
                              expandedHeight: _kHomeExpandedHeight,
                              titleSpacing: 0,
                              title: IgnorePointer(
                                ignoring: _homeCollapseT < 0.45,
                                child: Opacity(
                                  opacity: _fadeIn(0.42, 0.86),
                                  child: Text(
                                    l(context, '项目列表', 'Projects'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: oc.text,
                                    ),
                                  ),
                                ),
                              ),
                              actions: [
                                IgnorePointer(
                                  ignoring: _homeCollapseT < 0.45,
                                  child: Opacity(
                                    opacity: _fadeIn(0.42, 0.86),
                                    child: IconButton(
                                      tooltip: l(context, '新建项目', 'New project'),
                                      onPressed: _showCreateProjectDialog,
                                      icon: const Icon(
                                        Icons.create_new_folder_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: l(context, '设置', 'Settings'),
                                  onPressed: () => openAppSettingsSheet(
                                    context,
                                    controller: widget.controller,
                                    modelConfig:
                                        widget.controller.state.modelConfig ??
                                            ModelConfig.defaults(),
                                  ),
                                  icon: const Icon(Icons.settings_outlined),
                                ),
                                IconButton(
                                  tooltip: l(context, '切换主题', 'Toggle theme'),
                                  onPressed: () =>
                                      widget.controller.toggleThemeMode(),
                                  icon: Icon(
                                    context.isDarkMode
                                        ? Icons.light_mode_outlined
                                        : Icons.dark_mode_outlined,
                                  ),
                                ),
                              ],
                              flexibleSpace: FlexibleSpaceBar(
                                collapseMode: CollapseMode.pin,
                                background: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    IgnorePointer(
                                      ignoring: _homeCollapseT > 0.8,
                                      child: Opacity(
                                        opacity:
                                            (1 - _homeCollapseT).clamp(0.0, 1.0),
                                        child: Transform.translate(
                                          offset: Offset(0, -18 * _homeCollapseT),
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 48,
                                              bottom: 40,
                                            ),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  l(context, 'Mag', 'Mag'),
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 42,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: -1.2,
                                                    color: oc.text.withOpacity(
                                                      0.12,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  l(
                                                    context,
                                                    '本地 AI 工作区',
                                                    'Local AI workspace',
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: oc.muted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 8,
                                      child: Opacity(
                                        opacity: _fadeOut(0.0, 0.3),
                                        child: Transform.translate(
                                          offset: Offset(0, 10 * _homeCollapseT),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  l(
                                                    context,
                                                    '项目列表',
                                                    'Projects',
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: oc.text,
                                                  ),
                                                ),
                                              ),
                                              IgnorePointer(
                                                ignoring: _homeCollapseT > 0.3,
                                                child: Opacity(
                                                  opacity: _fadeOut(0.0, 0.3),
                                                  child: FilledButton.icon(
                                                    onPressed:
                                                        _showCreateProjectDialog,
                                                    icon: const Icon(
                                                      Icons
                                                          .create_new_folder_rounded,
                                                      size: 17,
                                                    ),
                                                    label: Text(
                                                      l(context, '新建', 'New'),
                                                    ),
                                                    style:
                                                        FilledButton.styleFrom(
                                                      backgroundColor:
                                                          oc.sendButtonBg,
                                                      foregroundColor:
                                                          oc.sendButtonFg,
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                      tapTargetSize:
                                                          MaterialTapTargetSize
                                                              .shrinkWrap,
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 11,
                                                        vertical: 7,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (snap.hasError)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _ProjectLoadError(
                                  onRetry: () {
                                    setState(() {
                                      _recentFuture = _loadRecents();
                                    });
                                  },
                                ),
                              )
                            else if (snap.connectionState ==
                                    ConnectionState.waiting &&
                                !snap.hasData)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: Center(
                                  child: Text(
                                    l(context, '加载中…', 'Loading…'),
                                    style:
                                        TextStyle(color: oc.muted, fontSize: 13),
                                  ),
                                ),
                              )
                            else if (list.isEmpty)
                              SliverFillRemaining(
                                hasScrollBody: false,
                                child: _EmptyProjects(
                                  onCreate: _showCreateProjectDialog,
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsets.only(bottom: 8),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      if (index.isOdd) {
                                        return const SizedBox(
                                          height: _kProjectListGap,
                                        );
                                      }
                                      final i = index ~/ 2;
                                      final workspace = list[i];
                                      final openedAt =
                                          times[workspace.id] ??
                                              workspace.createdAt;
                                      return _ProjectListTile(
                                        displayName: _displayPath(
                                          context,
                                          workspace.name,
                                        ),
                                        openedLabel: _relativeTime(
                                          context,
                                          openedAt,
                                        ),
                                        onOpen: () async {
                                          await widget.controller
                                              .openSavedProject(workspace);
                                          await _requestNotificationPermissionAfterProjectEnter();
                                        },
                                        onRename: () =>
                                            _showRenameProjectDialog(workspace),
                                        onDelete: () =>
                                            _confirmDeleteProject(workspace),
                                      );
                                    },
                                    childCount: list.isEmpty
                                        ? 0
                                        : list.length * 2 - 1,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    if (widget.controller.state.error != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 8,
                        child: Text(
                          widget.controller.state.error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700,
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

class _ProjectListTile extends StatelessWidget {
  const _ProjectListTile({
    required this.displayName,
    required this.openedLabel,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final String displayName;
  final String openedLabel;
  final Future<void> Function() onOpen;
  final Future<void> Function() onRename;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Material(
      color: oc.panelBackground,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: oc.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                openedLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: oc.muted,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: l(context, '项目操作', 'Project actions'),
                icon: Icon(Icons.more_horiz_rounded, color: oc.muted),
                color: oc.panelBackground,
                elevation: 10,
                position: PopupMenuPosition.under,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: oc.softBorderColor),
                ),
                onSelected: (value) async {
                  if (value == 'rename') {
                    await onRename();
                  } else if (value == 'delete') {
                    await onDelete();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.drive_file_rename_outline_rounded,
                            size: 18, color: oc.foregroundMuted),
                        const SizedBox(width: 10),
                        Text(l(context, '重命名', 'Rename')),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded,
                            size: 18, color: Colors.red.shade600),
                        const SizedBox(width: 10),
                        Text(
                          l(context, '删除', 'Delete'),
                          style: TextStyle(color: Colors.red.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectLoadError extends StatelessWidget {
  const _ProjectLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 34,
            color: oc.muted.withOpacity(0.75),
          ),
          const SizedBox(height: 10),
          Text(
            l(context, '项目列表加载失败', 'Failed to load projects'),
            textAlign: TextAlign.center,
            style: TextStyle(color: oc.muted, fontSize: 14),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: Text(l(context, '重试', 'Retry')),
          ),
        ],
      ),
    );
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

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: oc.panelBackground,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: oc.borderColor),
          boxShadow: [
            BoxShadow(
              color: context.isDarkMode
                  ? Colors.black.withOpacity(0.32)
                  : Colors.black.withOpacity(0.08),
              blurRadius: 28,
              spreadRadius: -10,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color:
                        oc.accent.withOpacity(context.isDarkMode ? 0.16 : 0.10),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: oc.accent
                          .withOpacity(context.isDarkMode ? 0.28 : 0.16),
                    ),
                  ),
                  child: Icon(
                    Icons.create_new_folder_rounded,
                    size: 20,
                    color: oc.accent,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: oc.foreground,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.15,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l(
                          context,
                          '给这个工作区取一个清晰的名字，之后可以随时重命名。',
                          'Give this workspace a clear name. You can rename it later.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: oc.foregroundMuted,
                              height: 1.35,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 15, height: 1.25),
              decoration: InputDecoration(
                hintText: widget.hintText,
                filled: true,
                fillColor: oc.composerOptionBg.withOpacity(0.72),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: oc.softBorderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: oc.softBorderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: oc.accent.withOpacity(0.55)),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  child: Text(l(context, '取消', 'Cancel')),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: oc.sendButtonBg,
                    foregroundColor: oc.sendButtonFg,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 11),
                  ),
                  child: Text(widget.confirmText),
                ),
              ],
            ),
          ],
        ),
      ),
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
