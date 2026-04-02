import 'dart:convert';
import 'dart:io';

import 'database.dart';
import 'json_coerce.dart';
import 'models.dart';
import 'tools/builtin_tool_descriptions.dart';
import 'tools/fileref_tool_spec.dart';
import 'tools/question_tool_spec.dart';
import 'tools/todo_tool_spec.dart';
import 'workspace_bridge.dart';

typedef AskPermission = Future<void> Function(PermissionRequest request);
typedef AskQuestion = Future<List<List<String>>> Function(
    QuestionRequest request);
typedef ResolveInstructionReminder = Future<String> Function(
    String relativePath);
typedef RunSubtask = Future<ToolExecutionResult> Function({
  required SessionInfo session,
  required String description,
  required String prompt,
  required String subagentType,
});
typedef SaveTodos = Future<void> Function(List<TodoItem> items);

const int _kDefaultReadLimit = 2000;
const int _kMaxReadBytes = 50 * 1024;
const int _kMaxReadLineLength = 2000;
const String _kMaxReadLineSuffix = '... (line truncated to 2000 chars)';
const int _kToolResultLimit = 100;
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

class ToolRuntimeContext {
  ToolRuntimeContext({
    required this.workspace,
    required this.session,
    required this.message,
    required this.agent,
    required this.agentDefinition,
    required this.bridge,
    required this.database,
    required this.askPermission,
    required this.askQuestion,
    required this.resolveInstructionReminder,
    required this.runSubtask,
    required this.saveTodos,
    this.callId,
  });

  final WorkspaceInfo workspace;
  final SessionInfo session;
  final MessageInfo message;
  final String agent;
  final AgentDefinition agentDefinition;
  final WorkspaceBridge bridge;
  final AppDatabase database;
  final AskPermission askPermission;
  final AskQuestion askQuestion;
  final ResolveInstructionReminder resolveInstructionReminder;
  final RunSubtask runSubtask;
  final SaveTodos saveTodos;

  /// 当前工具调用的 `call.id`，与 OpenCode `ctx.callID` 一致（如 `question` 关联 UI）。
  final String? callId;
}

typedef ToolExecutor = Future<ToolExecutionResult> Function(
  JsonMap args,
  ToolRuntimeContext ctx,
);

class ToolDefinition {
  ToolDefinition({
    required this.id,
    required this.description,
    required this.parameters,
    required this.execute,
  });

  final String id;
  final String description;
  final JsonMap parameters;
  final ToolExecutor execute;

  ToolDefinitionModel toModel() => ToolDefinitionModel(
        id: id,
        description: description,
        parameters: parameters,
      );
}

class ToolRegistry {
  ToolRegistry._(this._definitions);

  final Map<String, ToolDefinition> _definitions;

