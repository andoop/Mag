part of '../home_page.dart';

String _ocRelativeTime(BuildContext context, int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
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

Widget _ocSheetDragHandle() {
  return Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: kOcMuted.withOpacity(0.35),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    ),
  );
}

extension _HomeOcShell on _HomePageState {
  Future<void> _openMoreMenu(BuildContext context) async {
    final state = widget.controller.state;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _kPageBackground,
      barrierColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(ctx).padding.bottom + 12,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: kOcSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kOcBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ocSheetDragHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l(context, 'Mag', 'Mag'),
                              style: const TextStyle(
                                color: kOcText,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l(
                                context,
                                '会话与工作区操作',
                                'Session & workspace actions',
                              ),
                              style: const TextStyle(
                                color: kOcMuted,
                                fontSize: 12.5,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(ctx).closeButtonLabel,
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded, color: kOcMuted),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
                _ocMoreTile(
                  ctx,
                  icon: Icons.smart_toy_outlined,
                  label: l(context, '切换 Agent', 'Switch Agent'),
                  hint: l(context, 'build / plan / explore …', 'build / plan / explore …'),
                  accent: kOcAccent,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openAgentPicker(context);
                  },
                ),
                _ocMoreTile(
                  ctx,
                  icon: Icons.history_rounded,
                  label: l(context, '历史会话', 'Sessions'),
                  hint: l(context, '浏览并选择会话', 'Browse and open a session'),
                  accent: kOcAccentMuted,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openSessionPicker(context);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, color: kOcBorder),
                ),
                _ocMoreTile(
                  ctx,
                  icon: Icons.compress_outlined,
                  label: l(context, '压缩当前会话', 'Compact session'),
                  hint: l(context, '总结上下文以节省 tokens', 'Summarize context to save tokens'),
                  accent: kOcOrange,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.controller.compactSession();
                  },
                ),
                _ocMoreTile(
                  ctx,
                  icon: Icons.note_alt_outlined,
                  label: l(
                    context,
                    '初始化/更新项目记忆',
                    'Initialize / update project memory',
                  ),
                  hint: l(context, '写入 Mag.md 等', 'Writes Mag.md, etc.'),
                  accent: kOcGreen,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    widget.controller.initializeProjectMemory();
                  },
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(height: 1, color: kOcBorder),
                ),
                _ocMoreTile(
                  ctx,
                  icon: Icons.settings_outlined,
                  label: l(context, '设置', 'Settings'),
                  hint: l(context, 'Base URL、API Key、模型', 'Base URL, API key, model'),
                  accent: kOcMuted,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openSettings(context, state.modelConfig);
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }
}

Widget _ocMoreTile(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String hint,
  required Color accent,
  required VoidCallback onTap,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kOcElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kOcBorder),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: kOcText,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    style: TextStyle(
                      color: kOcMuted.withOpacity(0.92),
                      fontSize: 12.5,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: kOcMuted.withOpacity(0.7),
              size: 22,
            ),
          ],
        ),
      ),
    ),
  );
}
