part of 'app_controller.dart';

class _WorkspaceSearchVariant {
  const _WorkspaceSearchVariant({
    required this.entry,
    required this.variants,
  });

  final WorkspaceEntry entry;
  final List<String> variants;
}

extension AppControllerWorkspace on AppController {
  Future<void> prewarmWorkspaceSearchIndex({
    WorkspaceInfo? workspace,
    bool force = false,
  }) async {
    final target = workspace ?? state.workspace;
    if (target == null) return;
    await _loadWorkspaceSearchIndex(target, force: force);
  }

  void invalidateWorkspaceSearchIndex({
    String? treeUri,
  }) {
    if (treeUri == null || treeUri.isEmpty) {
      _workspaceSearchIndexCache.clear();
      _workspaceSearchIndexInflight.clear();
      return;
    }
    _workspaceSearchIndexCache.remove(treeUri);
    _workspaceSearchIndexInflight.remove(treeUri);
  }

  Future<List<WorkspaceEntry>> searchWorkspaceEntries({
    required String query,
    int limit = 12,
  }) async {
    final workspace = state.workspace;
    if (workspace == null) return const [];
    final normalized = query.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) {
      final rootEntries = await _workspaceBridge.listDirectory(
        treeUri: workspace.treeUri,
        relativePath: '',
        limit: limit * 2,
      );
      return rootEntries.take(limit).toList();
    }
    final entries = await _loadWorkspaceSearchIndex(workspace);
    final variants = entries.map(_workspaceSearchVariant).toList();
    final scored = <MapEntry<WorkspaceEntry, int>>[];
    for (final item in variants) {
      final score = _workspaceFuzzyScore(normalized, item.variants);
      if (score == null) continue;
      scored.add(MapEntry(item.entry, score));
    }
    scored.sort((a, b) {
      final scoreDiff = a.value - b.value;
      if (scoreDiff != 0) return scoreDiff;
      if (a.key.isDirectory != b.key.isDirectory) {
        return a.key.isDirectory ? -1 : 1;
      }
      final nameDiff = a.key.name.length - b.key.name.length;
      if (nameDiff != 0) return nameDiff;
      return a.key.path.compareTo(b.key.path);
    });
    if (scored.length <= limit) {
      return scored.map((item) => item.key).toList();
    }
    return scored.take(limit).map((item) => item.key).toList();
  }

  Future<List<WorkspaceEntry>> _loadWorkspaceSearchIndex(
    WorkspaceInfo workspace, {
    bool force = false,
  }) {
    final treeUri = workspace.treeUri;
    if (force) {
      _workspaceSearchIndexCache.remove(treeUri);
      _workspaceSearchIndexInflight.remove(treeUri);
    }
    final cached = _workspaceSearchIndexCache[treeUri];
    if (cached != null) return Future.value(cached);
    final inflight = _workspaceSearchIndexInflight[treeUri];
    if (inflight != null) return inflight;
    final future = _workspaceBridge
        .searchEntries(
          treeUri: treeUri,
          relativePath: '',
          pattern: '**',
          limit: 50000,
          filesOnly: false,
        )
        .then((entries) {
          entries.sort((a, b) => a.path.compareTo(b.path));
          _workspaceSearchIndexCache[treeUri] = entries;
          _workspaceSearchIndexInflight.remove(treeUri);
          return entries;
        }).catchError((error) {
          _workspaceSearchIndexInflight.remove(treeUri);
          throw error;
        });
    _workspaceSearchIndexInflight[treeUri] = future;
    return future;
  }

  _WorkspaceSearchVariant _workspaceSearchVariant(WorkspaceEntry entry) {
    final path = entry.path.replaceAll('\\', '/');
    final lowerPath = path.toLowerCase();
    final rawBasename = entry.name;
    final basename = rawBasename.toLowerCase();
    final rawBasenameNoExt = entry.isDirectory
        ? rawBasename.replaceAll(RegExp(r'/+$'), '')
        : rawBasename.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final basenameNoExt = rawBasenameNoExt.toLowerCase();
    final tokens = _tokenizeWorkspaceSearchTokens(rawBasenameNoExt);
    final variants = <String>{
      lowerPath,
      basename,
      basenameNoExt,
      lowerPath.replaceAll('/', ''),
    };
    if (tokens.isNotEmpty) {
      variants.add(tokens.join());
      variants.add(tokens.reversed.join());
      for (var i = 0; i < tokens.length; i++) {
        variants.add(tokens[i]);
        for (var j = i + 1; j < tokens.length; j++) {
          final slice = tokens.sublist(i, j + 1);
          variants.add(slice.join());
          variants.add(slice.reversed.join());
        }
      }
    }
    return _WorkspaceSearchVariant(
      entry: entry,
      variants: variants.where((item) => item.isNotEmpty).toList(),
    );
  }

  List<String> _tokenizeWorkspaceSearchTokens(String value) {
    final normalized = value
        .replaceAll(RegExp(r'([a-z0-9])([A-Z])'), r'$1 $2')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
        .trim();
    if (normalized.isEmpty) return const [];
    return normalized
        .split(RegExp(r'\s+'))
        .map((item) => item.toLowerCase())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  int? _workspaceFuzzyScore(String query, List<String> variants) {
    final needle = query.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    if (needle.isEmpty) return 0;
    int? best;
    for (final raw in variants) {
      final candidate = raw.toLowerCase();
      final normalizedCandidate = candidate.replaceAll(RegExp(r'[^a-z0-9]+'), '');
      final score = _workspaceVariantScore(needle, candidate, normalizedCandidate);
      if (score == null) continue;
      if (best == null || score < best) best = score;
    }
    return best;
  }

  int? _workspaceVariantScore(
    String needle,
    String rawCandidate,
    String candidate,
  ) {
    if (candidate.isEmpty) return null;
    if (candidate == needle) return 0;
    if (candidate.startsWith(needle)) return 20 + candidate.length - needle.length;
    final containsIndex = candidate.indexOf(needle);
    if (containsIndex >= 0) {
      return 60 + containsIndex * 2 + (candidate.length - needle.length);
    }
    var queryIndex = 0;
    var matched = 0;
    var gaps = 0;
    var start = -1;
    var previousMatch = -1;
    for (var i = 0; i < candidate.length; i++) {
      if (candidate.codeUnitAt(i) != needle.codeUnitAt(queryIndex)) continue;
      if (start < 0) start = i;
      if (previousMatch >= 0) {
        gaps += i - previousMatch - 1;
      }
      previousMatch = i;
      matched++;
      queryIndex++;
      if (queryIndex == needle.length) {
        final compactness = candidate.length - needle.length;
        final tokenBonus = rawCandidate.startsWith(needle) ? -10 : 0;
        return 120 + start * 2 + gaps * 3 + compactness + tokenBonus - matched;
      }
    }
    return null;
  }

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
    final toolName = part.data['tool'] as String? ?? '';
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
    if (toolName == 'write' ||
        toolName == 'edit' ||
        toolName == 'apply_patch' ||
        toolName == 'delete' ||
        toolName == 'rename' ||
        toolName == 'move' ||
        toolName == 'copy' ||
        toolName == 'git') {
      invalidateWorkspaceSearchIndex(treeUri: workspaceTree);
      unawaited(prewarmWorkspaceSearchIndex(force: true));
    }
  }

  String _workspacePreviewKey(String treeUri, String relativePath) =>
      '$treeUri::${relativePath.trim()}';

  void _clearWorkspacePreviewCaches() {
    _workspaceBytesCache.clear();
    _workspaceTextCache.clear();
    _workspaceSearchIndexCache.clear();
    _workspaceSearchIndexInflight.clear();
  }
}
