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
    if (type == 'write_stream_preview') {
      return _WriteStreamPreviewAttachmentTile(
        attachment: attachment,
        controller: controller,
        workspace: workspace,
        serverUri: serverUri,
        onInsertPromptReference: onInsertPromptReference,
        onSendPromptReference: onSendPromptReference,
      );
    }
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
        serverUri: serverUri,
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
              border: Border.fromBorderSide(
                  BorderSide(color: context.oc.borderColor)),
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

class _WriteStreamPreviewAttachmentTile extends StatelessWidget {
  const _WriteStreamPreviewAttachmentTile({
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
    final path = attachment['path'] as String? ?? '';
    final content = attachment['content'] as String? ?? '';
    final status = attachment['status'] as String? ?? 'pending';
    final previewKind = attachment['previewKind'] as String? ?? 'write';
    final isEditPreview = previewKind == 'edit';
    final previewPhase = attachment['previewPhase'] as String? ?? 'new';
    final isEditOldPreview = isEditPreview && previewPhase == 'old';
    final inline = attachment['inline'] == true;
    final isRunning = status == 'running' || status == 'pending';
    final diffPreview = attachment['diffPreview'] as String?;
    final lineCount =
        content.isEmpty ? 0 : const LineSplitter().convert(content).length;
    final metaLabel = isRunning
        ? (isEditPreview
            ? (isEditOldPreview
                ? l(context, '正在定位原文 · $lineCount 行',
                    'Locating original · $lineCount line(s)')
                : l(context, '正在生成替换内容 · $lineCount 行',
                    'Generating replacement · $lineCount line(s)'))
            : l(context, '正在生成 · $lineCount 行',
                'Generating · $lineCount line(s)'))
        : (isEditPreview
            ? (isEditOldPreview
                ? l(context, '原文 · $lineCount 行',
                    'Original · $lineCount line(s)')
                : l(context, '替换内容 · $lineCount 行',
                    'Replacement · $lineCount line(s)'))
            : l(context, '预览 · $lineCount 行', 'Preview · $lineCount line(s)'));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: _panelDecoration(
        context,
        background: context.oc.composerOptionBg,
        radius: 12,
        elevated: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isEditPreview
                    ? Icons.find_replace_rounded
                    : Icons.notes_rounded,
                size: 15,
                color: context.oc.foregroundHint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  metaLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.oc.foregroundMuted,
                        fontWeight: FontWeight.w600,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (workspace != null && path.isNotEmpty) ...[
                    _CompactIconButton(
                      tooltip: l(context, '打开文件', 'Open file'),
                      icon: Icons.open_in_new_rounded,
                      small: true,
                      quiet: true,
                      onPressed: () => _openFilePreview(
                        context,
                        controller: controller,
                        workspace: workspace!,
                        path: path,
                        serverUri: serverUri,
                        onInsertPromptReference: onInsertPromptReference,
                        onSendPromptReference: onSendPromptReference,
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  if (diffPreview != null && diffPreview.isNotEmpty) ...[
                    _CompactIconButton(
                      tooltip: l(context, '查看 diff', 'View diff'),
                      icon: Icons.difference_outlined,
                      small: true,
                      quiet: true,
                      onPressed: () => _openDiffPreviewSheet(
                        context,
                        title: path.isEmpty ? metaLabel : path,
                        subtitle: metaLabel,
                        diff: diffPreview,
                      ),
                    ),
                    const SizedBox(width: 7),
                  ],
                  _CompactIconButton(
                    tooltip: l(context, '全屏预览', 'Full screen preview'),
                    icon: Icons.open_in_full_outlined,
                    small: true,
                    quiet: true,
                    onPressed: () => _openWriteStreamPreview(
                      context,
                      controller: controller,
                      workspace: workspace,
                      path: path,
                      initialContent: content,
                      messageId: attachment['messageID'] as String?,
                      partId: attachment['partID'] as String?,
                      contentKey: attachment['contentKey'] as String?,
                      previewKind: previewKind,
                      previewPhase: previewPhase,
                      onInsertPromptReference: onInsertPromptReference,
                      onSendPromptReference: onSendPromptReference,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (inline && content.isNotEmpty) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: _WriteStreamPreviewBody(
                path: path,
                content: content,
                streaming: isRunning,
                sourceOnly: isEditPreview || _pathLooksHtmlFile(path),
                workspace: workspace,
                controller: controller,
                onInsertPromptReference: onInsertPromptReference,
                onSendPromptReference: onSendPromptReference,
              ),
            ),
          ],
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
    final oc = context.oc;
    final path = attachment['path'] as String? ?? '';
    final filename = attachment['filename'] as String? ?? path;
    final preview = attachment['preview'] as String? ?? '';
    final startLine = attachment['startLine'];
    final endLine = attachment['endLine'];
    final lineCount = attachment['lineCount'];
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: oc.panelBackground.withOpacity(0.58),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: oc.borderColor.withOpacity(0.6)),
                ),
                child: Icon(Icons.article_outlined,
                    size: 14, color: oc.foregroundHint),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      filename,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: oc.foreground,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$path · $startLine-$endLine / $lineCount',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: oc.foregroundHint,
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _CompactIconButton(
                tooltip: l(context, '打开文件', 'Open file'),
                icon: Icons.open_in_new_rounded,
                small: true,
                quiet: true,
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
                _CompactIconButton(
                  tooltip: l(context, '查看片段', 'View snippet'),
                  icon: Icons.notes_rounded,
                  small: true,
                  quiet: true,
                  onPressed: () => _openTextPreviewSheet(
                    context,
                    title: filename,
                    subtitle: '$path · $startLine-$endLine / $lineCount',
                    content: preview,
                  ),
                ),
            ],
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: oc.panelBackground.withOpacity(0.42),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: oc.borderColor.withOpacity(0.42)),
              ),
              child: Text(
                preview.split('\n').take(3).join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: oc.foregroundMuted,
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  height: 1.3,
                ),
              ),
            ),
          ],
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
