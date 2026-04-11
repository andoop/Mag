part of 'tool_runtime.dart';

const String _kHashlineAlphabet = 'ZPMQVRWSNKTXJBYH';

final RegExp _kHashlineRefPattern =
    RegExp(r'^([0-9]+)#([ZPMQVRWSNKTXJBYH]{2})$');
final RegExp _kHashlineRefExtractPattern =
    RegExp(r'([0-9]+#[ZPMQVRWSNKTXJBYH]{2})');

class _HashlineLineRef {
  _HashlineLineRef({
    required this.line,
    required this.hash,
  });

  final int line;
  final String hash;
}

class _HashlineFileEnvelope {
  _HashlineFileEnvelope({
    required this.content,
    required this.hadBom,
    required this.lineEnding,
  });

  final String content;
  final bool hadBom;
  final String lineEnding;
}

class _HashlineEditOp {
  _HashlineEditOp({
    required this.op,
    this.pos,
    this.end,
    required this.lines,
  });

  final String op;
  final String? pos;
  final String? end;
  final List<String>? lines;
}

class _HashlineMismatchException implements Exception {
  _HashlineMismatchException(this.message);

  final String message;

  @override
  String toString() => message;
}

String _normalizeForHash(String content) {
  var s = content.replaceAll('\r', '').trimRight();
  if (s.startsWith('\uFEFF')) s = s.substring(1);
  return s;
}

String _computeHashlineHash(int lineNumber, String content) {
  final normalized = _normalizeForHash(content);
  final hasSignificant =
      RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(normalized);
  final seed = hasSignificant ? '0' : lineNumber.toString();
  final digest =
      sha1.convert(utf8.encode('$seed:$normalized')).bytes.first & 0xff;
  final first = _kHashlineAlphabet[(digest >> 4) & 0x0f];
  final second = _kHashlineAlphabet[digest & 0x0f];
  return '$first$second';
}

/// Legacy hash: strips ALL whitespace before hashing (like oh-my-openagent).
/// Provides a fallback when minor whitespace differences cause primary hash
/// mismatches, or when the hash algorithm changes.
String _computeLegacyHashlineHash(int lineNumber, String content) {
  var s = content.replaceAll('\r', '');
  if (s.startsWith('\uFEFF')) s = s.substring(1);
  s = s.replaceAll(RegExp(r'\s+'), '');
  final hasSignificant =
      RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s);
  final seed = hasSignificant ? '0' : lineNumber.toString();
  final digest =
      sha1.convert(utf8.encode('$seed:$s')).bytes.first & 0xff;
  final first = _kHashlineAlphabet[(digest >> 4) & 0x0f];
  final second = _kHashlineAlphabet[digest & 0x0f];
  return '$first$second';
}

bool _isCompatibleHashlineHash(int lineNumber, String content, String hash) {
  return _computeHashlineHash(lineNumber, content) == hash ||
      _computeLegacyHashlineHash(lineNumber, content) == hash;
}

String _formatHashlineReadLine(
  int lineNumber,
  String content, {
  required bool truncated,
}) {
  if (truncated) {
    return '$lineNumber: $content';
  }
  return '$lineNumber#${_computeHashlineHash(lineNumber, content)}|$content';
}

String _detectHashlineLineEnding(String content) {
  final crlfIndex = content.indexOf('\r\n');
  final lfIndex = content.indexOf('\n');
  if (lfIndex == -1) return '\n';
  if (crlfIndex == -1) return '\n';
  return crlfIndex < lfIndex ? '\r\n' : '\n';
}

_HashlineFileEnvelope _canonicalizeHashlineFileText(String content) {
  final hadBom = content.startsWith('\uFEFF');
  final withoutBom = hadBom ? content.substring(1) : content;
  return _HashlineFileEnvelope(
    content: withoutBom.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
    hadBom: hadBom,
    lineEnding: _detectHashlineLineEnding(withoutBom),
  );
}

String _restoreHashlineFileText(
    String content, _HashlineFileEnvelope envelope) {
  final restored = envelope.lineEnding == '\r\n'
      ? content.replaceAll('\n', '\r\n')
      : content;
  return envelope.hadBom ? '\uFEFF$restored' : restored;
}

