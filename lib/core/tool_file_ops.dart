part of 'tool_runtime.dart';

Future<ToolExecutionResult> _listTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final relativePath =
      _normalizeWorkspaceRelativePath(args['path'] as String? ?? '');
  final ignore = (args['ignore'] as List?)
          ?.map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList() ??
      const <String>[];
  final searchPath = relativePath.isEmpty ? '.' : relativePath;
  await ctx.updateToolProgress(
    title: searchPath,
    displayOutput: 'Listing $searchPath',
    metadata: {'phase': 'scanning', 'path': searchPath},
  );
  final files = await ctx.bridge.searchEntries(
    treeUri: ctx.workspace.treeUri,
    relativePath: relativePath,
    pattern: '**',
    limit: _kToolResultLimit + 1,
    filesOnly: true,
    ignorePatterns: [..._kDefaultWorkspaceIgnorePatterns, ...ignore],
  );
  final truncated = files.length > _kToolResultLimit;
  final visible = truncated ? files.take(_kToolResultLimit).toList() : files;
  final output = _renderListOutput(
    rootLabel: searchPath,
    basePath: relativePath,
    files: visible,
  );
  return ToolExecutionResult(
    title: searchPath,
    output: output,
    displayOutput:
        'Listed $searchPath · ${visible.length}${truncated ? '+' : ''} files',
    metadata: {
      'count': visible.length,
      'truncated': truncated,
    },
  );
}

Future<ToolExecutionResult> _globTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final pattern = args['pattern'] as String? ?? '*';
  final pathPrefix =
      _normalizeWorkspaceRelativePath(args['path'] as String? ?? '');
  await ctx.updateToolProgress(
    title: pathPrefix.isEmpty ? pattern : pathPrefix,
    displayOutput: 'Searching $pattern',
    metadata: {
      'phase': 'scanning',
      'path': pathPrefix,
      'pattern': pattern,
    },
  );
  final matches = await ctx.bridge.searchEntries(
    treeUri: ctx.workspace.treeUri,
    relativePath: pathPrefix,
    pattern: pattern,
    limit: _kToolResultLimit + 1,
    filesOnly: true,
    ignorePatterns: _kDefaultWorkspaceIgnorePatterns,
  );
  final truncated = matches.length > _kToolResultLimit;
  final visible =
      truncated ? matches.take(_kToolResultLimit).toList() : matches;
  final output = <String>[];
  if (visible.isEmpty) {
    output.add('No files found');
  } else {
    output.addAll(visible.map((item) => item.path));
    if (truncated) {
      output.add('');
      output.add(
        '(Results are truncated: showing first $_kToolResultLimit results. Consider using a more specific path or pattern.)',
      );
    }
  }
  return ToolExecutionResult(
    title: pathPrefix.isEmpty ? '.' : pathPrefix,
    output: output.join('\n'),
    displayOutput:
        'Glob $pattern · ${visible.length}${truncated ? '+' : ''} matches',
    metadata: {
      'count': visible.length,
      'truncated': truncated,
    },
    attachments: [
      {
        'type': 'glob_results',
        'pattern': pattern,
        'pathPrefix': pathPrefix,
        'count': visible.length,
        'truncated': truncated,
        'items': visible
            .take(30)
            .map((item) => {
                  'path': item.path,
                  'name': item.name,
                  'lastModified': item.lastModified,
                  'size': item.size,
                })
            .toList(),
      },
    ],
  );
}

Future<ToolExecutionResult> _grepTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final pattern = args['pattern'] as String? ?? '';
  final pathPrefix =
      _normalizeWorkspaceRelativePath(args['path'] as String? ?? '');
  final includeArg = args['include'] as String?;
  final includeTrimmed = includeArg?.trim();
  final include = (includeTrimmed != null && includeTrimmed.isNotEmpty)
      ? includeTrimmed
      : (args['glob'] as String?)?.trim();
  await ctx.updateToolProgress(
    title: pattern,
    displayOutput: 'Searching $pattern',
    metadata: {
      'phase': 'scanning',
      'pattern': pattern,
      'path': pathPrefix,
      if (include != null && include.isNotEmpty) 'include': include,
    },
  );
  final matches = await ctx.bridge.grepText(
    treeUri: ctx.workspace.treeUri,
    pattern: pattern,
    relativePath: pathPrefix,
    include: include,
    limit: _kToolResultLimit + 1,
    maxLineLength: _kMaxReadLineLength,
    ignorePatterns: _kDefaultWorkspaceIgnorePatterns,
  );
  final truncated = matches.length > _kToolResultLimit;
  final visible =
      truncated ? matches.take(_kToolResultLimit).toList() : matches;
  if (visible.isEmpty) {
    return ToolExecutionResult(
      title: pattern,
      output: 'No files found',
      displayOutput: 'Grep $pattern · 0 matches',
      metadata: {'matches': 0, 'truncated': false},
    );
  }
  final totalLabel =
      truncated ? 'at least ${matches.length}' : '${visible.length}';
  final buffer =
      _formatGrepOutput(visible, totalLabel: totalLabel, truncated: truncated);
  return ToolExecutionResult(
    title: pattern,
    output: buffer,
    displayOutput:
        'Grep $pattern · ${visible.length}${truncated ? '+' : ''} matches',
    metadata: {'count': visible.length, 'truncated': truncated},
    attachments: [
      {
        'type': 'grep_results',
        'pattern': pattern,
        'pathPrefix': pathPrefix,
        'include': include,
        'count': visible.length,
        'truncated': truncated,
        'items': visible,
      },
    ],
  );
}

