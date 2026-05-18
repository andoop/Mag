part of '../models.dart';

const Object _unset = Object();

String _defaultBaseUrlForProvider(String providerId) {
  switch (providerId) {
    case 'anthropic':
      return 'https://api.anthropic.com/v1';
    case 'deepseek':
      return 'https://api.deepseek.com/v1';
    case 'google':
      return 'https://generativelanguage.googleapis.com/v1beta/openai';
    case 'mag':
      return 'https://opencode.ai/zen/v1';
    case 'groq':
      return 'https://api.groq.com/openai/v1';
    case 'mistral':
      return 'https://api.mistral.ai/v1';
    case 'ollama':
      return 'http://localhost:11434/v1';
    case 'openrouter':
      return 'https://openrouter.ai/api/v1';
    case 'openai':
      return 'https://api.openai.com/v1';
    case 'github_models':
      return 'https://models.github.ai/inference';
    case 'vercel':
      return 'https://ai-gateway.vercel.sh/v1';
    case 'xai':
      return 'https://api.x.ai/v1';
    case 'openai_compatible':
      return 'https://api.openai.com/v1';
    default:
      return 'https://api.openai.com/v1';
  }
}

List<String> _defaultConnectedModelsForProvider(String providerId) {
  switch (providerId) {
    case 'mag':
      return const [
        'deepseek-v4-flash-free',
        'minimax-m2.5-free',
        'nemotron-3-super-free',
        'big-pickle',
      ];
    default:
      return const [];
  }
}

/// Mag Zen 免费模型的本地兜底判定。优先使用 models.dev 的 cost 元数据。
bool isMagZenFreeModelId(String modelId) {
  final m = modelId.trim().toLowerCase();
  if (m.endsWith('-free')) return true;
  if (m == 'big-pickle') return true;
  return false;
}

List<String> filterMagZenFreeModels(Iterable<String> models) {
  final filtered =
      models.map((e) => e.trim()).where(isMagZenFreeModelId).toList();
  filtered.sort();
  return filtered;
}

List<String> normalizeProviderModelIds(Iterable<String> models) {
  final normalized = models
      .map((e) => e.trim())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList();
  normalized.sort();
  return normalized;
}

/// 清理连接里的模型列表；Mag 免费/付费可见性由 catalog cost 动态决定。
ModelConfig normalizeProviderConnectionModels(ModelConfig config) {
  final nextConnections = config.connections.map((c) {
    final m = normalizeProviderModelIds(c.models);
    return c.copyWith(
      models: m.isEmpty ? _defaultConnectedModelsForProvider(c.id) : m,
    );
  }).toList();
  return config.copyWith(
    connections: nextConnections,
  );
}

class ProviderConnection {
  ProviderConnection({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.models,
    this.custom = false,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final List<String> models;
  final bool custom;

  ProviderConnection copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    List<String>? models,
    bool? custom,
  }) {
    return ProviderConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      custom: custom ?? this.custom,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'models': models,
        'custom': custom,
      };

  factory ProviderConnection.fromJson(JsonMap json) {
    final id = (json['id'] as String?) ?? 'mag';
    var models = (json['models'] as List? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList();
    models = normalizeProviderModelIds(models);
    if (models.isEmpty) {
      models = _defaultConnectedModelsForProvider(id);
    }
    return ProviderConnection(
      id: id,
      name: (json['name'] as String?) ?? 'Mag',
      baseUrl:
          (json['baseUrl'] as String?) ?? _defaultBaseUrlForProvider('mag'),
      apiKey: (json['apiKey'] as String?) ?? '',
      models: models,
      custom: (json['custom'] as bool?) ?? false,
    );
  }
}

class ModelVisibilityRule {
  ModelVisibilityRule({
    required this.providerId,
    required this.modelId,
    required this.visibility,
  });

  final String providerId;
  final String modelId;
  final ModelVisibility visibility;

  String get key => '$providerId/$modelId';

  JsonMap toJson() => {
        'providerId': providerId,
        'modelId': modelId,
        'visibility': visibility.name,
      };

  factory ModelVisibilityRule.fromJson(JsonMap json) {
    final raw = (json['visibility'] as String?) ?? ModelVisibility.show.name;
    return ModelVisibilityRule(
      providerId: (json['providerId'] as String?) ?? '',
      modelId: (json['modelId'] as String?) ?? '',
      visibility: raw == ModelVisibility.hide.name
          ? ModelVisibility.hide
          : ModelVisibility.show,
    );
  }
}

class ModelConfig {
  ModelConfig({
    required this.currentProviderId,
    required this.currentModelId,
    required this.connections,
    required this.visibilityRules,
    this.currentModelLimit,
    this.currentModelModalities,
    this.currentModelCapabilities,
    this.currentModelOptions,
    this.currentModelVariants,
  });

