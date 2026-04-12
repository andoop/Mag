library tool_runtime;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'database.dart';
import 'git/exceptions/git_exceptions.dart';
import 'git/git_service.dart';
import 'git/git_settings_store.dart';
import 'json_coerce.dart';
import 'mcp_service.dart';
import 'models.dart';
import 'skill_registry.dart';
import 'tools/builtin_tool_descriptions.dart';
import 'tools/question_tool_spec.dart';
import 'tools/todo_tool_spec.dart';
import 'workspace_bridge.dart';

part 'tool_read_write.dart';
part 'tool_hashline.dart';
part 'tool_file_ops.dart';
part 'tool_patch.dart';
part 'tool_misc.dart';
part 'tool_utils.dart';
part 'tool_git.dart';

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
  String? taskId,
});
typedef SaveTodos = Future<void> Function(List<TodoItem> items);
typedef UpdateToolProgress = Future<void> Function({
  String? title,
  String? displayOutput,
  JsonMap? metadata,
  List<JsonMap>? attachments,
});

const int _kDefaultReadLimit = 2000;
const int _kMaxReadBytes = 50 * 1024;
const int _kMaxReadLineLength = 2000;
const String _kMaxReadLineSuffix = '... (line truncated to 2000 chars)';
const int _kToolResultLimit = 100;

HttpClient Function() _toolHttpClientFactory = HttpClient.new;

void debugSetToolHttpClientFactoryForTests(HttpClient Function() factory) {
  _toolHttpClientFactory = factory;
}

