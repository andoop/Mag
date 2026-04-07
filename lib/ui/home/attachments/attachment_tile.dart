part of '../../home_page.dart';

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.controller,
    required this.workspace,
    required this.serverUri,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final Map<String, dynamic> attachment;
  final AppController controller;
  final WorkspaceInfo? workspace;
  final Uri? serverUri;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final type = attachment['type'] as String? ?? 'file';
    final mime = attachment['mime'] as String? ?? 'application/octet-stream';
    final path = attachment['url'] as String? ?? '';
    final filename = attachment['filename'] as String? ?? path;
    if (type == 'text_preview' && workspace != null) {
      return _TextPreviewAttachmentTile(
        attachment: attachment,
        controller: controller,
        workspace: workspace!,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      );
    }
    if (type == 'glob_results') {
      return _GlobResultsAttachmentTile(
        attachment: attachment,
        controller: controller,
        workspace: workspace,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      );
    }
    if (type == 'grep_results') {
      return _GrepResultsAttachmentTile(
        attachment: attachment,
        controller: controller,
        workspace: workspace,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      );
    }
    if (type == 'webpage') {
      return _WebAttachmentTile(attachment: attachment);
    }
    if (type == 'browser_page' && workspace != null && serverUri != null) {
      return _BrowserAttachmentTile(
        attachment: attachment,
        workspace: workspace!,
        serverUri: serverUri!,
      );
    }
    if (type == 'diff_preview') {
      return _DiffPreviewAttachmentTile(
        attachment: attachment,
        controller: controller,
        workspace: workspace,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      );
    }
    if (mime.startsWith('image/') && workspace != null && path.isNotEmpty) {
      return _ImageAttachmentTile(
        filename: filename,
        mime: mime,
        controller: controller,
        treeUri: workspace!.treeUri,
        relativePath: path,
      );
    }
    if (mime == 'application/pdf' && workspace != null && path.isNotEmpty) {
      return _PdfAttachmentTile(
        filename: filename,
        controller: controller,
        treeUri: workspace!.treeUri,
        relativePath: path,
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(context,
          background: context.oc.mutedPanel, radius: 14, elevated: false),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.oc.panelBackground,
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.fromBorderSide(BorderSide(color: context.oc.borderColor)),
            ),
            child: Icon(
              mime == 'application/pdf'
                  ? Icons.picture_as_pdf
                  : Icons.attach_file,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$filename\n$mime',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _TextPreviewAttachmentTile extends StatelessWidget {
  const _TextPreviewAttachmentTile({
    required this.attachment,
    required this.controller,
    required this.workspace,
    required this.onInsertPromptReference,
    required this.onSendPromptReference,
  });

  final Map<String, dynamic> attachment;
  final AppController controller;
  final WorkspaceInfo workspace;
  final ValueChanged<String> onInsertPromptReference;
  final PromptReferenceAction onSendPromptReference;

  @override
  Widget build(BuildContext context) {
    final path = attachment['path'] as String? ?? '';
    final filename = attachment['filename'] as String? ?? path;
    final preview = attachment['preview'] as String? ?? '';
    final startLine = attachment['startLine'];
    final endLine = attachment['endLine'];
    final lineCount = attachment['lineCount'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(context,
          background: context.oc.composerOptionBg, radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            filename,
            style: const TextStyle(fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            l(context, '文本片段', 'Text preview'),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: context.oc.foregroundMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CompactActionButton(
                label: l(context, '打开', 'Open'),
                onPressed: () => _openFilePreview(
                  context,
                  controller: controller,
                  workspace: workspace,
                  path: path,
                  initialLine: startLine as int?,
                  onInsertPromptReference: onInsertPromptReference,
                  onSendPromptReference: onSendPromptReference,
                ),
              ),
              if (preview.isNotEmpty)
                _CompactActionButton(
                  label: l(context, '查看片段', 'View snippet'),
                  onPressed: () => _openTextPreviewSheet(
                    context,
                    title: filename,
                    subtitle: '$path · $startLine-$endLine / $lineCount',
                    content: preview,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$path · $startLine-$endLine / $lineCount',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.oc.foregroundMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

Future<void> _openTextPreviewSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String content,
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
                    child: SelectableText(
                      content,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12, height: 1.4),
                    ),
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
