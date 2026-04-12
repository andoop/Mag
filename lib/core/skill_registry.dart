import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';
import 'workspace_bridge.dart';

class SkillInfo {
  SkillInfo({
    required this.name,
    required this.description,
    required this.location,
    required this.directory,
    required this.locationPath,
    required this.directoryPath,
    required this.content,
    required this.workspaceRelative,
    this.requiredTools = const [],
  });

  final String name;
  final String description;
  final String location;
  final String directory;
  final String locationPath;
  final String directoryPath;
  final String content;
  final bool workspaceRelative;
  final List<String> requiredTools;
}

class SkillRegistry {
  SkillRegistry(this._bridge);

  static final SkillRegistry instance = SkillRegistry(WorkspaceBridge.instance);

  final WorkspaceBridge _bridge;
  final Map<String, Future<List<SkillInfo>>> _cache = {};

  static const List<String> _workspaceExternalRoots = [
    '.claude/skills',
    '.agents/skills',
  ];
  static const List<String> _workspaceOpenCodeRoots = [
    '.opencode/skill',
    '.opencode/skills',
  ];
  static final List<SkillInfo> _builtinSkills = [
    SkillInfo(
      name: 'public-file-download',
      description:
          'Download a public http/https file into the workspace at a chosen path.',
      location: 'builtin://skills/public-file-download',
      directory: 'builtin://skills/public-file-download',
      locationPath: 'builtin://skills/public-file-download',
      directoryPath: 'builtin://skills/public-file-download',
      content: '''
Use this skill when the user wants a remote public file to exist inside the workspace.

Workflow:
1. Decide whether you only need to inspect remote text first. If so, prefer `webfetch`.
2. If the user needs an actual file saved into the workspace, use `download`.
3. Always provide an explicit workspace-relative `filePath`.
4. Pick a destination path that matches the file type and project context, such as `downloads/`, `assets/`, or another user-requested location.
5. If the destination already exists, only set `overwrite: true` when you intentionally want to replace it.
6. After downloading, use `read`, preview, or other workspace tools to inspect or continue working with the saved file.

Do not use this skill for authenticated browser-only downloads, login-gated URLs, or websites that require cookies or manual interaction.
''',
      workspaceRelative: false,
      requiredTools: ['download'],
    ),
  ];

  Future<List<SkillInfo>> all(WorkspaceInfo workspace) {
    return _cache.putIfAbsent(
      workspace.treeUri,
      () => _scanWorkspace(workspace),
    );
  }

  Future<List<SkillInfo>> available(
    WorkspaceInfo workspace, {
    AgentDefinition? agentDefinition,
  }) async {
    final list = await all(workspace);
    if (agentDefinition == null) return list;
    return list
        .where((skill) =>
            skill.requiredTools.every(agentDefinition.availableTools.contains) &&
            _evaluatePermission('skill', skill.name, agentDefinition) !=
            PermissionAction.deny)
        .toList(growable: false);
  }

  Future<SkillInfo?> get(
    WorkspaceInfo workspace,
    String name, {
    AgentDefinition? agentDefinition,
  }) async {
    final list = await available(workspace, agentDefinition: agentDefinition);
    for (final skill in list) {
      if (skill.name == name) return skill;
    }
    return null;
  }

  void invalidateWorkspace(String treeUri) {
    _cache.remove(treeUri);
  }

  String format(
    List<SkillInfo> list, {
    required bool verbose,
  }) {
    if (list.isEmpty) return 'No skills are currently available.';
    if (verbose) {
      return [
        '<available_skills>',
        ...list.expand((skill) => [
              '  <skill>',
              '    <name>${_escapeXml(skill.name)}</name>',
              '    <description>${_escapeXml(skill.description)}</description>',
              '    <location>${_escapeXml(skill.location)}</location>',
              '  </skill>',
            ]),
        '</available_skills>',
      ].join('\n');
    }
    return [
      '## Available Skills',
      ...list.map((skill) => '- **${skill.name}**: ${skill.description}'),
    ].join('\n');
  }

