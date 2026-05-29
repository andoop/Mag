part of 'tool_runtime.dart';

const String _kZipToolDescription = '''
Create a .zip archive from `sourcePath` or `sourcePaths`.
''';

const String _kUnzipToolDescription = '''
Extract a .zip archive into `destinationPath` or workspace root.
''';

const int _kArchiveMaxFiles = 1000;
const int _kArchiveMaxUncompressedBytes = 100 * 1024 * 1024;

JsonMap zipToolParametersSchema() => {
      'type': 'object',
      'properties': {
        'sourcePaths': {
          'type': 'array',
          'description': 'Files or directories to include.',
          'items': {'type': 'string'},
        },
        'sourcePath': {
          'type': 'string',
          'description': 'Single file or directory to include.',
        },
        'filePath': {
          'type': 'string',
          'description': 'Destination .zip path.',
        },
        'overwrite': {
          'type': 'boolean',
          'description': 'Replace existing zip.',
        },
      },
      'required': ['filePath'],
      'additionalProperties': false,
    };

JsonMap unzipToolParametersSchema() => {
      'type': 'object',
      'properties': {
        'filePath': {
          'type': 'string',
          'description': 'Source .zip path.',
        },
        'destinationPath': {
          'type': 'string',
          'description': 'Extraction directory.',
        },
        'overwrite': {
          'type': 'boolean',
          'description': 'Replace existing files.',
        },
      },
      'required': ['filePath'],
      'additionalProperties': false,
    };

Future<ToolExecutionResult> _zipTool(
  JsonMap args,
  ToolRuntimeContext ctx,
) async {
  final overwrite = args['overwrite'] == true;
  final destinationPath = _archiveZipOutputPath(
    _strictFilePathArg(args, toolName: 'zip'),
  );
  final sources = _archiveSourcePaths(args);

  final existing = await ctx.bridge.getEntry(
    treeUri: ctx.workspace.treeUri,
    relativePath: destinationPath,
  );
  if (existing != null && existing.isDirectory) {
    throw Exception('Destination path is a directory: $destinationPath');
  }
  if (existing != null && !overwrite) {
    throw Exception(
      'Destination already exists: $destinationPath\n'
      'If you intentionally want to replace it, call `zip` again with '
      '`overwrite: true`.',
    );
  }

  await ctx.updateToolProgress(
    title: destinationPath,
    displayOutput: 'Preparing archive $destinationPath',
    metadata: {
      'phase': 'scanning',
      'path': destinationPath,
      'filePath': destinationPath,
      'sourcePaths': sources,
      'overwrite': overwrite,
    },
  );

  final archive = archive_pkg.Archive();
  final usedNames = <String>{};
  var totalBytes = 0;
  var fileCount = 0;
  final sourceCount = sources.length;

  for (final sourcePath in sources) {
    final entry = await ctx.bridge.getEntry(
      treeUri: ctx.workspace.treeUri,
      relativePath: sourcePath,
    );
    if (entry == null) {
      throw Exception(
          'Source not found: ${sourcePath.isEmpty ? '.' : sourcePath}');
    }
    final files = entry.isDirectory
        ? await ctx.bridge.searchEntries(
            treeUri: ctx.workspace.treeUri,
            relativePath: sourcePath,
            pattern: '**',
            limit: _kArchiveMaxFiles + 1,
            filesOnly: true,
            ignorePatterns: const [],
          )
        : <WorkspaceEntry>[entry];
    if (files.length > _kArchiveMaxFiles) {
      throw Exception(
        'Too many files to zip. Limit is $_kArchiveMaxFiles files.',
      );
    }
    for (final file in files) {
      if (file.isDirectory) continue;
      if (file.path == destinationPath) continue;
      final bytes = await ctx.bridge.readBytes(
        treeUri: ctx.workspace.treeUri,
        relativePath: file.path,
      );
      totalBytes += bytes.length;
      if (totalBytes > _kArchiveMaxUncompressedBytes) {
        throw Exception(
          'Archive input is too large. Limit is '
          '${_formatArchiveBytes(_kArchiveMaxUncompressedBytes)}.',
        );
      }
      final archiveName = _zipEntryName(
        sourcePath: sourcePath,
        filePath: file.path,
        sourceIsDirectory: entry.isDirectory,
        sourceCount: sourceCount,
      );
      if (!usedNames.add(archiveName)) {
        throw Exception('Duplicate archive entry name: $archiveName');
      }
      final archiveFile =
          archive_pkg.ArchiveFile(archiveName, bytes.length, bytes);
      archiveFile.lastModTime = file.lastModified ~/ 1000;
      archive.addFile(archiveFile);
      fileCount++;
    }
  }
  if (fileCount == 0) {
    throw Exception('No files found to zip.');
  }

  final encoded = archive_pkg.ZipEncoder().encode(archive);
  if (encoded == null) {
    throw Exception('Failed to encode zip archive.');
  }

  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'write',
      patterns: [destinationPath],
      metadata: {
        'tool': 'zip',
        'path': destinationPath,
        'filePath': destinationPath,
        'sourcePaths': sources,
        'files': fileCount,
        'inputBytes': totalBytes,
        'bytes': encoded.length,
        'overwrite': overwrite,
      },
      always: [destinationPath],
      messageId: ctx.message.id,
      callId: ctx.callId ?? newId('call'),
    ),
  );

  await ctx.bridge.writeBytes(
    treeUri: ctx.workspace.treeUri,
    relativePath: destinationPath,
    bytes: Uint8List.fromList(encoded),
  );
  final written = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: destinationPath,
  );

  return ToolExecutionResult(
    title: destinationPath,
    output: 'Created $destinationPath with $fileCount files.',
    displayOutput: 'Created $destinationPath',
    metadata: {
      'path': destinationPath,
      'filePath': destinationPath,
      'format': 'zip',
      'mime': 'application/zip',
      'files': fileCount,
      'inputBytes': totalBytes,
      'bytes': encoded.length,
      'overwrite': overwrite,
      if (written != null)
        'readLedger': _toolReadLedgerMetadata(
          path: destinationPath,
          lastModified: written.lastModified,
          sourceTool: 'zip',
        ),
    },
    attachments: [
      {
        'type': 'file',
        'url': destinationPath,
        'path': destinationPath,
        'filename': p.basename(destinationPath),
        'mime': 'application/zip',
        'bytes': encoded.length,
        'format': 'zip',
      },
    ],
  );
}