String _formatStatEntry(WorkspaceEntry entry) {
  final m = DateTime.fromMillisecondsSinceEpoch(entry.lastModified);
  final lines = <String>[
    'path: ${entry.path}',
    'name: ${entry.name}',
    'isDirectory: ${entry.isDirectory}',
    'size: ${entry.size}',
    'lastModified: ${entry.lastModified} (${m.toIso8601String()})',
  ];
  if (entry.mimeType != null && entry.mimeType!.isNotEmpty) {
    lines.add('mimeType: ${entry.mimeType}');
  }
  return lines.join('\n');
}

Future<ToolExecutionResult> _statTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final filePath = _toolFilePathArg(args);
  await ctx.updateToolProgress(
    title: filePath.isEmpty ? ctx.workspace.name : filePath,
    displayOutput: 'Inspecting ${filePath.isEmpty ? '.' : filePath}',
    metadata: {
      'phase': 'inspecting',
      'path': filePath,
      if (filePath.isNotEmpty) 'filePath': filePath,
    },
  );
  WorkspaceEntry? entry;
  if (filePath.isEmpty) {
    entry = await ctx.bridge.getEntry(
      treeUri: ctx.workspace.treeUri,
      relativePath: '',
    );
    entry ??= WorkspaceEntry(
      path: '',
      name: ctx.workspace.name,
      isDirectory: true,
      lastModified: ctx.workspace.createdAt,
      size: 0,
    );
  } else {
    entry = await ctx.bridge.stat(
      treeUri: ctx.workspace.treeUri,
      relativePath: filePath,
    );
  }
  if (entry == null) {
    throw Exception('Not found: ${filePath.isEmpty ? '.' : filePath}');
  }
  final output = _formatStatEntry(entry);
  return ToolExecutionResult(
    title: filePath,
    output: output,
    displayOutput: 'Stat $filePath',
    metadata: {
      'path': entry.path,
      'isDirectory': entry.isDirectory,
      'size': entry.size,
      'lastModified': entry.lastModified,
      'mimeType': entry.mimeType,
    },
  );
}

Future<ToolExecutionResult> _deleteTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final filePath = _toolFilePathArg(args);
  if (filePath.isEmpty) {
    throw Exception('Missing required `path`.');
  }
  final existing = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  if (existing == null) {
    throw Exception('Not found: $filePath');
  }
  await ctx.updateToolProgress(
    title: filePath,
    displayOutput: 'Preparing delete for $filePath',
    metadata: {'phase': 'preparing', 'path': filePath, 'filePath': filePath},
  );
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'edit',
      patterns: [filePath],
      metadata: {
        'tool': 'delete',
        'path': filePath,
        'filePath': filePath,
        'preview': {
          'kind': 'delete',
          'path': filePath,
          'isDirectory': existing.isDirectory,
        },
      },
      always: [filePath],
      messageId: ctx.message.id,
      callId: newId('call'),
    ),
  );
  await ctx.bridge.deleteEntry(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  final targetKind = existing.isDirectory ? 'directory' : 'file';
  return ToolExecutionResult(
    title: filePath,
    output: 'Deleted $targetKind `$filePath` successfully.',
    displayOutput: 'Deleted $targetKind $filePath',
    metadata: {'path': filePath, 'isDirectory': existing.isDirectory},
  );
}

