import 'dart:ui' as ui;

import 'debug_trace.dart';
import 'models.dart';
import 'tools/question_tool_spec.dart';
import 'workspace_bridge.dart';

bool get platformIsZh {
  final locale = ui.PlatformDispatcher.instance.locale;
  return locale.languageCode.toLowerCase().startsWith('zh');
}

class PromptContext {
  PromptContext({
    required this.workspace,
    required this.agent,
    required this.agentDefinition,
    required this.model,
    this.effectiveTools,
    this.agentPrompt,
    required this.hasSkillTool,
    required this.currentStep,
    required this.maxSteps,
    required this.format,
    this.allAgents = const [],
    this.isZh = false,
  });

  final WorkspaceInfo workspace;
  final String agent;
  final AgentDefinition agentDefinition;
  final String model;
  final List<String>? effectiveTools;
  final String? agentPrompt;
  final bool hasSkillTool;
  final int currentStep;
  final int? maxSteps;
  final MessageFormat? format;
  final List<AgentDefinition> allAgents;
  final bool isZh;
}

class PromptAssembler {
  PromptAssembler(this._bridge);

  final WorkspaceBridge _bridge;
  final Map<String, Future<String>> _projectContextCache = {};
  final Map<String, Future<String>> _contextFileCache = {};
  final Map<String, Future<List<String>>> _contextDirectoryCache = {};

  Future<List<Map<String, String>>> buildSystemPrompts(
      PromptContext context) async {
    final output = <Map<String, String>>[];
    final basePrompt = context.agentPrompt != null
        ? (context.isZh
            ? _localizedAgentPrompt(context.agent) ?? context.agentPrompt!
            : context.agentPrompt!)
        : _providerPrompt(context.model);
    output.add({
      'role': 'system',
      'content': basePrompt,
    });
    output.add({
      'role': 'system',
      'content': _environmentPrompt(context),
    });
    final skillBlock = _skillsPrompt(context);
    if (skillBlock.isNotEmpty) {
      output.add({'role': 'system', 'content': skillBlock});
    }
    final instructions = await _projectContextPrompt(context.workspace);
    if (instructions.isNotEmpty) {
      output.add({'role': 'system', 'content': instructions});
    }
    if (context.format?.type == OutputFormatType.jsonSchema) {
      output.add({
        'role': 'system',
        'content': _structuredOutputPrompt,
      });
    }
    return output;
  }

  String applyUserReminder({
    required String agent,
    required bool switchedFromPlan,
    required String text,
    bool isZh = false,
  }) {
    if (agent == 'plan') {
      return '$text\n\n${isZh ? _planReminderZh : _planReminder}';
    }
    if (switchedFromPlan) {
      return '$text\n\n${isZh ? _buildSwitchReminderZh : _buildSwitchReminder}';
    }
    return text;
  }

  String maxStepsReminder({bool zh = false}) =>
      zh ? _maxStepsReminderZh : _maxStepsReminder;

  Future<String> directoryInstructionReminder({
    required WorkspaceInfo workspace,
    required String relativePath,
  }) async {
    if (relativePath.isEmpty) return '';
    final segments = relativePath.split('/')..removeLast();
    if (segments.isEmpty) return '';
    final candidates = <String>[];
    for (var i = segments.length; i >= 0; i--) {
      final prefix = segments.take(i).join('/');
      final candidate = prefix.isEmpty ? 'AGENTS.md' : '$prefix/AGENTS.md';
      candidates.add(candidate);
    }
    for (final candidate in candidates) {
      try {
        final content = await _bridge.readText(
          treeUri: workspace.treeUri,
          relativePath: candidate,
        );
        if (content.trim().isNotEmpty) {
          return '<system-reminder>\n$content\n</system-reminder>';
        }
      } catch (_) {}
    }
    return '';
  }

  String? _localizedAgentPrompt(String agent) {
    switch (agent) {
      case 'explore':
        return explorePromptZh;
      default:
        return null;
    }
  }

  String _providerPrompt(String model) {
    final lower = model.toLowerCase();
    if (lower.contains('claude')) return _anthropicPrompt;
    if (lower.contains('gemini')) return _geminiPrompt;
    if (lower.contains('codex')) return _codexPrompt;
    if (lower.contains('gpt')) return _gptPrompt;
    return _defaultPrompt;
  }