String _normalizeHashlineRef(String ref) {
  final originalTrimmed = ref.trim();
  var trimmed = originalTrimmed;
  trimmed = trimmed.replaceFirst(RegExp(r'^(?:>>>|[+-])\s*'), '');
  trimmed = trimmed.replaceAll(RegExp(r'\s*#\s*'), '#');
  trimmed = trimmed.replaceFirst(RegExp(r'\|.*$'), '');
  trimmed = trimmed.trim();
  if (_kHashlineRefPattern.hasMatch(trimmed)) {
    return trimmed;
  }
  final extracted = _kHashlineRefExtractPattern.firstMatch(trimmed);
  if (extracted != null) {
    return extracted.group(1) ?? originalTrimmed;
  }
  return originalTrimmed;
}

_HashlineLineRef _parseHashlineRef(String ref) {
  final normalized = _normalizeHashlineRef(ref);
  final match = _kHashlineRefPattern.firstMatch(normalized);
  if (match == null) {
    throw Exception(
      'Invalid line reference format: "$ref". Expected "{line_number}#{hash_id}".',
    );
  }
  return _HashlineLineRef(
    line: int.parse(match.group(1)!),
    hash: match.group(2)!,
  );
}

String _formatHashlineMismatchMessage(
  List<int> mismatchLines,
  List<String> fileLines,
) {
  const mismatchContext = 2;
  final displayLines = <int>{};
  for (final line in mismatchLines) {
    final low = line - mismatchContext < 1 ? 1 : line - mismatchContext;
    final high = line + mismatchContext > fileLines.length
        ? fileLines.length
        : line + mismatchContext;
    for (var current = low; current <= high; current++) {
      displayLines.add(current);
    }
  }
  final sorted = displayLines.toList()..sort();
  final out = <String>[
    '${mismatchLines.length} line${mismatchLines.length > 1 ? "s have" : " has"} changed since last read. '
        'Use updated {line_number}#{hash_id} references below (>>> marks changed lines).',
    '',
  ];
  var previous = -1;
  for (final line in sorted) {
    if (previous != -1 && line > previous + 1) {
      out.add('    ...');
    }
    previous = line;
    final content = fileLines[line - 1];
    final formatted = '$line#${_computeHashlineHash(line, content)}|$content';
    out.add(mismatchLines.contains(line) ? '>>> $formatted' : '    $formatted');
  }
  return out.join('\n');
}

String? _suggestLineForHash(String ref, List<String> lines) {
  final hashMatch = RegExp(r'#([ZPMQVRWSNKTXJBYH]{2})$').firstMatch(ref.trim());
  if (hashMatch == null) return null;
  final hash = hashMatch.group(1)!;
  for (var i = 0; i < lines.length; i++) {
    if (_isCompatibleHashlineHash(i + 1, lines[i], hash)) {
      final actual = _computeHashlineHash(i + 1, lines[i]);
      return 'Did you mean "${i + 1}#$actual"?';
    }
  }
  return null;
}

_HashlineLineRef _parseHashlineRefWithHint(String ref, List<String> lines) {
  try {
    return _parseHashlineRef(ref);
  } on Exception catch (e) {
    final hint = _suggestLineForHash(ref, lines);
    if (hint != null) {
      throw Exception('${e.toString()} $hint');
    }
    rethrow;
  }
}

/// Returns a warning string if [lenient] is true and mismatches were found,
/// or throws [_HashlineMismatchException] if not lenient.
/// Returns empty string when all refs match.
String _validateHashlineRefs(
  List<String> lines,
  Iterable<String> refs, {
  bool lenient = false,
}) {
  final mismatches = <int>[];
  for (final ref in refs) {
    final parsed = _parseHashlineRefWithHint(ref, lines);
    if (parsed.line < 1 || parsed.line > lines.length) {
      final hint = _suggestLineForHash(ref, lines);
      throw Exception(
        'Line number ${parsed.line} out of bounds. File has ${lines.length} lines.'
        '${hint != null ? ' $hint' : ''}',
      );
    }
    final content = lines[parsed.line - 1];
    if (!_isCompatibleHashlineHash(parsed.line, content, parsed.hash)) {
      mismatches.add(parsed.line);
    }
  }
  if (mismatches.isEmpty) return '';
  if (lenient) {
    return 'WARNING: ${mismatches.length} hash mismatch(es) on line(s) '
        '${mismatches.join(', ')} — file is unchanged since your last read, '
        'proceeding with line numbers. Please copy exact LINE#HASH references '
        'from `read` output next time.';
  }
  throw _HashlineMismatchException(
    _formatHashlineMismatchMessage(mismatches, lines),
  );
}

