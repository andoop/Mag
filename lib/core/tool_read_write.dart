part of 'tool_runtime.dart';

String _toolFilePathArg(JsonMap args) {
  final raw = args['filePath'] ?? args['path'];
  return _normalizeWorkspaceRelativePath(jsonStringCoerce(raw, ''));
}

String _strictReadPathArg(JsonMap args) {
  final raw = jsonStringCoerce(args['filePath'] ?? args['path'], '').trim();
  if (raw.isEmpty) {
    throw Exception(
      'Missing required read path. Provide `filePath` explicitly.',
    );
  }
  final normalized = _normalizeWorkspaceRelativePath(raw);
  if (normalized.isEmpty) {
    throw Exception(
      'Reading the workspace root is not supported. '
      'Provide a specific file or directory path.',
    );
  }
  return normalized;
}

String _strictFilePathArg(JsonMap args, {required String toolName}) {
  final raw = jsonStringCoerce(args['filePath'], '');
  final path = _normalizeWorkspaceRelativePath(raw);
  if (path.isEmpty) {
    throw Exception('Missing required `filePath` for `$toolName`.');
  }
  return path;
}

String _normalizeWriteContent(Object? value) {
  if (value == null) {
    return '';
  }
  if (value is String) {
    return value;
  }
  if (value is Map || value is List) {
    return const JsonEncoder.withIndent('  ').convert(value);
  }
  return value.toString();
}

Future<String> _resolveWriteContent(
    JsonMap args, ToolRuntimeContext ctx) async {
  if (args.containsKey('content')) {
    return _normalizeWriteContent(args['content']);
  }
  throw Exception(
    'The write tool requires both `filePath` and `content`. '
    'Provide the full file body in `content` and call write again.',
  );
}

class _ToolReadLedgerEntry {
  _ToolReadLedgerEntry({
    required this.path,
    required this.lastModified,
    this.startLine,
    this.endLine,
    this.sourceTool,
  });

  final String path;
  final int lastModified;
  final int? startLine;
  final int? endLine;
  final String? sourceTool;

  bool get hasCoverage =>
      startLine != null &&
      endLine != null &&
      startLine! > 0 &&
      endLine! >= startLine!;

  bool coversLine(int line) =>
      hasCoverage && line >= startLine! && line <= endLine!;
}

JsonMap _toolReadLedgerMetadata({
  required String path,
  required int lastModified,
  int? startLine,
  int? endLine,
  String? sourceTool,
}) =>
    {
      'path': path,
      'lastModified': lastModified,
      if (startLine != null) 'startLine': startLine,
      if (endLine != null) 'endLine': endLine,
      if (sourceTool != null && sourceTool.isNotEmpty) 'sourceTool': sourceTool,
    };

_ToolReadLedgerEntry? _toolReadLedgerFromMetadata(
  JsonMap metadata,
  String path, {
  String? fallbackSourceTool,
}) {
  final normalized = _normalizeWorkspaceRelativePath(path);
  final single = metadata['readLedger'];
  if (single is Map) {
    final map = Map<String, dynamic>.from(single);
    final ledgerPath =
        _normalizeWorkspaceRelativePath(jsonStringCoerce(map['path'], ''));
    if (ledgerPath == normalized) {
      return _ToolReadLedgerEntry(
        path: ledgerPath,
        lastModified: (map['lastModified'] as num?)?.toInt() ?? 0,
        startLine: (map['startLine'] as num?)?.toInt(),
        endLine: (map['endLine'] as num?)?.toInt(),
        sourceTool: jsonStringCoerce(
          map['sourceTool'],
          fallbackSourceTool ?? '',
        ),
      );
    }
  }
  final multiple = metadata['readLedgers'];
  if (multiple is List) {
    for (final item in multiple.whereType<Map>()) {
      final map = Map<String, dynamic>.from(item);
      final ledgerPath =
          _normalizeWorkspaceRelativePath(jsonStringCoerce(map['path'], ''));
      if (ledgerPath == normalized) {
        return _ToolReadLedgerEntry(
          path: ledgerPath,
          lastModified: (map['lastModified'] as num?)?.toInt() ?? 0,
          startLine: (map['startLine'] as num?)?.toInt(),
          endLine: (map['endLine'] as num?)?.toInt(),
          sourceTool: jsonStringCoerce(
            map['sourceTool'],
            fallbackSourceTool ?? '',
          ),
        );
      }
    }
  }
  return null;
}