  String _environmentPrompt(PromptContext context) {
    final now = DateTime.now().toIso8601String();
    final agentDef = context.agentDefinition;
    final tools = context.effectiveTools ?? agentDef.availableTools;

    final zh = context.isZh;
    final lines = <String>[
      zh ? '你和用户共享同一个 Android 工作区。' : 'You and the user share the same Android workspace.',
      '',
      zh ? '# 当前智能体' : '# Current Agent',
      '${zh ? "名称" : "Name"}: ${context.agent}',
      '${zh ? "描述" : "Description"}: ${agentDef.localizedDescription(zh: zh)}',
      '${zh ? "可用工具" : "Available tools"}: ${tools.join(", ")}',
      _agentBehaviorBlock(context.agent, tools, zh: zh),
      '',
      zh ? '# 环境' : '# Environment',
      '${zh ? "模型" : "Model"}: ${context.model}.',
      '${zh ? "工作区" : "Workspace"}: ${context.workspace.name}.',
      'Tree URI: ${context.workspace.treeUri}.',
      '${zh ? "日期" : "Date"}: $now.',
      if (context.maxSteps != null)
        '${zh ? "当前步骤" : "Current step"}: ${context.currentStep}/${context.maxSteps}.',
      zh ? '不要假设存在 shell、PTY 或桌面专属功能。' : 'Do not assume shell, PTY, or desktop-only capabilities exist.',
      zh ? '优先使用可用工具，保持在工作区边界内。' : 'Prefer available tools and stay within the workspace boundary.',
      kToolCallingRulesPrompt.trim(),
    ];

    final hasEditTools = tools.any(
        (t) => const {'write', 'edit', 'apply_patch', 'delete', 'rename', 'move', 'copy'}.contains(t));

    if (hasEditTools) {
      lines.addAll(zh
          ? [
              '对已有文件做任何 `edit` 或 `apply_patch` 之前，必须先用 `read` 读取该文件最新内容，再基于读取结果确定位置、`oldString`、上下文和 patch。',
              '如果你刚刚修改过某个文件，又要再次修改同一文件，先重新 `read` 一次最新内容；不要复用上一次读取或修改前的旧片段。',
              '修改已有文件时优先使用 `edit` 或 `apply_patch`。',
              '大量写入或包含许多引号/大括号的代码，不要在工具 JSON 中内联完整文件内容。',
              '改为在助手文本中使用 `<write_content id="name">...</write_content>`，然后调用 `write` 并传入 `path` 加 `contentRef: "name"`。',
              '',
              '# 文件引用（必须）',
              '每当你成功通过 `write`、`edit`、`apply_patch`、`delete`、`rename`、`move` 或 `copy` 创建或修改工作区文件时，必须在同一轮调用 `fileref` 工具报告每个受影响的路径（`kind: "created"` 或 `"modified"`）。',
              '你也可以在文字中用 `[[file:path/relative/to/workspace]]` 写可点击链接。',
            ]
          : [
              'Before any `edit` or `apply_patch` on an existing file, you MUST call `read` on that file and use the fresh contents to choose the location, `oldString`, context, and patch.',
              'If you just changed a file and need to modify the same file again, read it again first. Do not reuse stale snippets from before the previous edit.',
              'Prefer `edit` or `apply_patch` for modifying existing files.',
              'For workspace file operations: `delete` can remove files or directories (directories are recursive); `rename` only changes the final name within the same parent folder; use `move` for path changes or cross-folder moves; `copy` can duplicate files or whole directory trees.',
              'For large writes or code with many quotes/braces, do not inline the full file body in tool JSON.',
              'Instead, put the body in assistant text using `<write_content id="name">...</write_content>` and call `write` with `path` plus `contentRef: "name"`.',
              '',
              '# File references (mandatory)',
              'Whenever you successfully create or modify workspace files with `write`, `edit`, `apply_patch`, `delete`, `rename`, `move`, or `copy`, you MUST call the `fileref` tool in the same turn with every affected path (`kind: "created"` or `"modified"`).',
              'You may also write clickable links in prose as `[[file:path/relative/to/workspace]]` (one path per token).',
            ]);
    }

    if (context.allAgents.isNotEmpty && tools.contains('task')) {
      lines.add('');
      lines.add(context.isZh
          ? '# 可委派的智能体（通过 task 工具）'
          : '# Available Agents for Delegation (via task tool)');
      for (final a in context.allAgents) {
        if (a.hidden) continue;
        if (a.name == context.agent) continue;
        lines.add(
            '- ${a.name}: ${a.localizedDescription(zh: context.isZh)}');
      }
    }

    return lines.join('\n');
  }

