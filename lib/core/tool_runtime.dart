library tool_runtime;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:archive/archive.dart' as archive_pkg;

import 'app_variable_store.dart';
import 'database.dart';
import 'git/exceptions/git_exceptions.dart';
import 'git/git_service.dart';
import 'git/git_settings_store.dart';
import 'json_coerce.dart';
import 'mcp_service.dart';
import 'models.dart';
import 'office_renderer.dart';
import 'qr_code_generator.dart';
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
part 'tool_office.dart';
part 'tool_qr.dart';
part 'tool_archive.dart';
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
              'description': 'File or directory path.',
            },
            'offset': {
              'type': 'integer',
              'description': 'Start line, 1-indexed.',
            },
            'limit': {
              'type': 'integer',
              'description': 'Maximum lines.',
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
              'description': 'Destination file path.',
            },
            'content': {
              'type': 'string',
              'description': 'Full file content.',
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
            '${kEditToolDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'filePath': {
              'type': 'string',
              'description': 'File to edit.',
            },
            'oldString': {
              'type': 'string',
              'description': 'Exact text to replace.',
            },
            'newString': {
              'type': 'string',
              'description':
                  'The replacement text. Must be different from `oldString`.',
            },
            'replaceAll': {
              'type': 'boolean',
              'description': 'Replace all matches.',
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
            'Search file contents line-by-line with a Kotlin-compatible regex. '
            '`path` is an optional directory. `include`/`glob` filters full workspace-relative paths.$kMobileWorkspacePathSuffix',
        parameters: {
          'type': 'object',
          'properties': {
            'pattern': {
              'type': 'string',
              'description':
                  'Regex searched per line. Escape metacharacters for literals.',
            },
            'path': {
              'type': 'string',
              'description':
                  'Optional directory to search. Omit for workspace root.',
            },
            'include': {
              'type': 'string',
              'description':
                  'Optional glob matched against full workspace-relative paths.',
            },
            'glob': {
              'type': 'string',
              'description': 'Alias for `include`.',
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
            'Get workspace file or directory metadata.$kMobileWorkspacePathSuffix',
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
            'Delete a workspace file or directory recursively.$kMobileWorkspacePathSuffix',
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
            'Rename a workspace file or directory within the same parent. `newName` must be one path segment.$kMobileWorkspacePathSuffix',
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
            'Move a workspace file or directory to `toPath`.$kMobileWorkspacePathSuffix',
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
            'Copy a workspace file or directory recursively to `toPath`.$kMobileWorkspacePathSuffix',
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
        id: 'variable',
        description:
            'List or read user-authorized app variables. Use `list` before `read`.',
        parameters: {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'enum': ['list', 'read'],
              'description':
                  'Use list to show available variables, read to fetch one value.',
            },
            'name': {
              'type': 'string',
              'description':
                  'Variable name to read. Required when action is read.',
            },
          },
          'required': ['action'],
          'additionalProperties': false,
        },
        execute: _variableTool,
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
              'description': 'URL to fetch.',
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
              'description': 'Public http/https URL.',
            },
            'filePath': {
              'type': 'string',
              'description': 'Destination path.',
            },
            'overwrite': {
              'type': 'boolean',
              'description': 'Replace existing file.',
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
        id: 'create_document',
        description:
            '${_kCreateDocumentDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: officeDocumentToolParametersSchema(),
        execute: _createDocumentTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'create_spreadsheet',
        description:
            '${_kCreateSpreadsheetDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: officeSpreadsheetToolParametersSchema(),
        execute: _createSpreadsheetTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'create_presentation',
        description:
            '${_kCreatePresentationDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: officePresentationToolParametersSchema(),
        execute: _createPresentationTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'create_qr_code',
        description:
            '${_kCreateQrCodeDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: qrCodeToolParametersSchema(),
        execute: _createQrCodeTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'zip',
        description:
            '${_kZipToolDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: zipToolParametersSchema(),
        execute: _zipTool,
      ),
    );
    register(
      ToolDefinition(
        id: 'unzip',
        description:
            '${_kUnzipToolDescription.trim()}$kMobileWorkspacePathSuffix',
        parameters: unzipToolParametersSchema(),
        execute: _unzipTool,
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
              'description': 'Limit to one MCP server.',
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
              'description': 'Limit to one MCP server.',
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
              'description': 'String arguments for the MCP prompt.',
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
            'Load workspace-local skill instructions by name. Returns instructions '
            'and sampled sibling files; does not execute scripts or hooks.',
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
            'Run git operations on the workspace repository. Set `command` to a git subcommand; '
            'use matching optional fields for that command.',
        parameters: {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'description':
                  'status | add | restore | reset | commit | log | diff | '
                      'branch | checkout | merge | cherry-pick | init | show | clone | fetch | pull | push | rebase | config | remote-url | remote',
            },
            'paths': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Paths for add, diff, restore, reset.',
            },
            'all': {
              'type': 'boolean',
              'description': 'Stage all changes.',
            },
            'message': {
              'type': 'string',
              'description': 'Commit/continue message.',
            },
            'amend': {
              'type': 'boolean',
              'description': 'Amend last commit.',
            },
            'maxCount': {
              'type': 'integer',
              'description': 'Max entries for log.',
            },
            'firstParentOnly': {
              'type': 'boolean',
              'description': 'Follow first parent only.',
            },
            'since': {
              'type': 'string',
              'description': 'ISO-8601 lower time bound.',
            },
            'until': {
              'type': 'string',
              'description': 'ISO-8601 upper time bound.',
            },
            'action': {
              'type': 'string',
              'description':
                  'Sub-action for branch/config/remote/merge/cherry-pick/rebase.',
            },
            'name': {
              'type': 'string',
              'description': 'Branch or remote name.',
            },
            'force': {
              'type': 'boolean',
              'description': 'Force when supported.',
            },
            'startPoint': {
              'type': 'string',
              'description': 'Start point ref.',
            },
            'target': {
              'type': 'string',
              'description': 'Checkout/reset target.',
            },
            'newBranch': {
              'type': 'boolean',
              'description': 'Create and switch to new branch.',
            },
            'mode': {
              'type': 'string',
              'description': 'Reset mode: soft | mixed | hard.',
            },
            'branch': {
              'type': 'string',
              'description': 'Branch for merge/fetch/pull.',
            },
            'remote': {
              'type': 'string',
              'description': 'Remote name.',
            },
            'oldName': {
              'type': 'string',
              'description': 'Existing remote name.',
            },
            'newName': {
              'type': 'string',
              'description': 'New remote name.',
            },
            'url': {
              'type': 'string',
              'description': 'Remote URL or local repo path.',
            },
            'path': {
              'type': 'string',
              'description': 'Workspace-relative clone destination.',
            },
            'rebase': {
              'type': 'boolean',
              'description': 'Pull with rebase.',
            },
            'refspec': {
              'type': 'string',
              'description': 'Explicit push refspec.',
            },
            'ref': {
              'type': 'string',
              'description': 'Commit or branch ref.',
            },
            'authorName': {
              'type': 'string',
              'description': 'Commit author name.',
            },
            'authorEmail': {
              'type': 'string',
              'description': 'Commit author email.',
            },
            'section': {
              'type': 'string',
              'description': 'Config section.',
            },
            'key': {
              'type': 'string',
              'description': 'Config key.',
            },
            'value': {
              'type': 'string',
              'description': 'Config value.',
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
    final tools = [
      ...availableForAgent(agent, modelId: modelId),
      ...extraTools
    ];
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
