part of '../home_page.dart';

void _pushWorkspaceFileBrowser(
  BuildContext context, {
  required WorkspaceInfo workspace,
  required AppController controller,
}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (ctx) => _WorkspaceFileBrowserPage(
        workspace: workspace,
        controller: controller,
      ),
    ),
  );
}

bool _browserPathLooksPdf(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.pdf');
}

bool _browserPathLooksImage(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.avif');
}

bool _browserEntryLooksImage(WorkspaceEntry e) {
  final m = e.mimeType?.toLowerCase() ?? '';
  if (m.startsWith('image/')) return true;
  return _browserPathLooksImage(e.path);
}

String _browserParentPath(String relativePath) {
  if (relativePath.isEmpty) return '';
  final parts = relativePath.split('/')..removeWhere((s) => s.isEmpty);
  if (parts.length <= 1) return '';
  parts.removeLast();
  return parts.join('/');
}

void _openBrowserFile(
  BuildContext context, {
  required AppController controller,
  required WorkspaceInfo workspace,
  required WorkspaceEntry entry,
}) {
  if (entry.isDirectory) return;
  final path = entry.path;
  if (_browserPathLooksPdf(path)) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          backgroundColor: ctx.oc.panelBackground,
          body: _PdfPreviewSheet(
            filename: entry.name,
            controller: controller,
            treeUri: workspace.treeUri,
            relativePath: path,
          ),
        ),
      ),
    );
    return;
  }
  if (_browserEntryLooksImage(entry)) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => _WorkspaceImagePreviewPage(
          filename: entry.name,
          controller: controller,
          treeUri: workspace.treeUri,
          relativePath: path,
        ),
      ),
    );
    return;
  }
  _openFilePreview(
    context,
    controller: controller,
    workspace: workspace,
    path: path,
  );
}

class _WorkspaceImagePreviewPage extends StatelessWidget {
  const _WorkspaceImagePreviewPage({
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          filename,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: FutureBuilder<Uint8List>(
        future: controller.loadWorkspaceBytes(
          treeUri: treeUri,
          relativePath: relativePath,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l(context, '图片加载失败', 'Failed to load image'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return InteractiveViewer(
            minScale: 0.25,
            maxScale: 6,
            child: Center(
              child: Image.memory(
                snapshot.data!,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WorkspaceFileBrowserPage extends StatefulWidget {
  const _WorkspaceFileBrowserPage({
    required this.workspace,
    required this.controller,
  });

  final WorkspaceInfo workspace;
  final AppController controller;

  @override
  State<_WorkspaceFileBrowserPage> createState() =>
      _WorkspaceFileBrowserPageState();
}

class _WorkspaceFileBrowserPageState extends State<_WorkspaceFileBrowserPage> {
  String _relativePath = '';
  Future<List<WorkspaceEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _future = WorkspaceBridge.instance.listDirectory(
        treeUri: widget.workspace.treeUri,
        relativePath: _relativePath,
        force: true,
      );
    });
  }

  void _enterDirectory(WorkspaceEntry entry) {
    setState(() {
      _relativePath = entry.path;
      _reload();
    });
  }

  void _goUp() {
    setState(() {
      _relativePath = _browserParentPath(_relativePath);
      _reload();
    });
  }

  List<WorkspaceEntry> _sorted(List<WorkspaceEntry> raw) {
    final dirs = raw.where((e) => e.isDirectory).toList();
    final files = raw.where((e) => !e.isDirectory).toList();
    int byName(WorkspaceEntry a, WorkspaceEntry b) => a.name
        .toLowerCase()
        .compareTo(b.name.toLowerCase());
    dirs.sort(byName);
    files.sort(byName);
    return [...dirs, ...files];
  }

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final title = _relativePath.isEmpty
        ? l(context, '工作区文件', 'Workspace files')
        : _relativePath;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            tooltip: l(context, '刷新', 'Refresh'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_relativePath.isNotEmpty)
            Material(
              color: oc.surface,
              child: InkWell(
                onTap: _goUp,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.arrow_upward_rounded,
                          size: 20, color: oc.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l(context, '上级目录', 'Parent folder'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: oc.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_relativePath.isNotEmpty)
            Divider(height: 1, color: oc.border),
          Expanded(
            child: FutureBuilder<List<WorkspaceEntry>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l(context, '无法读取目录', 'Could not read folder'),
                            style: TextStyle(
                                fontWeight: FontWeight.w600, color: oc.text),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${snapshot.error}',
                            style: TextStyle(
                                fontSize: 12, color: oc.muted),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(l(context, '重试', 'Retry')),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final items = _sorted(snapshot.data ?? const []);
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      l(context, '此文件夹为空', 'This folder is empty'),
                      style: TextStyle(color: oc.muted),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: oc.border),
                  itemBuilder: (context, i) {
                    final e = items[i];
                    final icon = e.isDirectory
                        ? Icons.folder_rounded
                        : _browserPathLooksPdf(e.path)
                            ? Icons.picture_as_pdf_rounded
                            : _browserEntryLooksImage(e)
                                ? Icons.image_outlined
                                : _pathLooksMarkdownFile(e.path)
                                    ? Icons.description_outlined
                                    : _pathLooksHtmlFile(e.path)
                                        ? Icons.language_rounded
                                        : Icons.insert_drive_file_outlined;
                    final meta = e.isDirectory
                        ? l(context, '文件夹', 'Folder')
                        : (e.size > 0
                            ? _formatBrowserFileSize(e.size)
                            : l(context, '文件', 'File'));
                    return ListTile(
                      leading: Icon(icon, color: oc.accent),
                      title: Text(
                        e.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        meta,
                        style: TextStyle(fontSize: 11, color: oc.muted),
                      ),
                      onTap: () {
                        if (e.isDirectory) {
                          _enterDirectory(e);
                        } else {
                          _openBrowserFile(
                            context,
                            controller: widget.controller,
                            workspace: widget.workspace,
                            entry: e,
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBrowserFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