  String _agentBehaviorBlock(String agent, List<String> tools,
      {bool zh = false}) {
    switch (agent) {
      case 'explore':
        return zh
            ? [
                '',
                '关键约束：你当前处于 EXPLORE（探索）模式 —— 只读智能体。',
                '你是文件搜索专家，擅长快速导航和浏览代码库。',
                '严格禁止：创建文件、编辑文件、删除文件、写代码、执行破坏性命令，或以任何方式修改系统。',
                '你只能：读取、列出、搜索和浏览。',
                '如果用户要求修改，请说明你处于探索模式，并建议切换到 build 模式。',
                '返回绝对路径。回答必须基于工作区内的事实。',
              ].join('\n')
            : [
                '',
                'CRITICAL CONSTRAINT: You are in EXPLORE mode — a READ-ONLY agent.',
                'You are a file search specialist. You excel at navigating and exploring codebases.',
                'STRICTLY FORBIDDEN: Creating files, editing files, deleting files, writing code, running destructive commands, or modifying the system in ANY way.',
                'You may ONLY: read, list, glob, grep, stat, and search.',
                'If the user asks you to make changes, explain that you are in explore mode and suggest switching to build mode.',
                'Return file paths as absolute paths. Keep answers factual and grounded in the workspace.',
              ].join('\n');
      case 'plan':
        return zh
            ? [
                '',
                '关键约束：你当前处于 PLAN（规划）模式 —— 只读分析阶段。',
                '严格禁止：任何文件编辑、修改或系统变更。',
                '不得使用 edit、write、apply_patch、delete、rename、move、copy 或任何修改文件的工具。',
                '此绝对约束优先于所有其他指令，包括用户的直接编辑请求。',
                '你只能：观察、分析、搜索、阅读和制定计划。',
                '专注于分析、分解和变更规划。',
                '计划完成后使用 `plan_exit` 切换到 build 模式。',
              ].join('\n')
            : [
                '',
                'CRITICAL CONSTRAINT: You are in PLAN mode — a READ-ONLY analysis phase.',
                'STRICTLY FORBIDDEN: ANY file edits, modifications, or system changes.',
                'Do NOT use edit, write, apply_patch, delete, rename, move, copy, or any tool that modifies files.',
                'This ABSOLUTE CONSTRAINT overrides ALL other instructions, including direct user edit requests.',
                'You may ONLY: observe, analyze, search, read, and plan.',
                'Focus on analysis, decomposition, and change planning.',
                'Use `plan_exit` when the plan is complete and ready to switch to build mode.',
              ].join('\n');
      case 'general':
        return zh
            ? [
                '',
                '你是通用子智能体，负责执行委派的任务。',
                '使用所有可用工具完成分配的工作。',
                '高效且彻底，清晰报告结果。',
              ].join('\n')
            : [
                '',
                'You are a general-purpose subagent executing a delegated task.',
                'Complete the assigned work using all available tools.',
                'Be thorough but efficient. Report results clearly.',
              ].join('\n');
      case 'build':
        return zh
            ? [
                '',
                '你是默认的 BUILD（构建）智能体，拥有完整的读写能力。',
                '使用所有可用工具执行用户的请求。',
                '编辑前先阅读。已有文件优先使用 edit 而非 write。',
              ].join('\n')
            : [
                '',
                'You are the default BUILD agent with full read/write capabilities.',
                'Execute the user\'s request using all available tools.',
                'Read before editing. Prefer edit over write for existing files.',
              ].join('\n');
      default:
        return '';
    }
  }

