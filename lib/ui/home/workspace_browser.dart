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

void _showWorkspaceHtmlOpenChoice(
  BuildContext context, {
  required AppController controller,
  required WorkspaceInfo workspace,
  required WorkspaceEntry entry,
}) {
  final path = entry.path;
  final filename = entry.name;
  final serverUri = controller.state.serverUri;
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                filename,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading: Icon(Icons.article_outlined, color: ctx.oc.accent),
              title: Text(l(ctx, '应用内预览', 'In-app preview')),
              subtitle: Text(
                l(
                  ctx,
                  '直接加载 HTML（部分相对路径资源可能无法加载）',
                  'Load HTML directly (some relative assets may not load)',
                ),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _openFilePreview(
                  context,
                  controller: controller,
                  workspace: workspace,
                  path: path,
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.dns_outlined, color: ctx.oc.accent),
              title: Text(l(ctx, '本地服务打开', 'Open via local server')),
              subtitle: Text(
                serverUri == null
                    ? l(ctx, '本地服务未就绪', 'Local server not ready')
                    : l(
                        ctx,
                        '与 Browser 工具相同，通过 HTTP 挂载工作区文件',
                        'Same as the Browser tool — workspace files served over HTTP',
                      ),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              enabled: serverUri != null,
              onTap: serverUri == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      final previewUrl = _workspacePreviewUrl(
                        serverUri: serverUri,
                        workspace: workspace,
                        path: path,
                      );
                      _openWebPreview(
                        context,
                        title: filename,
                        subtitle: path,
                        url: previewUrl.toString(),
                      );
                    },
            ),
            ListTile(
              leading: Icon(Icons.link_rounded, color: ctx.oc.accent),
              title: Text(l(ctx, '复制访问地址', 'Copy access URL')),
              subtitle: Text(
                serverUri == null
                    ? l(ctx, '本地服务未就绪', 'Local server not ready')
                    : l(
                        ctx,
                        '复制带真实内网 IP 的 HTTP 地址',
                        'Copy the HTTP URL with the real LAN IP',
                      ),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              enabled: serverUri != null,
              onTap: serverUri == null
                  ? null
                  : () {
                      Navigator.of(ctx).pop();
                      unawaited(_copyWorkspaceEntryAccessUrl(
                        context,
                        controller: controller,
                        workspace: workspace,
                        entry: entry,
                      ));
                    },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

void _openBrowserFile(
  BuildContext context, {
  required AppController controller,
  required WorkspaceInfo workspace,
  required WorkspaceEntry entry,
}) {
  if (entry.isDirectory) return;
  final path = entry.path;
  if (_pathLooksHtmlFile(path)) {
    _showWorkspaceHtmlOpenChoice(
      context,
      controller: controller,
      workspace: workspace,
      entry: entry,
    );
    return;
  }
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

Future<String?> _absolutePathForWorkspaceEntry(
  WorkspaceInfo workspace,
  WorkspaceEntry entry,
) async {
  final root = await WorkspaceBridge.instance.resolveFilesystemPath(
    treeUri: workspace.treeUri,
  );
  if (root == null || root.isEmpty) return null;
  final rel = entry.path.replaceAll('\\', '/').trim();
  if (rel.isEmpty) return p.normalize(root);
  final parts = rel.split('/').where((s) => s.isNotEmpty).toList();
  return p.normalize(p.join(root, p.joinAll(parts)));
}

void _invalidatePreviewAfterDelete(
  AppController controller,
  WorkspaceInfo workspace,
  WorkspaceEntry entry,
) {
  final t = workspace.treeUri;
  if (entry.isDirectory) {
    controller.invalidateWorkspacePreview(treeUri: t, relativePath: '');
  } else {
    controller.invalidateWorkspacePreview(treeUri: t, relativePath: entry.path);
  }
  controller.invalidateWorkspaceSearchIndex(treeUri: t);
}

void _invalidatePreviewAfterRename(
  AppController controller,
  WorkspaceInfo workspace,
  WorkspaceEntry before,
  WorkspaceEntry after,
) {
  final t = workspace.treeUri;
  if (before.isDirectory || after.isDirectory) {
    controller.invalidateWorkspacePreview(treeUri: t, relativePath: '');
  } else {
    controller.invalidateWorkspacePreview(
        treeUri: t, relativePath: before.path);
    controller.invalidateWorkspacePreview(treeUri: t, relativePath: after.path);
  }
  controller.invalidateWorkspaceSearchIndex(treeUri: t);
}

Future<void> _copyWorkspaceEntryRelativePath(
  BuildContext context,
  WorkspaceEntry entry,
) async {
  final copiedLabel = l(context, '相对路径已复制', 'Relative path copied');
  final messenger = ScaffoldMessenger.maybeOf(context);
  await Clipboard.setData(ClipboardData(text: entry.path));
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(copiedLabel)));
}

bool _serverHostNeedsLanAddress(String host) {
  final lower = host.toLowerCase();
  return lower == 'localhost' ||
      lower == '0.0.0.0' ||
      lower == '::' ||
      lower == '::1' ||
      lower.startsWith('127.');
}

bool _isUsableLanIPv4(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length != 4 || address.isLoopback) return false;
  if (bytes[0] == 0 || bytes[0] == 127) return false;
  if (bytes[0] == 169 && bytes[1] == 254) return false;
  return true;
}

bool _isPrivateLanIPv4(InternetAddress address) {
  final bytes = address.rawAddress;
  if (!_isUsableLanIPv4(address)) return false;
  return bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127);
}

