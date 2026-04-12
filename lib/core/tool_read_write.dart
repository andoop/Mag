part of 'tool_runtime.dart';

String _toolFilePathArg(JsonMap args) {
  final raw = args['filePath'] ?? args['path'];
  return _normalizeWorkspaceRelativePath(jsonStringCoerce(raw, ''));
}

String _strictReadPathArg(JsonMap args) {
  final raw = jsonStringCoerce(args['filePath'], '').trim();
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
      'Required action: call `read` with `filePath` "$filePath" first, then retry your `$toolName` call.',
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
    final numbered = '${i + 1}: $line';
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
  if (args.containsKey('edits') ||
      args.containsKey('delete') ||
      args.containsKey('rename')) {
    throw Exception(
      'The edit tool only accepts `filePath`, `oldString`, `newString`, and optional `replaceAll`.\n'
      'Required action: call `read`, copy the exact text you want to replace (without line-number prefixes), then retry `edit` with `oldString` / `newString`.',
    );
  }
  final filePath = _strictFilePathArg(args, toolName: 'edit');
  final oldString = jsonStringCoerce(args['oldString'], '');
  final newString = jsonStringCoerce(args['newString'], '');
  final replaceAll = args['replaceAll'] == true;

  if (oldString == newString) {
    throw Exception('No changes to apply: oldString and newString are identical.');
  }

  final existingEntry = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  if (existingEntry != null && existingEntry.isDirectory) {
    throw Exception('Path is a directory, not a file: $filePath');
  }

  if (oldString.isEmpty) {
    final preview = _buildDiffAttachment(
      kind: 'edit',
      path: filePath,
      before: '',
      after: newString,
    );
    await ctx.updateToolProgress(
      title: filePath,
      displayOutput: 'Preparing edit for $filePath',
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
          'tool': 'edit',
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
      content: newString,
    );
    final updatedEntry = await ctx.bridge.stat(
      treeUri: ctx.workspace.treeUri,
      relativePath: filePath,
    );
    return ToolExecutionResult(
      title: filePath,
      output: 'Edit applied successfully.',
      displayOutput: 'Updated $filePath',
      metadata: {
        'path': filePath,
        'filepath': filePath,
        'diagnostics': const <String, dynamic>{},
        'filediff': {
          'file': filePath,
          'before': '',
          'after': newString,
          ..._diffLineChangeCounts('', newString),
        },
        if (updatedEntry != null)
          'readLedger': _toolReadLedgerMetadata(
            path: filePath,
            lastModified: updatedEntry.lastModified,
            sourceTool: 'edit',
          ),
      },
      attachments: [preview],
    );
  }

  if (existingEntry == null) {
    throw Exception('File $filePath not found');
  }
  await _assertFreshReadForExistingFile(
    ctx,
    filePath,
    toolName: 'edit',
  );
  final existingRaw = await ctx.bridge.readText(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  final envelope = _canonicalizeHashlineFileText(existingRaw);
  final normalizedOld = _normalizeEditLineEndings(oldString);
  final normalizedNew = _normalizeEditLineEndings(newString);
  final updatedCanonical = _replaceEditContent(
    envelope.content,
    normalizedOld,
    normalizedNew,
    replaceAll: replaceAll,
  );
  final restored = _restoreHashlineFileText(updatedCanonical, envelope);
  final preview = _buildDiffAttachment(
    kind: 'edit',
    path: filePath,
    before: existingRaw,
    after: restored,
  );
  await ctx.updateToolProgress(
    title: filePath,
    displayOutput: 'Preparing edit for $filePath',
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
        'tool': 'edit',
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
    content: restored,
  );
  final updatedEntry = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  return ToolExecutionResult(
    title: filePath,
    output: 'Edit applied successfully.',
    displayOutput: 'Updated $filePath',
    metadata: {
      'path': filePath,
      'filepath': filePath,
      'diagnostics': const <String, dynamic>{},
      'filediff': {
        'file': filePath,
        'before': existingRaw,
        'after': restored,
        ..._diffLineChangeCounts(existingRaw, restored),
      },
      if (updatedEntry != null)
        'readLedger': _toolReadLedgerMetadata(
          path: filePath,
          lastModified: updatedEntry.lastModified,
          sourceTool: 'edit',
        ),
    },
    attachments: [preview],
  );
}

String _normalizeEditLineEndings(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

typedef _StringReplacer = Iterable<String> Function(String content, String find);

Iterable<String> _simpleReplacer(String content, String find) sync* {
  yield find;
}

Iterable<String> _lineTrimmedReplacer(String content, String find) sync* {
  final originalLines = content.split('\n');
  final searchLines = find.split('\n').toList();
  if (searchLines.isNotEmpty && searchLines.last.isEmpty) {
    searchLines.removeLast();
  }
  for (var i = 0; i <= originalLines.length - searchLines.length; i++) {
    var matches = true;
    for (var j = 0; j < searchLines.length; j++) {
      if (originalLines[i + j].trim() != searchLines[j].trim()) {
        matches = false;
        break;
      }
    }
    if (!matches) continue;
    final block = originalLines.sublist(i, i + searchLines.length).join('\n');
    yield block;
  }
}

int _levenshtein(String a, String b) {
  if (a.isEmpty || b.isEmpty) return a.length > b.length ? a.length : b.length;
  final matrix =
      List.generate(a.length + 1, (i) => List<int>.filled(b.length + 1, 0));
  for (var i = 0; i <= a.length; i++) {
    matrix[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    matrix[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      matrix[i][j] = [
        matrix[i - 1][j] + 1,
        matrix[i][j - 1] + 1,
        matrix[i - 1][j - 1] + cost,
      ].reduce((a, b) => a < b ? a : b);
    }
  }
  return matrix[a.length][b.length];
}

Iterable<String> _blockAnchorReplacer(String content, String find) sync* {
  final originalLines = content.split('\n');
  final searchLines = find.split('\n').toList();
  if (searchLines.length < 3) return;
  if (searchLines.isNotEmpty && searchLines.last.isEmpty) {
    searchLines.removeLast();
  }
  final firstLineSearch = searchLines.first.trim();
  final lastLineSearch = searchLines.last.trim();
  final candidates = <Map<String, int>>[];
  for (var i = 0; i < originalLines.length; i++) {
    if (originalLines[i].trim() != firstLineSearch) continue;
    for (var j = i + 2; j < originalLines.length; j++) {
      if (originalLines[j].trim() == lastLineSearch) {
        candidates.add({'start': i, 'end': j});
        break;
      }
    }
  }
  if (candidates.isEmpty) return;
  Map<String, int>? bestMatch;
  var maxSimilarity = -1.0;
  for (final candidate in candidates) {
    final startLine = candidate['start']!;
    final endLine = candidate['end']!;
    final actualBlockSize = endLine - startLine + 1;
    final linesToCheck = [
      searchLines.length - 2,
      actualBlockSize - 2,
    ].reduce((a, b) => a < b ? a : b);
    var similarity = 0.0;
    if (linesToCheck > 0) {
      for (var j = 1;
          j < searchLines.length - 1 && j < actualBlockSize - 1;
          j++) {
        final originalLine = originalLines[startLine + j].trim();
        final searchLine = searchLines[j].trim();
        final maxLen =
            originalLine.length > searchLine.length ? originalLine.length : searchLine.length;
        if (maxLen == 0) continue;
        final distance = _levenshtein(originalLine, searchLine);
        similarity += 1 - distance / maxLen;
      }
      similarity /= linesToCheck;
    } else {
      similarity = 1.0;
    }
    if (similarity > maxSimilarity) {
      maxSimilarity = similarity;
      bestMatch = candidate;
    }
  }
  if (bestMatch == null) return;
  final startLine = bestMatch['start']!;
  final endLine = bestMatch['end']!;
  yield originalLines.sublist(startLine, endLine + 1).join('\n');
}

String _normalizeWhitespace(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();

Iterable<String> _whitespaceNormalizedReplacer(String content, String find) sync* {
  final normalizedFind = _normalizeWhitespace(find);
  final lines = content.split('\n');
  for (final line in lines) {
    if (_normalizeWhitespace(line) == normalizedFind) {
      yield line;
    }
  }
  final findLines = find.split('\n');
  if (findLines.length > 1) {
    for (var i = 0; i <= lines.length - findLines.length; i++) {
      final block = lines.sublist(i, i + findLines.length).join('\n');
      if (_normalizeWhitespace(block) == normalizedFind) {
        yield block;
      }
    }
  }
}

String _removeIndentation(String text) {
  final lines = text.split('\n');
  final nonEmptyLines = lines.where((line) => line.trim().isNotEmpty).toList();
  if (nonEmptyLines.isEmpty) return text;
  var minIndent = 1 << 30;
  for (final line in nonEmptyLines) {
    final match = RegExp(r'^(\s*)').firstMatch(line);
    minIndent = [minIndent, match?.group(1)?.length ?? 0]
        .reduce((a, b) => a < b ? a : b);
  }
  return lines
      .map((line) =>
          line.trim().isEmpty ? line : line.substring(minIndent.clamp(0, line.length)))
      .join('\n');
}

Iterable<String> _indentationFlexibleReplacer(String content, String find) sync* {
  final normalizedFind = _removeIndentation(find);
  final contentLines = content.split('\n');
  final findLines = find.split('\n');
  for (var i = 0; i <= contentLines.length - findLines.length; i++) {
    final block = contentLines.sublist(i, i + findLines.length).join('\n');
    if (_removeIndentation(block) == normalizedFind) {
      yield block;
    }
  }
}

String _unescapeEditString(String str) {
  return str.replaceAllMapped(
    RegExp(r"""\\(n|t|r|'|"|`|\\|\n|\$)"""),
    (match) {
      final captured = match.group(1);
      switch (captured) {
        case 'n':
          return '\n';
        case 't':
          return '\t';
        case 'r':
          return '\r';
        case '\'':
          return '\'';
        case '"':
          return '"';
        case '`':
          return '`';
        case r'\\':
          return '\\';
        case '\n':
          return '\n';
        case r'$':
          return r'$';
      }
      return match.group(0) ?? '';
    },
  );
}

Iterable<String> _escapeNormalizedReplacer(String content, String find) sync* {
  final unescapedFind = _unescapeEditString(find);
  if (content.contains(unescapedFind)) {
    yield unescapedFind;
  }
  final lines = content.split('\n');
  final findLines = unescapedFind.split('\n');
  for (var i = 0; i <= lines.length - findLines.length; i++) {
    final block = lines.sublist(i, i + findLines.length).join('\n');
    if (_unescapeEditString(block) == unescapedFind) {
      yield block;
    }
  }
}

Iterable<String> _trimmedBoundaryReplacer(String content, String find) sync* {
  final trimmedFind = find.trim();
  if (trimmedFind == find) return;
  if (content.contains(trimmedFind)) {
    yield trimmedFind;
  }
  final lines = content.split('\n');
  final findLines = find.split('\n');
  for (var i = 0; i <= lines.length - findLines.length; i++) {
    final block = lines.sublist(i, i + findLines.length).join('\n');
    if (block.trim() == trimmedFind) {
      yield block;
    }
  }
}

Iterable<String> _contextAwareReplacer(String content, String find) sync* {
  final findLines = find.split('\n').toList();
  if (findLines.length < 3) return;
  if (findLines.isNotEmpty && findLines.last.isEmpty) {
    findLines.removeLast();
  }
  final contentLines = content.split('\n');
  final firstLine = findLines.first.trim();
  final lastLine = findLines.last.trim();
  for (var i = 0; i < contentLines.length; i++) {
    if (contentLines[i].trim() != firstLine) continue;
    for (var j = i + 2; j < contentLines.length; j++) {
      if (contentLines[j].trim() != lastLine) continue;
      final blockLines = contentLines.sublist(i, j + 1);
      if (blockLines.length == findLines.length) {
        var matchingLines = 0;
        var totalNonEmptyLines = 0;
        for (var k = 1; k < blockLines.length - 1; k++) {
          final blockLine = blockLines[k].trim();
          final findLine = findLines[k].trim();
          if (blockLine.isNotEmpty || findLine.isNotEmpty) {
            totalNonEmptyLines += 1;
            if (blockLine == findLine) matchingLines += 1;
          }
        }
        if (totalNonEmptyLines == 0 ||
            matchingLines / totalNonEmptyLines >= 0.5) {
          yield blockLines.join('\n');
          break;
        }
      }
      break;
    }
  }
}

Iterable<String> _multiOccurrenceReplacer(String content, String find) sync* {
  var startIndex = 0;
  while (true) {
    final index = content.indexOf(find, startIndex);
    if (index == -1) break;
    yield find;
    startIndex = index + find.length;
  }
}

String _replaceEditContent(
  String content,
  String oldString,
  String newString, {
  bool replaceAll = false,
}) {
  var notFound = true;
  final replacers = <_StringReplacer>[
    _simpleReplacer,
    _lineTrimmedReplacer,
    _blockAnchorReplacer,
    _whitespaceNormalizedReplacer,
    _indentationFlexibleReplacer,
    _escapeNormalizedReplacer,
    _trimmedBoundaryReplacer,
    _contextAwareReplacer,
    _multiOccurrenceReplacer,
  ];
  for (final replacer in replacers) {
    for (final search in replacer(content, oldString)) {
      final index = content.indexOf(search);
      if (index == -1) continue;
      notFound = false;
      if (replaceAll) {
        return content.replaceAll(search, newString);
      }
      final lastIndex = content.lastIndexOf(search);
      if (index != lastIndex) continue;
      return '${content.substring(0, index)}$newString${content.substring(index + search.length)}';
    }
  }
  if (notFound) {
    throw Exception(
      'Could not find oldString in the file. It must match exactly, including whitespace, indentation, and line endings.',
    );
  }
  throw Exception(
    'Found multiple matches for oldString. Provide more surrounding context to make the match unique.',
  );
}