  factory ToolRegistry.builtins() {
    final map = <String, ToolDefinition>{};

    void register(ToolDefinition def) {
      map[def.id] = def;
    }

    register(
      ToolDefinition(
        id: 'read',
        description:
            '${kReadToolDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Workspace-relative path to the file or directory',
            },
            'filePath': {
              'type': 'string',
              'description': 'Alias for path (accepted for compatibility)',
            },
            'offset': {
              'type': 'integer',
              'description': 'Line number to start from (1-indexed)',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum number of lines to read',
            },
          },
          'additionalProperties': false,
        },
        execute: _readTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'write',
        description:
            '${kWriteToolDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
            'content': {'type': 'string'},
            'contentRef': {'type': 'string'},
          },
          'required': ['path'],
          'additionalProperties': false,
        },
        execute: _writeTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'edit',
        description:
            'Replace text in a file at `path` using `oldString` and `newString`.$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
            'oldString': {'type': 'string'},
            'newString': {'type': 'string'},
            'replaceAll': {'type': 'boolean'},
          },
          'required': ['path', 'oldString', 'newString'],
          'additionalProperties': false,
        },
        execute: _editTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'apply_patch',
        description:
            '${kApplyPatchToolDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'patchText': {'type': 'string'},
          },
          'required': ['patchText'],
          'additionalProperties': false,
        },
        execute: _applyPatchTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'list',
        description:
            'List files and directories in the workspace.$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
            'ignore': {
              'type': 'array',
              'items': {'type': 'string'},
            },
          },
          'additionalProperties': false,
        },
        execute: _listTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'glob',
        description:
            'Search workspace files by glob pattern.$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'pattern': {'type': 'string'},
            'path': {'type': 'string'},
          },
          'required': ['pattern'],
          'additionalProperties': false,
        },
        execute: _globTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'grep',
        description:
            'Search file contents by regular expression.$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'pattern': {'type': 'string'},
            'path': {'type': 'string'},
            'include': {'type': 'string'},
          },
          'required': ['pattern'],
          'additionalProperties': false,
        },
        execute: _grepTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'stat',
        description:
            'Get file or directory metadata (path, size, lastModified, mimeType, isDirectory) in the workspace.$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
          'required': ['path'],
          'additionalProperties': false,
        },
        execute: _statTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'delete',
        description:
            'Delete a file or directory in the workspace. Directories are removed recursively.$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
          'required': ['path'],
          'additionalProperties': false,
        },
        execute: _deleteTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'rename',
        description:
            'Rename a file or directory within the same parent folder (provide `newName` only, not a path).$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
            'newName': {'type': 'string'},
          },
          'required': ['path', 'newName'],
          'additionalProperties': false,
        },
        execute: _renameTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'move',
        description:
            'Move or rename a file or directory to a new workspace-relative path (`toPath` is the final destination path).$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'fromPath': {'type': 'string'},
            'toPath': {'type': 'string'},
          },
          'required': ['fromPath', 'toPath'],
          'additionalProperties': false,
        },
        execute: _moveTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'copy',
        description:
            'Copy a file or directory to another path within the workspace. Directory copies are recursive (subject to platform limits).$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'fromPath': {'type': 'string'},
            'toPath': {'type': 'string'},
          },
          'required': ['fromPath', 'toPath'],
          'additionalProperties': false,
        },
        execute: _copyTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'todowrite',
        description: kTodoWriteToolDescription.trim(),
        parameters: todoWriteToolParametersSchema(),
        execute: _todoTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'question',
        description: kQuestionToolDescription.trim(),
        parameters: questionToolParametersSchema(),
        execute: _questionTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'webfetch',
        description:
            '${kWebfetchToolDescription.trim()}$kMobileWebFetchSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description': 'The URL to fetch content from',
            },
          },
          'required': ['url'],
          'additionalProperties': false,
        },
        execute: _webFetchTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'browser',
        description:
            'Open an HTML page from the workspace in the in-app browser.$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
          'required': ['path'],
          'additionalProperties': false,
        },
        execute: _browserTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'skill',
        description: 'Read a built-in mobile agent skill by name.',
        parameters: {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
          },
          'required': ['name'],
          'additionalProperties': false,
        },
        execute: _skillTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'fileref',
        description: kFilerefToolDescription.trim(),
        parameters: filerefToolParametersSchema(),
        execute: _filerefTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'invalid',
        description: 'Explain that a tool call was malformed.',
        parameters: {
          'type': 'object',
          'properties': {
            'tool': {'type': 'string'},
            'error': {'type': 'string'},
          },
          'required': ['tool', 'error'],
          'additionalProperties': false,
        },
        execute: _invalidTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'plan_exit',
        description: 'Ask to leave plan mode and switch to build mode.',
        parameters: {
          'type': 'object',
          'properties': const {},
          'additionalProperties': false,
        },
        execute: _planExitTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'task',
        description: 'Create a subtask using a subagent.',
        parameters: {
          'type': 'object',
          'properties': {
            'description': {'type': 'string'},
            'prompt': {'type': 'string'},
            'subagent_type': {'type': 'string'},
          },
          'required': ['description', 'prompt'],
          'additionalProperties': false,
        },
        execute: _taskTool,
      ),
    );

    return ToolRegistry._(map);
  }

  List<ToolDefinitionModel> all() =>
      _definitions.values.map((item) => item.toModel()).toList();

  List<ToolDefinitionModel> availableForAgent(AgentDefinition agent) {
    final ids = agent.availableTools.toSet();
    return _definitions.values
        .where((item) => ids.contains(item.id))
        .map((item) => item.toModel())
        .toList();
  }

  ToolDefinition? operator [](String id) => _definitions[id];
}

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