Future<InternetAddress?> _findLanIPv4Address() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: InternetAddressType.IPv4,
  );
  final candidates = <InternetAddress>[
    for (final networkInterface in interfaces)
      for (final address in networkInterface.addresses)
        if (_isUsableLanIPv4(address)) address,
  ];
  if (candidates.isEmpty) return null;
  for (final address in candidates) {
    if (_isPrivateLanIPv4(address)) return address;
  }
  return candidates.first;
}

Future<Uri?> _workspaceLanPreviewUrl({
  required Uri serverUri,
  required WorkspaceInfo workspace,
  required String path,
}) async {
  final lanServerUri = _serverHostNeedsLanAddress(serverUri.host)
      ? serverUri.replace(host: (await _findLanIPv4Address())?.address)
      : serverUri;
  if (_serverHostNeedsLanAddress(lanServerUri.host)) return null;
  return _workspacePreviewUrl(
    serverUri: lanServerUri,
    workspace: workspace,
    path: path,
  );
}

Future<void> _copyWorkspaceEntryAccessUrl(
  BuildContext context, {
  required AppController controller,
  required WorkspaceInfo workspace,
  required WorkspaceEntry entry,
}) async {
  final serverUri = controller.state.serverUri;
  final copiedLabel = l(context, '访问地址已复制', 'Access URL copied');
  final serverNotReadyLabel = l(context, '本地服务未就绪', 'Local server not ready');
  final noLanIpLabel = l(context, '未找到可用的内网 IP', 'No usable LAN IP found');
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (serverUri == null) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(serverNotReadyLabel)));
    return;
  }
  final previewUrl = await _workspaceLanPreviewUrl(
    serverUri: serverUri,
    workspace: workspace,
    path: entry.path,
  );
  if (previewUrl == null) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(noLanIpLabel)));
    return;
  }
  await Clipboard.setData(ClipboardData(text: previewUrl.toString()));
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(content: Text(copiedLabel)));
}

