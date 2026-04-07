part of '../../home_page.dart';

class _DiffPreviewAttachmentTile extends StatelessWidget {
  const _DiffPreviewAttachmentTile({
    required this.attachment,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final Map<String, dynamic> attachment;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final path = attachment['path'] as String? ?? '';
    final kind = attachment['kind'] as String? ?? 'update';
    final preview = attachment['preview'] as String? ?? '';
    final canOpen = workspace != null && path.isNotEmpty && kind != 'delete';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(context,
          background: context.oc.permissionPreviewBg, radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('$kind · $path',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (canOpen)
                OutlinedButton(
                  onPressed: () => _openFilePreview(
                    context,
                    controller: controller,
                    workspace: workspace!,
                    path: path,
                    onInsertPromptReference: onInsertPromptReference,
                    onSendPromptReference: onSendPromptReference,
                  ),
                  child: Text(l(context, '打开', 'Open')),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CompactActionButton(
                label: l(context, '插入', 'Insert'),
                icon: Icons.playlist_add_outlined,
                onPressed: () => onInsertPromptReference(
                  _asPromptReference(
                    path: path,
                    language: null,
                    startLine: 1,
                    endLine: preview.split('\n').length,
                    content: preview,
                  ),
                ),
              ),
              _CompactActionButton(
                label: l(context, '发送', 'Send'),
                icon: Icons.send_outlined,
                filled: true,
                onPressed: () async {
                  await onSendPromptReference(
                    _asPromptReference(
                      path: path,
                      language: null,
                      startLine: 1,
                      endLine: preview.split('\n').length,
                      content: preview,
                    ),
                  );
                },
              ),
              _CompactActionButton(
                label: l(context, '查看 diff', 'View diff'),
                icon: Icons.difference_outlined,
                onPressed: () => _openDiffPreviewSheet(
                  context,
                  title: '$kind · $path',
                  subtitle: path,
                  diff: attachment['fullPreview'] as String? ?? preview,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiffPreviewBody extends StatelessWidget {
  const _DiffPreviewBody({required this.preview});

  final String preview;

  @override
  Widget build(BuildContext context) {
    final lines = const LineSplitter().convert(preview);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 80,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines.map(_buildLine).toList(),
        ),
      ),
    );
  }

  Widget _buildLine(String line) {
    Color? background;
    Color? foreground;
    if (line.startsWith('+')) {
      background = const Color(0xFFDCFCE7);
      foreground = Colors.green.shade900;
    } else if (line.startsWith('-')) {
      background = const Color(0xFFFEE2E2);
      foreground = Colors.red.shade900;
    } else if (line.startsWith('@@')) {
      background = const Color(0xFFEDE9FE);
      foreground = Colors.deepPurple.shade900;
    }
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Text(
        line.isEmpty ? ' ' : line,
        softWrap: false,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.35,
          color: foreground,
        ),
      ),
    );
  }
}

Future<void> _openDiffPreviewSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String diff,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CompactIconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icons.close,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: _panelDecoration(context,
                      background: context.oc.shadow,
                      radius: 14,
                      elevated: false),
                  child: SingleChildScrollView(
                    child: _DiffPreviewBody(preview: diff),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
