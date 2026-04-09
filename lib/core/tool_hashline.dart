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

String _computeHashlineHash(int lineNumber, String content) {
  final normalized = content.replaceAll('\r', '').trimRight();
  final hasSignificant =
      RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(normalized);
  final seed = hasSignificant ? '0' : lineNumber.toString();
  final digest =
      sha1.convert(utf8.encode('$seed:$normalized')).bytes.first & 0xff;
  final first = _kHashlineAlphabet[(digest >> 4) & 0x0f];
  final second = _kHashlineAlphabet[digest & 0x0f];
  return '$first$second';
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

void _validateHashlineRefs(List<String> lines, Iterable<String> refs) {
  final mismatches = <int>[];
  for (final ref in refs) {
    final parsed = _parseHashlineRef(ref);
    if (parsed.line < 1 || parsed.line > lines.length) {
      throw Exception(
        'Line number ${parsed.line} out of bounds. File has ${lines.length} lines.',
      );
    }
    final content = lines[parsed.line - 1];
    final actual = _computeHashlineHash(parsed.line, content);
    if (actual != parsed.hash) {
      mismatches.add(parsed.line);
    }
  }
  if (mismatches.isNotEmpty) {
    throw _HashlineMismatchException(
      _formatHashlineMismatchMessage(mismatches, lines),
    );
  }
}

List<String> _hashlineToLines(Object? raw) {
  if (raw == null) return const <String>[];
  if (raw is String) return raw.split('\n');
  if (raw is List) return raw.map((item) => item.toString()).toList();
  throw Exception('Hashline edit `lines` must be a string, string[], or null.');
}

List<String> _normalizeInsertedHashlineLines(List<String> lines) {
  final normalized = <String>[];
  for (final line in lines) {
    var next = line;
    next = next.replaceFirst(RegExp(r'^(?:>>>|[+-])\s*'), '');
    next = next.replaceFirst(RegExp(r'^[0-9]+#[ZPMQVRWSNKTXJBYH]{2}\|'), '');
    normalized.add(next);
  }
  return normalized;
}

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
  final insertion = edit.lines ?? const <String>[];
  if (insertion.isEmpty) {
    throw Exception('append requires non-empty lines.');
  }
  if (edit.pos == null) {
    return [...lines, ...insertion];
  }
  final line = _parseHashlineRef(edit.pos!).line;
  final next = List<String>.of(lines);
  next.insertAll(line, insertion);
  return next;
}

List<String> _applyHashlinePrepend(
  List<String> lines,
  _HashlineEditOp edit,
) {
  final insertion = edit.lines ?? const <String>[];
  if (insertion.isEmpty) {
    throw Exception('prepend requires non-empty lines.');
  }
  if (edit.pos == null) {
    return [...insertion, ...lines];
  }
  final line = _parseHashlineRef(edit.pos!).line;
  final next = List<String>.of(lines);
  next.insertAll(line - 1, insertion);
  return next;
}

List<String> _applyHashlineEditsToLines(
  List<String> originalLines,
  List<_HashlineEditOp> edits,
) {
  final refs = <String>[];
  for (final edit in edits) {
    if (edit.pos != null) refs.add(edit.pos!);
    if (edit.end != null) refs.add(edit.end!);
  }
  if (refs.isNotEmpty) {
    _validateHashlineRefs(originalLines, refs);
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
  return lines;
}

Future<ToolExecutionResult> _executeHashlineEditTool(
  JsonMap args,
  ToolRuntimeContext ctx,
) async {
  final filePath = _toolFilePathArg(args);
  if (filePath.isEmpty) {
    throw Exception('Missing required `path`.');
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
  lines = _applyHashlineEditsToLines(lines, edits);
  final updatedCanonical = lines.join('\n');
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
  return ToolExecutionResult(
    title: targetPath,
    output: targetPath == filePath
        ? 'Updated file successfully.'
        : 'Moved file successfully.',
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