Future<ToolExecutionResult> _renameTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final filePath = _toolFilePathArg(args);
  final newName = (args['newName'] as String? ?? '').trim();
  if (filePath.isEmpty || newName.isEmpty) {
    throw Exception('Missing required `path` or `newName`.');
  }
  if (newName.contains('/') || newName.contains('\\')) {
    throw Exception(
        '`newName` must be a single segment (no slashes). Use `move` for paths.');
  }
  final existing = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  if (existing == null) {
    throw Exception('Not found: $filePath');
  }
  final parent = _parentPath(filePath);
  final newPath = parent.isEmpty ? newName : '$parent/$newName';
  final preview = _buildDiffAttachment(
    kind: 'rename',
    path: newPath,
    before: filePath,
    after: newPath,
  );
  await ctx.updateToolProgress(
    title: newPath,
    displayOutput: 'Preparing rename $filePath → $newPath',
    metadata: {
      'phase': 'preparing',
      'path': filePath,
      'filePath': filePath,
      'newPath': newPath
    },
    attachments: [preview],
  );
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'edit',
      patterns: [filePath, newPath],
      metadata: {
        'tool': 'rename',
        'path': filePath,
        'filePath': filePath,
        'newPath': newPath,
        'preview': preview,
      },
      always: [filePath],
      messageId: ctx.message.id,
      callId: newId('call'),
    ),
  );
  final entry = await ctx.bridge.renameEntry(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
    newName: newName,
  );
  final targetKind = existing.isDirectory ? 'directory' : 'file';
  return ToolExecutionResult(
    title: newPath,
    output:
        'Renamed $targetKind `$filePath` to `$newPath`.\n\n${_formatStatEntry(entry)}',
    displayOutput: 'Renamed $targetKind $filePath → $newPath',
    metadata: {
      'path': entry.path,
      'from': filePath,
      'isDirectory': existing.isDirectory
    },
  );
}

Future<ToolExecutionResult> _moveTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final fromPath =
      _normalizeWorkspaceRelativePath(args['fromPath'] as String? ?? '');
  final toPath =
      _normalizeWorkspaceRelativePath(args['toPath'] as String? ?? '');
  if (fromPath.isEmpty || toPath.isEmpty) {
    throw Exception('Missing required `fromPath` or `toPath`.');
  }
  final existing = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: fromPath,
  );
  if (existing == null) {
    throw Exception('Not found: $fromPath');
  }
  final preview = _buildDiffAttachment(
    kind: 'move',
    path: toPath,
    before: fromPath,
    after: toPath,
  );
  await ctx.updateToolProgress(
    title: toPath,
    displayOutput: 'Preparing move $fromPath → $toPath',
    metadata: {
      'phase': 'preparing',
      'path': fromPath,
      'filePath': fromPath,
      'newPath': toPath
    },
    attachments: [preview],
  );
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'edit',
      patterns: [fromPath, toPath],
      metadata: {
        'tool': 'move',
        'path': fromPath,
        'filePath': fromPath,
        'newPath': toPath,
        'preview': preview,
      },
      always: [fromPath, toPath],
      messageId: ctx.message.id,
      callId: newId('call'),
    ),
  );
  final entry = await ctx.bridge.moveEntry(
    treeUri: ctx.workspace.treeUri,
    fromPath: fromPath,
    toPath: toPath,
  );
  final targetKind = existing.isDirectory ? 'directory' : 'file';
  return ToolExecutionResult(
    title: toPath,
    output:
        'Moved $targetKind `$fromPath` to `$toPath`.\n\n${_formatStatEntry(entry)}',
    displayOutput: 'Moved $targetKind $fromPath → $toPath',
    metadata: {
      'path': entry.path,
      'from': fromPath,
      'isDirectory': existing.isDirectory
    },
  );
}

Future<ToolExecutionResult> _copyTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final fromPath =
      _normalizeWorkspaceRelativePath(args['fromPath'] as String? ?? '');
  final toPath =
      _normalizeWorkspaceRelativePath(args['toPath'] as String? ?? '');
  if (fromPath.isEmpty || toPath.isEmpty) {
    throw Exception('Missing required `fromPath` or `toPath`.');
  }
  final existing = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: fromPath,
  );
  if (existing == null) {
    throw Exception('Not found: $fromPath');
  }
  final preview = _buildDiffAttachment(
    kind: 'copy',
    path: toPath,
    before: fromPath,
    after: toPath,
  );
  await ctx.updateToolProgress(
    title: toPath,
    displayOutput: 'Preparing copy $fromPath → $toPath',
    metadata: {
      'phase': 'preparing',
      'path': fromPath,
      'filePath': fromPath,
      'newPath': toPath
    },
    attachments: [preview],
  );
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'edit',
      patterns: [fromPath, toPath],
      metadata: {
        'tool': 'copy',
        'path': fromPath,
        'filePath': fromPath,
        'newPath': toPath,
        'preview': preview,
      },
      always: [toPath],
      messageId: ctx.message.id,
      callId: newId('call'),
    ),
  );
  final entry = await ctx.bridge.copyEntry(
    treeUri: ctx.workspace.treeUri,
    fromPath: fromPath,
    toPath: toPath,
  );
  final targetKind = existing.isDirectory ? 'directory' : 'file';
  return ToolExecutionResult(
    title: toPath,
    output:
        'Copied $targetKind `$fromPath` to `$toPath`.\n\n${_formatStatEntry(entry)}',
    displayOutput: 'Copied $targetKind $fromPath → $toPath',
    metadata: {
      'path': entry.path,
      'from': fromPath,
      'isDirectory': existing.isDirectory
    },
  );
}
