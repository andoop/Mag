part of '../../home_page.dart';

class _GlobResultsAttachmentTile extends StatelessWidget {
  const _GlobResultsAttachmentTile({
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
    final items = (attachment['items'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final count = attachment['count'];
    final pattern = attachment['pattern'] as String? ?? '*';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(context,
          background: const Color(0xFFEEF2FF), radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Glob · $pattern',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(l(context, '匹配: $count', 'Matches: $count')),
          const SizedBox(height: 8),
          ...items.map(
            (item) => _FileResultRow(
              path: item['path'] as String? ?? '',
              controller: controller,
              workspace: workspace,
              onInsertPromptReference: onInsertPromptReference,
              onSendPromptReference: onSendPromptReference,
            ),
          ),
        ],
      ),
    );
  }
}

class _GrepResultsAttachmentTile extends StatelessWidget {
  const _GrepResultsAttachmentTile({
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
    final items = (attachment['items'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final pattern = attachment['pattern'] as String? ?? '';
    final count = attachment['count'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(context,
          background: const Color(0xFFFFF7ED), radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Grep · $pattern',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(l(context, '匹配: $count', 'Matches: $count')),
          const SizedBox(height: 8),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _GrepResultRow(
                path: item['path'] as String? ?? '',
                line: item['line'] as int? ?? 1,
                text: item['text'] as String? ?? '',
                controller: controller,
                workspace: workspace,
                onInsertPromptReference: onInsertPromptReference,
                onSendPromptReference: onSendPromptReference,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileResultRow extends StatelessWidget {
  const _FileResultRow({
    required this.path,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final String path;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final canOpen = workspace != null && path.isNotEmpty;
    return InkWell(
      onTap: canOpen
          ? () => _openFilePreview(
                context,
                controller: controller,
                workspace: workspace!,
                path: path,
                onInsertPromptReference: onInsertPromptReference,
                onSendPromptReference: onSendPromptReference,
              )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.description, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(path)),
          ],
        ),
      ),
    );
  }
}

class _GrepResultRow extends StatelessWidget {
  const _GrepResultRow({
    required this.path,
    required this.line,
    required this.text,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final String path;
  final int line;
  final String text;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final canOpen = workspace != null && path.isNotEmpty;
    return InkWell(
      onTap: canOpen
          ? () => _openFilePreview(
                context,
                controller: controller,
                workspace: workspace!,
                path: path,
                initialLine: line,
                onInsertPromptReference: onInsertPromptReference,
                onSendPromptReference: onSendPromptReference,
              )
          : null,
      child: Text(
        '$path:$line: $text',
        style: const TextStyle(fontFamily: 'monospace'),
      ),
    );
  }
}