String? _extractWriteContentRef(String source, String contentRef) {
  if (source.isEmpty || contentRef.isEmpty) {
    return null;
  }
  final pattern = RegExp(
    r"""<write_content\s+id=(?:"([^"]+)"|'([^']+)')\s*>([\s\S]*?)</write_content>""",
    multiLine: true,
  );
  for (final match in pattern.allMatches(source)) {
    final id = match.group(1) ?? match.group(2) ?? '';
    if (id != contentRef) {
      continue;
    }
    var body = match.group(3) ?? '';
    body = body.replaceFirst(RegExp(r'^\r?\n'), '');
    body = body.replaceFirst(RegExp(r'\r?\n$'), '');
    final trimmed = body.trim();
    final fenced = RegExp(
      r'^```[^\n]*\n([\s\S]*?)\n```$',
      multiLine: true,
    ).firstMatch(trimmed);
    if (fenced != null) {
      return fenced.group(1) ?? '';
    }
    return body;
  }
  return null;
}

Future<String> _resolveWriteContent(
    JsonMap args, ToolRuntimeContext ctx) async {
  if (args.containsKey('content')) {
    return _normalizeWriteContent(args['content']);
  }
  final contentRef = (args['contentRef'] as String? ?? '').trim();
  if (contentRef.isEmpty) {
    throw Exception(
      'Missing write payload. Provide `content` for short text or `contentRef` for a `<write_content id="...">` block.',
    );
  }
  final parts = await ctx.database.listPartsForMessage(ctx.message.id);
  final source = parts
      .where((item) => item.type == PartType.text)
      .map((item) =>
          (item.data['rawText'] ?? item.data['text']) as String? ?? '')
      .join('\n');
  final resolved = _extractWriteContentRef(source, contentRef);
  if (resolved == null) {
    throw Exception(
      'contentRef `$contentRef` not found. Add `<write_content id="$contentRef">...</write_content>` to the assistant text before calling `write`.',
    );
  }
  return resolved;
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
  final previewLines = <String>[];
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
    if (previewLines.length < 20) {
      previewLines.add(numbered);
    }
    bytes += size;
  }
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
      'preview': previewLines.join('\n'),
      'truncated': truncated,
      'loaded': reminder.isEmpty ? const <String>[] : <String>[filePath],
      'path': filePath,
      'kind': 'file',
      'lineCount': rawLines.length,
    },
    attachments: [
      {
        'type': 'text_preview',
        'path': filePath,
        'filename': entry.name,
        'startLine': safeOffset,
        'endLine': lastReadLine < safeOffset ? safeOffset : lastReadLine,
        'lineCount': rawLines.length,
        'preview': previewLines.join('\n'),
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
  String existing = '';
  try {
    existing = await ctx.bridge.readText(
      treeUri: ctx.workspace.treeUri,
      relativePath: filePath,
    );
  } catch (_) {}
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
          kind: existing.isEmpty ? 'write' : 'write_update',
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
  return ToolExecutionResult(
    title: filePath,
    output: 'Wrote file successfully.',
    displayOutput: 'Wrote $filePath',
    metadata: {
      'path': filePath,
      'filepath': filePath,
      'exists': existing.isNotEmpty,
      'diagnostics': const <String, dynamic>{},
    },
    attachments: [
      _buildDiffAttachment(
        kind: existing.isEmpty ? 'write' : 'write_update',
        path: filePath,
        before: existing,
        after: content,
      ),
    ],
  );
}

Future<ToolExecutionResult> _editTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final filePath = _toolFilePathArg(args);
  final oldString = args['oldString'] as String? ?? '';
  final newString = args['newString'] as String? ?? '';
  final replaceAll = (args['replaceAll'] as bool?) ?? false;
  if (filePath.isEmpty) {
    throw Exception('Missing required `path`.');
  }
  final existing = await ctx.bridge.readText(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  if (!existing.contains(oldString)) {
    throw Exception('oldString not found in $filePath');
  }
  final updated = replaceAll
      ? existing.replaceAll(oldString, newString)
      : existing.replaceFirst(oldString, newString);
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
          before: existing,
          after: updated,
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
    content: updated,
  );
  return ToolExecutionResult(
    title: filePath,
    output: 'Updated file successfully.',
    displayOutput: 'Updated $filePath',
    metadata: {
      'path': filePath,
      'filepath': filePath,
      'diagnostics': const <String, dynamic>{},
    },
    attachments: [
      _buildDiffAttachment(
        kind: 'edit',
        path: filePath,
        before: existing,
        after: updated,
      ),
    ],
  );
}

