import 'dart:convert';

import 'package:flutter/services.dart';

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
  final Map<String, List<WorkspaceEntry>> _directoryCache = {};
  final Map<String, Future<List<WorkspaceEntry>>> _directoryInflight = {};

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
        // #region agent log
        _debugLogWorkspaceBridge(
          location: 'workspace_bridge.dart:listDirectory',
          message: 'WorkspaceBridge.listDirectory',
          hypothesisId: 'H11',
          runId: 'listDirectory',
          data: {
            'relativePath': normalizedPath,
            'offset': offset,
            'limit': limit,
            'force': force,
          },
        );
        // #endregion
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
      } catch (error) {
        // #region agent log
        _debugLogWorkspaceBridge(
          location: 'workspace_bridge.dart:listDirectory',
          message: 'WorkspaceBridge.listDirectory error',
          hypothesisId: 'H11',
          runId: 'listDirectory',
          data: {
            'relativePath': normalizedPath,
            'error': error.toString(),
          },
        );
        // #endregion
        rethrow;
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

  /// Metadata for a file or directory (same as [getEntry]; alias for tool naming).
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
    final raw = await _channel.invokeListMethod<dynamic>(
      'searchEntries',
      {
        'treeUri': treeUri,
        'relativePath': _normalizeCachePath(relativePath),
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
    final raw = await _channel.invokeListMethod<dynamic>(
      'grepText',
      {
        'treeUri': treeUri,
        'pattern': pattern,
        'relativePath': _normalizeCachePath(relativePath),
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
    try {
      // #region agent log
      _debugLogWorkspaceBridge(
        location: 'workspace_bridge.dart:73',
        message: 'WorkspaceBridge.readText',
        hypothesisId: 'H11',
        runId: 'readText',
        data: {
          'relativePath': relativePath,
        },
      );
      // #endregion
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
      // #region agent log
      _debugLogWorkspaceBridge(
        location: 'workspace_bridge.dart:88',
        message: 'WorkspaceBridge.readText error',
        hypothesisId: 'H11',
        runId: 'readText',
        data: {
          'relativePath': relativePath,
          'error': error.toString(),
        },
      );
      // #endregion
      rethrow;
    } catch (error) {
      // #region agent log
      _debugLogWorkspaceBridge(
        location: 'workspace_bridge.dart:88',
        message: 'WorkspaceBridge.readText error',
        hypothesisId: 'H11',
        runId: 'readText',
        data: {
          'relativePath': relativePath,
          'error': error.toString(),
        },
      );
      // #endregion
      rethrow;
    }
  }

  Future<Uint8List> readBytes({
    required String treeUri,
    required String relativePath,
  }) async {
    try {
      // #region agent log
      _debugLogWorkspaceBridge(
        location: 'workspace_bridge.dart:100',
        message: 'WorkspaceBridge.readBytes',
        hypothesisId: 'H11',
        runId: 'readBytes',
        data: {
          'relativePath': relativePath,
        },
      );
      // #endregion
      final raw = await _channel.invokeMethod<Uint8List>(
        'readBytes',
        {
          'treeUri': treeUri,
          'relativePath': _normalizeCachePath(relativePath),
        },
      );
      return raw ?? Uint8List(0);
    } catch (error) {
      // #region agent log
      _debugLogWorkspaceBridge(
        location: 'workspace_bridge.dart:115',
        message: 'WorkspaceBridge.readBytes error',
        hypothesisId: 'H11',
        runId: 'readBytes',
        data: {
          'relativePath': relativePath,
          'error': error.toString(),
        },
      );
      // #endregion
      rethrow;
    }
  }

  Future<void> writeText({
    required String treeUri,
    required String relativePath,
    required String content,
  }) async {
    await _channel.invokeMethod<void>(
      'writeText',
      {
        'treeUri': treeUri,
        'relativePath': _normalizeCachePath(relativePath),
        'content': content,
      },
    );
    invalidateCaches(treeUri: treeUri, relativePath: relativePath);
  }

  Future<void> deleteEntry({
    required String treeUri,
    required String relativePath,
  }) async {
    await _channel.invokeMethod<void>(
      'deleteEntry',
      {
        'treeUri': treeUri,
        'relativePath': _normalizeCachePath(relativePath),
      },
    );
    invalidateCaches(treeUri: treeUri, relativePath: relativePath);
  }

  Future<WorkspaceEntry> renameEntry({
    required String treeUri,
    required String relativePath,
    required String newName,
  }) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'renameEntry',
      {
        'treeUri': treeUri,
        'relativePath': _normalizeCachePath(relativePath),
        'newName': newName.trim(),
      },
    );
    if (raw == null) {
      throw Exception('renameEntry returned null');
    }
    final newPath = raw['path'] as String? ?? '';
    invalidateCaches(treeUri: treeUri, relativePath: relativePath);
    if (newPath.isNotEmpty && newPath != _normalizeCachePath(relativePath)) {
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

void _debugLogWorkspaceBridge({
  required String location,
  required String message,
  required String hypothesisId,
  required Map<String, dynamic> data,
  String runId = 'workspace-bridge',
}) {
  final tag = message.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final payload = {
    'sessionId': '0ac6da',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  // #region agent log
  try {
    // ignore: avoid_print
    print('[agent-debug][$hypothesisId][$tag] ${jsonEncode(payload)}');
  } catch (_) {}
  // #endregion
}
