import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../core/models.dart';

class WorkspaceWebShortcut {
  const WorkspaceWebShortcut({
    required this.workspace,
    required this.path,
    required this.title,
  });

  final WorkspaceInfo workspace;
  final String path;
  final String title;

  Uri get launchUri => Uri(
        scheme: 'mag',
        host: 'workspace-web',
        queryParameters: {
          'workspaceId': workspace.id,
          'workspaceName': workspace.name,
          'workspaceTreeUri': workspace.treeUri,
          'workspaceCreatedAt': workspace.createdAt.toString(),
          'path': path,
          'title': title,
        },
      );

  Map<String, Object?> toJson() => {
        'workspaceId': workspace.id,
        'workspaceName': workspace.name,
        'workspaceTreeUri': workspace.treeUri,
        'workspaceCreatedAt': workspace.createdAt,
        'path': path,
        'title': title,
      };

  static WorkspaceWebShortcut? fromJson(Map<dynamic, dynamic>? raw) {
    if (raw == null) return null;
    final workspaceId = raw['workspaceId'] as String?;
    final workspaceName = raw['workspaceName'] as String?;
    final workspaceTreeUri = raw['workspaceTreeUri'] as String?;
    final path = raw['path'] as String?;
    if (workspaceId == null ||
        workspaceName == null ||
        workspaceTreeUri == null ||
        path == null) {
      return null;
    }
    return WorkspaceWebShortcut(
      workspace: WorkspaceInfo(
        id: workspaceId,
        name: workspaceName,
        treeUri: workspaceTreeUri,
        createdAt: (raw['workspaceCreatedAt'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      path: path,
      title: (raw['title'] as String?)?.trim().isNotEmpty == true
          ? raw['title'] as String
          : path,
    );
  }
}

class ShortcutBridge {
  ShortcutBridge._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static final ShortcutBridge instance = ShortcutBridge._();
  static const MethodChannel _channel = MethodChannel('mobile_agent/shortcuts');

  final StreamController<WorkspaceWebShortcut> _launches =
      StreamController<WorkspaceWebShortcut>.broadcast();

  Stream<WorkspaceWebShortcut> get launches => _launches.stream;

  Future<bool> createWorkspaceWebShortcut(WorkspaceWebShortcut shortcut) async {
    if (!Platform.isAndroid) return false;
    final created = await _channel.invokeMethod<bool>(
      'createWorkspaceWebShortcut',
      shortcut.toJson(),
    );
    return created ?? false;
  }

  Future<WorkspaceWebShortcut?> takeInitialLaunch() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
      'takeInitialWorkspaceWebShortcut',
    );
    return WorkspaceWebShortcut.fromJson(raw);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'workspaceWebShortcutLaunched') return;
    final shortcut = WorkspaceWebShortcut.fromJson(
      call.arguments as Map<dynamic, dynamic>?,
    );
    if (shortcut != null) {
      _launches.add(shortcut);
    }
  }
}
