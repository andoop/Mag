part of '../models.dart';

const String kModelsDevCatalogCacheKey = 'models_dev_catalog_v1';

class ProviderModelCost {
  const ProviderModelCost({
    this.input = 0,
    this.output = 0,
  });

  final double input;
  final double output;

  JsonMap toJson() => {
        'input': input,
        'output': output,
      };

  factory ProviderModelCost.fromJson(JsonMap json) => ProviderModelCost(
        input: (json['input'] as num?)?.toDouble() ?? 0,
        output: (json['output'] as num?)?.toDouble() ?? 0,
      );
}

class ProviderModelLimit {
  const ProviderModelLimit({
    this.context = 0,
    this.input,
    this.output = 0,
  });

  final int context;
  final int? input;
  final int output;

  JsonMap toJson() => {
        'context': context,
        if (input != null) 'input': input,
        'output': output,
      };

  factory ProviderModelLimit.fromJson(JsonMap json) => ProviderModelLimit(
        context: (json['context'] as num?)?.toInt() ?? 0,
        input: (json['input'] as num?)?.toInt(),
        output: (json['output'] as num?)?.toInt() ?? 0,
      );
}

class ProviderModelModalities {
  const ProviderModelModalities({
    this.input = const [],
    this.output = const [],
  });

  final List<String> input;
  final List<String> output;

  JsonMap toJson() => {
        'input': input,
        'output': output,
      };

