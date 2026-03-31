part of '../home_page.dart';

class _ProviderPreset {
  const _ProviderPreset({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.note,
    this.recommended = false,
    this.popular = false,
    this.custom = false,
    this.requiresApiKey = true,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String? note;
  final bool recommended;
  final bool popular;
  final bool custom;
  final bool requiresApiKey;
}

class _ModelChoice {
  const _ModelChoice({
    required this.providerId,
    required this.id,
    required this.name,
    this.free = false,
    this.latest = false,
    this.recommended = false,
    this.unpaid = false,
  });

  final String providerId;
  final String id;
  final String name;
  final bool free;
  final bool latest;
  final bool recommended;
  final bool unpaid;
}


const Map<String, String> _schemaTemplateLabels = {
  'answer': 'Answer',
  'summary': 'Summary',
  'patchPlan': 'Patch Plan',
  'taskResult': 'Task Result',
};

const Map<String, Map<String, dynamic>> _structuredSchemaTemplates = {
  'answer': {
    'type': 'object',
    'properties': {
      'answer': {'type': 'string'},
    },
    'required': ['answer'],
    'additionalProperties': false,
  },
  'summary': {
    'type': 'object',
    'properties': {
      'summary': {'type': 'string'},
      'key_points': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'risks': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['summary', 'key_points'],
    'additionalProperties': false,
  },
  'patchPlan': {
    'type': 'object',
    'properties': {
      'goal': {'type': 'string'},
      'steps': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'files': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'risks': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['goal', 'steps'],
    'additionalProperties': false,
  },
  'taskResult': {
    'type': 'object',
    'properties': {
      'status': {
        'type': 'string',
        'enum': ['done', 'blocked', 'needs_input'],
      },
      'summary': {'type': 'string'},
      'changed_files': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'next_actions': {
        'type': 'array',
        'items': {'type': 'string'},
      },
    },
    'required': ['status', 'summary'],
    'additionalProperties': false,
  },
};

const List<_ProviderPreset> _providerPresets = [
  _ProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    note: 'Official DeepSeek API with deepseek-chat as the default model.',
    recommended: true,
    popular: true,
  ),
  _ProviderPreset(
    id: 'mag',
    name: 'Mag',
    baseUrl: 'https://opencode.ai/zen/v1',
    note: 'Mag Zen free-model entry with optional public token fallback.',
    recommended: true,
    popular: true,
    requiresApiKey: false,
  ),
  _ProviderPreset(
    id: 'mag_go',
    name: 'Mag Go',
    baseUrl: 'https://opencode.ai/zen/v1',
    note: 'Recommended Mag Go entry.',
    recommended: true,
    popular: true,
    requiresApiKey: false,
  ),
  _ProviderPreset(
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    note: 'Recommended Mag-style entry with free and aggregated models.',
    recommended: true,
    popular: true,
  ),
  _ProviderPreset(
    id: 'openai',
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    note: 'Official OpenAI API.',
    popular: true,
  ),
  _ProviderPreset(
    id: 'github_models',
    name: 'GitHub Models',
    baseUrl: 'https://models.github.ai/inference',
    note: 'GitHub Models using a GitHub token.',
    popular: true,
  ),
  _ProviderPreset(
    id: 'openai_compatible',
    name: 'OpenAI Compatible',
    baseUrl: 'https://api.openai.com/v1',
    note: 'Custom OpenAI-compatible endpoint.',
    custom: true,
  ),
];

const List<_ModelChoice> _modelCatalog = [
  _ModelChoice(
    providerId: 'deepseek',
    id: 'deepseek-chat',
    name: 'DeepSeek Chat',
    recommended: true,
    latest: true,
  ),
  _ModelChoice(
    providerId: 'mag',
    id: 'minimax-m2.5-free',
    name: 'MiniMax M2.5 Free',
    free: true,
    recommended: true,
    unpaid: true,
  ),
  _ModelChoice(
    providerId: 'mag',
    id: 'mimo-v2-pro-free',
    name: 'MiMo V2 Pro Free',
    free: true,
    recommended: true,
    unpaid: true,
  ),
  _ModelChoice(
    providerId: 'mag',
    id: 'mimo-v2-omni-free',
    name: 'MiMo V2 Omni Free',
    free: true,
    recommended: true,
    unpaid: true,
  ),
  _ModelChoice(
    providerId: 'mag',
    id: 'nemotron-3-super-free',
    name: 'Nemotron 3 Super Free',
    free: true,
    recommended: true,
    unpaid: true,
  ),
  _ModelChoice(
    providerId: 'mag',
    id: 'big-pickle',
    name: 'Big Pickle',
    free: true,
    recommended: true,
    unpaid: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'openrouter/free',
    name: 'OpenRouter Free Router',
    free: true,
    latest: true,
    recommended: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'qwen/qwen3-coder:free',
    name: 'Qwen 3 Coder Free',
    free: true,
    recommended: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'z-ai/glm-4.5-air:free',
    name: 'GLM 4.5 Air Free',
    free: true,
    recommended: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'openai/gpt-4.1-mini',
    name: 'GPT-4.1 Mini',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'google/gemini-2.5-flash',
    name: 'Gemini 2.5 Flash',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'openrouter',
    id: 'anthropic/claude-sonnet-4',
    name: 'Claude Sonnet 4',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'openai',
    id: 'gpt-4.1-mini',
    name: 'GPT-4.1 Mini',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'openai',
    id: 'gpt-4.1',
    name: 'GPT-4.1',
  ),
  _ModelChoice(
    providerId: 'github_models',
    id: 'openai/gpt-4.1-mini',
    name: 'GPT-4.1 Mini',
  ),
  _ModelChoice(
    providerId: 'github_models',
    id: 'openai/gpt-4.1',
    name: 'GPT-4.1',
  ),
  _ModelChoice(
    providerId: 'openai_compatible',
    id: 'gpt-4.1-mini',
    name: 'GPT-4.1 Mini',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'openai_compatible',
    id: 'openrouter/free',
    name: 'OpenRouter Free Router',
    free: true,
  ),
];

_ProviderPreset? _providerById(String id) {
  for (final item in _providerPresets) {
    if (item.id == id) return item;
  }
  return null;
}

String _providerLabel(String id) => _providerById(id)?.name ?? id;

List<_ModelChoice> _modelsForProvider(String providerId) {
  final items =
      _modelCatalog.where((item) => item.providerId == providerId).toList();
  if (items.isNotEmpty) return items;
  return _modelCatalog
      .where((item) => item.providerId == 'openai_compatible')
      .toList();
}
