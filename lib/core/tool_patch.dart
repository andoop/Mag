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
    _logApplyPatchToolFailure(
      phase: 'parse_empty',
      error: 'apply_patch verification failed: no hunks found',
      patchText: patchText,
      rawArgs: rawArgs,
    );
    throw Exception('apply_patch verification failed: no hunks found');
  }
  final changedFiles = <String>[];
  final attachments = <JsonMap>[];
  for (var sectionIdx = 0; sectionIdx < sections.length; sectionIdx++) {
    final section = sections[sectionIdx];
    final targetPath = section.movePath ?? section.path;
    var existing = '';
    String previewAfter = '';
    var previewKind = section.kind.name;
    try {
      if (section.kind == _PatchSectionKind.add) {
        previewAfter = section.lines
            .where((line) => line.startsWith('+'))
            .map((line) => line.substring(1))
            .join('\n');
      } else if (section.kind == _PatchSectionKind.delete) {
        existing = await ctx.bridge.readText(
          treeUri: ctx.workspace.treeUri,
          relativePath: section.path,
        );
      } else {
        existing = await ctx.bridge.readText(
          treeUri: ctx.workspace.treeUri,
          relativePath: section.path,
        );
        previewAfter = _applyPatchToContent(existing, section.lines);
        if (section.kind == _PatchSectionKind.move) {
          previewKind = 'move';
        } else {
          previewKind = 'update';
        }
      }
      await ctx.askPermission(
        PermissionRequest(
          id: newId('perm'),
          sessionId: ctx.session.id,
          permission: 'edit',
          patterns: [targetPath],
          metadata: {
            'tool': 'apply_patch',
            'filePath': targetPath,
            'kind': section.kind.name,
            'preview': _buildDiffAttachment(
              kind: previewKind,
              path: targetPath,
              before: existing,
              after: previewAfter,
              sourcePath:
                  section.kind == _PatchSectionKind.move ? section.path : null,
            ),
          },
          always: [targetPath],
          messageId: ctx.message.id,
          callId: newId('call'),
        ),
      );
      if (section.kind == _PatchSectionKind.add) {
        await ctx.bridge.writeText(
          treeUri: ctx.workspace.treeUri,
          relativePath: section.path,
          content: previewAfter,
        );
        changedFiles.add(section.path);
        attachments.add(
          _buildDiffAttachment(
            kind: 'add',
            path: section.path,
            before: '',
            after: previewAfter,
          ),
        );
        continue;
      }
      if (section.kind == _PatchSectionKind.delete) {
        await ctx.bridge.deleteEntry(
          treeUri: ctx.workspace.treeUri,
          relativePath: section.path,
        );
        changedFiles.add(section.path);
        attachments.add(
          _buildDiffAttachment(
            kind: 'delete',
            path: section.path,
            before: existing,
            after: '',
          ),
        );
        continue;
      }
      final writePath = section.movePath ?? section.path;
      await ctx.bridge.writeText(
        treeUri: ctx.workspace.treeUri,
        relativePath: writePath,
        content: previewAfter,
      );
      changedFiles.add(writePath);
      attachments.add(
        _buildDiffAttachment(
          kind: section.kind == _PatchSectionKind.move ? 'move' : 'update',
          path: writePath,
          before: existing,
          after: previewAfter,
          sourcePath:
              section.kind == _PatchSectionKind.move ? section.path : null,
        ),
      );
      if (section.kind == _PatchSectionKind.move && section.movePath != null) {
        await ctx.bridge.deleteEntry(
          treeUri: ctx.workspace.treeUri,
          relativePath: section.path,
        );
      }
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
        sectionLineCount: section.lines.length,
        sectionLinesHead: section.lines
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
  return ToolExecutionResult(
    title: 'Apply Patch',
    output: 'Applied patch successfully.',
    displayOutput: changedFiles.isEmpty
        ? 'Applied patch'
        : 'Applied patch · ${changedFiles.length} file(s)',
    metadata: {'files': changedFiles},
    attachments: attachments,
  );
}

class _PatchSection {
  _PatchSection({
    required this.kind,
    required this.path,
    required this.lines,
    this.movePath,
  });

  final _PatchSectionKind kind;
  final String path;
  final List<String> lines;
  final String? movePath;
}

class _PatchHunk {
  _PatchHunk({
    required this.header,
    required this.lines,
  });

  final String? header;
  final List<String> lines;
}

enum _PatchSectionKind { add, update, delete, move }

String _normalizePatchHeaderPath(String raw) {
  final out = _normalizeWorkspaceRelativePath(raw);
  if (out.isEmpty) {
    throw Exception(
      'apply_patch: file path in patch header cannot be empty or only "."',
    );
  }
  return out;
}

List<_PatchSection> _parsePatchSections(String patchText) {
  final lines = const LineSplitter().convert(patchText);
  final sections = <_PatchSection>[];
  _PatchSectionKind? currentKind;
  String? currentPath;
  String? currentMovePath;
  final currentLines = <String>[];
  void flush() {
    if (currentKind != null && currentPath != null) {
      sections.add(
        _PatchSection(
          kind: currentKind,
          path: currentPath,
          lines: List.of(currentLines),
          movePath: currentMovePath,
        ),
      );
    }
  }

  for (final line in lines) {
    if (line.startsWith('*** Add File: ')) {
      flush();
      currentKind = _PatchSectionKind.add;
      currentPath = _normalizePatchHeaderPath(
        line.substring('*** Add File: '.length).trim(),
      );
      currentMovePath = null;
      currentLines.clear();
      continue;
    }
    if (line.startsWith('*** Update File: ')) {
      flush();
      currentKind = _PatchSectionKind.update;
      currentPath = _normalizePatchHeaderPath(
        line.substring('*** Update File: '.length).trim(),
      );
      currentMovePath = null;
      currentLines.clear();
      continue;
    }
    if (line.startsWith('*** Delete File: ')) {
      flush();
      currentKind = _PatchSectionKind.delete;
      currentPath = _normalizePatchHeaderPath(
        line.substring('*** Delete File: '.length).trim(),
      );
      currentMovePath = null;
      currentLines.clear();
      continue;
    }
    if (line.startsWith('*** Move to: ')) {
      currentKind = _PatchSectionKind.move;
      currentMovePath = _normalizePatchHeaderPath(
        line.substring('*** Move to: '.length).trim(),
      );
      continue;
    }
    if (line.startsWith('*** End')) continue;
    if (currentKind != null) {
      currentLines.add(line);
    }
  }
  flush();
  return sections;
}

String _applyPatchToContent(String existing, List<String> patchLines) {
  final oldLines = const LineSplitter().convert(existing);
  final hunks = _splitPatchHunks(patchLines);
  final output = <String>[];
  var cursor = 0;
  for (final hunk in hunks) {
    final start = _findHunkStart(oldLines, cursor, hunk);
    output.addAll(oldLines.sublist(cursor, start));
    var localCursor = start;
    for (final line in hunk.lines) {
      if (line == r'\ No newline at end of file') {
        continue;
      }
      if (line.isEmpty) {
        throw Exception(
            'apply_patch verification failed: empty patch line in hunk');
      }
      final prefix = line[0];
      final value = line.length > 1 ? line.substring(1) : '';
      if (prefix == ' ') {
        if (localCursor >= oldLines.length || oldLines[localCursor] != value) {
          throw Exception(
              'apply_patch verification failed: context mismatch for "$value"');
        }
        output.add(oldLines[localCursor]);
        localCursor += 1;
        continue;
      }
      if (prefix == '-') {
        if (localCursor >= oldLines.length || oldLines[localCursor] != value) {
          throw Exception(
              'apply_patch verification failed: delete mismatch for "$value"');
        }
        localCursor += 1;
        continue;
      }
      if (prefix == '+') {
        output.add(value);
        continue;
      }
      throw Exception(
          'apply_patch verification failed: unsupported patch line "$line"');
    }
    cursor = localCursor;
  }
  while (cursor < oldLines.length) {
    output.add(oldLines[cursor]);
    cursor += 1;
  }
  return output.join('\n');
}

List<_PatchHunk> _splitPatchHunks(List<String> patchLines) {
  final hunks = <_PatchHunk>[];
  String? currentHeader;
  final currentLines = <String>[];

  void flush() {
    if (currentHeader != null || currentLines.isNotEmpty) {
      hunks
          .add(_PatchHunk(header: currentHeader, lines: List.of(currentLines)));
    }
  }

  for (final line in patchLines) {
    if (line.startsWith('@@')) {
      flush();
      currentHeader = line;
      currentLines.clear();
      continue;
    }
    currentLines.add(line);
  }
  flush();
  return hunks.where((item) => item.lines.isNotEmpty).toList();
}

int _findHunkStart(List<String> oldLines, int cursor, _PatchHunk hunk) {
  final anchor = _hunkAnchor(hunk.lines);
  if (anchor.isEmpty) {
    return cursor;
  }
  for (var start = cursor; start <= oldLines.length - anchor.length; start++) {
    var matches = true;
    for (var i = 0; i < anchor.length; i++) {
      if (oldLines[start + i] != anchor[i]) {
        matches = false;
        break;
      }
    }
    if (!matches) continue;
    if (_verifyHunkAt(oldLines, start, hunk.lines)) {
      return start;
    }
  }
  throw Exception(
    'apply_patch verification failed: unable to locate hunk ${hunk.header ?? ''}'
        .trim(),
  );
}

List<String> _hunkAnchor(List<String> hunkLines) {
  final leadingContext = <String>[];
  for (final line in hunkLines) {
    if (line.isEmpty || line == r'\ No newline at end of file') continue;
    if (line.startsWith(' ')) {
      leadingContext.add(line.substring(1));
      if (leadingContext.length >= 3) {
        return leadingContext;
      }
      continue;
    }
    if (line.startsWith('+')) {
      continue;
    }
    if (line.startsWith('-')) {
      break;
    }
    break;
  }
  if (leadingContext.isNotEmpty) {
    return leadingContext;
  }

  final oldContent = <String>[];
  for (final line in hunkLines) {
    if (line.isEmpty || line == r'\ No newline at end of file') continue;
    if (line.startsWith(' ') || line.startsWith('-')) {
      oldContent.add(line.substring(1));
      if (oldContent.length >= 3) break;
    }
  }
  return oldContent;
}

bool _verifyHunkAt(List<String> oldLines, int start, List<String> hunkLines) {
  var cursor = start;
  for (final line in hunkLines) {
    if (line == r'\ No newline at end of file') continue;
    if (line.isEmpty) return false;
    final prefix = line[0];
    final value = line.length > 1 ? line.substring(1) : '';
    if (prefix == ' ' || prefix == '-') {
      if (cursor >= oldLines.length || oldLines[cursor] != value) {
        return false;
      }
      cursor += 1;
      continue;
    }
    if (prefix == '+') {
      continue;
    }
    return false;
  }
  return true;
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
