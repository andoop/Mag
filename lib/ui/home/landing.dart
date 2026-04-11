part of '../home_page.dart';

extension _HomePageLanding on _HomePageState {
  Widget _buildNewSessionLanding(BuildContext context, AppState state) {
    final ws = state.workspace!;
    final oc = context.oc;
    final currentModel = state.modelConfig ?? ModelConfig.defaults();
    final currentModelChoice = _findModelChoice(
      currentModel.provider,
      currentModel.model,
      config: currentModel,
    );
    final currentVariant = _effectiveSelectedVariant(state);
    return ColoredBox(
      color: oc.pageBackground,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Icon(
              Icons.blur_circular_rounded,
              size: 44,
              color: oc.muted.withOpacity(0.35),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            l(context, '新建会话', 'New session'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: oc.text,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            ws.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
              color: oc.muted,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _TinyTag(
                label: _selectedAgent ?? state.session?.agent ?? 'build',
                color: oc.tagBlueGrey,
              ),
              _TinyTag(
                label: _providerLabel(
                  currentModel.provider,
                  config: currentModel,
                  state: state,
                ),
                color: oc.tagGreen,
              ),
              _TinyTag(
                label: currentModelChoice?.name ?? currentModel.model,
                color: oc.tagBlue,
              ),
              if (currentVariant != null && currentVariant.isNotEmpty)
                _TinyTag(label: currentVariant, color: oc.tagOrange),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.call_split_rounded,
                size: 15,
                color: oc.muted.withOpacity(0.9),
              ),
              const SizedBox(width: 6),
              Text(
                l(context, '主工作区', 'main'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: oc.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${l(context, '加入于', 'Added')} · ${_formatLandingDate(ws.createdAt)}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: oc.muted,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            l(
              context,
              '在下方输入第一条消息以开始；将自动创建会话。',
              'Type your first message below to start — a session will be created.',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: oc.muted.withOpacity(0.95),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLandingDate(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  /// 左侧滑出：会话列表 + 新建 + 压缩/记忆（原「更多」里依赖会话的项）。
  Widget _buildSessionDrawer(BuildContext context, AppState state) {
    final ws = state.workspace!;
    final oc = context.oc;
    return Drawer(
      backgroundColor: oc.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l(context, '会话记录', 'Sessions'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: oc.muted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ws.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: oc.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: oc.muted,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: oc.border),
            ListTile(
              leading: Icon(Icons.edit_note_outlined, color: oc.accent),
              title: Text(l(context, '新建空白页', 'New chat (blank)')),
              subtitle: Text(
                l(context, '仅输入区，首条消息再建会话',
                    'Composer only; first send creates session'),
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.controller.enterNewSessionLanding();
              },
            ),
            ListTile(
              leading: Icon(Icons.add_comment_outlined, color: oc.accentMuted),
              title: Text(l(context, '新建会话', 'New session')),
              subtitle: Text(
                l(context, '立即创建新对话', 'Create a new thread now'),
                style: const TextStyle(fontSize: 11),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.controller.createSession(
                  agent: _selectedAgent ?? state.session?.agent ?? 'build',
                );
              },
            ),
            Divider(height: 1, color: oc.border),
            Expanded(
              child: state.sessions.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l(context, '暂无历史会话', 'No sessions yet'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: oc.muted, fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: state.sessions.length,
                      itemBuilder: (context, i) {
                        final s = state.sessions[i];
                        final selected = s.id == state.session?.id;
                        final status = state.statusForSession(s.id);
                        final menuLocked = state.isSessionBusy(s.id);
                        return ListTile(
                          leading: Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: selected ? oc.accent : oc.muted,
                          ),
                          selected: selected,
                          selectedTileColor: oc.selectedFill.withOpacity(0.5),
                          title: Text(
                            s.title.isNotEmpty
                                ? s.title
                                : l(context, '未命名', 'Untitled'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            selected
                                ? '${l(context, '当前', 'Current')} · ${s.agent}'
                                : s.agent,
                            style: selected
                                ? TextStyle(
                                    fontSize: 11,
                                    color: oc.accent.withOpacity(0.95),
                                    fontWeight: FontWeight.w600,
                                  )
                                : TextStyle(
                                    fontSize: 11,
                                    color: oc.muted,
                                  ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (status.isBusy)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: _SessionStatusBadge(status: status),
                                ),
                              if (selected)
                                Padding(
                                  padding: const EdgeInsets.only(right: 2),
                                  child: Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: oc.accent,
                                  ),
                                ),
                              PopupMenuButton<String>(
                                icon: Icon(
                                  Icons.more_vert_rounded,
                                  color: oc.muted,
                                  size: 20,
                                ),
                                padding: const EdgeInsets.all(0),
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                enabled: !menuLocked,
                                tooltip: l(context, '会话操作', 'Session actions'),
                                onSelected: (value) {
                                  if (value == 'rename') {
                                    _promptRenameSession(context, state, s);
                                  } else if (value == 'delete') {
                                    _confirmDeleteSession(context, state, s);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: Text(l(context, '重命名', 'Rename')),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      l(context, '删除', 'Delete'),
                                      style: const TextStyle(
                                          color: Colors.redAccent),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            widget.controller.switchSession(s);
                          },
                        );
                      },
                    ),
            ),
            if (state.session != null) ...[
              Divider(height: 1, color: oc.border),
              ListTile(
                leading: Icon(Icons.compress_outlined, color: oc.orange),
                title: Text(l(context, '压缩当前会话', 'Compact session')),
                enabled: !state.isBusy,
                onTap: state.isBusy
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.controller.compactSession();
                      },
              ),
              ListTile(
                leading: Icon(Icons.note_alt_outlined, color: oc.green),
                title: Text(l(
                  context,
                  '初始化/更新项目记忆',
                  'Initialize / update project memory',
                )),
                enabled: !state.isBusy,
                onTap: state.isBusy
                    ? null
                    : () {
                        Navigator.pop(context);
                        widget.controller.initializeProjectMemory();
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _promptRenameSession(
    BuildContext context,
    AppState state,
    SessionInfo s,
  ) async {
    if (state.isSessionBusy(s.id)) return;
    final controller = TextEditingController(text: s.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l(context, '重命名会话', 'Rename session')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 256,
          decoration: InputDecoration(
            hintText: l(context, '标题', 'Title'),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l(context, '取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l(context, '保存', 'Save')),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty) return;
    await widget.controller.renameSession(s, newTitle);
  }

  Future<void> _confirmDeleteSession(
    BuildContext context,
    AppState state,
    SessionInfo s,
  ) async {
    if (state.isSessionBusy(s.id)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l(context, '删除会话', 'Delete session')),
        content: Text(
          l(
            context,
            '将永久删除该会话及其消息，不可恢复。',
            'This permanently deletes the session and its messages.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l(context, '取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l(context, '删除', 'Delete'),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (context.mounted) Navigator.pop(context);
    await widget.controller.removeSession(s);
  }
}

class _SessionStatusBadge extends StatelessWidget {
  const _SessionStatusBadge({required this.status});

  final SessionRunStatus status;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final label = status.isCompacting
        ? l(context, '压缩中', 'Compacting')
        : status.isRetrying
            ? l(context, '重试中', 'Retrying')
            : l(context, '运行中', 'Running');
    final color = status.isCompacting
        ? oc.orange
        : status.isRetrying
            ? oc.accentMuted
            : oc.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