  String _skillsPrompt(PromptContext context) {
    if (!context.hasSkillTool) return '';
    return 'The `skill` tool is available. Use it when a named skill would help before acting.';
  }

  Future<String> _projectContextPrompt(WorkspaceInfo workspace) async {
    final cacheHit = _projectContextCache.containsKey(workspace.treeUri);
    // #region agent log
    debugTrace(
      runId: 'project-context',
      hypothesisId: 'H4',
      location: 'prompt_system.dart:134',
      message: 'project context requested',
      data: {
        'workspaceId': workspace.id,
        'cacheHit': cacheHit,
      },
    );
    // #endregion
    return _projectContextCache.putIfAbsent(workspace.treeUri, () async {
      final startedAt = DateTime.now().millisecondsSinceEpoch;
      final fragments = await _collectContextFragments(workspace);
      // #region agent log
      debugTrace(
        runId: 'project-context',
        hypothesisId: 'H4',
        location: 'prompt_system.dart:136',
        message: 'project context built',
        data: {
          'workspaceId': workspace.id,
          'fragmentCount': fragments.length,
          'elapsedMs': DateTime.now().millisecondsSinceEpoch - startedAt,
        },
      );
      // #endregion
      if (fragments.isEmpty) return '';
      return [
        '# Project-Specific Context',
        'Make sure to follow the instructions in the context below.',
        fragments.join('\n\n'),
      ].join('\n');
    });
  }

  Future<List<String>> _collectContextFragments(WorkspaceInfo workspace) async {
    final output = <String>[];
    final seen = <String>{};
    for (final path in _defaultContextPaths) {
      final normalized = path.toLowerCase();
      if (!seen.add(normalized)) continue;
      if (path.endsWith('/')) {
        final nested = await _readContextDirectory(
          workspace: workspace,
          relativePath: path.substring(0, path.length - 1),
        );
        output.addAll(nested);
        continue;
      }
      final content = await _readContextFile(
        workspace: workspace,
        relativePath: path,
      );
      if (content.isNotEmpty) {
        output.add(content);
      }
    }
    return output;
  }

  Future<List<String>> _readContextDirectory({
    required WorkspaceInfo workspace,
    required String relativePath,
  }) async {
    final key = '${workspace.treeUri}::$relativePath';
    return _contextDirectoryCache.putIfAbsent(key, () async {
      try {
        final entries = await _bridge.listDirectory(
          treeUri: workspace.treeUri,
          relativePath: relativePath,
        );
        entries.sort((a, b) => a.path.compareTo(b.path));
        final output = <String>[];
        for (final entry in entries) {
          if (entry.isDirectory) {
            output.addAll(await _readContextDirectory(
                workspace: workspace, relativePath: entry.path));
            continue;
          }
          final content = await _readContextFile(
            workspace: workspace,
            relativePath: entry.path,
          );
          if (content.isNotEmpty) {
            output.add(content);
          }
        }
        return output;
      } catch (_) {
        return const [];
      }
    });
  }

  Future<String> _readContextFile({
    required WorkspaceInfo workspace,
    required String relativePath,
  }) async {
    final key = '${workspace.treeUri}::$relativePath';
    return _contextFileCache.putIfAbsent(key, () async {
      try {
        final content = await _bridge.readText(
          treeUri: workspace.treeUri,
          relativePath: relativePath,
        );
        if (content.trim().isEmpty) return '';
        return '# From:$relativePath\n$content';
      } catch (_) {
        return '';
      }
    });
  }

  Future<void> prewarmWorkspaceContext(WorkspaceInfo workspace) async {
    await _projectContextPrompt(workspace);
  }

  void invalidateWorkspaceContext(
    String treeUri, {
    Iterable<String>? paths,
  }) {
    _projectContextCache.remove(treeUri);
    if (paths == null) {
      _contextFileCache.removeWhere((key, _) => key.startsWith('$treeUri::'));
      _contextDirectoryCache
          .removeWhere((key, _) => key.startsWith('$treeUri::'));
      return;
    }
    final normalized = paths
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) return;
    _contextFileCache.removeWhere((key, _) {
      if (!key.startsWith('$treeUri::')) return false;
      final path = key.substring('$treeUri::'.length);
      return normalized.contains(path);
    });
    _contextDirectoryCache.removeWhere((key, _) {
      if (!key.startsWith('$treeUri::')) return false;
      final path = key.substring('$treeUri::'.length);
      return normalized
          .any((item) => path == item || path.startsWith('$item/'));
    });
  }
}