Future<void> _shareWorkspaceEntry(
  BuildContext context,
  WorkspaceInfo workspace,
  WorkspaceEntry entry,
) async {
  final fallbackShareText = l(
    context,
    '工作区相对路径:\n${entry.path}',
    'Workspace path:\n${entry.path}',
  );
  final shareFailedPrefix = l(context, '分享失败', 'Share failed');
  final langIsZh =
      Localizations.localeOf(context).languageCode.startsWith('zh');
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final abs = await _absolutePathForWorkspaceEntry(workspace, entry);
    if (abs != null && !entry.isDirectory) {
      final file = File(abs);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(abs)],
          subject: entry.name,
        );
        return;
      }
    }
    if (abs != null && entry.isDirectory) {
      final dir = Directory(abs);
      if (await dir.exists()) {
        final folderText = langIsZh ? '文件夹路径:\n$abs' : 'Folder path:\n$abs';
        await Share.share(
          folderText,
          subject: entry.name,
        );
        return;
      }
    }
    await Share.share(
      fallbackShareText,
      subject: entry.name,
    );
  } catch (e) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text('$shareFailedPrefix: $e')),
    );
  }
}

Future<void> _createWorkspaceWebShortcut(
  BuildContext context,
  WorkspaceInfo workspace,
  WorkspaceEntry entry,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final createdLabel = l(context, '已请求创建桌面快捷方式', 'Shortcut creation requested');
  final iosSharedLabel =
      l(context, '已生成快捷方式链接，请用快捷指令添加到主屏幕', 'Shortcut link created');
  final failedPrefix = l(context, '创建快捷方式失败', 'Failed to create shortcut');
  final unsupportedLabel = l(context, '当前启动器不支持创建快捷方式',
      'The current launcher does not support shortcuts');
  final shortcut = WorkspaceWebShortcut(
    workspace: workspace,
    path: entry.path,
    title: workspace.name,
  );
  try {
    if (Platform.isIOS) {
      await Share.share(
        shortcut.launchUri.toString(),
        subject: workspace.name,
      );
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(SnackBar(content: Text(iosSharedLabel)));
      return;
    }

    final ok =
        await ShortcutBridge.instance.createWorkspaceWebShortcut(shortcut);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          ok ? createdLabel : unsupportedLabel,
        ),
      ),
    );
  } catch (e) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text('$failedPrefix: $e')));
  }
}

Future<void> _promptRenameWorkspaceEntry(
  BuildContext context, {
  required WorkspaceInfo workspace,
  required WorkspaceEntry entry,
  required AppController controller,
  required VoidCallback onChanged,
}) async {
  final textController = TextEditingController(text: entry.name);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final renamedOkLabel = l(context, '已重命名', 'Renamed');
  final renameFailedPrefix = l(context, '重命名失败', 'Rename failed');
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l(ctx, '重命名', 'Rename')),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l(ctx, '新名称', 'New name'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l(ctx, '取消', 'Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l(ctx, '确定', 'OK')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final newName = textController.text.trim();
    if (newName.isEmpty || newName == entry.name) return;
    final updated = await WorkspaceBridge.instance.renameEntry(
      treeUri: workspace.treeUri,
      relativePath: entry.path,
      newName: newName,
    );
    _invalidatePreviewAfterRename(controller, workspace, entry, updated);
    onChanged();
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(renamedOkLabel)));
  } catch (e) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text('$renameFailedPrefix: $e')),
    );
  } finally {
    textController.dispose();
  }
}

Future<void> _confirmDeleteWorkspaceEntry(
  BuildContext context, {
  required WorkspaceInfo workspace,
  required WorkspaceEntry entry,
  required AppController controller,
  required VoidCallback onChanged,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final deletedLabel = l(context, '已删除', 'Deleted');
  final deleteFailedPrefix = l(context, '删除失败', 'Delete failed');
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l(ctx, '删除', 'Delete')),
      content: Text(
        entry.isDirectory
            ? l(
                ctx,
                '确定删除文件夹「${entry.name}」及其中的全部内容？',
                'Delete folder "${entry.name}" and everything inside it?',
              )
            : l(
                ctx,
                '确定删除文件「${entry.name}」？',
                'Delete file "${entry.name}"?',
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l(ctx, '取消', 'Cancel')),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l(ctx, '删除', 'Delete')),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await WorkspaceBridge.instance.deleteEntry(
      treeUri: workspace.treeUri,
      relativePath: entry.path,
    );
    _invalidatePreviewAfterDelete(controller, workspace, entry);
    onChanged();
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(deletedLabel)));
  } catch (e) {
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(content: Text('$deleteFailedPrefix: $e')),
    );
  }
}