  String toolDescription(List<SkillInfo> list) {
    if (list.isEmpty) {
      return 'Load a specialized skill that provides domain-specific '
          'instructions and workflows. No skills are currently available.';
    }
    return [
      'Load a specialized skill that provides domain-specific instructions and workflows.',
      '',
      'When you recognize that a task matches one of the available skills listed below, use this tool to load the full skill instructions.',
      '',
      'This tool only loads skill instructions and bundled references into the conversation context. It does not execute scripts or hooks.',
      '',
      'Tool output includes a `<skill_content name="...">` block with the loaded content.',
      '',
      'Invoke this tool to load a skill when a task matches one of the available skills listed below:',
      '',
      format(list, verbose: false),
    ].join('\n');
  }

  String toolNameParameterDescription(List<SkillInfo> list) {
    final examples = list
        .map((skill) => "'${skill.name}'")
        .take(3)
        .join(', ');
    final hint = examples.isNotEmpty ? ' (e.g., $examples, ...)' : '';
    return 'The name of the skill from available_skills$hint';
  }

  Future<List<String>> sampleFiles(
    WorkspaceInfo workspace,
    SkillInfo skill, {
    int limit = 10,
  }) async {
    if (limit <= 0) return const [];
    if (!skill.workspaceRelative) return const [];
    final resolvedRoot = await _bridge.resolveFilesystemPath(
      treeUri: workspace.treeUri,
    );
    final results = <String>[];
    await _collectSkillFiles(
      workspace: workspace,
      resolvedRoot: resolvedRoot,
      directory: skill.directoryPath,
      out: results,
      limit: limit,
    );
    return results;
  }

  Future<List<SkillInfo>> _scanWorkspace(WorkspaceInfo workspace) async {
    final skillsByName = <String, SkillInfo>{
      for (final skill in _builtinSkills) skill.name: skill,
    };
    final resolvedRoot = await _bridge.resolveFilesystemPath(
      treeUri: workspace.treeUri,
    );

    for (final root in _workspaceExternalRoots) {
      await _scanWorkspaceRoot(
        workspace: workspace,
        resolvedRoot: resolvedRoot,
        root: root,
        onSkill: (skill) => skillsByName[skill.name] = skill,
      );
    }
    for (final root in _workspaceOpenCodeRoots) {
      await _scanWorkspaceRoot(
        workspace: workspace,
        resolvedRoot: resolvedRoot,
        root: root,
        onSkill: (skill) => skillsByName[skill.name] = skill,
      );
    }

    final list = skillsByName.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List<SkillInfo>.unmodifiable(list);
  }

  Future<void> _scanWorkspaceRoot({
    required WorkspaceInfo workspace,
    required String? resolvedRoot,
    required String root,
    required void Function(SkillInfo skill) onSkill,
  }) async {
    final entries = await _bridge.listDirectory(
      treeUri: workspace.treeUri,
      relativePath: root,
    );
    if (entries.isEmpty) return;
    await _scanWorkspaceDirectory(
      workspace: workspace,
      resolvedRoot: resolvedRoot,
      directory: root,
      entries: entries,
      onSkill: onSkill,
    );
  }

  Future<void> _scanWorkspaceDirectory({
    required WorkspaceInfo workspace,
    required String? resolvedRoot,
    required String directory,
    required List<WorkspaceEntry> entries,
    required void Function(SkillInfo skill) onSkill,
  }) async {
    for (final entry in entries) {
      if (entry.isDirectory) {
        final childEntries = await _bridge.listDirectory(
          treeUri: workspace.treeUri,
          relativePath: entry.path,
        );
        if (childEntries.isEmpty) continue;
        await _scanWorkspaceDirectory(
          workspace: workspace,
          resolvedRoot: resolvedRoot,
          directory: entry.path,
          entries: childEntries,
          onSkill: onSkill,
        );
        continue;
      }
      if (entry.name != 'SKILL.md') continue;
      final raw = await _bridge.readText(
        treeUri: workspace.treeUri,
        relativePath: entry.path,
      );
      final parsed = _parseSkillMarkdown(raw);
      if (parsed == null) continue;
      onSkill(
        SkillInfo(
          name: parsed.name,
          description: parsed.description,
          location: _displayLocation(
            resolvedRoot: resolvedRoot,
            relativePath: entry.path,
          ),
          directory: _displayLocation(
            resolvedRoot: resolvedRoot,
            relativePath: directory,
          ),
          locationPath: entry.path,
          directoryPath: directory,
          content: parsed.content,
          workspaceRelative: true,
        ),
      );
    }
  }