  factory ProviderModelModalities.fromJson(JsonMap json) =>
      ProviderModelModalities(
        input: (json['input'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        output: (json['output'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
      );
}

class ProviderModelInterleaved {
  const ProviderModelInterleaved({
    this.enabled = false,
    this.field,
  });

  final bool enabled;
  final String? field;

  JsonMap toJson() => {
        'enabled': enabled,
        if (field != null) 'field': field,
      };

  factory ProviderModelInterleaved.fromJson(JsonMap json) =>
      ProviderModelInterleaved(
        enabled: (json['enabled'] as bool?) ?? false,
        field: json['field'] as String?,
      );
}

class ProviderModelCapabilities {
  const ProviderModelCapabilities({
    this.temperature = false,
    this.reasoning = false,
    this.attachment = false,
    this.toolCall = true,
    this.interleaved = const ProviderModelInterleaved(),
  });

  final bool temperature;
  final bool reasoning;
  final bool attachment;
  final bool toolCall;
  final ProviderModelInterleaved interleaved;

  JsonMap toJson() => {
        'temperature': temperature,
        'reasoning': reasoning,
        'attachment': attachment,
        'tool_call': toolCall,
        'interleaved': interleaved.toJson(),
      };

  factory ProviderModelCapabilities.fromJson(JsonMap json) =>
      ProviderModelCapabilities(
        temperature: (json['temperature'] as bool?) ?? false,
        reasoning: (json['reasoning'] as bool?) ?? false,
        attachment: (json['attachment'] as bool?) ?? false,
        toolCall: (json['tool_call'] as bool?) ?? true,
        interleaved: json['interleaved'] == null
            ? const ProviderModelInterleaved()
            : ProviderModelInterleaved.fromJson(
                Map<String, dynamic>.from(json['interleaved'] as Map),
              ),
      );
}

class ProviderModelInfo {
  const ProviderModelInfo({
    required this.id,
    required this.name,
    this.family,
    this.releaseDate = '',
    this.status = 'active',
    this.cost = const ProviderModelCost(),
    this.limit = const ProviderModelLimit(),
    this.modalities,
    this.capabilities = const ProviderModelCapabilities(),
    this.options = const {},
    this.variants = const {},
  });

  final String id;
  final String name;
  final String? family;
  final String releaseDate;
  final String status;
  final ProviderModelCost cost;
  final ProviderModelLimit limit;
  final ProviderModelModalities? modalities;
  final ProviderModelCapabilities capabilities;
  final JsonMap options;
  final Map<String, JsonMap> variants;

  bool get isDeprecated => status == 'deprecated';

  ProviderModelInfo copyWith({
    String? id,
    String? name,
    Object? family = _unset,
    String? releaseDate,
    String? status,
    ProviderModelCost? cost,
    ProviderModelLimit? limit,
    Object? modalities = _unset,
    ProviderModelCapabilities? capabilities,
    JsonMap? options,
    Map<String, JsonMap>? variants,
  }) {
    return ProviderModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      family: identical(family, _unset) ? this.family : family as String?,
      releaseDate: releaseDate ?? this.releaseDate,
      status: status ?? this.status,
      cost: cost ?? this.cost,
      limit: limit ?? this.limit,
      modalities: identical(modalities, _unset)
          ? this.modalities
          : modalities as ProviderModelModalities?,
      capabilities: capabilities ?? this.capabilities,
      options: options ?? this.options,
      variants: variants ?? this.variants,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'name': name,
        if (family != null) 'family': family,
        'release_date': releaseDate,
        'status': status,
        'cost': cost.toJson(),
        'limit': limit.toJson(),
        if (modalities != null) 'modalities': modalities!.toJson(),
        'capabilities': capabilities.toJson(),
        'options': options,
        'variants': variants.map((key, value) => MapEntry(key, value)),
      };

  factory ProviderModelInfo.fromJson(JsonMap json) => ProviderModelInfo(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? (json['id'] as String? ?? ''),
        family: json['family'] as String?,
        releaseDate: (json['release_date'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'active',
        cost: ProviderModelCost.fromJson(
          Map<String, dynamic>.from(json['cost'] as Map? ?? const {}),
        ),
        limit: ProviderModelLimit.fromJson(
          Map<String, dynamic>.from(json['limit'] as Map? ?? const {}),
        ),
        modalities: json['modalities'] == null
            ? null
            : ProviderModelModalities.fromJson(
                Map<String, dynamic>.from(json['modalities'] as Map),
              ),
        capabilities: ProviderModelCapabilities.fromJson(
          Map<String, dynamic>.from(json['capabilities'] as Map? ?? const {}),
        ),
        options: Map<String, dynamic>.from(json['options'] as Map? ?? const {}),
        variants: (json['variants'] as Map? ?? const {}).map(
          (key, value) => MapEntry(
            key.toString(),
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      );

  factory ProviderModelInfo.fromModelsDevJson(JsonMap json) =>
      ProviderModelInfo(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? (json['id'] as String? ?? ''),
        family: json['family'] as String?,
        releaseDate: (json['release_date'] as String?) ?? '',
        status: (json['status'] as String?) ?? 'active',
        cost: ProviderModelCost.fromJson(
          Map<String, dynamic>.from(json['cost'] as Map? ?? const {}),
        ),
        limit: ProviderModelLimit.fromJson(
          Map<String, dynamic>.from(json['limit'] as Map? ?? const {}),
        ),
        modalities: json['modalities'] == null
            ? null
            : ProviderModelModalities.fromJson(
                Map<String, dynamic>.from(json['modalities'] as Map),
              ),
        capabilities: ProviderModelCapabilities(
          temperature: (json['temperature'] as bool?) ?? false,
          reasoning: (json['reasoning'] as bool?) ?? false,
          attachment: (json['attachment'] as bool?) ?? false,
          toolCall: (json['tool_call'] as bool?) ?? true,
          interleaved: () {
            final value = json['interleaved'];
            if (value is bool) {
              return ProviderModelInterleaved(enabled: value);
            }
            if (value is Map) {
              return ProviderModelInterleaved(
                enabled: true,
                field: value['field'] as String?,
              );
            }
            return const ProviderModelInterleaved();
          }(),
        ),
        options: Map<String, dynamic>.from(json['options'] as Map? ?? const {}),
        variants: (json['variants'] as Map? ?? const {}).map(
          (key, value) => MapEntry(
            key.toString(),
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      );
}

class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    required this.models,
    this.api,
    this.env = const [],
    this.custom = false,
    this.connected = false,
  });

  final String id;
  final String name;
  final String? api;
  final List<String> env;
  final Map<String, ProviderModelInfo> models;
  final bool custom;
  final bool connected;

  ProviderInfo copyWith({
    String? id,
    String? name,
    Object? api = _unset,
    List<String>? env,
    Map<String, ProviderModelInfo>? models,
    bool? custom,
    bool? connected,
  }) {
    return ProviderInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      api: identical(api, _unset) ? this.api : api as String?,
      env: env ?? this.env,
      models: models ?? this.models,
      custom: custom ?? this.custom,
      connected: connected ?? this.connected,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'name': name,
        if (api != null) 'api': api,
        'env': env,
        'models': models.map((key, value) => MapEntry(key, value.toJson())),
        'custom': custom,
        'connected': connected,
      };

  factory ProviderInfo.fromJson(JsonMap json) {
    final rawModels = Map<String, dynamic>.from(
      json['models'] as Map? ?? const {},
    );
    return ProviderInfo(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? (json['id'] as String? ?? ''),
      api: json['api'] as String?,
      env: (json['env'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      models: rawModels.map(
        (key, value) => MapEntry(
          key,
          ProviderModelInfo.fromJson(Map<String, dynamic>.from(value as Map)),
        ),
      ),
      custom: (json['custom'] as bool?) ?? false,
      connected: (json['connected'] as bool?) ?? false,
    );
  }

  factory ProviderInfo.fromModelsDevJson(String id, JsonMap json) {
    final rawModels = Map<String, dynamic>.from(
      json['models'] as Map? ?? const {},
    );
    return ProviderInfo(
      id: id,
      name: (json['name'] as String?) ?? id,
      api: json['api'] as String?,
      env: (json['env'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      models: rawModels.map(
        (key, value) => MapEntry(
          key,
          ProviderModelInfo.fromModelsDevJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
    );
  }
}

class ProviderListResponse {
  const ProviderListResponse({
    required this.all,
    required this.connected,
    required this.defaultModels,
  });

  final List<ProviderInfo> all;
  final List<String> connected;
  final Map<String, String> defaultModels;

  JsonMap toJson() => {
        'all': all.map((item) => item.toJson()).toList(),
        'connected': connected,
        'default': defaultModels,
      };

  factory ProviderListResponse.fromJson(JsonMap json) => ProviderListResponse(
        all: (json['all'] as List? ?? const [])
            .map((item) =>
                ProviderInfo.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        connected: (json['connected'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        defaultModels: Map<String, String>.from(
          json['default'] as Map? ?? const <String, String>{},
        ),
      );
}

ProviderListResponse buildProviderListResponse({
  required List<ProviderInfo> catalog,
  required ModelConfig config,
}) {
  final catalogMap = <String, ProviderInfo>{
    for (final provider in catalog) provider.id: provider,
  };
  final connected = <String, ProviderInfo>{};
  for (final connection in config.connections) {
    final existing = catalogMap[connection.id];
    final models = <String, ProviderModelInfo>{
      ...?existing?.models,
    };
    final modelIds = connection.id == 'mag'
        ? filterMagZenFreeModels(connection.models)
        : connection.models;
    for (final modelId in modelIds) {
      models.putIfAbsent(
        modelId,
        () => fallbackProviderModelInfo(
          modelId,
          providerId: connection.id,
          cost: connection.id == 'mag'
              ? const ProviderModelCost(input: 0, output: 0)
              : const ProviderModelCost(),
        ),
      );
    }
    connected[connection.id] = (existing ??
            ProviderInfo(
              id: connection.id,
              name:
                  connection.name.isNotEmpty ? connection.name : connection.id,
              api: connection.baseUrl,
              env: const [],
              models: const {},
              custom: connection.custom,
            ))
        .copyWith(
      name: connection.name.isNotEmpty
          ? connection.name
          : (existing?.name ?? connection.id),
      api: connection.baseUrl.isNotEmpty ? connection.baseUrl : existing?.api,
      models: models,
      custom: connection.custom,
      connected: true,
    );
  }
  final providers = <String, ProviderInfo>{
    ...catalogMap,
    ...connected,
  };
  final all = normalizeProviderCatalog(providers.values.toList());
  final defaults = <String, String>{};
  for (final provider in all) {
    final defaultModel = defaultModelIdForProvider(provider);
    if (defaultModel != null) {
      defaults[provider.id] = defaultModel;
    }
  }
  return ProviderListResponse(
    all: all,
    connected: config.connections.map((item) => item.id).toList(),
    defaultModels: defaults,
  );
}

List<ProviderInfo> normalizeProviderCatalog(List<ProviderInfo> input) {
  return input.map((provider) {
    final models = Map<String, ProviderModelInfo>.from(provider.models)
      ..removeWhere((_, model) => model.isDeprecated);
    return provider.copyWith(models: models);
  }).toList();
}

const List<String> _providerSortPriority = [
  'gpt-5',
  'claude-sonnet-4',
  'big-pickle',
  'gemini-3-pro',
];

List<ProviderModelInfo> sortProviderModels(Iterable<ProviderModelInfo> models) {
  final list = models.toList();
  int priorityRank(String id) {
    for (var i = 0; i < _providerSortPriority.length; i++) {
      if (id.contains(_providerSortPriority[i])) {
        return i;
      }
    }
    return _providerSortPriority.length + 1;
  }

  list.sort((a, b) {
    final aRank = priorityRank(a.id);
    final bRank = priorityRank(b.id);
    if (aRank != bRank) return aRank.compareTo(bRank);
    final aLatest = a.id.contains('latest') ? 0 : 1;
    final bLatest = b.id.contains('latest') ? 0 : 1;
    if (aLatest != bLatest) return aLatest.compareTo(bLatest);
    return b.id.compareTo(a.id);
  });
  return list;
}

String? defaultModelIdForProvider(ProviderInfo provider) {
  final sorted = sortProviderModels(provider.models.values);
  if (sorted.isEmpty) return null;
  return sorted.first.id;
}

ProviderModelLimit inferProviderModelLimitFallback(String modelId) {
  final context = inferContextWindow(modelId);
  final output = inferMaxOutputTokens(modelId);
  return ProviderModelLimit(
    context: context,
    input: context > 0 ? math.max(0, context - output) : null,
    output: output,
  );
}

ProviderModelModalities? inferProviderModelModalitiesFallback(String modelId) {
  final lower = modelId.toLowerCase();
  if (lower.contains('claude')) {
    return const ProviderModelModalities(
      input: ['text', 'image', 'pdf'],
      output: ['text'],
    );
  }
  if (lower.contains('gemini')) {
    return const ProviderModelModalities(
      input: ['text', 'image'],
      output: ['text'],
    );
  }
  if (lower.contains('gpt-4o') ||
      lower.contains('gpt-4.1') ||
      lower.contains('gpt-4-1') ||
      lower.contains('o1') ||
      lower.contains('o3') ||
      lower.contains('o4')) {
    return const ProviderModelModalities(
      input: ['text', 'image'],
      output: ['text'],
    );
  }
  return const ProviderModelModalities(
    input: ['text'],
    output: ['text'],
  );
}

double? inferTemperatureForProviderFallback(String modelId) {
  final lower = modelId.toLowerCase();
  if (lower.contains('qwen') || lower.contains('qwq')) return 0.55;
  if (lower.contains('gemini')) return 1.0;
  if (lower.contains('glm-4.6') || lower.contains('glm-4.7')) return 1.0;
  if (lower.contains('minimax-m2')) return 1.0;
  if (lower.contains('kimi-k2')) {
    if (['thinking', 'k2.', 'k2p', 'k2-5'].any(lower.contains)) return 1.0;
    return 0.6;
  }
  return null;
}

ProviderModelCapabilities inferProviderModelCapabilitiesFallback(
  String modelId, {
  String providerId = '',
}) {
  final modalities = inferProviderModelModalitiesFallback(modelId);
  final lower = modelId.toLowerCase();
  return ProviderModelCapabilities(
    temperature: inferTemperatureForProviderFallback(modelId) != null,
    reasoning: lower.contains('gpt-5') ||
        RegExp(r'(^|[^a-z0-9])o[134]\b').hasMatch(lower) ||
        lower.contains('claude') ||
        lower.contains('gemini-2.5') ||
        lower.contains('gemini-3') ||
        lower.contains('grok') ||
        lower.contains('reasoner') ||
        lower.contains('deepseek-r1') ||
        lower.contains('qwen3') ||
        lower.contains('qwq') ||
        lower.contains('kimi-k2') ||
        lower.contains('glm-4.6') ||
        lower.contains('glm-4.7') ||
        lower.contains('sonnet-4') ||
        lower.contains('opus-4') ||
        lower.contains('haiku-4') ||
        providerId == 'anthropic',
    attachment: (modalities?.input.any((item) => item != 'text') ?? false),
    toolCall: true,
    interleaved: const ProviderModelInterleaved(),
  );
}

JsonMap inferProviderModelOptionsFallback({
  required String providerId,
  required String modelId,
  ProviderModelCapabilities? capabilities,
}) {
  final result = <String, dynamic>{};
  final temperature = inferTemperatureForProviderFallback(modelId);
  if (temperature != null) {
    result['temperature'] = temperature;
  }
  final lower = modelId.toLowerCase();
  if (lower.contains('qwen') || lower.contains('qwq')) {
    result['top_p'] = 1;
  } else if ([
    'minimax-m2',
    'gemini',
    'kimi-k2.5',
    'kimi-k2p5',
    'kimi-k2-5',
  ].any(lower.contains)) {
    result['top_p'] = 0.95;
  }
  if (lower.contains('minimax-m2')) {
    result['top_k'] = ['m2.', 'm25', 'm21'].any(lower.contains) ? 40 : 20;
  } else if (lower.contains('gemini')) {
    result['top_k'] = 64;
  }
  final resolvedCapabilities = capabilities ??
      inferProviderModelCapabilitiesFallback(
        modelId,
        providerId: providerId,
      );
  if (providerId == 'openai' || providerId == 'github_models') {
    result['store'] = false;
  }
  if (providerId == 'alibaba-cn' &&
      resolvedCapabilities.reasoning &&
      !lower.contains('kimi-k2-thinking')) {
    result['enable_thinking'] = true;
  }
  if (['zai', 'zhipuai'].contains(providerId)) {
    result['thinking'] = {
      'type': 'enabled',
      'clear_thinking': false,
    };
  }
  if ((providerId == 'google' || providerId == 'google-vertex') &&
      resolvedCapabilities.reasoning) {
    result['thinkingConfig'] = {
      'includeThoughts': true,
      if (lower.contains('gemini-3')) 'thinkingLevel': 'high',
    };
  }
  if (lower.contains('gpt-5') && !lower.contains('gpt-5-chat')) {
    if (!lower.contains('gpt-5-pro')) {
      result['reasoningEffort'] = 'medium';
      result['reasoningSummary'] = 'auto';
    }
    if (lower.contains('gpt-5.') &&
        !lower.contains('codex') &&
        !lower.contains('-chat') &&
        providerId != 'azure') {
      result['textVerbosity'] = 'low';
    }
  }
  return result;
}

JsonMap inferProviderSmallOptionsFallback({
  required String providerId,
  required String modelId,
}) {
  final lower = modelId.toLowerCase();
  if (providerId == 'openai' || providerId == 'github_models') {
    if (lower.contains('gpt-5')) {
      if (lower.contains('5.')) {
        return const {
          'store': false,
          'reasoningEffort': 'low',
        };
      }
      return const {
        'store': false,
        'reasoningEffort': 'minimal',
      };
    }
    return const {
      'store': false,
    };
  }
  if (providerId == 'google') {
    if (lower.contains('gemini-3')) {
      return const {
        'thinkingConfig': {'thinkingLevel': 'minimal'},
      };
    }
    return const {
      'thinkingConfig': {'thinkingBudget': 0},
    };
  }
  if (providerId == 'openrouter') {
    if (lower.contains('google')) {
      return const {
        'reasoning': {'enabled': false},
      };
    }
    return const {
      'reasoningEffort': 'minimal',
    };
  }
  if (providerId == 'venice') {
    return const {
      'veniceParameters': {'disableThinking': true},
    };
  }
  return const {};
}

Map<String, JsonMap> inferProviderModelVariantsFallback({
  required String providerId,
  required String modelId,
  ProviderModelCapabilities? capabilities,
  ProviderModelLimit? limit,
}) {
  final resolvedCapabilities = capabilities ??
      inferProviderModelCapabilitiesFallback(
        modelId,
        providerId: providerId,
      );
  if (!resolvedCapabilities.reasoning) return const {};
  final lower = modelId.toLowerCase();
  final resolvedLimit = limit ?? inferProviderModelLimitFallback(modelId);
  if (lower.contains('deepseek') ||
      lower.contains('minimax') ||
      lower.contains('glm') ||
      lower.contains('mistral') ||
      lower.contains('kimi') ||
      lower.contains('k2p5')) {
    return const {};
  }
  if (providerId == 'anthropic' || lower.contains('claude')) {
    return {
      'high': {
        'thinking': {
          'type': 'enabled',
          'budgetTokens': math.min(
            16000,
            math.max(1, resolvedLimit.output ~/ 2 - 1),
          ),
        },
      },
      'max': {
        'thinking': {
          'type': 'enabled',
          'budgetTokens': math.min(
            31999,
            math.max(1, resolvedLimit.output - 1),
          ),
        },
      },
    };
  }
  if (providerId == 'google' ||
      providerId == 'google-vertex' ||
      lower.contains('gemini')) {
    if (lower.contains('2.5')) {
      return const {
        'high': {
          'thinkingConfig': {
            'includeThoughts': true,
            'thinkingBudget': 16000,
          },
        },
        'max': {
          'thinkingConfig': {
            'includeThoughts': true,
            'thinkingBudget': 24576,
          },
        },
      };
    }
    return const {
      'low': {
        'thinkingConfig': {
          'includeThoughts': true,
          'thinkingLevel': 'low',
        },
      },
      'high': {
        'thinkingConfig': {
          'includeThoughts': true,
          'thinkingLevel': 'high',
        },
      },
    };
  }
  if (lower.contains('gpt') ||
      RegExp(r'(^|[^a-z0-9])o[1-9]\b').hasMatch(lower)) {
    return const {
      'minimal': {'reasoningEffort': 'minimal'},
      'low': {'reasoningEffort': 'low'},
      'medium': {'reasoningEffort': 'medium'},
      'high': {'reasoningEffort': 'high'},
    };
  }
  if (providerId == 'openai_compatible' ||
      providerId == 'openrouter' ||
      providerId == 'xai' ||
      lower.contains('grok')) {
    return const {
      'low': {'reasoningEffort': 'low'},
      'medium': {'reasoningEffort': 'medium'},
      'high': {'reasoningEffort': 'high'},
    };
  }
  return const {};
}

ProviderModelInfo fallbackProviderModelInfo(
  String modelId, {
  String providerId = '',
  ProviderModelCost cost = const ProviderModelCost(),
}) {
  final capabilities = inferProviderModelCapabilitiesFallback(
    modelId,
    providerId: providerId,
  );
  final limit = inferProviderModelLimitFallback(modelId);
  return ProviderModelInfo(
    id: modelId,
    name: modelId,
    cost: cost,
    limit: limit,
    modalities: inferProviderModelModalitiesFallback(modelId),
    capabilities: capabilities,
    options: inferProviderModelOptionsFallback(
      providerId: providerId,
      modelId: modelId,
      capabilities: capabilities,
    ),
    variants: inferProviderModelVariantsFallback(
      providerId: providerId,
      modelId: modelId,
      capabilities: capabilities,
      limit: limit,
    ),
  );
}

class ProviderCatalogModelMatch {
  const ProviderCatalogModelMatch({
    required this.source,
    this.matchedProviderId,
    this.matchedModelId,
  });

  final String source;
  final String? matchedProviderId;
  final String? matchedModelId;
}

ProviderCatalogModelMatch resolveCatalogModelMatch({
  required List<ProviderInfo> catalog,
  required String providerId,
  required String modelId,
}) {
  final catalogProvider = catalog.cast<ProviderInfo?>().firstWhere(
        (provider) => provider?.id == providerId,
        orElse: () => null,
      );
  if (catalogProvider == null) {
    return const ProviderCatalogModelMatch(source: 'fallback');
  }
  final catalogModel = catalogProvider.models[modelId];
  if (catalogModel == null) {
    return ProviderCatalogModelMatch(
      source: 'fallback',
      matchedProviderId: catalogProvider.id,
    );
  }
  return ProviderCatalogModelMatch(
    source: 'catalog',
    matchedProviderId: catalogProvider.id,
    matchedModelId: catalogModel.id,
  );
}

List<ProviderInfo> providerCatalogFromCacheSetting(JsonMap? cached) {
  if (cached == null) return const [];
  final providers = (cached['all'] as List? ?? const [])
      .map((item) =>
          ProviderInfo.fromJson(Map<String, dynamic>.from(item as Map)))
      .toList();
  if (providers.isEmpty) return const [];
  return normalizeProviderCatalog(providers);
}

ProviderModelLimit resolveProviderModelLimit({
  required List<ProviderInfo> catalog,
  required String providerId,
  required String modelId,
}) {
  if (catalog.isNotEmpty) {
    final provider = catalog.cast<ProviderInfo?>().firstWhere(
          (item) => item?.id == providerId,
          orElse: () => null,
        );
    final model = provider?.models[modelId];
    if (model != null) return model.limit;
  }
  return inferProviderModelLimitFallback(modelId);
}

ProviderModelModalities? lookupProviderModelModalitiesInCatalog({
  required List<ProviderInfo> catalog,
  required String providerId,
  required String modelId,
}) {
  if (catalog.isEmpty) return null;
  final provider = catalog.cast<ProviderInfo?>().firstWhere(
        (item) => item?.id == providerId,
        orElse: () => null,
      );
  return provider?.models[modelId]?.modalities;
}

ProviderModelCapabilities? lookupProviderModelCapabilitiesInCatalog({
  required List<ProviderInfo> catalog,
  required String providerId,
  required String modelId,
}) {
  if (catalog.isEmpty) return null;
  final provider = catalog.cast<ProviderInfo?>().firstWhere(
        (item) => item?.id == providerId,
        orElse: () => null,
      );
  return provider?.models[modelId]?.capabilities;
}

JsonMap? lookupProviderModelOptionsInCatalog({
  required List<ProviderInfo> catalog,
  required String providerId,
  required String modelId,
}) {
  if (catalog.isEmpty) return null;
  final provider = catalog.cast<ProviderInfo?>().firstWhere(
        (item) => item?.id == providerId,
        orElse: () => null,
      );
  final options = provider?.models[modelId]?.options;
  return options == null ? null : Map<String, dynamic>.from(options);
}

Map<String, JsonMap>? lookupProviderModelVariantsInCatalog({
  required List<ProviderInfo> catalog,
  required String providerId,
  required String modelId,
}) {
  if (catalog.isEmpty) return null;
  final provider = catalog.cast<ProviderInfo?>().firstWhere(
        (item) => item?.id == providerId,
        orElse: () => null,
      );
  final variants = provider?.models[modelId]?.variants;
  return variants?.map(
    (key, value) => MapEntry(key, Map<String, dynamic>.from(value)),
  );
}

ProviderModelModalities? resolveProviderModelModalities({
  required List<ProviderInfo> catalog,
  required String providerId,
  required String modelId,
}) {
  return lookupProviderModelModalitiesInCatalog(
        catalog: catalog,
        providerId: providerId,
        modelId: modelId,
      ) ??
      inferProviderModelModalitiesFallback(modelId);
}

ProviderModelCapabilities resolveProviderModelCapabilities({
  required List<ProviderInfo> catalog,
  required String providerId,
  required String modelId,
}) {
  return lookupProviderModelCapabilitiesInCatalog(
        catalog: catalog,
        providerId: providerId,
        modelId: modelId,
      ) ??
      inferProviderModelCapabilitiesFallback(
        modelId,
        providerId: providerId,
      );
}

JsonMap resolveProviderModelOptions({
  required List<ProviderInfo> catalog,
  required String providerId,
  required String modelId,
  ProviderModelCapabilities? capabilities,
}) {
  return lookupProviderModelOptionsInCatalog(
        catalog: catalog,
        providerId: providerId,
        modelId: modelId,
      ) ??
      inferProviderModelOptionsFallback(
        providerId: providerId,
        modelId: modelId,
        capabilities: capabilities,
      );
}

Map<String, JsonMap> resolveProviderModelVariants({
  required List<ProviderInfo> catalog,
  required String providerId,
  required String modelId,
  ProviderModelCapabilities? capabilities,
  ProviderModelLimit? limit,
}) {
  return lookupProviderModelVariantsInCatalog(
        catalog: catalog,
        providerId: providerId,
        modelId: modelId,
      ) ??
      inferProviderModelVariantsFallback(
        providerId: providerId,
        modelId: modelId,
        capabilities: capabilities,
        limit: limit,
      );
}

List<ProviderInfo> fallbackProviderCatalog() {
  final ids = [
    'mag',
    'anthropic',
    'openai',
    'google',
    'openrouter',
    'vercel',
    'deepseek',
    'github_models',
    'groq',
    'mistral',
    'ollama',
    'xai',
    'openai_compatible',
  ];
  return ids
      .map(
        (id) => ProviderInfo(
          id: id,
          name: id == 'github_models'
              ? 'GitHub Models'
              : id == 'openai_compatible'
                  ? 'OpenAI Compatible'
                  : id == 'xai'
                      ? 'xAI'
                      : '${id[0].toUpperCase()}${id.substring(1)}',
          api: _defaultBaseUrlForProvider(id),
          env: const [],
          models: id == 'mag'
              ? {
                  for (final item in _defaultConnectedModelsForProvider('mag'))
                    item: fallbackProviderModelInfo(
                      item,
                      providerId: id,
                      cost: const ProviderModelCost(input: 0, output: 0),
                    ),
                }
              : const {},
        ),
      )
      .toList();
}