Future<ToolExecutionResult> _applyPatchTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final patchText = args['patchText'] as String? ?? '';
  final sections = _parsePatchSections(patchText);
  if (sections.isEmpty) {
    throw Exception('apply_patch verification failed: no hunks found');
  }
  final changedFiles = <String>[];
  final attachments = <JsonMap>[];
  for (final section in sections) {
    final targetPath = section.movePath ?? section.path;
    String existing = '';
    String previewAfter = '';
    String previewKind = section.kind.name;
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

Future<ToolExecutionResult> _listTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final relativePath = _normalizeWorkspaceRelativePath(args['path'] as String? ?? '');
  final ignore = (args['ignore'] as List?)
          ?.map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList() ??
      const <String>[];
  final searchPath = relativePath.isEmpty ? '.' : relativePath;
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
  final pathPrefix = _normalizeWorkspaceRelativePath(args['path'] as String? ?? '');
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
  final pathPrefix = _normalizeWorkspaceRelativePath(args['path'] as String? ?? '');
  final include = args['include'] as String?;
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
  return ToolExecutionResult(
    title: filePath,
    output: 'Deleted successfully.',
    displayOutput: 'Deleted $filePath',
    metadata: {'path': filePath},
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
    throw Exception('`newName` must be a single segment (no slashes). Use `move` for paths.');
  }
  final existing = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  if (existing == null) {
    throw Exception('Not found: $filePath');
  }
  final parent = _parentPath(filePath);
  final newPath =
      parent.isEmpty ? newName : '$parent/$newName';
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
        'preview': _buildDiffAttachment(
          kind: 'rename',
          path: newPath,
          before: filePath,
          after: newPath,
        ),
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
  return ToolExecutionResult(
    title: newPath,
    output: 'Renamed to ${_formatStatEntry(entry)}',
    displayOutput: 'Renamed $filePath → $newPath',
    metadata: {'path': entry.path, 'from': filePath},
  );
}

Future<ToolExecutionResult> _moveTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final fromPath = _normalizeWorkspaceRelativePath(args['fromPath'] as String? ?? '');
  final toPath = _normalizeWorkspaceRelativePath(args['toPath'] as String? ?? '');
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
        'preview': _buildDiffAttachment(
          kind: 'move',
          path: toPath,
          before: fromPath,
          after: toPath,
        ),
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
  return ToolExecutionResult(
    title: toPath,
    output: _formatStatEntry(entry),
    displayOutput: 'Moved $fromPath → $toPath',
    metadata: {'path': entry.path, 'from': fromPath},
  );
}

Future<ToolExecutionResult> _copyTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final fromPath = _normalizeWorkspaceRelativePath(args['fromPath'] as String? ?? '');
  final toPath = _normalizeWorkspaceRelativePath(args['toPath'] as String? ?? '');
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
        'preview': _buildDiffAttachment(
          kind: 'copy',
          path: toPath,
          before: fromPath,
          after: toPath,
        ),
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
  return ToolExecutionResult(
    title: toPath,
    output: _formatStatEntry(entry),
    displayOutput: 'Copied $fromPath → $toPath',
    metadata: {'path': entry.path, 'from': fromPath},
  );
}