Future<_ToolReadLedgerEntry?> _latestToolReadLedgerForPath(
  ToolRuntimeContext ctx,
  String filePath,
  {
  String? requiredSourceTool,
  bool requireCoverage = false,
}
) async {
  final parts = await ctx.database.listPartsForSession(ctx.session.id);
  for (final part in parts.reversed) {
    if (part.type != PartType.tool) continue;
    final state =
        Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
    if (state['status'] != ToolStatus.completed.name) continue;
    final metadata =
        Map<String, dynamic>.from(state['metadata'] as Map? ?? const {});
    final toolName = jsonStringCoerce(part.data['tool'], '');
    final ledger = _toolReadLedgerFromMetadata(
      metadata,
      filePath,
      fallbackSourceTool: toolName,
    );
    if (ledger == null) continue;
    if (requiredSourceTool != null && ledger.sourceTool != requiredSourceTool) {
      continue;
    }
    if (requireCoverage && !ledger.hasCoverage) continue;
    return ledger;
  }
  return null;
}

String _formatLedgerTimestamp(int millis) =>
    DateTime.fromMillisecondsSinceEpoch(millis).toIso8601String();

String _formatLineList(List<int> lines) {
  if (lines.isEmpty) return '';
  final sorted = lines.toSet().toList()..sort();
  if (sorted.length == 1) return '${sorted.first}';
  if (sorted.length <= 4) return sorted.join(', ');
  return '${sorted.first}-${sorted.last}';
}

Future<void> _assertHashlineAnchorsCoveredByLatestReadWindow(
  ToolRuntimeContext ctx,
  String filePath, {
  required Iterable<String> refs,
  required String toolName,
}) async {
  final anchorLines = refs
      .map((ref) => _parseHashlineRef(ref).line)
      .toSet()
      .toList()
    ..sort();
  if (anchorLines.isEmpty) return;
  final ledger = await _latestToolReadLedgerForPath(
    ctx,
    filePath,
    requiredSourceTool: 'read',
    requireCoverage: true,
  );
  if (ledger == null) {
    throw Exception(
      'BLOCKED: Your `$toolName` call for "$filePath" uses LINE#ID anchors, '
      'but there is no recent `read` window recorded for those lines.\n'
      'Required action: call `read` on "$filePath" with an `offset`/`limit` '
      'range that includes line(s) ${_formatLineList(anchorLines)}, then '
      'rebuild the `$toolName` call using anchors from that newest output.',
    );
  }
  final uncovered =
      anchorLines.where((line) => !ledger.coversLine(line)).toList();
  if (uncovered.isEmpty) return;
  throw Exception(
    'BLOCKED: Your `$toolName` call for "$filePath" uses LINE#ID anchor line(s) '
    '${_formatLineList(uncovered)}, but the most recent `read` window for this '
    'file only covered lines ${ledger.startLine}-${ledger.endLine}.\n'
    'Required action: call `read` on "$filePath" again with an `offset`/`limit` '
    'range that includes the target lines, then rebuild `$toolName` using '
    'anchors from that newest output. Do not reuse anchors from an older read window.',
  );
}

