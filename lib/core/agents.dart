import 'models.dart';
import 'prompt_system.dart';

class AgentRegistry {
  AgentRegistry._();

  static List<AgentDefinition> all() => [
        build,
        plan,
        general,
        explore,
      ];

  static AgentDefinition get build => AgentDefinition(
        name: 'build',
        description:
            'Default agent. Executes tools inside configured permissions.',
        descriptionZh: '默认智能体，可读写文件、执行工具，完成编码任务。',
        mode: AgentMode.primary,
        steps: 128,
        permissionRules: _defaultRules(
          overrides: [
            PermissionRule(
                permission: 'question',
                pattern: '*',
                action: PermissionAction.allow),
          ],
        ),
        availableTools: _commonTools,
      );

  static AgentDefinition get plan => AgentDefinition(
        name: 'plan',
        description:
            'Plan mode. Focuses on analysis and intentionally blocks edit tools.',
        descriptionZh: '规划模式，只读分析代码并制定方案，禁止任何文件修改。',
        mode: AgentMode.primary,
        promptOverride: null,
        permissionRules: _defaultRules(
          overrides: [
            PermissionRule(
                permission: 'question',
                pattern: '*',
                action: PermissionAction.allow),
            PermissionRule(
                permission: 'plan_exit',
                pattern: '*',
                action: PermissionAction.allow),
            PermissionRule(
                permission: 'edit',
                pattern: '*',
                action: PermissionAction.deny),
            PermissionRule(
                permission: 'write',
                pattern: '*',
                action: PermissionAction.deny),
          ],
        ),
        availableTools: const [
          'read',
          'list',
          'glob',
          'grep',
          'stat',
          'git',
          'question',
          'webfetch',
          'browser',
          'skill',
          'todowrite',
          'task',
          'plan_exit',
          'invalid',
        ],
      );

  static AgentDefinition get general => AgentDefinition(
        name: 'general',
        description: 'General-purpose subagent for multi-step work.',
        descriptionZh: '通用子智能体，用于执行多步骤任务。',
        mode: AgentMode.subagent,
        permissionRules: _defaultRules(
          overrides: [
            PermissionRule(
                permission: 'todowrite',
                pattern: '*',
                action: PermissionAction.deny),
          ],
        ),
        availableTools: _commonTools,
      );

  static AgentDefinition get explore => AgentDefinition(
        name: 'explore',
        description:
            'Fast codebase exploration agent with read and search tools.',
        descriptionZh: '快速代码探索智能体，只读搜索和浏览，不修改任何文件。',
        mode: AgentMode.subagent,
        promptOverride: explorePrompt,
        permissionRules: [
          PermissionRule(
              permission: '*', pattern: '*', action: PermissionAction.deny),
          PermissionRule(
              permission: 'read', pattern: '*', action: PermissionAction.allow),
          PermissionRule(
              permission: 'glob', pattern: '*', action: PermissionAction.allow),
          PermissionRule(
              permission: 'grep', pattern: '*', action: PermissionAction.allow),
          PermissionRule(
              permission: 'webfetch',
              pattern: '*',
              action: PermissionAction.allow),
          PermissionRule(
              permission: 'browser',
              pattern: '*',
              action: PermissionAction.allow),
          PermissionRule(
              permission: 'skill',
              pattern: '*',
              action: PermissionAction.allow),
          PermissionRule(
              permission: 'question',
              pattern: '*',
              action: PermissionAction.allow),
        ],
        availableTools: const [
          'read',
          'list',
          'glob',
          'grep',
          'stat',
          'git',
          'webfetch',
          'browser',
          'skill',
          'fileref',
          'question',
          'invalid',
        ],
      );

  static AgentDefinition resolve(String name) {
    return all().firstWhere(
      (item) => item.name == name,
      orElse: () => build,
    );
  }

  static List<PermissionRule> _defaultRules({
    List<PermissionRule> overrides = const [],
  }) {
    return [
      PermissionRule(
          permission: '*', pattern: '*', action: PermissionAction.allow),
      PermissionRule(
          permission: 'question', pattern: '*', action: PermissionAction.deny),
      PermissionRule(
          permission: 'plan_exit', pattern: '*', action: PermissionAction.deny),
      PermissionRule(
          permission: 'webfetch', pattern: '*', action: PermissionAction.ask),
      PermissionRule(
          permission: 'edit', pattern: '*.env', action: PermissionAction.ask),
      PermissionRule(
          permission: 'edit', pattern: '*.env.*', action: PermissionAction.ask),
      PermissionRule(
          permission: 'read', pattern: '*.env', action: PermissionAction.ask),
      PermissionRule(
          permission: 'read', pattern: '*.env.*', action: PermissionAction.ask),
      ...overrides,
    ];
  }

  static const List<String> _commonTools = [
    'read',
    'list',
    'write',
    'edit',
    'apply_patch',
    'glob',
    'grep',
    'stat',
    'delete',
    'rename',
    'move',
    'copy',
    'git',
    'task',
    'todowrite',
    'question',
    'webfetch',
    'browser',
    'skill',
    'fileref',
    'invalid',
    'plan_exit',
  ];
}
