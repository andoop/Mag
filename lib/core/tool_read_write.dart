part of 'tool_runtime.dart';

String _toolFilePathArg(JsonMap args) {
  final raw = args['filePath'] ?? args['path'];
  return _normalizeWorkspaceRelativePath(jsonStringCoerce(raw, ''));
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
  });

  final String path;
  final int lastModified;
}

JsonMap _toolReadLedgerMetadata({
  required String path,
  required int lastModified,
}) =>
    {
      'path': path,
      'lastModified': lastModified,
    };

_ToolReadLedgerEntry? _toolReadLedgerFromMetadata(
    JsonMap metadata, String path) {
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
        );
      }
    }
  }
  return null;
}

Future<_ToolReadLedgerEntry?> _latestToolReadLedgerForPath(
  ToolRuntimeContext ctx,
  String filePath,
) async {
  final parts = await ctx.database.listPartsForSession(ctx.session.id);
  for (final part in parts.reversed) {
    if (part.type != PartType.tool) continue;
    final state =
        Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
    if (state['status'] != ToolStatus.completed.name) continue;
    final metadata =
        Map<String, dynamic>.from(state['metadata'] as Map? ?? const {});
    final ledger = _toolReadLedgerFromMetadata(metadata, filePath);
    if (ledger != null) return ledger;
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
      'you must read the file $filePath before using $toolName. Use the read tool first',
    );
  }
  if (entry.lastModified > ledger.lastModified) {
    throw Exception(
      'file $filePath has been modified since it was last read '
      '(mod time: ${_formatLedgerTimestamp(entry.lastModified)}, '
      'last read: ${_formatLedgerTimestamp(ledger.lastModified)})',
    );
  }
}

Future<ToolExecutionResult> _readTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final filePath = _toolFilePathArg(args);
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

  final content = await ctx.bridge.readText(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
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
  final filePath = _toolFilePathArg(args);
  final content = await _resolveWriteContent(args, ctx);
  if (filePath.isEmpty) {
    throw Exception('Missing required `path`.');
  }
  var existing = '';
  final entry = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  final exists = entry != null && !entry.isDirectory;
  if (exists) {
    existing = await ctx.bridge.readText(
      treeUri: ctx.workspace.treeUri,
      relativePath: filePath,
    );
  }
  if (exists) {
    throw Exception(
      'File already exists: $filePath. Use `edit` or `apply_patch` instead of `write` for existing files.',
    );
  }
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
        'preview': _buildDiffAttachment(
          kind: exists ? 'write_update' : 'write',
          path: filePath,
          before: existing,
          after: content,
        ),
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
        ),
    },
    attachments: [
      _buildDiffAttachment(
        kind: exists ? 'write_update' : 'write',
        path: filePath,
        before: existing,
        after: content,
      ),
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

/// Logs model/tool arguments when edit matching fails (search console: `[mag-edit]`).
void _logEditToolMismatch({
  required String filePath,
  required Map<String, dynamic> rawArgs,
  required String oldString,
  required String newString,
  required bool replaceAll,
  required String existing,
}) {
  final oldLines = _editLogicalLinesNoTrailingBlank(oldString);
  final fileLines = existing.split('\n').length;
  var ambiguous = 0;
  var foundButNotUnique = 0;
  for (final search in _editSearchCandidates(existing, oldString)) {
    if (search.isEmpty) continue;
    final first = existing.indexOf(search);
    if (first < 0) continue;
    ambiguous++;
    if (!replaceAll && first != existing.lastIndexOf(search)) {
      foundButNotUnique++;
    }
  }
  final payload = <String, dynamic>{
    'path': filePath,
    'replaceAll': replaceAll,
    'argKeys': rawArgs.keys.toList(),
    'oldStringChars': oldString.length,
    'oldStringUtf8Bytes': utf8.encode(oldString).length,
    'oldStringLines': oldLines.length,
    'newStringChars': newString.length,
    'oldStringPreview':
        _editDebugEscapedPreview(oldString, _kEditMismatchLogPreviewChars),
    'newStringPreview':
        _editDebugEscapedPreview(newString, _kEditMismatchLogPreviewChars ~/ 2),
    'fileChars': existing.length,
    'fileLines': fileLines,
    'exactSubstringMatch': existing.contains(oldString),
    'oldStringLeadingRunes': oldString.runes.take(32).toList(),
    'candidatesWithAnyIndexMatch': ambiguous,
    'candidatesNonUniqueWithoutReplaceAll': foundButNotUnique,
  };
  // ignore: avoid_print
  print('[mag-edit][mismatch] ${jsonEncode(payload)}');
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

String _editOldStringNotFoundHint(String filePath) =>
    'oldString not found in $filePath. '
    'If you edited this file earlier in the same task, call `read` on the file again first and use the latest contents. '
    'Then copy the exact text from `read` output (without the `read` line-number prefixes). '
    'The tool also accepts: per-line trim match, common-indent stripped match, and '
    'CRLF/LF between lines for multi-line spans. '
    'Check console for a line starting with [mag-edit][mismatch] for argument details.';

/// Split [s] on logical newlines for flexible matching between lines.
String _editNormalizeNewlines(String s) =>
    s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

List<String> _editLogicalLinesNoTrailingBlank(String s) {
  var lines = _editNormalizeNewlines(s).split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines = lines.sublist(0, lines.length - 1);
  }
  return lines;
}

/// Strips the minimum leading whitespace shared by all non-empty lines (OpenCode-style).
String _editStripCommonIndent(String text) {
  final lines = text.split('\n');
  final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();
  if (nonEmpty.isEmpty) return text;
  var minIndent = nonEmpty
      .map((l) => RegExp(r'^(\s*)').firstMatch(l)!.group(1)!.length)
      .reduce((a, b) => a < b ? a : b);
  return lines.map((l) {
    if (l.trim().isEmpty) return l;
    if (l.length >= minIndent) return l.substring(minIndent);
    return l;
  }).join('\n');
}

String _editUnescapeForMatch(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) != 0x5C || i + 1 >= s.length) {
      b.writeCharCode(s.codeUnitAt(i));
      continue;
    }
    i++;
    final c = s[i];
    if (c == 'n') {
      b.write('\n');
    } else if (c == 't') {
      b.write('\t');
    } else if (c == 'r') {
      b.write('\r');
    } else if (c == r'\') {
      b.write(r'\');
    } else if (c == "'") {
      b.write("'");
    } else if (c == '"') {
      b.write('"');
    } else {
      b.write(r'\');
      b.write(c);
    }
  }
  return b.toString();
}