Future<ToolExecutionResult> _unzipTool(
  JsonMap args,
  ToolRuntimeContext ctx,
) async {
  final overwrite = args['overwrite'] == true;
  final filePath = _strictFilePathArg(args, toolName: 'unzip');
  final destinationPath = _normalizeWorkspaceRelativePath(
    jsonStringCoerce(args['destinationPath'], ''),
  );
  final source = await ctx.bridge.getEntry(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  if (source == null || source.isDirectory) {
    throw Exception('Zip file not found: $filePath');
  }

  await ctx.updateToolProgress(
    title: filePath,
    displayOutput: 'Reading $filePath',
    metadata: {
      'phase': 'reading',
      'path': filePath,
      'filePath': filePath,
      'destinationPath': destinationPath,
      'overwrite': overwrite,
    },
  );

  final bytes = await ctx.bridge.readBytes(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  final decoded = archive_pkg.ZipDecoder().decodeBytes(bytes, verify: true);
  final files = decoded.files.where((item) => item.isFile).toList();
  if (files.length > _kArchiveMaxFiles) {
    throw Exception(
      'Too many files to unzip. Limit is $_kArchiveMaxFiles files.',
    );
  }

  final planned = <_UnzipPlan>[];
  var totalBytes = 0;
  for (final file in files) {
    final entryPath = _normalizeArchiveEntryPath(file.name);
    if (entryPath.isEmpty) continue;
    totalBytes += file.size;
    if (totalBytes > _kArchiveMaxUncompressedBytes) {
      throw Exception(
        'Archive output is too large. Limit is '
        '${_formatArchiveBytes(_kArchiveMaxUncompressedBytes)}.',
      );
    }
    final outputPath =
        destinationPath.isEmpty ? entryPath : '$destinationPath/$entryPath';
    final existing = await ctx.bridge.getEntry(
      treeUri: ctx.workspace.treeUri,
      relativePath: outputPath,
    );
    if (existing != null && existing.isDirectory) {
      throw Exception('Cannot overwrite directory with file: $outputPath');
    }
    if (existing != null && !overwrite) {
      throw Exception(
        'Destination already exists: $outputPath\n'
        'If you intentionally want to replace it, call `unzip` again with '
        '`overwrite: true`.',
      );
    }
    planned.add(_UnzipPlan(file: file, outputPath: outputPath));
  }
  if (planned.isEmpty) {
    throw Exception('No files found in zip archive: $filePath');
  }

  final patterns = destinationPath.isEmpty
      ? planned.map((item) => item.outputPath).take(20).toList()
      : [destinationPath];
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'write',
      patterns: patterns,
      metadata: {
        'tool': 'unzip',
        'path': filePath,
        'filePath': filePath,
        'destinationPath': destinationPath,
        'files': planned.length,
        'bytes': totalBytes,
        'overwrite': overwrite,
      },
      always: patterns,
      messageId: ctx.message.id,
      callId: ctx.callId ?? newId('call'),
    ),
  );

  var writtenBytes = 0;
  for (final item in planned) {
    final content = item.file.content;
    if (content is! List<int>) {
      throw Exception('Unsupported zip entry content: ${item.file.name}');
    }
    writtenBytes += content.length;
    await ctx.bridge.writeBytes(
      treeUri: ctx.workspace.treeUri,
      relativePath: item.outputPath,
      bytes: Uint8List.fromList(content),
    );
  }

  return ToolExecutionResult(
    title: filePath,
    output:
        'Extracted ${planned.length} files from $filePath to ${destinationPath.isEmpty ? '.' : destinationPath}.',
    displayOutput:
        'Extracted ${planned.length} files to ${destinationPath.isEmpty ? '.' : destinationPath}',
    metadata: {
      'path': filePath,
      'filePath': filePath,
      'destinationPath': destinationPath,
      'files': planned.length,
      'bytes': writtenBytes,
      'overwrite': overwrite,
      'items': planned.take(30).map((item) => item.outputPath).toList(),
    },
    attachments: [
      {
        'type': 'file_results',
        'kind': 'unzip',
        'pathPrefix': destinationPath,
        'count': planned.length,
        'items': planned
            .take(30)
            .map((item) => {
                  'path': item.outputPath,
                  'name': p.basename(item.outputPath),
                  'size': item.file.size,
                })
            .toList(),
      },
    ],
  );
}