Future<void> _assertFreshReadForExistingFile(
  ToolRuntimeContext ctx,
  String filePath, {
  required String toolName,
}) async {
  final entry = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  if (entry == null || entry.isDirectory) {
    return;
  }
  final ledger = await _latestToolReadLedgerForPath(ctx, filePath);
  if (ledger == null) {
    throw Exception(
      'BLOCKED: You must `read` the file "$filePath" before using `$toolName`.\n'
      'Required action: call `read` with path "$filePath" first, then retry your `$toolName` call.',
    );
  }
  if (entry.lastModified > ledger.lastModified) {
    throw Exception(
      'BLOCKED: File "$filePath" has been modified since your last `read` '
      '(file modified: ${_formatLedgerTimestamp(entry.lastModified)}, '
      'your last read: ${_formatLedgerTimestamp(ledger.lastModified)}).\n'
      'Required action: call `read` on "$filePath" again to get the latest content, then rebuild your `$toolName` call with the fresh data.',
    );
  }
}

Future<ToolExecutionResult> _readTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final filePath = _strictReadPathArg(args);
  await ctx.updateToolProgress(
    title: filePath.isEmpty ? ctx.workspace.name : filePath,
    metadata: {
      'phase': 'reading',
      'path': filePath,
      if (filePath.isNotEmpty) 'filePath': filePath,
    },
  );
  final safeOffset = ((args['offset'] as int?) ?? 1).clamp(1, 1 << 30);
  final limit = ((args['limit'] as int?) ?? _kDefaultReadLimit).clamp(1, 5000);
  final pathLabel = filePath.isEmpty ? '.' : filePath;
  final entry = filePath.isEmpty
      ? WorkspaceEntry(
          path: '',
          name: ctx.workspace.name,
          isDirectory: true,
          lastModified: ctx.workspace.createdAt,
          size: 0,
        )
      : await ctx.bridge.getEntry(
          treeUri: ctx.workspace.treeUri,
          relativePath: filePath,
        );
  if (entry == null) {
    final suggestions = await _fileNotFoundSuggestions(filePath, ctx);
    if (suggestions.isNotEmpty) {
      throw Exception(
        'File not found: $filePath\n\nDid you mean one of these?\n${suggestions.join('\n')}',
      );
    }
    throw Exception('File not found: $filePath');
  }

  if (entry.isDirectory) {
    final entries = await ctx.bridge.listDirectory(
      treeUri: ctx.workspace.treeUri,
      relativePath: filePath,
    );
    final start = safeOffset - 1;
    final sliced = entries.skip(start).take(limit).toList();
    final truncated = start + sliced.length < entries.length;
    final output = [
      '<path>$pathLabel</path>',
      '<type>directory</type>',
      '<entries>',
      ...sliced.map((item) => item.isDirectory ? '${item.name}/' : item.name),
      truncated
          ? "\n(Showing ${sliced.length} of ${entries.length} entries. Use 'offset' parameter to read beyond entry ${safeOffset + sliced.length})"
          : '\n(${entries.length} entries)',
      '</entries>',
    ].join('\n');
    return ToolExecutionResult(
      title: filePath.isEmpty ? ctx.workspace.name : filePath,
      output: output,
      displayOutput:
          'Listed $pathLabel · ${sliced.length}/${entries.length} entries',
      metadata: {
        'preview': sliced.take(20).map((item) => item.name).join('\n'),
        'truncated': truncated,
        'loaded': const <String>[],
        'path': filePath,
        'kind': 'directory',
      },
    );
  }

  final mime = entry.mimeType ?? '';
  if (_isImageMime(mime) || mime == 'application/pdf') {
    final msg = _isImageMime(mime)
        ? 'Image read successfully'
        : 'PDF read successfully';
    return ToolExecutionResult(
      title: filePath,
      output: msg,
      displayOutput: '$msg · $filePath',
      metadata: {
        'preview': msg,
        'truncated': false,
        'loaded': const <String>[],
        'path': filePath,
        'kind': 'attachment',
      },
      attachments: [
        {
          'type': 'file',
          'mime': mime,
          'path': filePath,
          'filename': entry.name,
        },
      ],
    );
  }

  if (_looksBinaryEntry(entry)) {
    throw Exception('Cannot read binary file: $filePath');
  }

  var content = await ctx.bridge.readText(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  // Strip BOM so hashes match the edit path and the model doesn't copy it.
  if (content.startsWith('\uFEFF')) content = content.substring(1);
  final reminder = await ctx.resolveInstructionReminder(filePath);
  final rawLines = const LineSplitter().convert(content);
  if (rawLines.length < safeOffset && !(rawLines.isEmpty && safeOffset == 1)) {
    throw Exception(
      'Offset $safeOffset is out of range for this file (${rawLines.length} lines)',
    );
  }

  final contentLines = <String>[];
  var bytes = 0;
  var hasMoreLines = false;
  var truncatedByBytes = false;
  for (var i = safeOffset - 1; i < rawLines.length; i++) {
    if (contentLines.length >= limit) {
      hasMoreLines = true;
      break;
    }
    final original = rawLines[i];
    final line = original.length > _kMaxReadLineLength
        ? '${original.substring(0, _kMaxReadLineLength)}$_kMaxReadLineSuffix'
        : original;
    final size = utf8.encode(line).length + (contentLines.isEmpty ? 0 : 1);
    if (bytes + size > _kMaxReadBytes) {
      truncatedByBytes = true;
      hasMoreLines = true;
      break;
    }
    final numbered = _formatHashlineReadLine(
      i + 1,
      line,
      truncated: original.length > _kMaxReadLineLength,
    );
    contentLines.add(numbered);
    bytes += size;
  }
  final previewText = contentLines.join('\n');
  final lastReadLine = contentLines.isEmpty
      ? safeOffset - 1
      : safeOffset + contentLines.length - 1;
  final nextOffset = lastReadLine + 1;
  final truncated = hasMoreLines || truncatedByBytes;
  var output = [
    '<path>$pathLabel</path>',
    '<type>file</type>',
    '<content>',
    ...contentLines,
  ].join('\n');
  if (truncatedByBytes) {
    output +=
        '\n\n(Output capped at 50 KB. Showing lines $safeOffset-$lastReadLine. Use offset=$nextOffset to continue.)';
  } else if (hasMoreLines) {
    output +=
        '\n\n(Showing lines $safeOffset-$lastReadLine of ${rawLines.length}. Use offset=$nextOffset to continue.)';
  } else {
    output += '\n\n(End of file - total ${rawLines.length} lines)';
  }
  output += '\n</content>';
  if (reminder.isNotEmpty) {
    output += '\n\n<system-reminder>\n$reminder\n</system-reminder>';
  }
  return ToolExecutionResult(
    title: filePath,
    output: output,
    displayOutput: contentLines.isEmpty
        ? 'Read $filePath · empty file'
        : 'Read $filePath · lines $safeOffset-$lastReadLine / ${rawLines.length}',
    metadata: {
      'preview': previewText,
      'truncated': truncated,
      'loaded': reminder.isEmpty ? const <String>[] : <String>[filePath],
      'path': filePath,
      'kind': 'file',
      'lineCount': rawLines.length,
      'lastModified': entry.lastModified,
      'readLedger': _toolReadLedgerMetadata(
        path: filePath,
        lastModified: entry.lastModified,
        startLine: safeOffset,
        endLine: lastReadLine < safeOffset ? safeOffset : lastReadLine,
        sourceTool: 'read',
      ),
    },
    attachments: [
      {
        'type': 'text_preview',
        'path': filePath,
        'filename': entry.name,
        'startLine': safeOffset,
        'endLine': lastReadLine < safeOffset ? safeOffset : lastReadLine,
        'lineCount': rawLines.length,
        'preview': previewText,
      },
    ],
  );
}