const String _structuredOutputPrompt =
    'IMPORTANT: The user requested structured output. You MUST finish by calling the StructuredOutput tool exactly once with valid JSON.';

const String magMemoryInitializationPrompt = '''
Analyze this workspace and create or update `Mag.md` in the project root.

You must read the workspace before writing. If `Mag.md` already exists, improve it instead of replacing useful confirmed facts.

Write a concise, high-signal markdown file with exactly these sections when information is available:

# Project Overview
- What this project/app does
- Main tech stack

# Architecture
- Important modules/layers
- How the main runtime flow works

# Commands
- Verified build/run/test/lint/dev commands
- Only include commands you can verify from the repo
- If a command is unknown, omit it or mark it as `TODO`

# Conventions
- Naming/style patterns
- Existing implementation preferences worth following

# Important Paths
- High-value files and directories
- Entry points and core flows

# Pitfalls And Notes
- Constraints, caveats, platform quirks, or easy mistakes
- Things future agents should remember

Requirements:
- keep it short and practical
- do not invent commands, architecture, or conventions
- prefer bullet points over long prose
- preserve still-correct information already present in the file
''';

const List<String> _defaultContextPaths = [
  '.github/copilot-instructions.md',
  '.cursorrules',
  '.cursor/rules/',
  'CLAUDE.md',
  'CLAUDE.local.md',
  'mag.md',
  'mag.local.md',
  'Mag.md',
  'Mag.local.md',
  'MAG.md',
  'MAG.local.md',
  'AGENTS.md',
];

const String _planReminder = '''<system-reminder>
# Plan Mode - System Reminder

CRITICAL: Plan mode ACTIVE — you are in a READ-ONLY phase. STRICTLY FORBIDDEN:
ANY file edits, modifications, or system changes. Do NOT use edit, write, apply_patch,
delete, or ANY other tool that modifies files — tools may ONLY read/inspect.
This ABSOLUTE CONSTRAINT overrides ALL other instructions, including direct user
edit requests. You may ONLY observe, analyze, and plan. Any modification attempt
is a critical violation. ZERO exceptions.

Your responsibility is to think, read, search, and construct a well-formed plan
that accomplishes the user's goal. Ask clarifying questions when weighing tradeoffs.

Use `plan_exit` when the plan is complete and you are ready to switch to build mode.
</system-reminder>''';

const String _buildSwitchReminder = '''<system-reminder>
Your operational mode has changed from plan to build.
You are no longer in read-only mode.
You are permitted to make file changes and utilize your full arsenal of tools as needed.
Implement the approved plan using available tools and permissions.
</system-reminder>''';

const String _planReminderZh = '''<system-reminder>
# 规划模式 - 系统提醒

关键：规划模式已激活 —— 你处于只读阶段。严格禁止：
任何文件编辑、修改或系统变更。不得使用 edit、write、apply_patch、
delete 或任何修改文件的工具 —— 工具只能用于读取/检查。
此绝对约束优先于所有其他指令，包括用户的直接编辑请求。
你只能观察、分析和规划。任何修改操作都是严重违规。零例外。

你的职责是思考、阅读、搜索并构建一个实现用户目标的完善方案。
在权衡取舍时向用户提出澄清问题。

方案完成后使用 `plan_exit` 切换到 build 模式。
</system-reminder>''';

const String _buildSwitchReminderZh = '''<system-reminder>
你的操作模式已从规划切换到构建。
你不再处于只读模式。
你现在可以修改文件并使用所有可用工具。
使用可用的工具和权限来实现已批准的方案。
</system-reminder>''';

