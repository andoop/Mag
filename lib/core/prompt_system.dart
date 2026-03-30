import 'models.dart';
import 'workspace_bridge.dart';

class PromptContext {
  PromptContext({
    required this.workspace,
    required this.agent,
    required this.model,
    this.agentPrompt,
    required this.hasSkillTool,
    required this.currentStep,
    required this.maxSteps,
    required this.format,
  });

  final WorkspaceInfo workspace;
  final String agent;
  final String model;
  final String? agentPrompt;
  final bool hasSkillTool;
  final int currentStep;
  final int maxSteps;
  final MessageFormat? format;
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
    output.add({
      'role': 'system',
      'content': context.agentPrompt ?? _providerPrompt(context.model),
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
  }) {
    if (agent == 'plan') {
      return '$text\n\n$_planReminder';
    }
    if (switchedFromPlan) {
      return '$text\n\n$_buildSwitchReminder';
    }
    return text;
  }

  String maxStepsReminder() => _maxStepsReminder;

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
    return [
      'You and the user share the same Android workspace.',
      'Current agent: ${context.agent}.',
      'Model: ${context.model}.',
      'Workspace: ${context.workspace.name}.',
      'Tree URI: ${context.workspace.treeUri}.',
      'Date: $now.',
      'Current step: ${context.currentStep}/${context.maxSteps}.',
      'Do not assume shell, PTY, or desktop-only capabilities exist.',
      'Prefer available tools and stay within the workspace boundary.',
    ].join('\n');
  }

  String _skillsPrompt(PromptContext context) {
    if (!context.hasSkillTool) return '';
    return 'The `skill` tool is available. Use it when a named skill would help before acting.';
  }

  Future<String> _projectContextPrompt(WorkspaceInfo workspace) async {
    return _projectContextCache.putIfAbsent(workspace.treeUri, () async {
      final fragments = await _collectContextFragments(workspace);
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

const String openCodeMemoryInitializationPrompt = '''
Analyze this workspace and create or update `OpenCode.md` in the project root.

You must read the workspace before writing. If `OpenCode.md` already exists, improve it instead of replacing useful confirmed facts.

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
  'opencode.md',
  'opencode.local.md',
  'OpenCode.md',
  'OpenCode.local.md',
  'OPENCODE.md',
  'OPENCODE.local.md',
  'AGENTS.md',
];

const String _planReminder = '''<system-reminder>
You are in plan mode.
- Focus on analysis, decomposition, and change planning.
- Do not perform file edits unless they are explicitly allowed.
- Use `plan_exit` when the plan is complete and you are ready to switch back to build mode.
</system-reminder>''';

const String _buildSwitchReminder = '''<system-reminder>
You are no longer in plan mode.
You may now implement the approved plan using available tools and permissions.
</system-reminder>''';

const String _maxStepsReminder = '''CRITICAL - MAXIMUM STEPS REACHED

You must stop using tools and provide a direct final answer.''';

const String _defaultPrompt = '''You are OpenCode, an interactive coding agent.

You help the user complete software engineering tasks inside the current workspace.
- Be concise.
- Prefer tools over guessing.
- Stay within the workspace.
- Do not invent capabilities that are not available.
- Keep going until the task is complete or blocked by the user.
''';

const String _anthropicPrompt =
    '''You are OpenCode, the best coding agent on the planet.

You are an interactive CLI tool that helps users with software engineering tasks.
- Be concise and factual.
- Prefer tools to assumptions.
- Minimize unnecessary output.
- Respect workspace boundaries and permissions.
''';

const String _gptPrompt =
    '''You are OpenCode, You and the user share the same workspace and collaborate to achieve the user's goals.

You are pragmatic, direct, and technically rigorous.
- Build context by reading before changing.
- Use tools to gather facts.
- Prefer actionable, minimal responses.
''';

const String _geminiPrompt =
    '''You are opencode, an interactive CLI agent specializing in software engineering tasks.

Core mandates:
- Follow project conventions.
- Verify libraries and assumptions before using them.
- Use tools safely and efficiently.
''';

const String _codexPrompt =
    '''You are opencode, an interactive CLI tool that helps users with software engineering tasks.

- Keep responses short.
- Explain non-trivial tool use through clear actions.
- Use tools, not guesses.
- Finish the job end to end.
''';

const String explorePrompt = '''You are OpenCode Explore.

Use fast search-oriented behavior.
- Prefer list, glob, and grep before deeper reasoning.
- Read only what is needed.
- Keep answers factual and grounded in the workspace.
''';