Future<ToolExecutionResult> _todoTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final raw = (args['todos'] as List?) ?? const [];
  final items = <TodoItem>[];
  var index = 0;
  for (final entry in raw.whereType<Map>()) {
    final m = Map<String, dynamic>.from(entry);
    final content = jsonStringCoerce(m['content'], '').trim();
    final status = jsonStringCoerce(m['status'], '').trim();
    if (content.isEmpty || status.isEmpty) {
      continue;
    }
    final idRaw = jsonStringCoerce(m['id'], '').trim();
    final priorityRaw = jsonStringCoerce(m['priority'], 'medium').trim();
    items.add(
      TodoItem(
        id: idRaw.isEmpty ? newId('todo') : idRaw,
        sessionId: ctx.session.id,
        content: content,
        status: status,
        priority: priorityRaw.isEmpty ? 'medium' : priorityRaw,
        position: index,
      ),
    );
    index++;
  }
  await ctx.saveTodos(items);
  final openCodeShape = items
      .map(
        (e) => <String, dynamic>{
          'content': e.content,
          'status': e.status,
          'priority': e.priority,
        },
      )
      .toList();
  final remaining = items.where((t) => t.status != 'completed').length;
  return ToolExecutionResult(
    title: '$remaining todos',
    output: const JsonEncoder.withIndent('  ').convert(openCodeShape),
    metadata: {
      'todos': openCodeShape,
    },
  );
}

Future<ToolExecutionResult> _questionTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final rawQuestions = (args['questions'] as List?) ?? const [];
  final parsed = rawQuestions
      .whereType<Map>()
      .map((item) =>
          QuestionInfo.fromJson(Map<String, dynamic>.from(item)))
      .toList();
  if (parsed.isEmpty) {
    return ToolExecutionResult(
      title: 'Question',
      output:
          'Invalid arguments: questions must be a non-empty array of objects with question, header, and options.',
      metadata: const {},
    );
  }
  final request = QuestionRequest(
    id: newId('question'),
    sessionId: ctx.session.id,
    questions: parsed,
    messageId: ctx.message.id,
    callId: ctx.callId,
  );
  final answersRaw = await ctx.askQuestion(request);
  final n = parsed.length;
  final answers = <List<String>>[];
  for (var i = 0; i < n; i++) {
    if (i < answersRaw.length) {
      answers.add(List<String>.from(answersRaw[i]));
    } else {
      answers.add(<String>[]);
    }
  }

  String formatAnswer(List<String> answer) {
    if (answer.isEmpty) return 'Unanswered';
    return answer.join(', ');
  }

  final formatted = List.generate(
    n,
    (i) => '"${parsed[i].question}"="${formatAnswer(answers[i])}"',
  ).join(', ');
  final title = n == 1 ? 'Asked 1 question' : 'Asked $n questions';
  final output =
      'User has answered your questions: $formatted. You can now continue with the user\'s answers in mind.';

  return ToolExecutionResult(
    title: title,
    output: output,
    metadata: {'answers': answers},
  );
}

Future<ToolExecutionResult> _webFetchTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final url = Uri.parse(args['url'] as String? ?? '');
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'webfetch',
      patterns: [url.host],
      metadata: {'tool': 'webfetch', 'url': url.toString()},
      always: [url.host],
      messageId: ctx.message.id,
      callId: newId('call'),
    ),
  );
  final client = HttpClient();
  final request = await client.getUrl(url);
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  final contentType = response.headers.contentType?.mimeType ?? 'text/plain';
  client.close(force: true);
  return ToolExecutionResult(
    title: 'WebFetch',
    output: text,
    displayOutput:
        'Fetched ${url.toString()} · ${response.statusCode} · $contentType',
    metadata: {'statusCode': response.statusCode, 'contentType': contentType},
    attachments: [
      {
        'type': 'webpage',
        'url': url.toString(),
        'statusCode': response.statusCode,
        'mime': contentType,
        'title': _extractHtmlTitle(text) ?? url.host,
        'excerpt': _plainTextPreview(text, maxLength: 600),
      },
    ],
  );
}

