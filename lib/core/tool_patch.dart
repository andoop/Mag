part of 'tool_runtime.dart';

Future<ToolExecutionResult> _applyPatchTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final patchText = args['patchText'] as String? ?? '';
  final rawArgs = Map<String, dynamic>.from(args);
  List<_PatchSection> sections;
  try {
    sections = _parsePatchSections(patchText);
  } catch (e) {
    _logApplyPatchToolFailure(
      phase: 'parse',
      error: e.toString(),
      patchText: patchText,
      rawArgs: rawArgs,
    );
    rethrow;
  }
  if (sections.isEmpty) {
    final normalized = _normalizePatchText(patchText).trim();
    if (normalized == '*** Begin Patch\n*** End Patch') {
      _logApplyPatchToolFailure(
        phase: 'parse_empty',
        error: 'patch rejected: empty patch',
        patchText: patchText,
        rawArgs: rawArgs,
      );
      throw Exception('patch rejected: empty patch');
    }
    _logApplyPatchToolFailure(
      phase: 'parse_empty',
      error: 'apply_patch verification failed: no hunks found',
      patchText: patchText,
      rawArgs: rawArgs,
    );
    throw Exception('apply_patch verification failed: no hunks found');
  }
  final planned = <_PatchPlannedChange>[];
  for (var sectionIdx = 0; sectionIdx < sections.length; sectionIdx++) {
    final section = sections[sectionIdx];
    var existing = '';
    var after = '';
    var previewKind = section.kind.name;
    try {
      if (section.kind == _PatchSectionKind.add) {
        after = section.contents;
        if (after.isEmpty || !after.endsWith('\n')) {
          after = '$after\n';
        }
      } else if (section.kind == _PatchSectionKind.delete) {
        await _assertFreshReadForExistingFile(
          ctx,
          section.path,
          toolName: 'apply_patch',
        );
        existing = await ctx.bridge.readText(
          treeUri: ctx.workspace.treeUri,
          relativePath: section.path,
        );
      } else {
        await _assertFreshReadForExistingFile(
          ctx,
          section.path,
          toolName: 'apply_patch',
        );
        existing = await ctx.bridge.readText(
          treeUri: ctx.workspace.treeUri,
          relativePath: section.path,
        );
        after = _deriveNewContentsFromChunks(
          filePath: section.path,
          existing: existing,
          chunks: section.chunks,
        );
        if (section.movePath != null) {
          previewKind = 'move';
        } else {
          previewKind = 'update';
        }
      }
      final targetPath = section.movePath ?? section.path;
      planned.add(
        _PatchPlannedChange(
          kind: previewKind,
          sourcePath: section.path,
          targetPath: targetPath,
          before: existing,
          after: after,
        ),
      );
    } catch (e) {
      var snap = existing;
      if (snap.isEmpty && section.kind != _PatchSectionKind.add) {
        try {
          snap = await ctx.bridge.readText(
            treeUri: ctx.workspace.treeUri,
            relativePath: section.path,
          );
        } catch (_) {}
      }
      _logApplyPatchToolFailure(
        phase: 'section',
        error: e.toString(),
        patchText: patchText,
        rawArgs: rawArgs,
        sectionIndex: sectionIdx,
        sectionPath: section.path,
        sectionKind: section.kind.name,
        movePath: section.movePath,
        sectionLineCount: _patchSectionDebugLines(section).length,
        sectionLinesHead: _patchSectionDebugLines(section)
            .take(_kApplyPatchLogSectionLines)
            .map((l) => l.length > 320
                ? '${l.substring(0, 320)}…(${l.length} chars)'
                : l)
            .toList(),
        existingChars: snap.length,
        existingLines:
            snap.isEmpty ? null : const LineSplitter().convert(snap).length,
      );
      rethrow;
    }
  }
  final attachments = planned
      .map((change) => _buildDiffAttachment(
            kind: change.kind,
            path: change.targetPath,
            before: change.before,
            after: change.after,
            sourcePath: change.kind == 'move' ? change.sourcePath : null,
          ))
      .toList();
  final targetPaths = planned.map((item) => item.targetPath).toSet().toList();
  await ctx.updateToolProgress(
    title: targetPaths.length == 1 ? targetPaths.first : 'Apply Patch',
    displayOutput: targetPaths.isEmpty
        ? 'Preparing patch'
        : 'Preparing patch for ${targetPaths.length} file(s)',
    metadata: {
      'phase': 'preparing',
      'files': targetPaths,
    },
    attachments: attachments,
  );
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'edit',
      patterns: targetPaths,
      metadata: {
        'tool': 'apply_patch',
        'filePath': targetPaths.join(', '),
        'files': attachments,
      },
      always: targetPaths,
      messageId: ctx.message.id,
      callId: newId('call'),
    ),
  );
  final changedFiles = <String>[];
  final readLedgers = <JsonMap>[];
  for (final change in planned) {
    if (change.kind == 'delete') {
      await ctx.bridge.deleteEntry(
        treeUri: ctx.workspace.treeUri,
        relativePath: change.sourcePath,
      );
      changedFiles.add(change.sourcePath);
      continue;
    }
    await ctx.bridge.writeText(
      treeUri: ctx.workspace.treeUri,
      relativePath: change.targetPath,
      content: change.after,
    );
    final updatedEntry = await ctx.bridge.stat(
      treeUri: ctx.workspace.treeUri,
      relativePath: change.targetPath,
    );
    if (updatedEntry != null) {
      readLedgers.add(
        _toolReadLedgerMetadata(
          path: change.targetPath,
          lastModified: updatedEntry.lastModified,
          sourceTool: 'apply_patch',
        ),
      );
    }
    changedFiles.add(change.targetPath);
    if (change.kind == 'move') {
      await ctx.bridge.deleteEntry(
        treeUri: ctx.workspace.treeUri,
        relativePath: change.sourcePath,
      );
    }
  }
  return ToolExecutionResult(
    title: 'Apply Patch',
    output: 'Applied patch successfully.',
    displayOutput: changedFiles.isEmpty
        ? 'Applied patch'
        : 'Applied patch · ${changedFiles.length} file(s)',
    metadata: {
      'files': changedFiles,
      'readLedgers': readLedgers,
    },
    attachments: attachments,
  );
}