/// Substrings of [content] that line-up with [find] when each line is `.trim()` equal.
Iterable<String> _editLineTrimmedMatchSubstrings(
    String content, String find) sync* {
  final searchLines = _editLogicalLinesNoTrailingBlank(find);
  if (searchLines.isEmpty) return;

  final originalLines = content.split('\n');
  for (var i = 0; i <= originalLines.length - searchLines.length; i++) {
    var ok = true;
    for (var j = 0; j < searchLines.length; j++) {
      if (originalLines[i + j].trim() != searchLines[j].trim()) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    var start = 0;
    for (var k = 0; k < i; k++) {
      start += originalLines[k].length + 1;
    }
    var end = start;
    for (var k = 0; k < searchLines.length; k++) {
      end += originalLines[i + k].length;
      if (k < searchLines.length - 1) end += 1;
    }
    yield content.substring(start, end);
  }
}

Iterable<String> _editTrimmedBoundaryMatchSubstrings(
    String content, String find) sync* {
  final trimmedFind = find.trim();
  if (trimmedFind.isEmpty || trimmedFind == find) return;
  if (content.contains(trimmedFind)) yield trimmedFind;

  final findLines = _editLogicalLinesNoTrailingBlank(find);
  if (findLines.isEmpty) return;

  final originalLines = content.split('\n');
  for (var i = 0; i <= originalLines.length - findLines.length; i++) {
    final block = originalLines.sublist(i, i + findLines.length).join('\n');
    if (block.trim() == trimmedFind) {
      yield block;
    }
  }
}

Iterable<String> _editIndentFlexibleMatchSubstrings(
    String content, String find) sync* {
  final want = _editStripCommonIndent(_editNormalizeNewlines(find));
  final findLines = _editLogicalLinesNoTrailingBlank(find);
  if (findLines.isEmpty) return;

  final originalLines = content.split('\n');
  for (var i = 0; i <= originalLines.length - findLines.length; i++) {
    final block = originalLines.sublist(i, i + findLines.length).join('\n');
    if (_editStripCommonIndent(block) == want) {
      yield block;
    }
  }
}

Iterable<String> _editNewlineFlexibleMatchSubstrings(
    String content, String find) sync* {
  final lines = _editLogicalLinesNoTrailingBlank(find);
  if (lines.length < 2) return;
  const sep = r'(?:\r\n|\r|\n)';
  final pattern = lines.map(RegExp.escape).join(sep);
  final re = RegExp(pattern);
  for (final m in re.allMatches(content)) {
    yield m.group(0)!;
  }
}

Iterable<String> _editEscapeNormalizedMatchSubstrings(
    String content, String find) sync* {
  final u = _editUnescapeForMatch(find);
  if (u != find && content.contains(u)) yield u;
}

/// Ordered search strategies (mirrors OpenCode `edit` tool loosely).
Iterable<String> _editSearchCandidates(String content, String find) sync* {
  yield find;
  yield* _editNewlineFlexibleMatchSubstrings(content, find);
  yield* _editLineTrimmedMatchSubstrings(content, find);
  yield* _editTrimmedBoundaryMatchSubstrings(content, find);
  yield* _editIndentFlexibleMatchSubstrings(content, find);
  yield* _editEscapeNormalizedMatchSubstrings(content, find);
}

String _performEditReplacement({
  required String filePath,
  required String existing,
  required String oldString,
  required String newString,
  required bool replaceAll,
  Map<String, dynamic>? mismatchLogArgs,
}) {
  if (oldString == newString) {
    throw Exception(
      'No changes to apply: oldString and newString are identical.',
    );
  }
  for (final search in _editSearchCandidates(existing, oldString)) {
    if (search.isEmpty) continue;
    final first = existing.indexOf(search);
    if (first < 0) continue;
    if (replaceAll) {
      return existing.replaceAll(search, newString);
    }
    final last = existing.lastIndexOf(search);
    if (first != last) {
      continue;
    }
    return existing.replaceRange(first, first + search.length, newString);
  }
  if (mismatchLogArgs != null) {
    _logEditToolMismatch(
      filePath: filePath,
      rawArgs: mismatchLogArgs,
      oldString: oldString,
      newString: newString,
      replaceAll: replaceAll,
      existing: existing,
    );
  }
  throw Exception(_editOldStringNotFoundHint(filePath));
}

Future<ToolExecutionResult> _editTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  if (args.containsKey('edits') ||
      args['delete'] == true ||
      args['rename'] != null) {
    return _executeHashlineEditTool(args, ctx);
  }
  final filePath = _toolFilePathArg(args);
  final oldString = args['oldString'] as String? ?? '';
  final newString = args['newString'] as String? ?? '';
  final replaceAll = (args['replaceAll'] as bool?) ?? false;
  // ignore: avoid_print
  print('[mag-edit][start] ${jsonEncode({
    'path': filePath,
    'argKeys': args.keys.toList(),
    'oldStringChars': oldString.length,
    'newStringChars': newString.length,
    'replaceAll': replaceAll,
  })}');
  if (filePath.isEmpty) {
    throw Exception('Missing required `path`.');
  }
  if (oldString.isEmpty) {
    throw Exception(
      'oldString must not be empty. Use `write` or `apply_patch` to replace entire file content.',
    );
  }
  await _assertFreshReadForExistingFile(
    ctx,
    filePath,
    toolName: 'edit',
  );
  // ignore: avoid_print
  print('[mag-edit][fresh-read-ok] ${jsonEncode({
    'path': filePath,
    'sessionId': ctx.session.id,
  })}');
  final existingRaw = await ctx.bridge.readText(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  var utf8Bom = '';
  var existing = existingRaw;
  if (existingRaw.startsWith('\uFEFF')) {
    utf8Bom = '\uFEFF';
    existing = existingRaw.substring(1);
  }
  var oldForMatch = oldString;
  if (oldForMatch.startsWith('\uFEFF')) {
    oldForMatch = oldForMatch.substring(1);
  }
  final updated = _performEditReplacement(
    filePath: filePath,
    existing: existing,
    oldString: oldForMatch,
    newString: newString,
    replaceAll: replaceAll,
    mismatchLogArgs: Map<String, dynamic>.from(args),
  );
  final out = utf8Bom + updated;
  // ignore: avoid_print
  print('[mag-edit][replacement-ok] ${jsonEncode({
    'path': filePath,
    'beforeChars': existingRaw.length,
    'afterChars': out.length,
  })}');
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
        'preview': _buildDiffAttachment(
          kind: 'edit',
          path: filePath,
          before: existingRaw,
          after: out,
        ),
      },
      always: [filePath],
      messageId: ctx.message.id,
      callId: newId('call'),
    ),
  );
  await ctx.bridge.writeText(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
    content: out,
  );
  final updatedEntry = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  return ToolExecutionResult(
    title: filePath,
    output: 'Updated file successfully.',
    displayOutput: 'Updated $filePath',
    metadata: {
      'path': filePath,
      'filepath': filePath,
      'diagnostics': const <String, dynamic>{},
      if (updatedEntry != null)
        'readLedger': _toolReadLedgerMetadata(
          path: filePath,
          lastModified: updatedEntry.lastModified,
        ),
    },
    attachments: [
      _buildDiffAttachment(
        kind: 'edit',
        path: filePath,
        before: existingRaw,
        after: out,
      ),
    ],
  );
}
