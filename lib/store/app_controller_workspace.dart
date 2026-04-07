part of 'app_controller.dart';

extension AppControllerWorkspace on AppController {
  Future<Uint8List> loadWorkspaceBytes({
    required String treeUri,
    required String relativePath,
    bool refresh = false,
  }) {
    final key = _workspacePreviewKey(treeUri, relativePath);
    if (refresh) {
      _workspaceBytesCache.remove(key);
    }
    return _workspaceBytesCache.putIfAbsent(key, () async {
      try {
        return await _workspaceBridge.readBytes(
          treeUri: treeUri,
          relativePath: relativePath,
        );
      } catch (_) {
        _workspaceBytesCache.remove(key);
        rethrow;
      }
    });
  }

  Future<String> loadWorkspaceText({
    required String treeUri,
    required String relativePath,
    bool refresh = false,
  }) {
    final key = _workspacePreviewKey(treeUri, relativePath);
    if (refresh) {
      _workspaceTextCache.remove(key);
    }
    return _workspaceTextCache.putIfAbsent(key, () async {
      try {
        return await _workspaceBridge.readText(
          treeUri: treeUri,
          relativePath: relativePath,
        );
      } catch (_) {
        _workspaceTextCache.remove(key);
        rethrow;
      }
    });
  }

  void invalidateWorkspacePreview({
    String? treeUri,
    String? relativePath,
  }) {
    if (treeUri == null) {
      _clearWorkspacePreviewCaches();
      return;
    }
    if (relativePath == null || relativePath.isEmpty) {
      _workspaceBytesCache
          .removeWhere((key, _) => key.startsWith('$treeUri::'));
      _workspaceTextCache.removeWhere((key, _) => key.startsWith('$treeUri::'));
      return;
    }
    final key = _workspacePreviewKey(treeUri, relativePath);
    _workspaceBytesCache.remove(key);
    _workspaceTextCache.remove(key);
  }

  void _invalidatePreviewCacheForPart(MessagePart part) {
    if (part.type != PartType.tool) return;
    final workspaceTree = state.workspace?.treeUri;
    if (workspaceTree == null) return;
    final stateMap = Map<String, dynamic>.from(
      part.data['state'] as Map? ?? const <String, dynamic>{},
    );
    final attachments = (stateMap['attachments'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    for (final attachment in attachments) {
      final path =
          attachment['path'] as String? ?? attachment['sourcePath'] as String?;
      if (path == null || path.isEmpty) continue;
      invalidateWorkspacePreview(treeUri: workspaceTree, relativePath: path);
    }
    final filePath = stateMap['filepath'] as String? ??
        stateMap['path'] as String? ??
        part.data['filePath'] as String?;
    if (filePath != null && filePath.isNotEmpty) {
      invalidateWorkspacePreview(
          treeUri: workspaceTree, relativePath: filePath);
    }
  }

  String _workspacePreviewKey(String treeUri, String relativePath) =>
      '$treeUri::${relativePath.trim()}';

  void _clearWorkspacePreviewCaches() {
    _workspaceBytesCache.clear();
    _workspaceTextCache.clear();
  }
}
