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
    final background =
        context.isDarkMode ? const Color(0xFF1F2233) : const Color(0xFFEEF2FF);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(context,
          background: background, radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Glob · $pattern',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: context.oc.foreground)),
          const SizedBox(height: 6),
          Text(
            l(context, '匹配: $count', 'Matches: $count'),
            style: TextStyle(color: context.oc.foregroundMuted),
          ),
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
    final oc = context.oc;
    final items = (attachment['items'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final pattern = attachment['pattern'] as String? ?? '';
    final count = attachment['count'] ?? items.length;
    final include = attachment['include'] as String?;
    final truncated = attachment['truncated'] == true;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: oc.composerOptionBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: oc.softBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      oc.accent.withOpacity(context.isDarkMode ? 0.14 : 0.08),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(Icons.manage_search_rounded,
                    size: 14, color: oc.accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pattern.isEmpty ? l(context, '文本搜索', 'Text search') : pattern,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: oc.foreground,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                l(context, '$count${truncated ? '+' : ''} 处',
                    '$count${truncated ? '+' : ''} matches'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: oc.foregroundHint,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
              ),
            ],
          ),
          if (include != null && include.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              include,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: oc.foregroundHint,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 210),
              child: Scrollbar(
                thumbVisibility: items.length > 6,
                child: ListView.separated(
                  primary: false,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 0.6,
                    color: oc.borderColor.withOpacity(0.42),
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _GrepResultRow(
                      path: item['path'] as String? ?? '',
                      line: item['line'] as int? ?? 1,
                      text: item['text'] as String? ?? '',
                      controller: controller,
                      workspace: workspace,
                      onInsertPromptReference: onInsertPromptReference,
                      onSendPromptReference: onSendPromptReference,
                    );
                  },
                ),
              ),
            ),
          ],
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
            Icon(Icons.description, size: 16, color: context.oc.foregroundHint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                path,
                style: TextStyle(color: context.oc.foreground),
              ),
            ),
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
    final oc = context.oc;
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 28),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: oc.panelBackground.withOpacity(0.55),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: oc.borderColor.withOpacity(0.55)),
              ),
              child: Text(
                '$line',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: oc.foregroundHint,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      color: oc.accent.withOpacity(0.9),
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    text.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      color: oc.foregroundMuted,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