void _showWorkspaceEntryMoreMenu(
  BuildContext context, {
  required WorkspaceInfo workspace,
  required AppController controller,
  required WorkspaceEntry entry,
  required VoidCallback onChanged,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                entry.name,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ListTile(
              leading:
                  Icon(Icons.drive_file_rename_outline, color: ctx.oc.accent),
              title: Text(l(ctx, '重命名', 'Rename')),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_promptRenameWorkspaceEntry(
                  context,
                  workspace: workspace,
                  entry: entry,
                  controller: controller,
                  onChanged: onChanged,
                ));
              },
            ),
            ListTile(
              leading: Icon(Icons.share_outlined, color: ctx.oc.accent),
              title: Text(l(ctx, '分享', 'Share')),
              subtitle: Text(
                l(ctx, '文件可分享副本；否则分享路径文本', 'Share a file copy, or path text'),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_shareWorkspaceEntry(context, workspace, entry));
              },
            ),
            if (!entry.isDirectory && _pathLooksHtmlFile(entry.path))
              ListTile(
                leading: Icon(Icons.add_to_home_screen, color: ctx.oc.accent),
                title: Text(l(ctx, '创建桌面快捷方式', 'Create home shortcut')),
                subtitle: Text(
                  l(ctx, '从桌面直接打开该网页预览',
                      'Open this web preview directly from the launcher'),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(
                    _createWorkspaceWebShortcut(context, workspace, entry),
                  );
                },
              ),
            if (!entry.isDirectory && _pathLooksHtmlFile(entry.path))
              ListTile(
                leading: Icon(Icons.link_rounded, color: ctx.oc.accent),
                title: Text(l(ctx, '复制访问地址', 'Copy access URL')),
                subtitle: Text(
                  l(ctx, '复制带真实内网 IP 的 HTTP 地址',
                      'Copy the HTTP URL with the real LAN IP'),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  unawaited(_copyWorkspaceEntryAccessUrl(
                    context,
                    controller: controller,
                    workspace: workspace,
                    entry: entry,
                  ));
                },
              ),
            ListTile(
              leading: Icon(Icons.link, color: ctx.oc.accent),
              title: Text(l(ctx, '复制相对路径', 'Copy relative path')),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_copyWorkspaceEntryRelativePath(context, entry));
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
              title: Text(
                l(ctx, '删除', 'Delete'),
                style: TextStyle(color: Colors.red.shade700),
              ),
              onTap: () {
                Navigator.pop(ctx);
                unawaited(_confirmDeleteWorkspaceEntry(
                  context,
                  workspace: workspace,
                  entry: entry,
                  controller: controller,
                  onChanged: onChanged,
                ));
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
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
          if (snapshot.hasError ||
              !snapshot.hasData ||
              snapshot.data!.isEmpty) {
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
    int byName(WorkspaceEntry a, WorkspaceEntry b) =>
        a.name.toLowerCase().compareTo(b.name.toLowerCase());
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
          if (_relativePath.isNotEmpty) Divider(height: 1, color: oc.border),
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
                            style: TextStyle(fontSize: 12, color: oc.muted),
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
                      trailing: IconButton(
                        tooltip: l(context, '更多', 'More'),
                        icon: Icon(Icons.more_vert_rounded, color: oc.muted),
                        onPressed: () => _showWorkspaceEntryMoreMenu(
                          context,
                          workspace: widget.workspace,
                          controller: widget.controller,
                          entry: e,
                          onChanged: _reload,
                        ),
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