void debugResetToolHttpClientFactoryForTests() {
  _toolHttpClientFactory = HttpClient.new;
}

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
    required this.mcpService,
    required this.askPermission,
    required this.askQuestion,
    required this.resolveInstructionReminder,
    required this.runSubtask,
    required this.saveTodos,
    required this.updateToolProgress,
    this.callId,
  });

  final WorkspaceInfo workspace;
  final SessionInfo session;
  final MessageInfo message;
  final String agent;
  final AgentDefinition agentDefinition;
  final WorkspaceBridge bridge;
  final AppDatabase database;
  final McpService mcpService;
  final AskPermission askPermission;
  final AskQuestion askQuestion;
  final ResolveInstructionReminder resolveInstructionReminder;
  final RunSubtask runSubtask;
  final SaveTodos saveTodos;
  final UpdateToolProgress updateToolProgress;

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
            'filePath': {
              'type': 'string',
              'description':
                  'REQUIRED. Workspace-relative path to the file or directory.',
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
          'required': ['filePath'],
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
                  'REQUIRED. Workspace-relative path for the new file. Must be present on every call; do not omit or rename this key.',
            },
            'content': {
              'type': 'string',
              'description':
                  'REQUIRED. The full file body to write. Must be present on every call.',
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
        description: '${kEditToolDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'filePath': {
              'type': 'string',
              'description':
                  'REQUIRED. Workspace-relative path to the file being edited.',
            },
            'oldString': {
              'type': 'string',
              'description': 'The exact text to replace.',
            },
            'newString': {
              'type': 'string',
              'description':
                  'The replacement text. Must be different from `oldString`.',
            },
            'replaceAll': {
              'type': 'boolean',
              'description':
                  'Optional. Replace all matches of `oldString` instead of requiring a unique match.',
            },
          },
          'required': ['filePath', 'oldString', 'newString'],
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
            'Delete a file or directory in the workspace. If `path` points to a directory, it is removed recursively. Use this for deleting files, deleting folders, or clearing a subtree.$kMobileWorkspacePathSuffix',
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
            'Rename a file or directory within the same parent folder. Provide `newName` only (a single final name segment, not a path). If the parent folder should change too, use `move` instead.$kMobileWorkspacePathSuffix',
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
            'Move or rename a file or directory to a new workspace-relative path. Use this when the parent folder changes or when you want the final path directly; `toPath` is the full destination path.$kMobileWorkspacePathSuffix',
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
            'Copy a file or directory to another path within the workspace. Directory copies are recursive (subject to platform limits), so this can duplicate a whole folder tree as well as a single file.$kMobileWorkspacePathSuffix',
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
        description: '${kWebfetchToolDescription.trim()}$kMobileWebFetchSuffix',
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
        id: 'download',
        description:
            '${kDownloadToolDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description': 'REQUIRED. Public http/https URL to download.',
            },
            'filePath': {
              'type': 'string',
              'description':
                  'REQUIRED. Workspace-relative destination path for the downloaded file.',
            },
            'overwrite': {
              'type': 'boolean',
              'description':
                  'Optional. Set to true to replace an existing file at `filePath`.',
            },
          },
          'required': ['url', 'filePath'],
          'additionalProperties': false,
        },
        execute: _downloadTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'list_mcp_resources',
        description: kListMcpResourcesToolDescription.trim(),
        parameters: {
          'type': 'object',
          'properties': {
            'serverId': {
              'type': 'string',
              'description': 'Optional. Limit results to one configured MCP server.',
            },
          },
          'additionalProperties': false,
        },
        execute: _listMcpResourcesTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'read_mcp_resource',
        description: kReadMcpResourceToolDescription.trim(),
        parameters: {
          'type': 'object',
          'properties': {
            'serverId': {'type': 'string'},
            'uri': {'type': 'string'},
          },
          'required': ['serverId', 'uri'],
          'additionalProperties': false,
        },
        execute: _readMcpResourceTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'list_mcp_prompts',
        description: kListMcpPromptsToolDescription.trim(),
        parameters: {
          'type': 'object',
          'properties': {
            'serverId': {
              'type': 'string',
              'description': 'Optional. Limit results to one configured MCP server.',
            },
          },
          'additionalProperties': false,
        },
        execute: _listMcpPromptsTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'get_mcp_prompt',
        description: kGetMcpPromptToolDescription.trim(),
        parameters: {
          'type': 'object',
          'properties': {
            'serverId': {'type': 'string'},
            'name': {'type': 'string'},
            'arguments': {
              'type': 'object',
              'description': 'Optional string arguments for the MCP prompt.',
            },
          },
          'required': ['serverId', 'name'],
          'additionalProperties': false,
        },
        execute: _getMcpPromptTool,
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
        description:
            'Load a skill by name. Skills are discovered from workspace-local '
            '`.opencode/skill`, `.opencode/skills`, `.claude/skills`, and '
            '`.agents/skills` directories. This tool returns the skill instructions '
            'and a sampled list of sibling files. It does not execute scripts or hooks.',
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
        id: 'git',
        description:
            'Run git operations on the workspace repository (pure-Dart, no CLI needed). '
            'Set `command` to one of: status, add, restore, reset, commit, log, diff, branch, '
            'checkout, merge, cherry-pick, init, show, clone, fetch, pull, push, rebase, config, remote-url, remote. '
            'Each command accepts additional parameters — see per-command docs in the schema.',
        parameters: {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'description':
                  'Git sub-command: status | add | restore | reset | commit | log | diff | '
                      'branch | checkout | merge | cherry-pick | init | show | clone | fetch | pull | push | rebase | config | remote-url | remote',
            },
            'paths': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'File paths (for add, diff, restore, reset path mode)',
            },
            'all': {
              'type': 'boolean',
              'description': 'Stage all changes (for add)',
            },
            'message': {
              'type': 'string',
              'description':
                  'Commit message (for commit, merge continue, cherry-pick continue)',
            },
            'amend': {
              'type': 'boolean',
              'description': 'Amend the last commit (for commit)',
            },
            'maxCount': {
              'type': 'integer',
              'description': 'Max entries to return (for log, default 10)',
            },
            'firstParentOnly': {
              'type': 'boolean',
              'description':
                  'Follow only the first parent when walking history',
            },
            'since': {
              'type': 'string',
              'description':
                  'Only include commits on or after this ISO-8601 timestamp',
            },
            'until': {
              'type': 'string',
              'description':
                  'Only include commits on or before this ISO-8601 timestamp',
            },
            'action': {
              'type': 'string',
              'description':
                  'Sub-action: list | create | delete (for branch), get | set (for config), list | get-url | add | set-url | remove | rename (for remote), start | continue | abort (for merge), start | continue | abort (for cherry-pick), start | continue | skip | abort (for rebase)',
            },
            'name': {
              'type': 'string',
              'description': 'Branch name (for branch create/delete)',
            },
            'force': {
              'type': 'boolean',
              'description':
                  'Force the operation when supported (branch delete, push)',
            },
            'startPoint': {
              'type': 'string',
              'description': 'Start point ref for branch creation',
            },
            'target': {
              'type': 'string',
              'description':
                  'Branch or commit to switch to (for checkout) or reset to (for reset)',
            },
            'newBranch': {
              'type': 'boolean',
              'description': 'Create and switch to a new branch (for checkout)',
            },
            'mode': {
              'type': 'string',
              'description':
                  'Reset mode: soft | mixed | hard (for reset, default mixed)',
            },
            'branch': {
              'type': 'string',
              'description':
                  'Branch to merge or fetch/pull from (for merge/fetch/pull)',
            },
            'remote': {
              'type': 'string',
              'description':
                  'Remote name (for fetch/pull/push/remote-url/remote, default origin)',
            },
            'oldName': {
              'type': 'string',
              'description': 'Existing remote name (for remote rename)',
            },
            'newName': {
              'type': 'string',
              'description': 'New remote name (for remote rename)',
            },
            'url': {
              'type': 'string',
              'description':
                  'Remote URL or local repo path (for clone, remote add/set-url)',
            },
            'path': {
              'type': 'string',
              'description':
                  'Destination path for clone, relative to the workspace root',
            },
            'rebase': {
              'type': 'boolean',
              'description': 'Use rebase instead of merge when pulling',
            },
            'refspec': {
              'type': 'string',
              'description':
                  'Explicit push refspec, for example refs/heads/main:refs/heads/main',
            },
            'ref': {
              'type': 'string',
              'description':
                  'Commit or branch ref to show/rebase onto, or commit to cherry-pick (for show/rebase start/cherry-pick start, default HEAD)',
            },
            'authorName': {
              'type': 'string',
              'description': 'Override author name (for commit)',
            },
            'authorEmail': {
              'type': 'string',
              'description': 'Override author email (for commit)',
            },
            'section': {
              'type': 'string',
              'description': 'Config section name (for config)',
            },
            'key': {
              'type': 'string',
              'description': 'Config key name (for config)',
            },
            'value': {
              'type': 'string',
              'description': 'Config value to set (for config set)',
            },
          },
          'required': ['command'],
          'additionalProperties': false,
        },
        execute: _gitTool,
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
        description:
            'Launch a new subagent to handle complex, multi-step work. '
            'Provide a short description, a detailed prompt, and an optional `subagent_type`. '
            'Reuse `task_id` to continue a previous subtask session instead of creating a new one.',
        parameters: {
          'type': 'object',
          'properties': {
            'description': {'type': 'string'},
            'prompt': {'type': 'string'},
            'subagent_type': {'type': 'string'},
            'task_id': {'type': 'string'},
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

  bool _shouldPreferApplyPatch(String modelId) {
    final lower = modelId.trim().toLowerCase();
    if (lower.isEmpty) return false;
    return lower.contains('gpt-') &&
        !lower.contains('oss') &&
        !lower.contains('gpt-4');
  }

  List<ToolDefinitionModel> availableForAgent(
    AgentDefinition agent, {
    String? modelId,
  }) {
    final ids = agent.availableTools.toSet();
    final preferApplyPatch =
        modelId != null && _shouldPreferApplyPatch(modelId);
    return _definitions.values
        .where((item) {
          if (!ids.contains(item.id)) return false;
          if (preferApplyPatch) {
            if (item.id == 'edit' || item.id == 'write') return false;
          } else {
            if (item.id == 'apply_patch') return false;
          }
          return true;
        })
        .map((item) => item.toModel())
        .toList();
  }

  Future<List<ToolDefinitionModel>> availableForWorkspaceAgent(
    WorkspaceInfo workspace,
    AgentDefinition agent, {
    String? modelId,
    List<ToolDefinitionModel> extraTools = const [],
  }) async {
    final tools = [...availableForAgent(agent, modelId: modelId), ...extraTools];
    final hasSkillTool = tools.any((item) => item.id == 'skill');
    if (!hasSkillTool) return tools;
    final skills = await SkillRegistry.instance.available(
      workspace,
      agentDefinition: agent,
    );
    final registry = SkillRegistry.instance;
    return tools.map((item) {
      if (item.id != 'skill') return item;
      final parameters = Map<String, dynamic>.from(item.parameters);
      final properties = Map<String, dynamic>.from(
        parameters['properties'] as Map? ?? const <String, dynamic>{},
      );
      final nameSpec = Map<String, dynamic>.from(
        properties['name'] as Map? ?? const <String, dynamic>{},
      );
      nameSpec['description'] = registry.toolNameParameterDescription(skills);
      properties['name'] = nameSpec;
      parameters['properties'] = properties;
      return ToolDefinitionModel(
        id: item.id,
        description: registry.toolDescription(skills),
        parameters: parameters,
      );
    }).toList(growable: false);
  }

  ToolDefinition? operator [](String id) => _definitions[id];
}