Future<ToolExecutionResult> _writeTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final filePath = _strictFilePathArg(args, toolName: 'write');
  final content = await _resolveWriteContent(args, ctx);
  await ctx.updateToolProgress(
    title: filePath,
    metadata: {
      'phase': 'preparing',
      'path': filePath,
      'filePath': filePath,
    },
  );
  var existing = '';
  final entry = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  final exists = entry != null && !entry.isDirectory;
  if (exists) {
    await _assertFreshReadForExistingFile(
      ctx,
      filePath,
      toolName: 'write',
    );
  }
  if (exists) {
    existing = await ctx.bridge.readText(
      treeUri: ctx.workspace.treeUri,
      relativePath: filePath,
    );
  }
  final preview = _buildDiffAttachment(
    kind: exists ? 'write_update' : 'write',
    path: filePath,
    before: existing,
    after: content,
  );
  await ctx.updateToolProgress(
    title: filePath,
    displayOutput: 'Preparing write to $filePath',
    metadata: {
      'phase': 'preparing',
      'path': filePath,
      'filePath': filePath,
    },
    attachments: [preview],
  );
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'edit',
      patterns: [filePath],
      metadata: {
        'tool': 'write',
        'path': filePath,
        'filePath': filePath,
        'preview': preview,
      },
      always: [filePath],
      messageId: ctx.message.id,
      callId: newId('call'),
    ),
  );
  await ctx.bridge.writeText(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
    content: content,
  );
  final updatedEntry = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  return ToolExecutionResult(
    title: filePath,
    output: 'Wrote file successfully.',
    displayOutput: 'Wrote $filePath',
    metadata: {
      'path': filePath,
      'filepath': filePath,
      'exists': exists,
      'diagnostics': const <String, dynamic>{},
      if (updatedEntry != null)
        'readLedger': _toolReadLedgerMetadata(
          path: filePath,
          lastModified: updatedEntry.lastModified,
          sourceTool: 'write',
        ),
    },
    attachments: [
      preview,
    ],
  );
}

