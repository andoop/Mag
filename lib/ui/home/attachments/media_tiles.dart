part of '../../home_page.dart';

class _WebAttachmentTile extends StatelessWidget {
  const _WebAttachmentTile({required this.attachment});

  final Map<String, dynamic> attachment;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final title = attachment['title'] as String? ?? 'Web page';
    final url = attachment['url'] as String? ?? '';
    final excerpt = attachment['excerpt'] as String? ?? '';
    final statusCode = attachment['statusCode'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(context,
          background: oc.userBubble, radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                child: const Icon(Icons.language, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
            ],
          ),
          const SizedBox(height: 4),
          Text(url,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.oc.foregroundMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(l(context, '状态: $statusCode', 'Status: $statusCode')),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (url.isNotEmpty)
                _CompactActionButton(
                  label: l(context, '预览', 'Preview'),
                  onPressed: () => _openWebPreview(
                    context,
                    title: title,
                    subtitle: url,
                    url: url,
                  ),
                ),
              if (excerpt.isNotEmpty)
                _CompactActionButton(
                  label: l(context, '查看摘要', 'View summary'),
                  onPressed: () => _openTextPreviewSheet(
                    context,
                    title: title,
                    subtitle: url,
                    content: excerpt,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrowserAttachmentTile extends StatelessWidget {
  const _BrowserAttachmentTile({
    required this.attachment,
    required this.workspace,
    required this.serverUri,
  });

  final Map<String, dynamic> attachment;
  final WorkspaceInfo workspace;
  final Uri serverUri;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final path = attachment['path'] as String? ?? '';
    final title = attachment['title'] as String? ?? path;
    final previewUrl = _workspacePreviewUrl(
      serverUri: serverUri,
      workspace: workspace,
      path: path,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(context,
          background: oc.selectedFill, radius: 14, elevated: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                child: const Icon(Icons.web, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )),
            ],
          ),
          const SizedBox(height: 4),
          Text(path,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.oc.foregroundMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CompactActionButton(
                label: l(context, '打开网页', 'Open page'),
                onPressed: () => _openWebPreview(
                  context,
                  title: title,
                  subtitle: path,
                  url: previewUrl.toString(),
                ),
              ),
              _CompactActionButton(
                label: l(context, '复制链接', 'Copy link'),
                onPressed: () => _copyText(
                  context,
                  previewUrl.toString(),
                  l(context, '预览链接已复制', 'Preview link copied'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Uri _workspacePreviewUrl({
  required Uri serverUri,
  required WorkspaceInfo workspace,
  required String path,
}) {
  final baseSegments =
      serverUri.pathSegments.where((item) => item.isNotEmpty).toList();
  final pathSegments =
      path.split('/').where((item) => item.isNotEmpty).toList();
  return serverUri.replace(
    pathSegments: [
      ...baseSegments,
      'workspace-file',
      workspace.id,
      ...pathSegments,
    ],
    queryParameters: null,
  );
}

Future<void> _openWebPreview(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String url,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => _WebPreviewSheet(
        title: title,
        subtitle: subtitle,
        url: url,
      ),
    ),
  );
}

class _PdfAttachmentTile extends StatelessWidget {
  const _PdfAttachmentTile({
    required this.filename,
    required this.controller,
    required this.treeUri,
    required this.relativePath,
  });

  final String filename;
  final AppController controller;
  final String treeUri;
  final String relativePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: _panelDecoration(context,
          background: const Color(0xFFFEF2F2), radius: 14, elevated: false),
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
            child: const Icon(Icons.picture_as_pdf, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              filename,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _CompactActionButton(
            label: l(context, '预览', 'Preview'),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => FractionallySizedBox(
                  heightFactor: 0.92,
                  child: _PdfPreviewSheet(
                    filename: filename,
                    controller: controller,
                    treeUri: treeUri,
                    relativePath: relativePath,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ImageAttachmentTile extends StatelessWidget {
  const _ImageAttachmentTile({
    required this.filename,
    required this.mime,
    required this.controller,
    required this.treeUri,
    required this.relativePath,
  });

  final String filename;
  final String mime;
  final AppController controller;
  final String treeUri;
  final String relativePath;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: controller.loadWorkspaceBytes(
        treeUri: treeUri,
        relativePath: relativePath,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Text(l(context, '附件加载失败: $filename',
              'Attachment failed to load: $filename'));
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: _panelDecoration(context,
              background: context.oc.mutedPanel, radius: 14, elevated: false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                filename,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Text(
                      l(context, '不支持的图片: $mime', 'Unsupported image: $mime')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