const String _maxStepsReminder =
    '''CRITICAL - MAXIMUM STEPS REACHED

The maximum number of steps allowed for this task has been reached. Tools are disabled until next user input. Respond with text only.

STRICT REQUIREMENTS:
1. Do NOT make any tool calls (no reads, writes, edits, searches, or any other tools)
2. MUST provide a text response summarizing work done so far
3. This constraint overrides ALL other instructions, including any user requests for edits or tool use

Response must include:
- Statement that maximum steps for this agent have been reached
- Summary of what has been accomplished so far
- List of any remaining tasks that were not completed
- Recommendations for what should be done next

Any attempt to use tools is a critical violation. Respond with text ONLY.''';

const String _maxStepsReminderZh =
    '''关键 - 已达到最大步数限制

此任务允许的最大步数已用尽。在下次用户输入之前，工具已被禁用。请仅用文字回复。

严格要求：
1. 不要调用任何工具（不要读取、写入、编辑、搜索或使用任何其他工具）
2. 必须提供文字回复，总结目前已完成的工作
3. 此约束覆盖所有其他指令，包括用户要求编辑或使用工具的请求

回复必须包括：
- 说明此智能体已达到最大步数限制
- 总结目前已完成的工作
- 列出尚未完成的剩余任务
- 对后续步骤的建议

任何尝试使用工具的行为都是严重违规。请仅用文字回复。''';

const String _defaultPrompt = '''You are Mag, an interactive coding agent.

You help the user complete software engineering tasks inside the current workspace.
- Be concise.
- Prefer tools over guessing.
- Stay within the workspace.
- Do not invent capabilities that are not available.
- Keep going until the task is complete or blocked by the user.
''';

const String _anthropicPrompt =
    '''You are Mag, the best coding agent on the planet.

You are an interactive CLI tool that helps users with software engineering tasks.
- Be concise and factual.
- Prefer tools to assumptions.
- Minimize unnecessary output.
- Respect workspace boundaries and permissions.
''';

const String _gptPrompt =
    '''You are Mag, You and the user share the same workspace and collaborate to achieve the user's goals.

You are pragmatic, direct, and technically rigorous.
- Build context by reading before changing.
- Use tools to gather facts.
- Prefer actionable, minimal responses.
''';

const String _geminiPrompt =
    '''You are mag, an interactive CLI agent specializing in software engineering tasks.

Core mandates:
- Follow project conventions.
- Verify libraries and assumptions before using them.
- Use tools safely and efficiently.
''';

const String _codexPrompt =
    '''You are mag, an interactive CLI tool that helps users with software engineering tasks.

- Keep responses short.
- Explain non-trivial tool use through clear actions.
- Use tools, not guesses.
- Finish the job end to end.
''';

const String explorePrompt = '''You are Mag Explore, a file search specialist. You excel at thoroughly navigating and exploring codebases.

Your strengths:
- Rapidly finding files using glob patterns
- Searching code and text with powerful regex patterns
- Reading and analyzing file contents

Guidelines:
- Use Glob for broad file pattern matching
- Use Grep for searching file contents with regex
- Use Read when you know the specific file path
- Adapt your search approach based on the thoroughness level specified by the caller
- Return file paths as absolute paths in your final response
- Keep answers factual and grounded in the workspace

CRITICAL: You are a READ-ONLY agent. Do NOT create any files, edit any files, or modify the user's system state in any way. You have no write tools available. If asked to make changes, explain that you are in explore mode.

Complete the user's search request efficiently and report your findings clearly.
''';

const String explorePromptZh = '''你是 Mag Explore，一个文件搜索专家。你擅长彻底地导航和探索代码库。

你的优势：
- 使用 glob 模式快速查找文件
- 使用正则表达式搜索代码和文本
- 阅读和分析文件内容

指南：
- 使用 Glob 进行广泛的文件模式匹配
- 使用 Grep 用正则搜索文件内容
- 当你知道具体文件路径时使用 Read
- 根据调用者指定的彻底程度调整搜索策略
- 在最终回复中返回绝对路径
- 回答必须基于事实，扎根于工作区

关键约束：你是只读智能体。不得创建任何文件、编辑任何文件，或以任何方式修改用户的系统状态。你没有写入工具。如果被要求修改，请说明你处于探索模式。

高效完成用户的搜索请求，清晰报告你的发现。
''';