  final String currentProviderId;
  final String currentModelId;
  final List<ProviderConnection> connections;
  final List<ModelVisibilityRule> visibilityRules;
  final ProviderModelLimit? currentModelLimit;
  final ProviderModelModalities? currentModelModalities;
  final ProviderModelCapabilities? currentModelCapabilities;
  final JsonMap? currentModelOptions;
  final Map<String, JsonMap>? currentModelVariants;

  static const String _defaultMagBaseUrl = 'https://opencode.ai/zen/v1';
  static const String _defaultMagModel = 'minimax-m2.5-free';

  factory ModelConfig.defaults() => ModelConfig(
        currentProviderId: 'mag',
        currentModelId: _defaultMagModel,
        connections: [
          ProviderConnection(
            id: 'mag',
            name: 'Mag',
            baseUrl: _defaultMagBaseUrl,
            apiKey: '',
            models: _defaultConnectedModelsForProvider('mag'),
          ),
        ],
        visibilityRules: const [],
      );

  String get provider => currentProviderId;
  String get model => currentModelId;

  ProviderConnection? get currentConnection {
    for (final item in connections) {
      if (item.id == currentProviderId) return item;
    }
    return null;
  }

  String get baseUrl => currentConnection?.baseUrl ?? _defaultMagBaseUrl;
  String get apiKey => currentConnection?.apiKey ?? '';
  ProviderModelLimit get resolvedCurrentModelLimit =>
      currentModelLimit ?? inferProviderModelLimitFallback(model);

  List<String> get configuredProviderIds =>
      connections.map((item) => item.id).toList();

  ProviderConnection? connectionFor(String providerId) {
    for (final item in connections) {
      if (item.id == providerId) return item;
    }
    return null;
  }

  ModelConfig copyWith({
    String? currentProviderId,
    String? currentModelId,
    List<ProviderConnection>? connections,
    List<ModelVisibilityRule>? visibilityRules,
    Object? currentModelLimit = _unset,
    Object? currentModelModalities = _unset,
    Object? currentModelCapabilities = _unset,
    Object? currentModelOptions = _unset,
    Object? currentModelVariants = _unset,
  }) {
    return ModelConfig(
      currentProviderId: currentProviderId ?? this.currentProviderId,
      currentModelId: currentModelId ?? this.currentModelId,
      connections: connections ?? this.connections,
      visibilityRules: visibilityRules ?? this.visibilityRules,
      currentModelLimit: identical(currentModelLimit, _unset)
          ? this.currentModelLimit
          : currentModelLimit as ProviderModelLimit?,
      currentModelModalities: identical(currentModelModalities, _unset)
          ? this.currentModelModalities
          : currentModelModalities as ProviderModelModalities?,
      currentModelCapabilities: identical(currentModelCapabilities, _unset)
          ? this.currentModelCapabilities
          : currentModelCapabilities as ProviderModelCapabilities?,
      currentModelOptions: identical(currentModelOptions, _unset)
          ? this.currentModelOptions
          : currentModelOptions as JsonMap?,
      currentModelVariants: identical(currentModelVariants, _unset)
          ? this.currentModelVariants
          : currentModelVariants as Map<String, JsonMap>?,
    );
  }

