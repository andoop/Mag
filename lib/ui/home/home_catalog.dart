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

const List<_ProviderPreset> _builtinProviderPresets = [
  _ProviderPreset(
    id: 'anthropic',
    name: 'Anthropic',
    baseUrl: 'https://api.anthropic.com/v1',
    note: 'Claude models via the official Anthropic API.',
    recommended: true,
    popular: true,
  ),
  _ProviderPreset(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    note: 'Official DeepSeek API with deepseek-chat as the default model.',
    recommended: true,
    popular: true,
  ),
  _ProviderPreset(
    id: 'google',
    name: 'Google',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    note: 'Gemini models via the Google Generative AI API.',
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
    id: 'openrouter',
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
    note: 'Recommended Mag-style entry with free and aggregated models.',
    recommended: true,
    popular: true,
  ),
  _ProviderPreset(
    id: 'groq',
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    note: 'Fast OpenAI-compatible inference from Groq.',
  ),
  _ProviderPreset(
    id: 'mistral',
    name: 'Mistral',
    baseUrl: 'https://api.mistral.ai/v1',
    note: 'Official Mistral API.',
  ),
  _ProviderPreset(
    id: 'ollama',
    name: 'Ollama',
    baseUrl: 'http://localhost:11434/v1',
    note: 'Local Ollama endpoint exposed in OpenAI-compatible mode.',
    requiresApiKey: false,
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
    id: 'vercel',
    name: 'Vercel AI Gateway',
    baseUrl: 'https://ai-gateway.vercel.sh/v1',
    note: 'Vercel AI Gateway in OpenAI-compatible mode.',
    popular: true,
  ),
  _ProviderPreset(
    id: 'xai',
    name: 'xAI',
    baseUrl: 'https://api.x.ai/v1',
    note: 'Grok models via the xAI API.',
  ),
  _ProviderPreset(
    id: 'openai_compatible',
    name: 'OpenAI Compatible',
    baseUrl: 'https://api.openai.com/v1',
    note: 'Custom OpenAI-compatible endpoint.',
    custom: true,
  ),
];