  Future<void> _collectSkillFiles({
    required WorkspaceInfo workspace,
    required String? resolvedRoot,
    required String directory,
    required List<String> out,
    required int limit,
  }) async {
    if (out.length >= limit) return;
    final entries = await _bridge.listDirectory(
      treeUri: workspace.treeUri,
      relativePath: directory,
    );
    for (final entry in entries) {
      if (out.length >= limit) return;
      if (entry.isDirectory) {
        await _collectSkillFiles(
          workspace: workspace,
          resolvedRoot: resolvedRoot,
          directory: entry.path,
          out: out,
          limit: limit,
        );
        continue;
      }
      if (entry.name == 'SKILL.md') continue;
      out.add(
        _absolutePath(
          resolvedRoot: resolvedRoot,
          relativePath: entry.path,
        ),
      );
    }
  }

  PermissionAction _evaluatePermission(
    String permission,
    String pattern,
    AgentDefinition agentDefinition,
  ) {
    var result = PermissionAction.ask;
    for (final rule in agentDefinition.permissionRules) {
      if (!_matches(rule.permission, permission)) continue;
      if (!_matches(rule.pattern, pattern)) continue;
      result = rule.action;
    }
    return result;
  }

  bool _matches(String pattern, String input) {
    if (pattern == '*' || pattern == input) return true;
    final escaped = RegExp.escape(pattern)
        .replaceAll(r'\*\*', '.*')
        .replaceAll(r'\*', '[^/]*')
        .replaceAll(r'\?', '.');
    return RegExp('^$escaped\$').hasMatch(input);
  }

  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  String _displayLocation({
    required String? resolvedRoot,
    required String relativePath,
  }) {
    final absolute = _absolutePath(
      resolvedRoot: resolvedRoot,
      relativePath: relativePath,
    );
    if (absolute == relativePath) return relativePath;
    return Uri.file(absolute, windows: Platform.isWindows).toString();
  }

  String _absolutePath({
    required String? resolvedRoot,
    required String relativePath,
  }) {
    if (resolvedRoot == null || resolvedRoot.trim().isEmpty) {
      return relativePath;
    }
    return p.normalize(p.join(resolvedRoot, relativePath));
  }

  _ParsedSkillMarkdown? _parseSkillMarkdown(String raw) {
    if (raw.trim().isEmpty) return null;
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = const LineSplitter().convert(normalized);
    if (lines.isEmpty || lines.first.trim() != '---') return null;
    var end = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        end = i;
        break;
      }
    }
    if (end <= 1) return null;
    final frontmatter = <String, String>{};
    for (final line in lines.sublist(1, end)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final idx = trimmed.indexOf(':');
      if (idx <= 0) continue;
      final key = trimmed.substring(0, idx).trim();
      var value = trimmed.substring(idx + 1).trim();
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      frontmatter[key] = value;
    }
    final name = (frontmatter['name'] ?? '').trim();
    final description = (frontmatter['description'] ?? '').trim();
    if (name.isEmpty || description.isEmpty) return null;
    if (!_validSkillName.hasMatch(name)) return null;
    final content = lines.sublist(end + 1).join('\n').trim();
    return _ParsedSkillMarkdown(
      name: name,
      description: description,
      content: content,
    );
  }

  static final RegExp _validSkillName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
}

class _ParsedSkillMarkdown {
  const _ParsedSkillMarkdown({
    required this.name,
    required this.description,
    required this.content,
  });

  final String name;
  final String description;
  final String content;
}
