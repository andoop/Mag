import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/models.dart';
import '../platform/shortcut_bridge.dart';
import '../store/app_controller.dart';
import 'home_page.dart';
import 'i18n.dart';
import 'project_home_page.dart';

/// 对齐 OpenCode：`/` 为项目首页，进入工作区后再显示会话壳（含新建会话落地页与时间线）。
class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  StreamSubscription<WorkspaceWebShortcut>? _shortcutSub;
  bool _handlingShortcut = false;

  @override
  void initState() {
    super.initState();
    _shortcutSub = ShortcutBridge.instance.launches.listen(_handleShortcut);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initial = await ShortcutBridge.instance.takeInitialLaunch();
      if (initial != null) {
        await _handleShortcut(initial);
      }
    });
  }

  @override
  void dispose() {
    _shortcutSub?.cancel();
    super.dispose();
  }

  Future<void> _handleShortcut(WorkspaceWebShortcut shortcut) async {
    if (_handlingShortcut) return;
    _handlingShortcut = true;
    try {
      if (widget.controller.state.workspace?.id != shortcut.workspace.id) {
        await widget.controller.enterWorkspace(shortcut.workspace);
      }
      if (!mounted) return;
      final serverUri = widget.controller.state.serverUri;
      if (serverUri == null) {
        _showShortcutError(l(context, '本地服务未就绪', 'Local server not ready'));
        return;
      }
      final url = _shortcutWorkspacePreviewUrl(
        serverUri: serverUri,
        workspace: shortcut.workspace,
        path: shortcut.path,
      );
      await Navigator.of(context, rootNavigator: true).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _ShortcutWebPreviewPage(
            title: shortcut.title,
            subtitle: shortcut.path,
            url: url.toString(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showShortcutError(
          '${l(context, '打开快捷方式失败', 'Failed to open shortcut')}: $e',
        );
      }
    } finally {
      _handlingShortcut = false;
    }
  }

  void _showShortcutError(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final workspace = widget.controller.state.workspace;
        return WillPopScope(
          onWillPop: () async {
            final s = widget.controller.state;
            if (s.workspace == null) {
              return true;
            }
            // 与 AppBar 左上角返回一致：直接回到项目首页，而非新建会话落地页。
            try {
              await widget.controller.leaveProject();
            } catch (_) {
              // 保留在当前界面，避免误退出
            }
            return false;
          },
          child: workspace == null
              ? ProjectHomePage(controller: widget.controller)
              : HomePage(controller: widget.controller),
        );
      },
    );
  }
}

Uri _shortcutWorkspacePreviewUrl({
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

class _ShortcutWebPreviewPage extends StatefulWidget {
  const _ShortcutWebPreviewPage({
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final String title;
  final String subtitle;
  final String url;

  @override
  State<_ShortcutWebPreviewPage> createState() =>
      _ShortcutWebPreviewPageState();
}

class _ShortcutWebPreviewPageState extends State<_ShortcutWebPreviewPage> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  tooltip: l(context, '关闭', 'Close'),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.45),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.all(10),
                    minimumSize: const Size(44, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.close, size: 22),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