Future<ToolExecutionResult> _browserTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final requestedPath = _normalizeWorkspaceRelativePath(args['path'] as String? ?? '');
  if (requestedPath.isEmpty) {
    throw Exception('Missing workspace page path');
  }
  final resolvedPath = await _resolveBrowserPath(requestedPath, ctx);
  return ToolExecutionResult(
    title: 'Browser',
    output: 'Opened workspace page at $resolvedPath',
    displayOutput: 'Opened workspace page $resolvedPath',
    metadata: {
      'path': resolvedPath,
      'kind': 'workspace_page',
    },
    attachments: [
      {
        'type': 'browser_page',
        'path': resolvedPath,
        'filename': resolvedPath.split('/').last,
        'title': resolvedPath.split('/').last,
      },
    ],
  );
}

Future<ToolExecutionResult> _filerefTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final raw = (args['refs'] as List?) ?? const [];
  final out = <JsonMap>[];
  final warnings = <String>[];
  for (final e in raw.whereType<Map>()) {
    final m = Map<String, dynamic>.from(e);
    String path;
    try {
      path = _normalizeWorkspaceRelativePath(jsonStringCoerce(m['path'], ''));
    } catch (e) {
      warnings.add('Invalid path ${m['path']}: $e');
      continue;
    }
    var kind = jsonStringCoerce(m['kind'], 'modified').trim().toLowerCase();
    if (path.isEmpty) {
      warnings.add('Skipped empty path');
      continue;
    }
    if (kind != 'created' && kind != 'modified') {
      kind = 'modified';
    }
    final entry = await ctx.bridge.stat(
      treeUri: ctx.workspace.treeUri,
      relativePath: path,
    );
    if (entry == null) {
      warnings.add('Not found in workspace: $path');
    }
    out.add({
      'path': path,
      'kind': kind,
      'exists': entry != null,
    });
  }
  if (out.isEmpty) {
    return ToolExecutionResult(
      title: 'fileref',
      output:
          'No valid refs. Provide refs: [{path, kind}] with workspace-relative paths (. and ./ allowed; .. cannot escape root).',
      metadata: {'refs': <JsonMap>[]},
    );
  }
  final pretty = const JsonEncoder.withIndent('  ').convert(out);
  final warnBlock =
      warnings.isEmpty ? '' : '\n\nWarnings:\n${warnings.join('\n')}';
  return ToolExecutionResult(
    title: '${out.length} file ref${out.length == 1 ? '' : 's'}',
    output:
        'Registered file references for the conversation UI.$warnBlock\n\n$pretty',
    metadata: {'refs': out},
  );
}

Future<ToolExecutionResult> _skillTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final name = (args['name'] as String? ?? '').trim();
  final skills = <String, String>{
    'android_workspace':
        'Use workspace tools before answering. Prefer read, glob, grep, edit, and apply_patch inside the selected Android workspace.',
    'mobile_agent':
        'This mobile agent mirrors Mag semantics. Keep actions observable through parts, permissions, and events.',
  };
  final content = skills[name];
  if (content == null) {
    throw Exception('Unknown skill: $name');
  }
  return ToolExecutionResult(
    title: 'Skill',
    output: '<skill_content>\n$content\n</skill_content>',
  );
}

Future<ToolExecutionResult> _invalidTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final tool = args['tool'] as String? ?? 'unknown';
  final error = args['error'] as String? ?? 'invalid input';
  return ToolExecutionResult(
    title: 'Invalid',
    output: 'The $tool tool call was invalid: $error',
  );
}