class _PatchSection {
  _PatchSection({
    required this.kind,
    required this.path,
    this.contents = '',
    this.chunks = const [],
    this.movePath,
  });

  final _PatchSectionKind kind;
  final String path;
  final String contents;
  final List<_PatchUpdateChunk> chunks;
  final String? movePath;
}

class _PatchSectionHeader {
  _PatchSectionHeader({
    required this.path,
    required this.nextIdx,
    this.movePath,
  });

  final String path;
  final int nextIdx;
  final String? movePath;
}

class _PatchAddParseResult {
  _PatchAddParseResult({
    required this.content,
    required this.nextIdx,
  });

  final String content;
  final int nextIdx;
}

class _PatchUpdateChunk {
  _PatchUpdateChunk({
    required this.oldLines,
    required this.newLines,
    this.changeContext,
    this.isEndOfFile = false,
  });

  final List<String> oldLines;
  final List<String> newLines;
  final String? changeContext;
  final bool isEndOfFile;
}

class _PatchChunkParseResult {
  _PatchChunkParseResult({
    required this.chunks,
    required this.nextIdx,
  });

  final List<_PatchUpdateChunk> chunks;
  final int nextIdx;
}

class _PatchReplacement {
  _PatchReplacement({
    required this.startIdx,
    required this.oldLength,
    required this.newSegment,
  });

  final int startIdx;
  final int oldLength;
  final List<String> newSegment;
}

class _PatchPlannedChange {
  _PatchPlannedChange({
    required this.kind,
    required this.sourcePath,
    required this.targetPath,
    required this.before,
    required this.after,
  });

  final String kind;
  final String sourcePath;
  final String targetPath;
  final String before;
  final String after;
}

enum _PatchSectionKind { add, update, delete }

String _normalizePatchHeaderPath(String raw) {
  final out = _normalizeWorkspaceRelativePath(raw);
  if (out.isEmpty) {
    throw Exception(
      'apply_patch: file path in patch header cannot be empty or only "."',
    );
  }
  return out;
}

