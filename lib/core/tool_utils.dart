part of 'tool_runtime.dart';

/// Workspace-root-relative path: trims, uses `/`, strips redundant `./`, resolves
/// `.` and `..`. A leading `/` is stripped (still under workspace). Returns `''`
/// for the workspace root. Throws if `..` would escape above the root.
String _normalizeWorkspaceRelativePath(String input) {
  var value = input.trim().replaceAll('\\', '/');
  if (value.isEmpty || value == '.') {
    return '';
  }
  while (value.startsWith('./')) {
    value = value.substring(2);
  }
  if (value.isEmpty || value == '.') {
    return '';
  }
  if (value.startsWith('/')) {
    value = value.substring(1);
  }
  if (value.isEmpty) {
    return '';
  }
  final parts = <String>[];
  for (final rawSeg in value.split('/')) {
    final seg = rawSeg.trim();
    if (seg.isEmpty || seg == '.') {
      continue;
    }
    if (seg == '..') {
      if (parts.isEmpty) {
        throw Exception(
          'Path escapes workspace root (invalid ..): ${_shortPathForError(input)}',
        );
      }
      parts.removeLast();
      continue;
    }
    parts.add(seg);
  }
  return parts.join('/');
}

String _shortPathForError(String s, [int max = 100]) {
  final t = s.trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…';
}

bool _looksBinaryEntry(WorkspaceEntry entry) {
  final mime = entry.mimeType ?? '';
  if (mime.startsWith('text/')) return false;
  if (_isImageMime(mime) || mime == 'application/pdf') return false;
  const textExtensions = [
    '.dart',
    '.kt',
    '.java',
    '.md',
    '.txt',
    '.yaml',
    '.yml',
    '.json',
    '.xml',
    '.gradle',
    '.properties',
    '.js',
    '.ts',
    '.tsx',
    '.jsx',
    '.html',
    '.css',
    '.scss',
    '.sh',
    '.py',
    '.rb',
    '.go',
    '.rs',
  ];
  return !textExtensions.any(
    (ext) => entry.path.toLowerCase().endsWith(ext),
  );
}

bool _isImageMime(String mime) => mime.startsWith('image/');

Future<List<String>> _fileNotFoundSuggestions(
  String filePath,
  ToolRuntimeContext ctx,
) async {
  if (filePath.isEmpty) return const [];
  final parent = _parentPath(filePath);
  final base = filePath.split('/').last.toLowerCase();
  try {
    final siblings = await ctx.bridge.listDirectory(
      treeUri: ctx.workspace.treeUri,
      relativePath: parent,
    );
    return siblings
        .where(
          (item) =>
              item.name.toLowerCase().contains(base) ||
              base.contains(item.name.toLowerCase()),
        )
        .take(3)
        .map((item) => item.path)
        .toList();
  } catch (_) {
    return const [];
  }
}

String _parentPath(String input) {
  if (!input.contains('/')) return '';
  return input.substring(0, input.lastIndexOf('/'));
}

String _renderListOutput({
  required String rootLabel,
  required String basePath,
  required List<WorkspaceEntry> files,
}) {
  final dirs = <String>{'.'};
  final filesByDir = <String, List<String>>{};
  for (final file in files) {
    final relative = basePath.isEmpty
        ? file.path
        : file.path.startsWith('$basePath/')
            ? file.path.substring(basePath.length + 1)
            : file.path;
    final segments =
        relative.split('/').where((item) => item.isNotEmpty).toList();
    if (segments.isEmpty) continue;
    final dirSegments = segments.take(segments.length - 1).toList();
    for (var i = 0; i <= dirSegments.length; i++) {
      final dirPath = i == 0 ? '.' : dirSegments.take(i).join('/');
      dirs.add(dirPath);
    }
    final dir = dirSegments.isEmpty ? '.' : dirSegments.join('/');
    filesByDir.putIfAbsent(dir, () => <String>[]).add(segments.last);
  }

  String renderDir(String dirPath, int depth) {
    final indent = '  ' * depth;
    final childIndent = '  ' * (depth + 1);
    final children = dirs
        .where((item) => item != dirPath && _parentTreePath(item) == dirPath)
        .toList()
      ..sort();
    final buffer = StringBuffer();
    if (depth > 0) {
      buffer.writeln('$indent${dirPath.split('/').last}/');
    }
    for (final child in children) {
      buffer.write(renderDir(child, depth + 1));
    }
    final directFiles = (filesByDir[dirPath] ?? <String>[])..sort();
    for (final file in directFiles) {
      buffer.writeln('$childIndent$file');
    }
    return buffer.toString();
  }

  return '$rootLabel/\n${renderDir('.', 0)}';
}

String _parentTreePath(String path) {
  if (path == '.' || !path.contains('/')) return '.';
  return path.substring(0, path.lastIndexOf('/'));
}

String _formatGrepOutput(
  List<JsonMap> matches, {
  required String totalLabel,
  required bool truncated,
}) {
  final buffer = <String>[
    'Found $totalLabel matches${truncated ? ' (showing first $_kToolResultLimit)' : ''}',
  ];
  var currentFile = '';
  for (final match in matches) {
    final path = match['path'] as String? ?? '';
    if (path != currentFile) {
      if (currentFile.isNotEmpty) {
        buffer.add('');
      }
      currentFile = path;
      buffer.add('$path:');
    }
    buffer.add('  Line ${match['line']}: ${match['text']}');
  }
  if (truncated) {
    buffer.add('');
    buffer.add(
      '(Results truncated: showing first $_kToolResultLimit matches. Consider using a more specific path or pattern.)',
    );
  }
  return buffer.join('\n');
}

Future<String> _resolveBrowserPath(
    String requestedPath, ToolRuntimeContext ctx) async {
  final normalized = _normalizeWorkspaceRelativePath(requestedPath);
  final direct = await ctx.bridge.getEntry(
    treeUri: ctx.workspace.treeUri,
    relativePath: normalized,
  );
  if (direct != null && !direct.isDirectory) {
    if (_isBrowserPagePath(direct.path)) {
      return direct.path;
    }
    throw Exception('Browser only supports HTML files: $normalized');
  }
  try {
    final children = await ctx.bridge.listDirectory(
      treeUri: ctx.workspace.treeUri,
      relativePath: normalized,
    );
    for (final candidate in const ['index.html', 'index.htm']) {
      final expected =
          normalized.isEmpty ? candidate : '$normalized/$candidate';
      final match = children.cast<WorkspaceEntry?>().firstWhere(
            (item) => item?.path == expected,
            orElse: () => null,
          );
      if (match != null && !match.isDirectory) {
        return match.path;
      }
    }
  } catch (_) {}
  throw Exception('Workspace page not found: $normalized');
}

bool _isBrowserPagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.htm');
}