Future<ToolExecutionResult> _planExitTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final answers = await ctx.askQuestion(
    QuestionRequest(
      id: newId('question'),
      sessionId: ctx.session.id,
      questions: [
        QuestionInfo(
          question: 'Leave plan mode and switch to build mode?',
          header: 'Plan Exit',
          options: [
            QuestionOption(
                label: 'Switch', description: 'Switch to build mode'),
            QuestionOption(label: 'Stay', description: 'Keep planning'),
          ],
        ),
      ],
      messageId: ctx.message.id,
      callId: ctx.callId,
    ),
  );
  final accepted = answers.isNotEmpty && answers.first.contains('Switch');
  if (!accepted) {
    throw Exception('User stayed in plan mode');
  }
  return ToolExecutionResult(
    title: 'Plan Exit',
    output: 'Switching to build mode.',
    metadata: {'switchAgent': 'build'},
  );
}

Future<ToolExecutionResult> _taskTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  return ctx.runSubtask(
    session: ctx.session,
    description: args['description'] as String? ?? '',
    prompt: args['prompt'] as String? ?? '',
    subagentType: args['subagent_type'] as String? ?? 'general',
  );
}

/// Workspace-root-relative path: trims, uses `/`, strips redundant `./`, resolves
/// `.` and `..`. A leading `/` is stripped (still under workspace). Returns `''`
/// for the workspace root. Throws if `..` would escape above the root.
String _normalizeWorkspaceRelativePath(String input) {
  var value = input.trim().replaceAll('\\', '/');
  if (value.isEmpty || value == '.') {
    return '';
  }
  while (value.startsWith('./')) {
    value = value.substring(2);
  }
  if (value.isEmpty || value == '.') {
    return '';
  }
  if (value.startsWith('/')) {
    value = value.substring(1);
  }
  if (value.isEmpty) {
    return '';
  }
  final parts = <String>[];
  for (final rawSeg in value.split('/')) {
    final seg = rawSeg.trim();
    if (seg.isEmpty || seg == '.') {
      continue;
    }
    if (seg == '..') {
      if (parts.isEmpty) {
        throw Exception(
          'Path escapes workspace root (invalid ..): ${_shortPathForError(input)}',
        );
      }
      parts.removeLast();
      continue;
    }
    parts.add(seg);
  }
  return parts.join('/');
}

String _shortPathForError(String s, [int max = 100]) {
  final t = s.trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max)}…';
}

bool _looksBinaryEntry(WorkspaceEntry entry) {
  final mime = entry.mimeType ?? '';
  if (mime.startsWith('text/')) return false;
  if (_isImageMime(mime) || mime == 'application/pdf') return false;
  const textExtensions = [
    '.dart',
    '.kt',
    '.java',
    '.md',
    '.txt',
    '.yaml',
    '.yml',
    '.json',
    '.xml',
    '.gradle',
    '.properties',
    '.js',
    '.ts',
    '.tsx',
    '.jsx',
    '.html',
    '.css',
    '.scss',
    '.sh',
    '.py',
    '.rb',
    '.go',
    '.rs',
  ];
  return !textExtensions.any(
    (ext) => entry.path.toLowerCase().endsWith(ext),
  );
}

bool _isImageMime(String mime) => mime.startsWith('image/');

Future<List<String>> _fileNotFoundSuggestions(
  String filePath,
  ToolRuntimeContext ctx,
) async {
  if (filePath.isEmpty) return const [];
  final parent = _parentPath(filePath);
  final base = filePath.split('/').last.toLowerCase();
  try {
    final siblings = await ctx.bridge.listDirectory(
      treeUri: ctx.workspace.treeUri,
      relativePath: parent,
    );
    return siblings
        .where(
          (item) =>
              item.name.toLowerCase().contains(base) ||
              base.contains(item.name.toLowerCase()),
        )
        .take(3)
        .map((item) => item.path)
        .toList();
  } catch (_) {
    return const [];
  }
}

String _parentPath(String input) {
  if (!input.contains('/')) return '';
  return input.substring(0, input.lastIndexOf('/'));
}

