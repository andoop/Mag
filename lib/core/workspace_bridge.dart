import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

const List<String> _kDefaultWorkspaceIgnorePatterns = [
  '.git/',
  'node_modules/',
  '.dart_tool/',
  'build/',
  'dist/',
  '.idea/',
  '.vscode/',
  '.gradle/',
  '.next/',
  '.turbo/',
  'coverage/',
  '.cache/',
];

class WorkspaceBridge {
  WorkspaceBridge._();

  static const MethodChannel _channel = MethodChannel('mobile_agent/workspace');
  static final WorkspaceBridge instance = WorkspaceBridge._();
  static const String _sandboxProjectsDirName = 'projects';

  final Map<String, List<WorkspaceEntry>> _directoryCache = {};
  final Map<String, Future<List<WorkspaceEntry>>> _directoryInflight = {};
  String? _sandboxRootPath;

  Future<WorkspaceInfo?> pickWorkspace() async {
    final raw =
        await _channel.invokeMapMethod<String, dynamic>('pickWorkspace');
    if (raw == null) return null;
    return WorkspaceInfo(
      id: newId('workspace'),
      name: (raw['displayName'] as String?) ?? 'Workspace',
      treeUri: raw['treeUri'] as String,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<String> getSandboxRootPath() async {
    final cached = _sandboxRootPath;
    if (cached != null && cached.isNotEmpty) {
      await Directory(cached).create(recursive: true);
      return cached;
    }
    final Directory baseDir;
    if (Platform.isAndroid) {
      baseDir =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      // iOS does not expose an "external storage" concept; keep projects in
      // the app sandbox where they remain writable and backed up correctly.
      baseDir = await getApplicationSupportDirectory();
    }
    final root = p.join(baseDir.path, _sandboxProjectsDirName);
    await Directory(root).create(recursive: true);
    _sandboxRootPath = root;
    return root;
  }

  Future<List<WorkspaceInfo>> listSandboxProjects() async {
    final root = Directory(await getSandboxRootPath());
    final projects = <WorkspaceInfo>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final stat = await entity.stat();
      projects.add(
        _workspaceInfoForPath(
          entity.path,
          name: p.basename(entity.path),
          createdAt: stat.changed.millisecondsSinceEpoch,
        ),
      );
    }
    projects.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return projects;
  }

  Future<WorkspaceInfo> createSandboxProject({
    required String name,
  }) async {
    final root = await getSandboxRootPath();
    final safeBase = _sanitizeProjectName(name);
    var candidate = safeBase;
    var suffix = 2;
    while (await Directory(p.join(root, candidate)).exists()) {
      candidate = '$safeBase $suffix';
      suffix++;
    }
    final dir = Directory(p.join(root, candidate));
    await dir.create(recursive: true);
    return _workspaceInfoForPath(
      dir.path,
      name: candidate,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<WorkspaceInfo> renameSandboxProject({
    required WorkspaceInfo workspace,
    required String newName,
  }) async {
    final root = await getSandboxRootPath();
    final currentPath = _treeUriToPath(workspace.treeUri);
    if (currentPath == null) {
      throw Exception('Unsupported workspace path: ${workspace.treeUri}');
    }
    final normalizedCurrent = p.normalize(currentPath);
    final normalizedRoot = p.normalize(root);
    if (!p.isWithin(normalizedRoot, normalizedCurrent)) {
      throw Exception('Workspace is outside sandbox: ${workspace.treeUri}');
    }
    final safeName = _sanitizeProjectName(newName);
    final currentName = p.basename(normalizedCurrent);
    if (safeName == currentName) {
      return WorkspaceInfo(
        id: workspace.id,
        name: currentName,
        treeUri: normalizedCurrent,
        createdAt: workspace.createdAt,
      );
    }
    final targetPath = p.join(normalizedRoot, safeName);
    if (await Directory(targetPath).exists()) {
      throw Exception('Project already exists: $safeName');
    }
    final renamed = await Directory(normalizedCurrent).rename(targetPath);
    invalidateCaches(treeUri: normalizedCurrent);
    invalidateCaches(treeUri: renamed.path);
    return _workspaceInfoForPath(
      renamed.path,
      name: p.basename(renamed.path),
      createdAt: workspace.createdAt,
    );
  }

  Future<void> deleteSandboxProject(WorkspaceInfo workspace) async {
    final root = await getSandboxRootPath();
    final currentPath = _treeUriToPath(workspace.treeUri);
    if (currentPath == null) {
      throw Exception('Unsupported workspace path: ${workspace.treeUri}');
    }
    final normalizedCurrent = p.normalize(currentPath);
    final normalizedRoot = p.normalize(root);
    if (!p.isWithin(normalizedRoot, normalizedCurrent)) {
      throw Exception('Workspace is outside sandbox: ${workspace.treeUri}');
    }
    final dir = Directory(normalizedCurrent);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    invalidateCaches(treeUri: normalizedCurrent);
  }

  bool isSandboxWorkspace(String treeUri) {
    final root = _sandboxRootPath;
    final path = _treeUriToPath(treeUri);
    if (root == null || path == null) {
      return false;
    }
    final normalizedRoot = p.normalize(root);
    final normalizedPath = p.normalize(path);
    return normalizedPath == normalizedRoot ||
        p.isWithin(normalizedRoot, normalizedPath);
  }

  Future<List<WorkspaceEntry>> listDirectory({
    required String treeUri,
    String relativePath = '',
    int? offset,
    int? limit,
    bool force = false,
  }) async {
    final normalizedPath = _normalizeCachePath(relativePath);
    final cacheKey = '$treeUri::$normalizedPath';
    if (!force && offset == null && limit == null) {
      final cached = _directoryCache[cacheKey];
      if (cached != null) {
        return cached;
      }
      final inflight = _directoryInflight[cacheKey];
      if (inflight != null) {
        return inflight;
      }
    }

    Future<List<WorkspaceEntry>> run() async {
      try {
        final localRoot = _treeUriToPath(treeUri);
        if (localRoot != null) {
          final dir = Directory(_resolveLocalPath(localRoot, normalizedPath));
          if (!await dir.exists()) {
            return const [];
          }
          final entries = <WorkspaceEntry>[];
          await for (final entity in dir.list(followLinks: false)) {
            entries.add(await _workspaceEntryForEntity(entity, localRoot));
          }
          entries.sort((a, b) {
            if (a.isDirectory != b.isDirectory) {
              return a.isDirectory ? -1 : 1;
            }
            return a.path.toLowerCase().compareTo(b.path.toLowerCase());
          });
          final start = ((offset ?? 1) - 1).clamp(0, entries.length);
          final end = limit == null || limit <= 0
              ? entries.length
              : (start + limit).clamp(0, entries.length);
          final result = entries.sublist(start, end);
          if (offset == null && limit == null) {
            _directoryCache[cacheKey] = result;
          }
          return result;
        }

        final raw = await _channel.invokeListMethod<dynamic>(
          'listDirectory',
          {
            'treeUri': treeUri,
            'relativePath': normalizedPath,
            if (offset != null) 'offset': offset,
            if (limit != null) 'limit': limit,
          },
        );
        if (raw == null) return const [];
        final result = raw
            .map((item) =>
                WorkspaceEntry.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        if (offset == null && limit == null) {
          _directoryCache[cacheKey] = result;
        }
        return result;
      } finally {
        _directoryInflight.remove(cacheKey);
      }
    }

    final future = run();
    if (!force && offset == null && limit == null) {
      _directoryInflight[cacheKey] = future;
    }
    return future;
  }

  Future<WorkspaceEntry?> stat({
    required String treeUri,
    required String relativePath,
  }) =>
      getEntry(treeUri: treeUri, relativePath: relativePath);

  Future<WorkspaceEntry?> getEntry({
    required String treeUri,
    required String relativePath,
  }) async {
    final normalizedPath = _normalizeCachePath(relativePath);
    final localRoot = _treeUriToPath(treeUri);
    if (localRoot != null) {
      final targetPath = _resolveLocalPath(localRoot, normalizedPath);
      final type = await FileSystemEntity.type(targetPath, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return null;
      }
      if (normalizedPath.isEmpty) {
        return await _workspaceEntryForEntity(Directory(localRoot), localRoot);
      }
      final entity = type == FileSystemEntityType.directory
          ? Directory(targetPath)
          : File(targetPath);
      return _workspaceEntryForEntity(entity, localRoot);
    }

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getEntry',
        {
          'treeUri': treeUri,
          'relativePath': normalizedPath,
        },
      );
      if (raw == null) return null;
      return WorkspaceEntry.fromJson(raw);
    } on PlatformException catch (error) {
      if (error.code == 'not_found') {
        return null;
      }
      rethrow;
    }
  }

  Future<List<WorkspaceEntry>> searchEntries({
    required String treeUri,
    String relativePath = '',
    String pattern = '*',
    int limit = 100,
    bool filesOnly = true,
    List<String> ignorePatterns = _kDefaultWorkspaceIgnorePatterns,
  }) async {
    final normalizedPath = _normalizeCachePath(relativePath);
    final localRoot = _treeUriToPath(treeUri);
    if (localRoot != null) {
      final dir = Directory(_resolveLocalPath(localRoot, normalizedPath));
      if (!await dir.exists()) {
        return const [];
      }
      final output = <WorkspaceEntry>[];
      await _searchLocalEntries(
        rootPath: normalizedPath,
        currentPath: normalizedPath,
        rootDir: dir,
        localRoot: localRoot,
        globRegex: _globToRegex(pattern),
        filesOnly: filesOnly,
        limit: limit,
        ignorePatterns: ignorePatterns,
        output: output,
      );
      output.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      return output;
    }

    final raw = await _channel.invokeListMethod<dynamic>(
      'searchEntries',
      {
        'treeUri': treeUri,
        'relativePath': normalizedPath,
        'pattern': pattern,
        'limit': limit,
        'filesOnly': filesOnly,
        'ignorePatterns': ignorePatterns,
      },
    );
    if (raw == null) return const [];
    return raw
        .map((item) =>
            WorkspaceEntry.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<JsonMap>> grepText({
    required String treeUri,
    required String pattern,
    String relativePath = '',
    String? include,
    int limit = 100,
    int maxLineLength = 2000,
    List<String> ignorePatterns = _kDefaultWorkspaceIgnorePatterns,
  }) async {
    final normalizedPath = _normalizeCachePath(relativePath);
    final localRoot = _treeUriToPath(treeUri);
    if (localRoot != null) {
      final dir = Directory(_resolveLocalPath(localRoot, normalizedPath));
      if (!await dir.exists()) {
        return const [];
      }
      final output = <JsonMap>[];
      await _grepLocalEntries(
        currentPath: normalizedPath,
        rootDir: dir,
        regex: RegExp(pattern),
        includeRegex:
            include == null || include.isEmpty ? null : _globToRegex(include),
        limit: limit,
        maxLineLength: maxLineLength,
        ignorePatterns: ignorePatterns,
        output: output,
      );
      return output;
    }

    final raw = await _channel.invokeListMethod<dynamic>(
      'grepText',
      {
        'treeUri': treeUri,
        'pattern': pattern,
        'relativePath': normalizedPath,
        if (include != null && include.isNotEmpty) 'include': include,
        'limit': limit,
        'maxLineLength': maxLineLength,
        'ignorePatterns': ignorePatterns,
      },
    );
    if (raw == null) return const [];
    return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<String> readText({
    required String treeUri,
    required String relativePath,
  }) async {
    final localRoot = _treeUriToPath(treeUri);
    if (localRoot != null) {
      final file = File(_resolveLocalPath(localRoot, relativePath));
      if (!await file.exists()) {
        return '';
      }
      return file.readAsString();
    }

    try {
      final raw = await _channel.invokeMethod<String>(
        'readText',
        {
          'treeUri': treeUri,
          'relativePath': _normalizeCachePath(relativePath),
        },
      );
      return raw ?? '';
    } on PlatformException catch (error) {
      if (error.code == 'not_file' || error.code == 'not_found') {
        return '';
      }
      rethrow;
    }
  }

  Future<Uint8List> readBytes({
    required String treeUri,
    required String relativePath,
  }) async {
    final localRoot = _treeUriToPath(treeUri);
    if (localRoot != null) {
      final file = File(_resolveLocalPath(localRoot, relativePath));
      if (!await file.exists()) {
        return Uint8List(0);
      }
      return file.readAsBytes();
    }

    final raw = await _channel.invokeMethod<Uint8List>(
      'readBytes',
      {
        'treeUri': treeUri,
        'relativePath': _normalizeCachePath(relativePath),
      },
    );
    return raw ?? Uint8List(0);
  }

  Future<void> writeText({
    required String treeUri,
    required String relativePath,
    required String content,
  }) async {
    final normalizedPath = _normalizeCachePath(relativePath);
    final localRoot = _treeUriToPath(treeUri);
    if (localRoot != null) {
      final file = File(_resolveLocalPath(localRoot, normalizedPath));
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      invalidateCaches(treeUri: treeUri, relativePath: normalizedPath);
      return;
    }

    await _channel.invokeMethod<void>(
      'writeText',
      {
        'treeUri': treeUri,
        'relativePath': normalizedPath,
        'content': content,
      },
    );
    invalidateCaches(treeUri: treeUri, relativePath: normalizedPath);
  }

  Future<void> deleteEntry({
    required String treeUri,
    required String relativePath,
  }) async {
    final normalizedPath = _normalizeCachePath(relativePath);
    final localRoot = _treeUriToPath(treeUri);
    if (localRoot != null) {
      final targetPath = _resolveLocalPath(localRoot, normalizedPath);
      final type = await FileSystemEntity.type(targetPath, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await Directory(targetPath).delete(recursive: true);
      } else if (type == FileSystemEntityType.file) {
        await File(targetPath).delete();
      }
      invalidateCaches(treeUri: treeUri, relativePath: normalizedPath);
      return;
    }

    await _channel.invokeMethod<void>(
      'deleteEntry',
      {
        'treeUri': treeUri,
        'relativePath': normalizedPath,
      },
    );
    invalidateCaches(treeUri: treeUri, relativePath: normalizedPath);
  }

  Future<WorkspaceEntry> renameEntry({
    required String treeUri,
    required String relativePath,
    required String newName,
  }) async {
    final normalizedPath = _normalizeCachePath(relativePath);
    final localRoot = _treeUriToPath(treeUri);
    if (localRoot != null) {
      final sourcePath = _resolveLocalPath(localRoot, normalizedPath);
      final type = await FileSystemEntity.type(sourcePath, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        throw Exception('Entry not found: $relativePath');
      }
      final targetPath = p.join(p.dirname(sourcePath), newName.trim());
      if (await FileSystemEntity.type(targetPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw Exception('Destination already exists: $newName');
      }
      final entity = type == FileSystemEntityType.directory
          ? await Directory(sourcePath).rename(targetPath)
          : await File(sourcePath).rename(targetPath);
      final newPath = p.relative(entity.path, from: localRoot).replaceAll('\\', '/');
      invalidateCaches(treeUri: treeUri, relativePath: normalizedPath);
      invalidateCaches(treeUri: treeUri, relativePath: newPath);
      return _workspaceEntryForEntity(entity, localRoot);
    }

    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'renameEntry',
      {
        'treeUri': treeUri,
        'relativePath': normalizedPath,
        'newName': newName.trim(),
      },
    );
    if (raw == null) {
      throw Exception('renameEntry returned null');
    }
    final newPath = raw['path'] as String? ?? '';
    invalidateCaches(treeUri: treeUri, relativePath: normalizedPath);
    if (newPath.isNotEmpty && newPath != normalizedPath) {
      invalidateCaches(treeUri: treeUri, relativePath: newPath);
    }
    return WorkspaceEntry.fromJson(raw);
  }

  Future<WorkspaceEntry> moveEntry({
    required String treeUri,
    required String fromPath,
    required String toPath,
  }) async {
    final from = _normalizeCachePath(fromPath);
    final to = _normalizeCachePath(toPath);
    final localRoot = _treeUriToPath(treeUri);
    if (localRoot != null) {
      final sourcePath = _resolveLocalPath(localRoot, from);
      final destPath = _resolveLocalPath(localRoot, to);
      if (await FileSystemEntity.type(destPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw Exception('Destination already exists: $to');
      }
      await Directory(p.dirname(destPath)).create(recursive: true);
      final type = await FileSystemEntity.type(sourcePath, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        throw Exception('Source not found: $from');
      }
      final entity = type == FileSystemEntityType.directory
          ? await Directory(sourcePath).rename(destPath)
          : await File(sourcePath).rename(destPath);
      invalidateCaches(treeUri: treeUri, relativePath: from);
      invalidateCaches(treeUri: treeUri, relativePath: to);
      return _workspaceEntryForEntity(entity, localRoot);
    }

    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'moveEntry',
      {
        'treeUri': treeUri,
        'fromPath': from,
        'toPath': to,
      },
    );
    if (raw == null) {
      throw Exception('moveEntry returned null');
    }
    invalidateCaches(treeUri: treeUri, relativePath: from);
    invalidateCaches(treeUri: treeUri, relativePath: to);
    return WorkspaceEntry.fromJson(raw);
  }

  Future<WorkspaceEntry> copyEntry({
    required String treeUri,
    required String fromPath,
    required String toPath,
  }) async {
    final from = _normalizeCachePath(fromPath);
    final to = _normalizeCachePath(toPath);
    final localRoot = _treeUriToPath(treeUri);
    if (localRoot != null) {
      final sourcePath = _resolveLocalPath(localRoot, from);
      final destPath = _resolveLocalPath(localRoot, to);
      if (await FileSystemEntity.type(destPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw Exception('Destination already exists: $to');
      }
      final entity = await _copyLocalEntity(sourcePath, destPath);
      invalidateCaches(treeUri: treeUri, relativePath: from);
      invalidateCaches(treeUri: treeUri, relativePath: to);
      return _workspaceEntryForEntity(entity, localRoot);
    }

    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'copyEntry',
      {
        'treeUri': treeUri,
        'fromPath': from,
        'toPath': to,
      },
    );
    if (raw == null) {
      throw Exception('copyEntry returned null');
    }
    invalidateCaches(treeUri: treeUri, relativePath: from);
    invalidateCaches(treeUri: treeUri, relativePath: to);
    return WorkspaceEntry.fromJson(raw);
  }

  Future<String?> resolveFilesystemPath({required String treeUri}) async {
    final localPath = _treeUriToPath(treeUri);
    if (localPath != null) {
      return localPath;
    }
    try {
      final raw = await _channel.invokeMethod<String>(
        'resolveFilesystemPath',
        {'treeUri': treeUri},
      );
      return raw;
    } on MissingPluginException {
      return _treeUriToPath(treeUri);
    } on PlatformException {
      return _treeUriToPath(treeUri);
    }
  }

  static String? _treeUriToPath(String treeUri) {
    if (treeUri.startsWith('/')) {
      return treeUri;
    }
    final uri = Uri.tryParse(treeUri);
    if (uri != null && uri.scheme == 'file') {
      return uri.toFilePath();
    }
    return null;
  }

  void invalidateCaches({required String treeUri, String? relativePath}) {
    final normalized =
        relativePath == null ? null : _normalizeCachePath(relativePath);
    final keys = _directoryCache.keys.where((key) {
      if (!key.startsWith('$treeUri::')) return false;
      if (normalized == null || normalized.isEmpty) return true;
      final cachedPath = key.substring('$treeUri::'.length);
      return cachedPath == normalized ||
          cachedPath == _parentDirectoryPath(normalized) ||
          cachedPath.startsWith('$normalized/');
    }).toList();
    for (final key in keys) {
      _directoryCache.remove(key);
      _directoryInflight.remove(key);
    }
  }

  WorkspaceInfo _workspaceInfoForPath(
    String path, {
    required String name,
    required int createdAt,
  }) {
    final normalized = p.normalize(path);
    final digest = sha1.convert(utf8.encode(normalized)).toString();
    return WorkspaceInfo(
      id: 'workspace_${digest.substring(0, 12)}',
      name: name,
      treeUri: normalized,
      createdAt: createdAt,
    );
  }

  String _sanitizeProjectName(String input) {
    final fallback = input.trim().isEmpty ? 'Project' : input.trim();
    final cleaned = fallback
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'Project' : cleaned;
  }

  String _resolveLocalPath(String rootPath, String relativePath) {
    final normalizedRoot = p.normalize(rootPath);
    final normalizedRelative = _normalizeCachePath(relativePath);
    final resolved = normalizedRelative.isEmpty
        ? normalizedRoot
        : p.normalize(p.join(normalizedRoot, normalizedRelative));
    if (resolved != normalizedRoot && !p.isWithin(normalizedRoot, resolved)) {
      throw Exception('Path escapes workspace: $relativePath');
    }
    return resolved;
  }

  Future<WorkspaceEntry> _workspaceEntryForEntity(
    FileSystemEntity entity,
    String localRoot,
  ) async {
    final stat = await entity.stat();
    final isDirectory = entity is Directory;
    final relative = p.relative(entity.path, from: localRoot).replaceAll('\\', '/');
    return WorkspaceEntry(
      path: relative == '.' ? '' : relative,
      name: p.basename(entity.path),
      isDirectory: isDirectory,
      lastModified: stat.modified.millisecondsSinceEpoch,
      size: isDirectory ? 0 : stat.size,
      mimeType: _mimeTypeForPath(entity.path, isDirectory),
    );
  }

  String? _mimeTypeForPath(String path, bool isDirectory) {
    if (isDirectory) return null;
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    return 'text/plain';
  }

  Future<void> _searchLocalEntries({
    required String rootPath,
    required String currentPath,
    required Directory rootDir,
    required String localRoot,
    required RegExp globRegex,
    required bool filesOnly,
    required int limit,
    required List<String> ignorePatterns,
    required List<WorkspaceEntry> output,
  }) async {
    if (output.length >= limit) {
      return;
    }
    final children = await rootDir.list(followLinks: false).toList()
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    for (final child in children) {
      if (output.length >= limit) {
        return;
      }
      final childPath = currentPath.isEmpty
          ? p.basename(child.path)
          : '$currentPath/${p.basename(child.path)}';
      final isDirectory = child is Directory;
      if (_shouldIgnore(childPath, isDirectory, ignorePatterns)) {
        continue;
      }
      final relativeToRoot = rootPath.isEmpty
          ? childPath
          : childPath.startsWith('$rootPath/')
              ? childPath.substring(rootPath.length + 1)
              : p.basename(child.path);
      if ((!filesOnly || !isDirectory) && globRegex.hasMatch(relativeToRoot)) {
        output.add(await _workspaceEntryForEntity(child, localRoot));
      }
      if (isDirectory) {
        await _searchLocalEntries(
          rootPath: rootPath,
          currentPath: childPath,
          rootDir: child,
          localRoot: localRoot,
          globRegex: globRegex,
          filesOnly: filesOnly,
          limit: limit,
          ignorePatterns: ignorePatterns,
          output: output,
        );
      }
    }
  }

  Future<void> _grepLocalEntries({
    required String currentPath,
    required Directory rootDir,
    required RegExp regex,
    required RegExp? includeRegex,
    required int limit,
    required int maxLineLength,
    required List<String> ignorePatterns,
    required List<JsonMap> output,
  }) async {
    if (output.length >= limit) {
      return;
    }
    final children = await rootDir.list(followLinks: false).toList()
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
    for (final child in children) {
      if (output.length >= limit) {
        return;
      }
      final childPath = currentPath.isEmpty
          ? p.basename(child.path)
          : '$currentPath/${p.basename(child.path)}';
      final isDirectory = child is Directory;
      if (_shouldIgnore(childPath, isDirectory, ignorePatterns)) {
        continue;
      }
      if (isDirectory) {
        await _grepLocalEntries(
          currentPath: childPath,
          rootDir: child,
          regex: regex,
          includeRegex: includeRegex,
          limit: limit,
          maxLineLength: maxLineLength,
          ignorePatterns: ignorePatterns,
          output: output,
        );
        continue;
      }
      if (includeRegex != null && !includeRegex.hasMatch(childPath)) {
        continue;
      }
      if (_looksBinaryPath(child.path)) {
        continue;
      }
      final lines = const LineSplitter().convert(await File(child.path).readAsString());
      for (var index = 0; index < lines.length; index++) {
        if (output.length >= limit) {
          return;
        }
        final line = lines[index];
        if (!regex.hasMatch(line)) {
          continue;
        }
        output.add({
          'path': childPath,
          'line': index + 1,
          'text': line.length > maxLineLength
              ? '${line.substring(0, maxLineLength)}...'
              : line,
        });
      }
    }
  }

  bool _looksBinaryPath(String path) {
    final lower = path.toLowerCase();
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
    ];
    return !textExtensions.any((ext) => lower.endsWith(ext));
  }

  bool _shouldIgnore(
    String path,
    bool isDirectory,
    List<String> ignorePatterns,
  ) {
    final normalized = _normalizeCachePath(path);
    for (final pattern in ignorePatterns) {
      final candidate = pattern.trim();
      if (candidate.isEmpty) {
        continue;
      }
      final regex = _globToRegex(candidate);
      if (regex.hasMatch(normalized) || regex.hasMatch('$normalized/')) {
        return true;
      }
      if (candidate.endsWith('/')) {
        final prefix = _normalizeCachePath(candidate.substring(0, candidate.length - 1));
        if (normalized == prefix || normalized.startsWith('$prefix/')) {
          return true;
        }
      }
      if (isDirectory && regex.hasMatch('$normalized/')) {
        return true;
      }
    }
    return false;
  }

  RegExp _globToRegex(String pattern) {
    final normalized = pattern.trim().isEmpty ? '*' : pattern.trim();
    final out = StringBuffer('^');
    var index = 0;
    while (index < normalized.length) {
      final char = normalized[index];
      if (char == '*') {
        final next =
            index + 1 < normalized.length ? normalized[index + 1] : null;
        if (next == '*') {
          out.write('.*');
          index += 2;
        } else {
          out.write('[^/]*');
          index += 1;
        }
        continue;
      }
      if (char == '?') {
        out.write('.');
        index += 1;
        continue;
      }
      if (char == '{') {
        final end = normalized.indexOf('}', index);
        if (end > index) {
          final body = normalized.substring(index + 1, end);
          out.write('(${body.split(',').map(RegExp.escape).join('|')})');
          index = end + 1;
          continue;
        }
      }
      out.write(RegExp.escape(char));
      index += 1;
    }
    out.write(r'$');
    return RegExp(out.toString());
  }

  Future<FileSystemEntity> _copyLocalEntity(String source, String dest) async {
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw Exception('Source not found: $source');
    }
    if (type == FileSystemEntityType.directory) {
      final root = Directory(dest);
      await root.create(recursive: true);
      await for (final entity
          in Directory(source).list(recursive: true, followLinks: false)) {
        final relative = p.relative(entity.path, from: source);
        final target = p.join(dest, relative);
        if (entity is Directory) {
          await Directory(target).create(recursive: true);
        } else if (entity is File) {
          await Directory(p.dirname(target)).create(recursive: true);
          await entity.copy(target);
        }
      }
      return root;
    }
    await Directory(p.dirname(dest)).create(recursive: true);
    return File(source).copy(dest);
  }
}

String _normalizeCachePath(String input) {
  final trimmed = input.trim().replaceAll('\\', '/');
  return trimmed.replaceAll(RegExp(r'^/+|/+$'), '');
}

String _parentDirectoryPath(String input) {
  final normalized = _normalizeCachePath(input);
  if (!normalized.contains('/')) return '';
  return normalized.substring(0, normalized.lastIndexOf('/'));
}