String _normalizePatchText(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _stripPatchHeredoc(String input) {
  final match = RegExp(
    r'''^(?:cat\s+)?<<['"]?(\w+)['"]?\s*\n([\s\S]*?)\n\1\s*$''',
    multiLine: true,
  ).firstMatch(input);
  if (match == null) return input;
  return match.group(2) ?? input;
}

_PatchSectionHeader? _parsePatchHeader(List<String> lines, int startIdx) {
  final line = lines[startIdx];
  if (line.startsWith('*** Add File:')) {
    final filePath = _normalizePatchHeaderPath(
        line.substring('*** Add File:'.length).trim());
    return _PatchSectionHeader(path: filePath, nextIdx: startIdx + 1);
  }
  if (line.startsWith('*** Delete File:')) {
    final filePath = _normalizePatchHeaderPath(
        line.substring('*** Delete File:'.length).trim());
    return _PatchSectionHeader(path: filePath, nextIdx: startIdx + 1);
  }
  if (line.startsWith('*** Update File:')) {
    final filePath = _normalizePatchHeaderPath(
        line.substring('*** Update File:'.length).trim());
    var nextIdx = startIdx + 1;
    String? movePath;
    if (nextIdx < lines.length && lines[nextIdx].startsWith('*** Move to:')) {
      movePath = _normalizePatchHeaderPath(
          lines[nextIdx].substring('*** Move to:'.length).trim());
      nextIdx += 1;
    }
    return _PatchSectionHeader(
      path: filePath,
      movePath: movePath,
      nextIdx: nextIdx,
    );
  }
  return null;
}

_PatchAddParseResult _parseAddFileContent(
  List<String> lines,
  int startIdx,
  int endIdx,
) {
  final buffer = StringBuffer();
  var i = startIdx;
  while (i < endIdx && !lines[i].startsWith('***')) {
    if (lines[i].startsWith('+')) {
      buffer.writeln(lines[i].substring(1));
    }
    i += 1;
  }
  var content = buffer.toString();
  if (content.endsWith('\n')) {
    content = content.substring(0, content.length - 1);
  }
  return _PatchAddParseResult(content: content, nextIdx: i);
}

_PatchChunkParseResult _parseUpdateFileChunks(
  List<String> lines,
  int startIdx,
  int endIdx,
) {
  final chunks = <_PatchUpdateChunk>[];
  var i = startIdx;
  while (i < endIdx && !lines[i].startsWith('***')) {
    if (lines[i].startsWith('@@')) {
      final contextLine = lines[i].substring(2).trim();
      i += 1;
      final oldLines = <String>[];
      final newLines = <String>[];
      var isEndOfFile = false;
      while (i < endIdx) {
        final changeLine = lines[i];
        if (changeLine.startsWith('@@')) break;
        if (changeLine.startsWith('***') && changeLine != '*** End of File') {
          break;
        }
        if (changeLine == '*** End of File') {
          isEndOfFile = true;
          i += 1;
          break;
        }
        if (changeLine.startsWith(' ')) {
          final content = changeLine.substring(1);
          oldLines.add(content);
          newLines.add(content);
        } else if (changeLine.startsWith('-')) {
          oldLines.add(changeLine.substring(1));
        } else if (changeLine.startsWith('+')) {
          newLines.add(changeLine.substring(1));
        }
        i += 1;
      }
      chunks.add(
        _PatchUpdateChunk(
          oldLines: oldLines,
          newLines: newLines,
          changeContext: contextLine.isEmpty ? null : contextLine,
          isEndOfFile: isEndOfFile,
        ),
      );
      continue;
    }
    i += 1;
  }
  return _PatchChunkParseResult(chunks: chunks, nextIdx: i);
}

List<_PatchSection> _parsePatchSections(String patchText) {
  final cleaned = _stripPatchHeredoc(_normalizePatchText(patchText).trim());
  final lines = cleaned.split('\n');
  final beginIdx = lines.indexWhere((line) => line.trim() == '*** Begin Patch');
  final endIdx = lines.indexWhere((line) => line.trim() == '*** End Patch');
  if (beginIdx == -1 || endIdx == -1 || beginIdx >= endIdx) {
    throw Exception(
        'apply_patch verification failed: Invalid patch format: missing Begin/End markers');
  }
  final sections = <_PatchSection>[];
  var i = beginIdx + 1;
  while (i < endIdx) {
    final header = _parsePatchHeader(lines, i);
    if (header == null) {
      i += 1;
      continue;
    }
    final currentLine = lines[i];
    if (currentLine.startsWith('*** Add File:')) {
      final parsed = _parseAddFileContent(lines, header.nextIdx, endIdx);
      sections.add(
        _PatchSection(
          kind: _PatchSectionKind.add,
          path: header.path,
          contents: parsed.content,
        ),
      );
      i = parsed.nextIdx;
      continue;
    }
    if (currentLine.startsWith('*** Delete File:')) {
      sections.add(
        _PatchSection(
          kind: _PatchSectionKind.delete,
          path: header.path,
        ),
      );
      i = header.nextIdx;
      continue;
    }
    if (currentLine.startsWith('*** Update File:')) {
      final parsed = _parseUpdateFileChunks(lines, header.nextIdx, endIdx);
      sections.add(
        _PatchSection(
          kind: _PatchSectionKind.update,
          path: header.path,
          movePath: header.movePath,
          chunks: parsed.chunks,
        ),
      );
      i = parsed.nextIdx;
      continue;
    }
    i += 1;
  }
  return sections;
}

List<String> _patchSectionDebugLines(_PatchSection section) {
  switch (section.kind) {
    case _PatchSectionKind.add:
      return section.contents.split('\n').map((line) => '+$line').toList();
    case _PatchSectionKind.delete:
      return const [];
    case _PatchSectionKind.update:
      final out = <String>[];
      for (final chunk in section.chunks) {
        out.add('@@ ${chunk.changeContext ?? ''}'.trimRight());
        var oldIdx = 0;
        var newIdx = 0;
        while (
            oldIdx < chunk.oldLines.length || newIdx < chunk.newLines.length) {
          final hasOld = oldIdx < chunk.oldLines.length;
          final hasNew = newIdx < chunk.newLines.length;
          if (hasOld &&
              hasNew &&
              chunk.oldLines[oldIdx] == chunk.newLines[newIdx]) {
            out.add(' ${chunk.oldLines[oldIdx]}');
            oldIdx += 1;
            newIdx += 1;
            continue;
          }
          if (hasOld) {
            out.add('-${chunk.oldLines[oldIdx]}');
            oldIdx += 1;
          }
          if (hasNew) {
            out.add('+${chunk.newLines[newIdx]}');
            newIdx += 1;
          }
        }
        if (chunk.isEndOfFile) {
          out.add('*** End of File');
        }
      }
      return out;
  }
}

String _deriveNewContentsFromChunks({
  required String filePath,
  required String existing,
  required List<_PatchUpdateChunk> chunks,
}) {
  var originalLines = _normalizePatchText(existing).split('\n');
  if (originalLines.isNotEmpty && originalLines.last.isEmpty) {
    originalLines = originalLines.sublist(0, originalLines.length - 1);
  }
  final replacements = _computePatchReplacements(
    originalLines: originalLines,
    filePath: filePath,
    chunks: chunks,
  );
  final newLines = _applyPatchReplacements(
    originalLines,
    replacements,
  );
  if (newLines.isEmpty || newLines.last != '') {
    newLines.add('');
  }
  return newLines.join('\n');
}

List<_PatchReplacement> _computePatchReplacements({
  required List<String> originalLines,
  required String filePath,
  required List<_PatchUpdateChunk> chunks,
}) {
  final replacements = <_PatchReplacement>[];
  var lineIndex = 0;
  for (final chunk in chunks) {
    final changeContext = chunk.changeContext;
    if (changeContext != null && changeContext.isNotEmpty) {
      final contextIdx = _seekPatchSequence(
        originalLines,
        [changeContext],
        lineIndex,
      );
      if (contextIdx == -1) {
        throw Exception(
          "apply_patch verification failed: Failed to find context '$changeContext' in $filePath",
        );
      }
      lineIndex = contextIdx + 1;
    }
    if (chunk.oldLines.isEmpty) {
      final insertionIdx = originalLines.isNotEmpty && originalLines.last == ''
          ? originalLines.length - 1
          : originalLines.length;
      replacements.add(
        _PatchReplacement(
          startIdx: insertionIdx,
          oldLength: 0,
          newSegment: chunk.newLines,
        ),
      );
      continue;
    }
    var pattern = List<String>.of(chunk.oldLines);
    var newSlice = List<String>.of(chunk.newLines);
    var found = _seekPatchSequence(
      originalLines,
      pattern,
      lineIndex,
      eof: chunk.isEndOfFile,
    );
    if (found == -1 && pattern.isNotEmpty && pattern.last.isEmpty) {
      pattern = pattern.sublist(0, pattern.length - 1);
      if (newSlice.isNotEmpty && newSlice.last.isEmpty) {
        newSlice = newSlice.sublist(0, newSlice.length - 1);
      }
      found = _seekPatchSequence(
        originalLines,
        pattern,
        lineIndex,
        eof: chunk.isEndOfFile,
      );
    }
    if (found == -1) {
      throw Exception(
        'apply_patch verification failed: Failed to find expected lines in $filePath:\n${chunk.oldLines.join('\n')}',
      );
    }
    replacements.add(
      _PatchReplacement(
        startIdx: found,
        oldLength: pattern.length,
        newSegment: newSlice,
      ),
    );
    lineIndex = found + pattern.length;
  }
  replacements.sort((a, b) => a.startIdx.compareTo(b.startIdx));
  return replacements;
}

List<String> _applyPatchReplacements(
  List<String> lines,
  List<_PatchReplacement> replacements,
) {
  final result = List<String>.of(lines);
  for (var i = replacements.length - 1; i >= 0; i--) {
    final replacement = replacements[i];
    result.removeRange(
      replacement.startIdx,
      replacement.startIdx + replacement.oldLength,
    );
    result.insertAll(replacement.startIdx, replacement.newSegment);
  }
  return result;
}

String _normalizePatchUnicode(String value) => value
    .replaceAll(RegExp(r'[\u2018\u2019\u201A\u201B]'), "'")
    .replaceAll(RegExp(r'[\u201C\u201D\u201E\u201F]'), '"')
    .replaceAll(RegExp(r'[\u2010\u2011\u2012\u2013\u2014\u2015]'), '-')
    .replaceAll('\u2026', '...')
    .replaceAll('\u00A0', ' ');

int _tryPatchMatch(
  List<String> lines,
  List<String> pattern,
  int startIndex,
  bool Function(String a, String b) compare,
  bool eof,
) {
  if (pattern.isEmpty) return -1;
  if (eof) {
    final fromEnd = lines.length - pattern.length;
    if (fromEnd >= startIndex) {
      var matches = true;
      for (var j = 0; j < pattern.length; j++) {
        if (!compare(lines[fromEnd + j], pattern[j])) {
          matches = false;
          break;
        }
      }
      if (matches) return fromEnd;
    }
  }
  for (var i = startIndex; i <= lines.length - pattern.length; i++) {
    var matches = true;
    for (var j = 0; j < pattern.length; j++) {
      if (!compare(lines[i + j], pattern[j])) {
        matches = false;
        break;
      }
    }
    if (matches) return i;
  }
  return -1;
}

int _seekPatchSequence(
  List<String> lines,
  List<String> pattern,
  int startIndex, {
  bool eof = false,
}) {
  if (pattern.isEmpty) return -1;
  final exact =
      _tryPatchMatch(lines, pattern, startIndex, (a, b) => a == b, eof);
  if (exact != -1) return exact;
  final rstrip = _tryPatchMatch(
    lines,
    pattern,
    startIndex,
    (a, b) => a.trimRight() == b.trimRight(),
    eof,
  );
  if (rstrip != -1) return rstrip;
  final trim = _tryPatchMatch(
    lines,
    pattern,
    startIndex,
    (a, b) => a.trim() == b.trim(),
    eof,
  );
  if (trim != -1) return trim;
  return _tryPatchMatch(
    lines,
    pattern,
    startIndex,
    (a, b) =>
        _normalizePatchUnicode(a.trim()) == _normalizePatchUnicode(b.trim()),
    eof,
  );
}

String? _extractHtmlTitle(String text) {
  final match =
      RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true)
          .firstMatch(text);
  if (match == null) return null;
  return match.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _plainTextPreview(String text, {int maxLength = 400}) {
  final withoutTags = text.replaceAll(RegExp(r'<[^>]+>', dotAll: true), ' ');
  final compact = withoutTags.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= maxLength) {
    return compact;
  }
  return '${compact.substring(0, maxLength)}...';
}