/// Escapes whitespace for logs; truncates with total char count.
String _editDebugEscapedPreview(String s, int maxChars) {
  String esc(String t) => t
      .replaceAll('\\', r'\\')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n')
      .replaceAll('\t', r'\t');
  if (s.length <= maxChars) return esc(s);
  final half = maxChars ~/ 2;
  return '${esc(s.substring(0, half))}…(${s.length} chars)…${esc(s.substring(s.length - half))}';
}

void _logApplyPatchToolFailure({
  required String phase,
  required String error,
  required String patchText,
  required Map<String, dynamic> rawArgs,
  int? sectionIndex,
  String? sectionPath,
  String? sectionKind,
  String? movePath,
  int? sectionLineCount,
  List<String>? sectionLinesHead,
  int? existingChars,
  int? existingLines,
}) {
  final patchPreview =
      _editDebugEscapedPreview(patchText, _kEditMismatchLogPreviewChars);
  final payload = <String, dynamic>{
    'phase': phase,
    'error': error,
    'patchTextChars': patchText.length,
    'patchTextPreview': patchPreview,
    'argKeys': rawArgs.keys.toList(),
    if (sectionIndex != null) 'sectionIndex': sectionIndex,
    if (sectionPath != null) 'sectionPath': sectionPath,
    if (sectionKind != null) 'sectionKind': sectionKind,
    if (movePath != null) 'movePath': movePath,
    if (sectionLineCount != null) 'sectionLineCount': sectionLineCount,
    if (sectionLinesHead != null) 'sectionLinesHead': sectionLinesHead,
    if (existingChars != null) 'existingChars': existingChars,
    if (existingLines != null) 'existingLines': existingLines,
  };
  // ignore: avoid_print
  print('[mag-patch][fail] ${jsonEncode(payload)}');
}

Future<ToolExecutionResult> _editTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  if (args.containsKey('oldString') ||
      args.containsKey('newString') ||
      args.containsKey('replaceAll')) {
    throw Exception(
      'The edit tool no longer accepts `oldString` / `newString` / `replaceAll`.\n'
      'Required action: call `read`, copy exact LINE#ID anchors, then retry `edit` with `edits` operations only.',
    );
  }
  return _executeHashlineEditTool(args, ctx);
}