  ModelConfig withResolvedCurrentModelLimit(List<ProviderInfo> catalog) {
    final catalogModalities = lookupProviderModelModalitiesInCatalog(
      catalog: catalog,
      providerId: currentProviderId,
      modelId: currentModelId,
    );
    final catalogCapabilities = lookupProviderModelCapabilitiesInCatalog(
      catalog: catalog,
      providerId: currentProviderId,
      modelId: currentModelId,
    );
    final resolvedCapabilities = catalogCapabilities ??
        currentModelCapabilities ??
        inferProviderModelCapabilitiesFallback(
          currentModelId,
          providerId: currentProviderId,
        );
    final catalogOptions = lookupProviderModelOptionsInCatalog(
      catalog: catalog,
      providerId: currentProviderId,
      modelId: currentModelId,
    );
    final resolvedLimit = resolveProviderModelLimit(
      catalog: catalog,
      providerId: currentProviderId,
      modelId: currentModelId,
    );
    final catalogVariants = lookupProviderModelVariantsInCatalog(
      catalog: catalog,
      providerId: currentProviderId,
      modelId: currentModelId,
    );
    return copyWith(
      currentModelLimit: resolvedLimit,
      currentModelModalities: catalogModalities ??
          currentModelModalities ??
          inferProviderModelModalitiesFallback(currentModelId),
      currentModelCapabilities: resolvedCapabilities,
      currentModelOptions: catalogOptions ??
          currentModelOptions ??
          inferProviderModelOptionsFallback(
            providerId: currentProviderId,
            modelId: currentModelId,
            capabilities: resolvedCapabilities,
          ),
      currentModelVariants: catalogVariants ??
          currentModelVariants ??
          inferProviderModelVariantsFallback(
            providerId: currentProviderId,
            modelId: currentModelId,
            capabilities: resolvedCapabilities,
            limit: resolvedLimit,
          ),
    );
  }

  bool get isMagProvider => provider == 'mag';

  bool get isMagZenFreeModel {
    if (!isMagProvider) return false;
    final m = model.trim().toLowerCase();
    if (m.endsWith('-free')) return true;
    if (m == 'big-pickle') return true;
    return false;
  }

  bool get usesMagPublicToken => isMagProvider && apiKey.trim().isEmpty;

  ModelVisibility? visibilityFor({
    required String providerId,
    required String modelId,
  }) {
    for (final item in visibilityRules) {
      if (item.providerId == providerId && item.modelId == modelId) {
        return item.visibility;
      }
    }
    return null;
  }

  JsonMap toJson() => {
        'currentProviderId': currentProviderId,
        'currentModelId': currentModelId,
        'connections': connections.map((item) => item.toJson()).toList(),
        'visibilityRules':
            visibilityRules.map((item) => item.toJson()).toList(),
        if (currentModelLimit != null)
          'currentModelLimit': currentModelLimit!.toJson(),
        if (currentModelModalities != null)
          'currentModelModalities': currentModelModalities!.toJson(),
        if (currentModelCapabilities != null)
          'currentModelCapabilities': currentModelCapabilities!.toJson(),
        if (currentModelOptions != null)
          'currentModelOptions': currentModelOptions,
        if (currentModelVariants != null)
          'currentModelVariants':
              currentModelVariants!.map((key, value) => MapEntry(key, value)),
      };

  factory ModelConfig.fromJson(JsonMap json) {
    if (json.containsKey('connections') ||
        json.containsKey('currentProviderId')) {
      final connections = (json['connections'] as List? ?? const [])
          .map((item) => ProviderConnection.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList();
      final normalizedConnections = connections.isEmpty
          ? ModelConfig.defaults().connections
          : connections;
      final currentProviderId = (json['currentProviderId'] as String?) ??
          normalizedConnections.first.id;
      final currentModelId =
          (json['currentModelId'] as String?) ?? _defaultMagModel;
      final visibilityRules = (json['visibilityRules'] as List? ?? const [])
          .map((item) => ModelVisibilityRule.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList();
      return normalizeProviderConnectionModels(ModelConfig(
        currentProviderId: currentProviderId,
        currentModelId: currentModelId,
        connections: normalizedConnections,
        visibilityRules: visibilityRules,
        currentModelLimit: json['currentModelLimit'] == null
            ? null
            : ProviderModelLimit.fromJson(
                Map<String, dynamic>.from(json['currentModelLimit'] as Map),
              ),
        currentModelModalities: json['currentModelModalities'] == null
            ? null
            : ProviderModelModalities.fromJson(
                Map<String, dynamic>.from(
                  json['currentModelModalities'] as Map,
                ),
              ),
        currentModelCapabilities: json['currentModelCapabilities'] == null
            ? null
            : ProviderModelCapabilities.fromJson(
                Map<String, dynamic>.from(
                  json['currentModelCapabilities'] as Map,
                ),
              ),
        currentModelOptions: json['currentModelOptions'] == null
            ? null
            : Map<String, dynamic>.from(
                json['currentModelOptions'] as Map,
              ),
        currentModelVariants: json['currentModelVariants'] == null
            ? null
            : (json['currentModelVariants'] as Map).map(
                (key, value) => MapEntry(
                  key.toString(),
                  Map<String, dynamic>.from(value as Map),
                ),
              ),
      ));
    }

    return normalizeProviderConnectionModels(ModelConfig.defaults());
  }
}
