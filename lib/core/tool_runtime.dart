library tool_runtime;

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

part 'tool_read_write.dart';
part 'tool_file_ops.dart';
part 'tool_patch.dart';
part 'tool_misc.dart';
part 'tool_utils.dart';

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
/// Preview length cap for `[mag-edit]` / `[mag-patch]` debug logs (lengths still printed).
const int _kEditMismatchLogPreviewChars = 900;
/// Max patch hunk lines included in `[mag-patch][fail]` logs per section.
const int _kApplyPatchLogSectionLines = 60;

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
            'filePath': {
              'type': 'string',
              'description':
                  'The path to the file to write (workspace-relative)',
            },
            'content': {
              'type': 'string',
              'description': 'The content to write to the file',
            },
          },
          'required': ['filePath', 'content'],
          'additionalProperties': false,
        },
        execute: _writeTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'edit',
        description:
            'Replace text in a file at `path` using `oldString` and `newString`. '
            'Copy `oldString` from a fresh `read` of the file (not from numbered `read` output). '
            'Multi-line spans tolerate CRLF vs LF; matching also allows per-line trim and common-indent stripping when unambiguous.$kMobileWorkspacePathSuffix',
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
            'Search file contents with a Kotlin-compatible regular expression (line-by-line; not ripgrep/PCRE). '
            'Optional `path` must be a workspace-relative **directory** (not a single file). '
            'Limit files with `include` or alias `glob`: pattern matches the **full** workspace-relative path, so use e.g. `**/*.dart` not `*.dart` for nested files.$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'pattern': {
              'type': 'string',
              'description':
                  'Regex searched per line (Kotlin Regex). Escape metacharacters when matching literals (e.g. `Foo\\(`).',
            },
            'path': {
              'type': 'string',
              'description':
                  'Optional directory under workspace root to search. Must be a folder; omit or empty for workspace root. Do not pass a file path—use parent dir + include filter or read the file.',
            },
            'include': {
              'type': 'string',
              'description':
                  'Optional glob; matched against the full workspace-relative file path. Use `**/*.ext` for files in subfolders; `*.ext` only matches at root.',
            },
            'glob': {
              'type': 'string',
              'description':
                  'Alias for `include` (same semantics). Ignored if `include` is non-empty.',
            },
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
