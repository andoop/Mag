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
        mode: AgentMode.primary,
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
          'webfetch',
          'browser',
          'skill',
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
    'task',
    'todowrite',
    'question',
    'webfetch',
    'browser',
    'skill',
    'invalid',
    'plan_exit',
  ];
}