const List<_ModelChoice> _builtinModelCatalog = [
  _ModelChoice(
    providerId: 'anthropic',
    id: 'claude-sonnet-4-5',
    name: 'Claude Sonnet 4.5',
    latest: true,
    recommended: true,
  ),
  _ModelChoice(
    providerId: 'anthropic',
    id: 'claude-haiku-4.5',
    name: 'Claude Haiku 4.5',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'deepseek',
    id: 'deepseek-chat',
    name: 'DeepSeek Chat',
    recommended: true,
    latest: true,
  ),
  _ModelChoice(
    providerId: 'google',
    id: 'gemini-2.5-pro',
    name: 'Gemini 2.5 Pro',
    latest: true,
    recommended: true,
  ),
  _ModelChoice(
    providerId: 'google',
    id: 'gemini-2.5-flash',
    name: 'Gemini 2.5 Flash',
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
    providerId: 'groq',
    id: 'llama-3.3-70b-versatile',
    name: 'Llama 3.3 70B Versatile',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'mistral',
    id: 'mistral-large-latest',
    name: 'Mistral Large Latest',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'ollama',
    id: 'qwen2.5-coder:latest',
    name: 'Qwen2.5 Coder Latest',
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
    providerId: 'vercel',
    id: 'openai/gpt-4.1-mini',
    name: 'GPT-4.1 Mini',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'xai',
    id: 'grok-4',
    name: 'Grok 4',
    latest: true,
  ),
  _ModelChoice(
    providerId: 'xai',
    id: 'grok-3-mini',
    name: 'Grok 3 Mini',
    latest: true,
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

const List<String> _popularProviderOrder = [
  'mag',
  'anthropic',
  'openai',
  'google',
  'openrouter',
  'vercel',
  'deepseek',
  'github_models',
];

int _providerSortRank(String providerId) {
  final index = _popularProviderOrder.indexOf(providerId);
  return index >= 0 ? index : 999;
}

ProviderListResponse _fallbackProviderListResponse() {
  final all = fallbackProviderCatalog();
  return ProviderListResponse(
    all: all,
    connected: const ['mag'],
    defaultModels: {
      for (final provider in all)
        if (defaultModelIdForProvider(provider) != null)
          provider.id: defaultModelIdForProvider(provider)!,
    },
  );
}

ProviderListResponse _providerListForState(AppState? state) {
  return state?.providerList ?? _fallbackProviderListResponse();
}

ProviderInfo? _providerInfoById(
  String id, {
  AppState? state,
  ProviderListResponse? providerList,
}) {
  final source = providerList ?? _providerListForState(state);
  for (final item in source.all) {
    if (item.id == id) return item;
  }
  return null;
}

_ProviderPreset? _builtinProviderById(String id) {
  for (final item in _builtinProviderPresets) {
    if (item.id == id) return item;
  }
  return null;
}

_ProviderPreset _presetFromProviderInfo(ProviderInfo provider) {
  final builtin = _builtinProviderById(provider.id);
  final envSummary = provider.env.isNotEmpty ? provider.env.join(', ') : null;
  if (builtin != null && !provider.custom) {
    return _ProviderPreset(
      id: builtin.id,
      name: provider.name,
      baseUrl: provider.api ?? builtin.baseUrl,
      note: [
        if ((builtin.note ?? '').isNotEmpty) builtin.note!,
        if ((envSummary ?? '').isNotEmpty) envSummary!,
      ].join(' · '),
      recommended: builtin.recommended,
      popular: builtin.popular,
      custom: builtin.custom,
      requiresApiKey: builtin.requiresApiKey,
    );
  }
  return _ProviderPreset(
    id: provider.id,
    name: provider.name,
    baseUrl: provider.api ?? (_builtinProviderById(provider.id)?.baseUrl ?? ''),
    note: provider.custom
        ? 'Custom OpenAI-compatible endpoint.'
        : envSummary,
    custom: provider.custom,
    recommended: _providerSortRank(provider.id) < 4,
    popular: _providerSortRank(provider.id) < 999,
    requiresApiKey: provider.id != 'mag' && provider.id != 'ollama',
  );
}

List<_ProviderPreset> _allProviderPresets({
  AppState? state,
  ProviderListResponse? providerList,
}) {
  final source = providerList ?? _providerListForState(state);
  return source.all.map(_presetFromProviderInfo).toList()
    ..sort((a, b) {
      final rankCompare = _providerSortRank(a.id).compareTo(_providerSortRank(b.id));
      if (rankCompare != 0) return rankCompare;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
}

List<_ProviderPreset> _connectedProviderPresets(
  ModelConfig config, {
  AppState? state,
  ProviderListResponse? providerList,
}) {
  final source = providerList ?? _providerListForState(state);
  final connected = source.connected.toSet();
  return source.all
      .where((item) => connected.contains(item.id))
      .map(_presetFromProviderInfo)
      .toList()
    ..sort((a, b) {
      final rankCompare = _providerSortRank(a.id).compareTo(_providerSortRank(b.id));
      if (rankCompare != 0) return rankCompare;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
}

_ProviderPreset? _providerById(
  String id, {
  ModelConfig? config,
  AppState? state,
  ProviderListResponse? providerList,
}) {
  final source = providerList ?? _providerListForState(state);
  if (config != null) {
    for (final item in _connectedProviderPresets(
      config,
      state: state,
      providerList: source,
    )) {
      if (item.id == id) return item;
    }
  }
  final info = _providerInfoById(id, providerList: source);
  if (info != null) return _presetFromProviderInfo(info);
  return _builtinProviderById(id);
}

String _providerLabel(
  String id, {
  ModelConfig? config,
  AppState? state,
  ProviderListResponse? providerList,
}) =>
    _providerById(
      id,
      config: config,
      state: state,
      providerList: providerList,
    )?.name ??
    id;

_ModelChoice? _builtinModelById(String providerId, String modelId) {
  for (final item in _builtinModelCatalog) {
    if (item.providerId == providerId && item.id == modelId) return item;
  }
  return null;
}

String _modelDisplayName(String id) {
  final normalized = id
      .replaceAll(':free', ' free')
      .replaceAll(':', ' ')
      .replaceAll('/', ' ')
      .replaceAll('-', ' ')
      .trim();
  if (normalized.isEmpty) return id;
  return normalized
      .split(RegExp(r'\s+'))
      .map((part) => part.isEmpty
          ? part
          : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

Set<String> _latestModelIdsForProvider(ProviderInfo provider) {
  final now = DateTime.now();
  final byFamily = <String, ProviderModelInfo>{};
  for (final model in provider.models.values) {
    final parsed = DateTime.tryParse(model.releaseDate);
    if (parsed == null) continue;
    if (parsed.isBefore(now.subtract(const Duration(days: 183)))) continue;
    final family = (model.family ?? model.id).trim();
    final existing = byFamily[family];
    if (existing == null) {
      byFamily[family] = model;
      continue;
    }
    final existingParsed = DateTime.tryParse(existing.releaseDate);
    if (existingParsed == null || parsed.isAfter(existingParsed)) {
      byFamily[family] = model;
    }
  }
  return byFamily.values.map((item) => item.id).toSet().cast<String>();
}

List<_ModelChoice> _modelsForProvider(
  String providerId, {
  ModelConfig? config,
  AppState? state,
  ProviderListResponse? providerList,
}) {
  final source = providerList ?? _providerListForState(state);
  final provider = _providerInfoById(providerId, providerList: source);
  final connection = config?.connectionFor(providerId);
  if (connection != null && connection.models.isNotEmpty) {
    final ids = providerId == 'mag'
        ? filterMagZenFreeModels(connection.models)
        : connection.models;
    final latestIds =
        provider != null ? _latestModelIdsForProvider(provider) : <String>{};
    return ids
        .map(
          (id) =>
              _modelChoiceFromProviderModel(
                providerId: providerId,
                id: id,
                info: provider?.models[id],
                latestIds: latestIds,
              ) ??
              _builtinModelById(providerId, id) ??
              _ModelChoice(
                providerId: providerId,
                id: id,
                name: _modelDisplayName(id),
              ),
        )
        .toList();
  }
  return const [];
}

_ModelChoice? _modelChoiceFromProviderModel({
  required String providerId,
  required String id,
  required Set<String> latestIds,
  ProviderModelInfo? info,
}) {
  if (info == null) return null;
  return _ModelChoice(
    providerId: providerId,
    id: id,
    name: info.name.replaceAll('(latest)', '').trim(),
    latest: latestIds.contains(id) || info.name.contains('(latest)'),
    free: providerId == 'mag'
        ? isMagZenFreeModelId(id)
        : (info.cost.input == 0 &&
            (id.contains(':free') || id.endsWith('-free') || id.contains('/free'))),
  );
}

List<_ModelChoice> _connectedModelChoices(
  ModelConfig config, {
  AppState? state,
  ProviderListResponse? providerList,
}) {
  return config.connections
      .expand((item) => _modelsForProvider(
            item.id,
            config: config,
            state: state,
            providerList: providerList,
          ))
      .toList();
}

bool _isModelVisible(ModelConfig config, _ModelChoice item) {
  final visibility =
      config.visibilityFor(providerId: item.providerId, modelId: item.id);
  if (visibility == null) return true;
  return visibility == ModelVisibility.show;
}

/// OpenCode 风格：列表中与 `Tag` 一致的「免费」判定（含 Mag Zen 与 `:free` 路由等）。
bool _modelChoiceIsFree(_ModelChoice item) {
  if (item.free || item.unpaid) return true;
  if (item.providerId == 'mag') return isMagZenFreeModelId(item.id);
  final id = item.id.toLowerCase();
  if (id.endsWith('-free') ||
      id.contains(':free') ||
      id.contains('/free')) {
    return true;
  }
  return false;
}

bool _modelChoiceIsLatest(_ModelChoice item) {
  if (item.latest) return true;
  final id = item.id.toLowerCase();
  return id.contains('latest');
}