String _renderListOutput({
  required String rootLabel,
  required String basePath,
  required List<WorkspaceEntry> files,
}) {
  final dirs = <String>{'.'};
  final filesByDir = <String, List<String>>{};
  for (final file in files) {
    final relative = basePath.isEmpty
        ? file.path
        : file.path.startsWith('$basePath/')
            ? file.path.substring(basePath.length + 1)
            : file.path;
    final segments =
        relative.split('/').where((item) => item.isNotEmpty).toList();
    if (segments.isEmpty) continue;
    final dirSegments = segments.take(segments.length - 1).toList();
    for (var i = 0; i <= dirSegments.length; i++) {
      final dirPath = i == 0 ? '.' : dirSegments.take(i).join('/');
      dirs.add(dirPath);
    }
    final dir = dirSegments.isEmpty ? '.' : dirSegments.join('/');
    filesByDir.putIfAbsent(dir, () => <String>[]).add(segments.last);
  }

  String renderDir(String dirPath, int depth) {
    final indent = '  ' * depth;
    final childIndent = '  ' * (depth + 1);
    final children = dirs
        .where((item) => item != dirPath && _parentTreePath(item) == dirPath)
        .toList()
      ..sort();
    final buffer = StringBuffer();
    if (depth > 0) {
      buffer.writeln('$indent${dirPath.split('/').last}/');
    }
    for (final child in children) {
      buffer.write(renderDir(child, depth + 1));
    }
    final directFiles = (filesByDir[dirPath] ?? <String>[])..sort();
    for (final file in directFiles) {
      buffer.writeln('$childIndent$file');
    }
    return buffer.toString();
  }

  return '$rootLabel/\n${renderDir('.', 0)}';
}

String _parentTreePath(String path) {
  if (path == '.' || !path.contains('/')) return '.';
  return path.substring(0, path.lastIndexOf('/'));
}

String _formatGrepOutput(
  List<JsonMap> matches, {
  required String totalLabel,
  required bool truncated,
}) {
  final buffer = <String>[
    'Found $totalLabel matches${truncated ? ' (showing first $_kToolResultLimit)' : ''}',
  ];
  var currentFile = '';
  for (final match in matches) {
    final path = match['path'] as String? ?? '';
    if (path != currentFile) {
      if (currentFile.isNotEmpty) {
        buffer.add('');
      }
      currentFile = path;
      buffer.add('$path:');
    }
    buffer.add('  Line ${match['line']}: ${match['text']}');
  }
  if (truncated) {
    buffer.add('');
    buffer.add(
      '(Results truncated: showing first $_kToolResultLimit matches. Consider using a more specific path or pattern.)',
    );
  }
  return buffer.join('\n');
}

Future<String> _resolveBrowserPath(
    String requestedPath, ToolRuntimeContext ctx) async {
  final normalized = _normalizeWorkspaceRelativePath(requestedPath);
  final direct = await ctx.bridge.getEntry(
    treeUri: ctx.workspace.treeUri,
    relativePath: normalized,
  );
  if (direct != null && !direct.isDirectory) {
    if (_isBrowserPagePath(direct.path)) {
      return direct.path;
    }
    throw Exception('Browser only supports HTML files: $normalized');
  }
  try {
    final children = await ctx.bridge.listDirectory(
      treeUri: ctx.workspace.treeUri,
      relativePath: normalized,
    );
    for (final candidate in const ['index.html', 'index.htm']) {
      final expected =
          normalized.isEmpty ? candidate : '$normalized/$candidate';
      final match = children.cast<WorkspaceEntry?>().firstWhere(
            (item) => item?.path == expected,
            orElse: () => null,
          );
      if (match != null && !match.isDirectory) {
        return match.path;
      }
    }
  } catch (_) {}
  throw Exception('Workspace page not found: $normalized');
}

bool _isBrowserPagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.html') || lower.endsWith('.htm');
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
  return {
    'type': 'diff_preview',
    'kind': kind,
    'path': path,
    'sourcePath': sourcePath,
    'preview': preview,
    'fullPreview': fullPreview,
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