List<String> _hashlineToLines(Object? raw) {
  if (raw == null) return const <String>[];
  if (raw is String) return raw.split('\n');
  if (raw is List) return raw.map((item) => item.toString()).toList();
  throw Exception('Hashline edit `lines` must be a string, string[], or null.');
}

/// Intelligent prefix stripping (ported from oh-my-openagent `stripLinePrefixes`).
/// Uses a statistical approach: only strip prefixes if ≥50% of non-empty lines
/// have the same prefix type, preventing false positives on normal code.
List<String> _normalizeInsertedHashlineLines(List<String> lines) {
  final hashRe = RegExp(r'^\s*(?:>>>|>>)?\s*\d+\s*#\s*[ZPMQVRWSNKTXJBYH]{2}\|');
  final diffPlusRe = RegExp(r'^[+](?![+])');
  var hashCount = 0;
  var diffPlusCount = 0;
  var nonEmpty = 0;
  for (final line in lines) {
    if (line.isEmpty) continue;
    nonEmpty++;
    if (hashRe.hasMatch(line)) hashCount++;
    if (diffPlusRe.hasMatch(line)) diffPlusCount++;
  }
  if (nonEmpty == 0) return lines;
  final stripHash = hashCount > 0 && hashCount >= nonEmpty * 0.5;
  final stripPlus = !stripHash && diffPlusCount > 0 && diffPlusCount >= nonEmpty * 0.5;
  return lines.map((line) {
    if (stripHash) return line.replaceFirst(hashRe, '');
    if (stripPlus) return line.replaceFirst(diffPlusRe, '');
    return line;
  }).toList();
}

// ---------------------------------------------------------------------------
// Echo stripping (ported from oh-my-openagent edit-text-normalization.ts)
// Models often accidentally echo anchor lines in their replacement text,
// causing duplicate lines (extra braces, duplicate statements, etc.)
// ---------------------------------------------------------------------------

bool _equalsIgnoringWhitespace(String a, String b) {
  if (a == b) return true;
  return a.replaceAll(RegExp(r'\s+'), '') == b.replaceAll(RegExp(r'\s+'), '');
}

/// Strip if first line of replacement matches the anchor line (append echo).
List<String> _stripInsertAnchorEcho(String anchorLine, List<String> newLines) {
  if (newLines.isEmpty) return newLines;
  if (_equalsIgnoringWhitespace(newLines[0], anchorLine)) {
    return newLines.sublist(1);
  }
  return newLines;
}

/// Strip if last line of replacement matches the anchor line (prepend echo).
List<String> _stripInsertBeforeEcho(String anchorLine, List<String> newLines) {
  if (newLines.length <= 1) return newLines;
  if (_equalsIgnoringWhitespace(newLines[newLines.length - 1], anchorLine)) {
    return newLines.sublist(0, newLines.length - 1);
  }
  return newLines;
}