/// Line +/- counts aligned with [_buildUnifiedDiffPreview] middle hunk (UI hint, not a full Myers diff).
Map<String, int> _diffLineChangeCounts(String before, String after) {
  final beforeLines = const LineSplitter().convert(before);
  final afterLines = const LineSplitter().convert(after);
  var prefix = 0;
  while (prefix < beforeLines.length &&
      prefix < afterLines.length &&
      beforeLines[prefix] == afterLines[prefix]) {
    prefix += 1;
  }
  var beforeSuffix = beforeLines.length - 1;
  var afterSuffix = afterLines.length - 1;
  while (beforeSuffix >= prefix &&
      afterSuffix >= prefix &&
      beforeLines[beforeSuffix] == afterLines[afterSuffix]) {
    beforeSuffix -= 1;
    afterSuffix -= 1;
  }
  var deletions = 0;
  for (var i = prefix; i <= beforeSuffix; i++) {
    if (i >= 0 && i < beforeLines.length) deletions += 1;
  }
  var additions = 0;
  for (var i = prefix; i <= afterSuffix; i++) {
    if (i >= 0 && i < afterLines.length) additions += 1;
  }
  return {'additions': additions, 'deletions': deletions};
}

JsonMap _buildDiffAttachment({
  required String kind,
  required String path,
  required String before,
  required String after,
  String? sourcePath,
}) {
  final preview = _buildUnifiedDiffPreview(before: before, after: after);
  final fullPreview = _buildUnifiedDiffPreview(
    before: before,
    after: after,
    maxLines: 280,
    contextLines: 12,
  );
  final counts = _diffLineChangeCounts(before, after);
  return {
    'type': 'diff_preview',
    'kind': kind,
    'path': path,
    'sourcePath': sourcePath,
    'preview': preview,
    'fullPreview': fullPreview,
    'additions': counts['additions']!,
    'deletions': counts['deletions']!,
  };
}

