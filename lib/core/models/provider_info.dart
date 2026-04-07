part of '../models.dart';

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

class ProviderModelInfo {
  const ProviderModelInfo({
    required this.id,
    required this.name,
    this.family,
    this.releaseDate = '',
    this.status = 'active',
    this.cost = const ProviderModelCost(),
    this.limit = const ProviderModelLimit(),
  });

  final String id;
  final String name;
  final String? family;
  final String releaseDate;
  final String status;
  final ProviderModelCost cost;
  final ProviderModelLimit limit;

  bool get isDeprecated => status == 'deprecated';

  ProviderModelInfo copyWith({
    String? id,
    String? name,
    Object? family = _unset,
    String? releaseDate,
    String? status,
    ProviderModelCost? cost,
    ProviderModelLimit? limit,
  }) {
    return ProviderModelInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      family: identical(family, _unset) ? this.family : family as String?,
      releaseDate: releaseDate ?? this.releaseDate,
      status: status ?? this.status,
      cost: cost ?? this.cost,
      limit: limit ?? this.limit,
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
      env: (json['env'] as List? ?? const []).map((item) => item.toString()).toList(),
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
      env: (json['env'] as List? ?? const []).map((item) => item.toString()).toList(),
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
            .map((item) => ProviderInfo.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
        connected:
            (json['connected'] as List? ?? const []).map((item) => item.toString()).toList(),
        defaultModels: Map<String, String>.from(
          json['default'] as Map? ?? const <String, String>{},
        ),
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
                    item: ProviderModelInfo(
                      id: item,
                      name: item,
                      cost: const ProviderModelCost(input: 0, output: 0),
                    ),
                }
              : const {},
        ),
      )
      .toList();
}