/// Strip boundary echoes in range replacement (both start-1 and end+1).
List<String> _stripRangeBoundaryEcho(
  List<String> fileLines,
  int startLine,
  int endLine,
  List<String> newLines,
) {
  final replacedCount = endLine - startLine + 1;
  if (newLines.length <= 1 || newLines.length <= replacedCount) {
    return newLines;
  }
  var out = newLines;
  final beforeIdx = startLine - 2;
  if (beforeIdx >= 0 &&
      _equalsIgnoringWhitespace(out[0], fileLines[beforeIdx])) {
    out = out.sublist(1);
  }
  final afterIdx = endLine;
  if (afterIdx < fileLines.length &&
      out.isNotEmpty &&
      _equalsIgnoringWhitespace(out[out.length - 1], fileLines[afterIdx])) {
    out = out.sublist(0, out.length - 1);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Autocorrect replacement lines (ported from oh-my-openagent)
// Handles common model mistakes: line merging, indentation loss, etc.
// ---------------------------------------------------------------------------

/// When model merges multi-line code into single line, try to re-expand it.
List<String> _maybeExpandSingleLineMerge(
  List<String> originalLines,
  List<String> replacementLines,
) {
  if (replacementLines.length != 1 || originalLines.length <= 1) {
    return replacementLines;
  }
  final merged = replacementLines[0];
  final parts = originalLines
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (parts.length != originalLines.length) return replacementLines;

  final indices = <int>[];
  var offset = 0;
  var orderedMatch = true;
  for (final part in parts) {
    final idx = merged.indexOf(part, offset);
    if (idx == -1) {
      orderedMatch = false;
      break;
    }
    indices.add(idx);
    offset = idx + part.length;
  }
  if (orderedMatch && indices.length == parts.length) {
    final expanded = <String>[];
    for (var i = 0; i < indices.length; i++) {
      final start = indices[i];
      final end = i + 1 < indices.length ? indices[i + 1] : merged.length;
      final candidate = merged.substring(start, end).trim();
      if (candidate.isEmpty) {
        orderedMatch = false;
        break;
      }
      expanded.add(candidate);
    }
    if (orderedMatch && expanded.length == originalLines.length) {
      return expanded;
    }
  }
  return replacementLines;
}

/// When replacement has same number of lines, restore indentation from original.
List<String> _restoreIndentForPairedReplacement(
  List<String> originalLines,
  List<String> replacementLines,
) {
  if (originalLines.length != replacementLines.length) {
    return replacementLines;
  }
  return replacementLines.asMap().entries.map((entry) {
    final idx = entry.key;
    final line = entry.value;
    if (line.isEmpty) return line;
    if (RegExp(r'^\s').hasMatch(line)) return line;
    final indent =
        RegExp(r'^\s*').firstMatch(originalLines[idx])?.group(0) ?? '';
    if (indent.isEmpty) return line;
    if (originalLines[idx].trim() == line.trim()) return line;
    return '$indent$line';
  }).toList();
}

/// Full autocorrect pipeline for replacement lines.
List<String> _autocorrectReplacementLines(
  List<String> originalLines,
  List<String> replacementLines,
) {
  var next = replacementLines;
  next = _maybeExpandSingleLineMerge(originalLines, next);
  next = _restoreIndentForPairedReplacement(originalLines, next);
  return next;
}

/// Legacy indent restoration for first-line only (used when autocorrect
/// already handled paired lines).
List<String> _restoreLeadingIndentForHashline(
  List<String> originalLines,
  List<String> replacementLines,
) {
  if (originalLines.isEmpty || replacementLines.isEmpty) {
    return replacementLines;
  }
  return replacementLines.asMap().entries.map((entry) {
    final idx = entry.key;
    final line = entry.value;
    if (idx >= originalLines.length) return line;
    if (line.isEmpty || RegExp(r'^\s').hasMatch(line)) return line;
    final indent =
        RegExp(r'^\s*').firstMatch(originalLines[idx])?.group(0) ?? '';
    if (indent.isEmpty) return line;
    return '$indent$line';
  }).toList();
}

List<_HashlineEditOp> _normalizeHashlineEdits(List<dynamic> rawEdits) {
  return rawEdits.asMap().entries.map((entry) {
    final index = entry.key;
    final raw = Map<String, dynamic>.from(entry.value as Map);
    final op = (raw['op'] as String? ?? '').trim();
    if (!const {'replace', 'append', 'prepend'}.contains(op)) {
      throw Exception('Edit $index: unsupported op "$op".');
    }
    final pos = (raw['pos'] as String?)?.trim();
    final end = (raw['end'] as String?)?.trim();
    if (op == 'replace' &&
        (pos == null || pos.isEmpty) &&
        (end == null || end.isEmpty)) {
      throw Exception(
        'Edit $index: replace requires at least one anchor line reference.',
      );
    }
    final linesValue = raw.containsKey('lines') ? raw['lines'] : null;
    if ((op == 'append' || op == 'prepend') && linesValue == null) {
      throw Exception('Edit $index: $op requires non-empty lines.');
    }
    return _HashlineEditOp(
      op: op,
      pos: pos != null && pos.isNotEmpty ? pos : null,
      end: end != null && end.isNotEmpty ? end : null,
      lines: linesValue == null
          ? null
          : _normalizeInsertedHashlineLines(_hashlineToLines(linesValue)),
    );
  }).toList();
}

int _hashlineEditSortKey(_HashlineEditOp edit) {
  switch (edit.op) {
    case 'replace':
      return _parseHashlineRef(edit.end ?? edit.pos!).line;
    case 'append':
    case 'prepend':
      return edit.pos == null ? -1 : _parseHashlineRef(edit.pos!).line;
  }
  return -1;
}

void _detectHashlineOverlaps(List<_HashlineEditOp> edits) {
  final ranges = <Map<String, int>>[];
  for (var i = 0; i < edits.length; i++) {
    final edit = edits[i];
    if (edit.op != 'replace' || edit.end == null || edit.pos == null) continue;
    final start = _parseHashlineRef(edit.pos!).line;
    final end = _parseHashlineRef(edit.end!).line;
    ranges.add({'start': start, 'end': end, 'idx': i});
  }
  ranges.sort((a, b) {
    final startCompare = a['start']!.compareTo(b['start']!);
    if (startCompare != 0) return startCompare;
    return a['end']!.compareTo(b['end']!);
  });
  for (var i = 1; i < ranges.length; i++) {
    final prev = ranges[i - 1];
    final curr = ranges[i];
    if (curr['start']! <= prev['end']!) {
      throw Exception(
        'Overlapping range edits detected: edit ${prev['idx']! + 1} overlaps with edit ${curr['idx']! + 1}.',
      );
    }
  }
}

List<String> _applyHashlineReplace(
  List<String> lines,
  _HashlineEditOp edit,
) {
  final start = _parseHashlineRef(edit.pos!).line;
  final end = edit.end == null ? start : _parseHashlineRef(edit.end!).line;
  if (start > end) {
    throw Exception(
        'Invalid range: start line $start cannot be greater than end line $end.');
  }
  final originalRange = lines.sublist(start - 1, end);
  var replacement = edit.lines ?? const <String>[];
  // Strip boundary echoes (model often echoes surrounding lines)
  if (edit.end != null) {
    replacement = _stripRangeBoundaryEcho(lines, start, end, replacement);
  }
  // Autocorrect: expand merged lines, restore paired indentation
  replacement = _autocorrectReplacementLines(originalRange, replacement);
  // Fallback: restore leading indent line-by-line
  replacement = _restoreLeadingIndentForHashline(originalRange, replacement);
  final next = List<String>.of(lines);
  next.removeRange(start - 1, end);
  next.insertAll(start - 1, replacement);
  return next;
}

List<String> _applyHashlineAppend(
  List<String> lines,
  _HashlineEditOp edit,
) {
  var insertion = edit.lines ?? const <String>[];
  if (insertion.isEmpty) {
    throw Exception('append requires non-empty lines.');
  }
  if (edit.pos == null) {
    return [...lines, ...insertion];
  }
  final line = _parseHashlineRef(edit.pos!).line;
  // Strip echo: model often echoes the anchor line as first line of insertion
  insertion = _stripInsertAnchorEcho(lines[line - 1], insertion);
  if (insertion.isEmpty) {
    throw Exception('append produced empty lines after stripping anchor echo.');
  }
  final next = List<String>.of(lines);
  next.insertAll(line, insertion);
  return next;
}

List<String> _applyHashlinePrepend(
  List<String> lines,
  _HashlineEditOp edit,
) {
  var insertion = edit.lines ?? const <String>[];
  if (insertion.isEmpty) {
    throw Exception('prepend requires non-empty lines.');
  }
  if (edit.pos == null) {
    return [...insertion, ...lines];
  }
  final line = _parseHashlineRef(edit.pos!).line;
  // Strip echo: model often echoes the anchor line as last line of insertion
  insertion = _stripInsertBeforeEcho(lines[line - 1], insertion);
  if (insertion.isEmpty) {
    throw Exception('prepend produced empty lines after stripping anchor echo.');
  }
  final next = List<String>.of(lines);
  next.insertAll(line - 1, insertion);
  return next;
}

class _HashlineEditResult {
  _HashlineEditResult(this.lines, this.hashWarning);
  final List<String> lines;
  final String hashWarning;
}

_HashlineEditResult _applyHashlineEditsToLines(
  List<String> originalLines,
  List<_HashlineEditOp> edits, {
  bool lenient = false,
}) {
  final refs = <String>[];
  for (final edit in edits) {
    if (edit.pos != null) refs.add(edit.pos!);
    if (edit.end != null) refs.add(edit.end!);
  }
  var hashWarning = '';
  if (refs.isNotEmpty) {
    hashWarning = _validateHashlineRefs(originalLines, refs, lenient: lenient);
  }
  _detectHashlineOverlaps(edits);
  final sorted = List<_HashlineEditOp>.of(edits)
    ..sort((a, b) {
      final lineCompare =
          _hashlineEditSortKey(b).compareTo(_hashlineEditSortKey(a));
      if (lineCompare != 0) return lineCompare;
      const precedence = {'replace': 0, 'append': 1, 'prepend': 2};
      return (precedence[a.op] ?? 3).compareTo(precedence[b.op] ?? 3);
    });
  var lines = List<String>.of(originalLines);
  for (final edit in sorted) {
    switch (edit.op) {
      case 'replace':
        lines = _applyHashlineReplace(lines, edit);
        break;
      case 'append':
        lines = _applyHashlineAppend(lines, edit);
        break;
      case 'prepend':
        lines = _applyHashlinePrepend(lines, edit);
        break;
    }
  }
  return _HashlineEditResult(lines, hashWarning);
}

Future<ToolExecutionResult> _executeHashlineEditTool(
  JsonMap args,
  ToolRuntimeContext ctx,
) async {
  final filePath =
      _normalizeWorkspaceRelativePath(jsonStringCoerce(args['filePath'], ''));
  if (filePath.isEmpty) {
    throw Exception('Missing required `filePath`.');
  }
  final deleteMode = args['delete'] == true;
  final rename = (args['rename'] as String?)?.trim();
  final rawEdits = (args['edits'] as List?)?.toList() ?? const <dynamic>[];
  if (deleteMode && rename != null && rename.isNotEmpty) {
    throw Exception('delete and rename cannot be used together.');
  }
  if (deleteMode && rawEdits.isNotEmpty) {
    throw Exception('delete mode requires edits to be an empty array.');
  }
  final existingEntry = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  final exists = existingEntry != null && !existingEntry.isDirectory;
  if (deleteMode) {
    if (!exists) throw Exception('File not found: $filePath');
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
          'preview': {
            'type': 'diff_preview',
            'kind': 'delete',
            'path': filePath,
            'preview':
                '@@\n-${await ctx.bridge.readText(treeUri: ctx.workspace.treeUri, relativePath: filePath)}',
            'fullPreview':
                '@@\n-${await ctx.bridge.readText(treeUri: ctx.workspace.treeUri, relativePath: filePath)}',
            'additions': 0,
            'deletions': 1,
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
    return ToolExecutionResult(
      title: filePath,
      output: 'Deleted file successfully.',
      displayOutput: 'Deleted $filePath',
      metadata: {
        'path': filePath,
        'filepath': filePath,
      },
    );
  }
  if (rawEdits.isEmpty) {
    throw Exception('edits must be a non-empty array.');
  }
  final edits = _normalizeHashlineEdits(rawEdits);
  if (!exists) {
    final canCreate = edits.every(
      (edit) =>
          (edit.op == 'append' || edit.op == 'prepend') && edit.pos == null,
    );
    if (!canCreate) {
      throw Exception('File not found: $filePath');
    }
  }

  // Read ledger check: determine if file is unchanged since last read.
  // If unchanged, use lenient hash validation (model may corrupt hashes).
  var fileUnchangedSinceRead = false;
  if (exists) {
    final existingEntry2 = await ctx.bridge.stat(
      treeUri: ctx.workspace.treeUri,
      relativePath: filePath,
    );
    final ledger = await _latestToolReadLedgerForPath(ctx, filePath);
    if (ledger == null) {
      throw Exception(
        'BLOCKED: You must `read` the file "$filePath" before using `edit`.\n'
        'Required action: call `read` with path "$filePath" first, then retry.',
      );
    }
    if (existingEntry2 != null &&
        existingEntry2.lastModified <= ledger.lastModified) {
      fileUnchangedSinceRead = true;
    }
  }

  final existingRaw = exists
      ? await ctx.bridge.readText(
          treeUri: ctx.workspace.treeUri,
          relativePath: filePath,
        )
      : '';
  final envelope = _canonicalizeHashlineFileText(existingRaw);
  final originalContent = envelope.content;
  var lines =
      originalContent.isEmpty ? <String>[] : originalContent.split('\n');
  // strip trailing empty element that split('\n') produces for files ending
  // with '\n', so line numbering matches LineSplitter used in _readTool.
  final hadTrailingNewline =
      lines.isNotEmpty && lines.last.isEmpty && originalContent.endsWith('\n');
  if (hadTrailingNewline) lines.removeLast();
  final editResult = _applyHashlineEditsToLines(
    lines,
    edits,
    lenient: fileUnchangedSinceRead,
  );
  lines = editResult.lines;
  final hashWarning = editResult.hashWarning;
  var updatedCanonical = lines.join('\n');
  if (hadTrailingNewline) updatedCanonical += '\n';
  if (updatedCanonical == originalContent &&
      (rename == null || rename == filePath)) {
    throw Exception(
        'No changes made to $filePath. The edits produced identical content.');
  }
  final restored = _restoreHashlineFileText(updatedCanonical, envelope);
  final targetPath = rename != null && rename.isNotEmpty
      ? _normalizeWorkspaceRelativePath(rename)
      : filePath;
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'edit',
      patterns: [targetPath],
      metadata: {
        'tool': 'edit',
        'path': filePath,
        'filePath': filePath,
        'newPath': targetPath == filePath ? null : targetPath,
        'preview': _buildDiffAttachment(
          kind: targetPath == filePath ? 'edit' : 'move',
          path: targetPath,
          before: existingRaw,
          after: restored,
          sourcePath: targetPath == filePath ? null : filePath,
        ),
      },
      always: [targetPath],
      messageId: ctx.message.id,
      callId: newId('call'),
    ),
  );
  await ctx.bridge.writeText(
    treeUri: ctx.workspace.treeUri,
    relativePath: targetPath,
    content: restored,
  );
  if (targetPath != filePath && exists) {
    await ctx.bridge.deleteEntry(
      treeUri: ctx.workspace.treeUri,
      relativePath: filePath,
    );
  }
  final updatedEntry = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: targetPath,
  );
  var output = targetPath == filePath
      ? 'Updated file successfully.'
      : 'Moved file successfully.';
  if (hashWarning.isNotEmpty) {
    output += '\n\n<hash-warning>\n$hashWarning\n</hash-warning>';
  }
  final bracketWarning = _checkBracketBalance(restored, targetPath);
  if (bracketWarning.isNotEmpty) {
    output += '\n\n<diagnostics file="$targetPath">\n$bracketWarning\nPlease review and fix the bracket issue.\n</diagnostics>';
  }
  return ToolExecutionResult(
    title: targetPath,
    output: output,
    displayOutput: targetPath == filePath
        ? 'Updated $targetPath'
        : 'Moved $filePath → $targetPath',
    metadata: {
      'path': targetPath,
      'filepath': targetPath,
      'diagnostics': const <String, dynamic>{},
      if (updatedEntry != null)
        'readLedger': _toolReadLedgerMetadata(
          path: targetPath,
          lastModified: updatedEntry.lastModified,
        ),
    },
    attachments: [
      _buildDiffAttachment(
        kind: targetPath == filePath ? 'edit' : 'move',
        path: targetPath,
        before: existingRaw,
        after: restored,
        sourcePath: targetPath == filePath ? null : filePath,
      ),
    ],
  );
}