String _buildUnifiedDiffPreview({
  required String before,
  required String after,
  int maxLines = 120,
  int contextLines = 3,
}) {
  final beforeLines = const LineSplitter().convert(before);
  final afterLines = const LineSplitter().convert(after);
  var prefix = 0;
  while (prefix < beforeLines.length &&
      prefix < afterLines.length &&
      beforeLines[prefix] == afterLines[prefix]) {
    prefix += 1;
  }

  var beforeSuffix = beforeLines.length - 1;
  var afterSuffix = afterLines.length - 1;
  while (beforeSuffix >= prefix &&
      afterSuffix >= prefix &&
      beforeLines[beforeSuffix] == afterLines[afterSuffix]) {
    beforeSuffix -= 1;
    afterSuffix -= 1;
  }

  final output = <String>['@@'];
  final beforeStart = prefix > contextLines ? prefix - contextLines : 0;
  for (var i = beforeStart; i < prefix; i++) {
    output.add(' ${beforeLines[i]}');
  }
  for (var i = prefix; i <= beforeSuffix; i++) {
    if (i >= 0 && i < beforeLines.length) {
      output.add('-${beforeLines[i]}');
    }
  }
  for (var i = prefix; i <= afterSuffix; i++) {
    if (i >= 0 && i < afterLines.length) {
      output.add('+${afterLines[i]}');
    }
  }
  var trailingShown = 0;
  for (var i = beforeSuffix + 1;
      i < beforeLines.length && trailingShown < contextLines;
      i++) {
    output.add(' ${beforeLines[i]}');
    trailingShown += 1;
  }
  if (output.length > maxLines) {
    return '${output.take(maxLines).join('\n')}\n...';
  }
  return output.join('\n');
}
