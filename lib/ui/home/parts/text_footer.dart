part of '../../home_page.dart';

/// OpenCode `TextPartDisplay` 底部：`IconButton` + `text-part-meta`（Agent · 模型 · 耗时）。
class _AssistantTextFooter extends StatefulWidget {
  const _AssistantTextFooter({
    required this.plainText,
    this.metaLine,
  });

  final String plainText;
  final String? metaLine;

  @override
  State<_AssistantTextFooter> createState() => _AssistantTextFooterState();
}

class _AssistantTextFooterState extends State<_AssistantTextFooter> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final meta = widget.metaLine?.trim();
    final hasMeta = meta != null && meta.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: _copied
                ? l(context, '已复制', 'Copied')
                : l(context, '复制回复', 'Copy response'),
            icon: Icon(
              _copied ? Icons.check : Icons.copy_outlined,
              size: 20,
              color: _copied ? context.oc.green : context.oc.muted,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.plainText));
              if (!mounted) return;
              setState(() => _copied = true);
              Future<void>.delayed(const Duration(seconds: 2), () {
                if (mounted) setState(() => _copied = false);
              });
              _showInfo(
                context,
                l(context, '回复已复制', 'Response copied'),
              );
            },
          ),
          if (hasMeta)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, left: 2),
                child: Text(
                  meta,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.oc.muted,
                        height: 1.35,
                        fontSize: 12,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

int _bundleCompletionMs(SessionMessageBundle b) {
  var maxMs = b.message.createdAt;
  for (final p in b.parts) {
    if (p.createdAt > maxMs) maxMs = p.createdAt;
  }
  return maxMs;
}

/// 与 OpenCode `SessionTurn.turnDurationMs` 一致：从本轮用户消息到各 assistant 完成时刻的最大值。
int? _turnDurationMsForAssistantBundle(AppState state, int bundleIdx) {
  if (bundleIdx < 0 || bundleIdx >= state.messages.length) return null;
  final target = state.messages[bundleIdx];
  if (target.message.role != SessionRole.assistant) return null;

  var userIdx = -1;
  for (var i = bundleIdx; i >= 0; i--) {
    if (state.messages[i].message.role == SessionRole.user) {
      userIdx = i;
      break;
    }
  }
  if (userIdx < 0) return null;

  if (state.isBusy &&
      state.messages.isNotEmpty &&
      state.messages.last.message.role == SessionRole.assistant) {
    var lastTurnUser = -1;
    for (var i = state.messages.length - 1; i >= 0; i--) {
      if (state.messages[i].message.role == SessionRole.user) {
        lastTurnUser = i;
        break;
      }
    }
    if (bundleIdx > lastTurnUser) return null;
  }

  final startMs = state.messages[userIdx].message.createdAt;
  var endMs = target.message.createdAt;
  for (var j = userIdx + 1; j < state.messages.length; j++) {
    if (state.messages[j].message.role == SessionRole.user) break;
    if (state.messages[j].message.role == SessionRole.assistant) {
      final c = _bundleCompletionMs(state.messages[j]);
      if (c > endMs) endMs = c;
    }
  }
  final ms = endMs - startMs;
  return ms >= 0 ? ms : null;
}

String? _formatTurnDurationLabel(BuildContext context, int ms) {
  if (ms < 0) return null;
  final totalSec = (ms / 1000).round();
  if (totalSec < 60) {
    return l(context, '$totalSec 秒', '${totalSec}s');
  }
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return l(context, '$m 分 $s 秒', '${m}m ${s}s');
}

/// OpenCode `TextPartDisplay` 的 `meta()`：`Agent · model · duration · interrupted`。
String? _assistantReplyFooterMeta(
  BuildContext context,
  MessageInfo message,
  int? turnDurationMs,
) {
  if (message.role != SessionRole.assistant) return null;
  final agent = message.agent.trim();
  final agentLabel = agent.isEmpty
      ? ''
      : '${agent[0].toUpperCase()}${agent.substring(1)}';
  final model = (message.model ?? '').trim();
  final durLabel = turnDurationMs != null
      ? _formatTurnDurationLabel(context, turnDurationMs)
      : null;
  final interruptedLabel =
      (message.error != null && message.error!.trim().isNotEmpty)
          ? l(context, '已中断', 'Interrupted')
          : '';
  final parts = <String>[
    if (agentLabel.isNotEmpty) agentLabel,
    if (model.isNotEmpty) model,
    if (durLabel != null && durLabel.isNotEmpty) durLabel,
    if (interruptedLabel.isNotEmpty) interruptedLabel,
  ];
  if (parts.isEmpty) return null;
  return parts.join(' \u00B7 ');
}