class _UnzipPlan {
  const _UnzipPlan({
    required this.file,
    required this.outputPath,
  });

  final archive_pkg.ArchiveFile file;
  final String outputPath;
}

List<String> _archiveSourcePaths(JsonMap args) {
  final rawSources = args['sourcePaths'];
  final output = <String>[];
  if (rawSources is List) {
    for (final item in rawSources) {
      final path = _normalizeWorkspaceRelativePath(jsonStringCoerce(item, ''));
      if (!output.contains(path)) output.add(path);
    }
  }
  final single = jsonStringCoerce(args['sourcePath'] ?? args['path'], '');
  if (single.trim().isNotEmpty) {
    final path = _normalizeWorkspaceRelativePath(single);
    if (!output.contains(path)) output.add(path);
  }
  if (output.isEmpty) {
    throw Exception(
        'Missing zip source. Provide `sourcePath` or `sourcePaths`.');
  }
  return output;
}

String _archiveZipOutputPath(String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  if (extension.isEmpty) {
    return '$filePath.zip';
  }
  if (extension != '.zip') {
    throw Exception('Zip output path must end with .zip: $filePath');
  }
  return filePath;
}

String _zipEntryName({
  required String sourcePath,
  required String filePath,
  required bool sourceIsDirectory,
  required int sourceCount,
}) {
  if (sourcePath.isEmpty) return filePath;
  if (!sourceIsDirectory) {
    return sourceCount == 1 ? p.basename(filePath) : filePath;
  }
  final relative = filePath.startsWith('$sourcePath/')
      ? filePath.substring(sourcePath.length + 1)
      : p.basename(filePath);
  final base = p.basename(sourcePath);
  return '$base/$relative';
}

String _normalizeArchiveEntryPath(String input) {
  var value = input.trim().replaceAll('\\', '/');
  while (value.startsWith('/')) {
    value = value.substring(1);
  }
  if (RegExp(r'^[A-Za-z]:').hasMatch(value)) {
    throw Exception('Zip entry uses an absolute path: $input');
  }
  final normalized = _normalizeWorkspaceRelativePath(value);
  if (normalized.isEmpty) return '';
  return normalized;
}

String _formatArchiveBytes(int bytes) {
  final mb = bytes / (1024 * 1024);
  if (mb >= 1) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  final kb = bytes / 1024;
  if (kb >= 1) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  return '$bytes bytes';
}
