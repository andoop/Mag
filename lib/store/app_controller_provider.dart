// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'app_controller.dart';

class ProviderDiscoveryException implements Exception {
  ProviderDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

extension AppControllerProvider on AppController {
  Future<void> saveModelConfig(ModelConfig config) async {
    final normalized = normalizeMagFreeModelsOnly(config);
    await _client!.saveModelConfig(normalized);
    final providerList = await _client!.listProviders();
    final providerAuth = await _client!.listProviderAuth();
    final recentModelKeys = await _saveRecentModelKeys(normalized);
    state = state.copyWith(
      modelConfig: normalized,
      providerList: providerList,
      providerAuth: providerAuth,
      recentModelKeys: recentModelKeys,
    );
    notifyListeners();
  }

  Future<ProviderAuthAuthorization?> authorizeProviderOAuth(
    String providerId, {
    required int method,
    Map<String, String>? inputs,
  }) async {
    return _client!.authorizeProviderOAuth(
      providerId,
      method: method,
      inputs: inputs,
    );
  }

  Future<void> callbackProviderOAuth(
    String providerId, {
    required int method,
    String? code,
  }) async {
    await _client!.callbackProviderOAuth(
      providerId,
      method: method,
      code: code,
    );
    final providerList = await _client!.listProviders();
    final providerAuth = await _client!.listProviderAuth();
    state = state.copyWith(
      providerList: providerList,
      providerAuth: providerAuth,
    );
    notifyListeners();
  }

  Future<void> connectProvider(
    ProviderConnection connection, {
    String? currentModelId,
    bool select = true,
  }) async {
    final config = state.modelConfig ?? ModelConfig.defaults();
    final nextConnections = [
      for (final item in config.connections)
        if (item.id != connection.id) item,
      connection,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final next = config.copyWith(
      currentProviderId: select ? connection.id : config.currentProviderId,
      currentModelId: select ? (currentModelId ?? config.currentModelId) : config.currentModelId,
      connections: nextConnections,
    );
    await saveModelConfig(next);
  }

  Future<void> setCurrentModel({
    required String providerId,
    required String modelId,
  }) async {
    final config = state.modelConfig ?? ModelConfig.defaults();
    await saveModelConfig(
      config.copyWith(
        currentProviderId: providerId,
        currentModelId: modelId,
      ),
    );
  }

  Future<void> setModelVisibility({
    required String providerId,
    required String modelId,
    required bool visible,
  }) async {
    final config = state.modelConfig ?? ModelConfig.defaults();
    final nextRules = [
      for (final item in config.visibilityRules)
        if (!(item.providerId == providerId && item.modelId == modelId)) item,
      ModelVisibilityRule(
        providerId: providerId,
        modelId: modelId,
        visibility: visible ? ModelVisibility.show : ModelVisibility.hide,
      ),
    ];
    await saveModelConfig(config.copyWith(visibilityRules: nextRules));
  }

  Future<void> setProviderModels({
    required String providerId,
    required List<String> models,
  }) async {
    final config = state.modelConfig ?? ModelConfig.defaults();
    final connection = config.connectionFor(providerId);
    if (connection == null) return;
    var nextModels = models;
    if (providerId == 'mag') {
      nextModels = filterMagZenFreeModels(models);
      if (nextModels.isEmpty) {
        nextModels = List<String>.from(
          ModelConfig.defaults().connections
              .firstWhere((c) => c.id == 'mag')
              .models,
        );
      }
    }
    final nextConnections = [
      for (final item in config.connections)
        if (item.id == providerId) item.copyWith(models: nextModels) else item,
    ];
    await saveModelConfig(config.copyWith(connections: nextConnections));
  }

  Future<void> disconnectProvider(String providerId) async {
    final config = state.modelConfig ?? ModelConfig.defaults();
    final nextConnections = [
      for (final item in config.connections)
        if (item.id != providerId) item,
    ];
    if (nextConnections.length == config.connections.length) return;

    var nextProviderId = config.currentProviderId;
    var nextModelId = config.currentModelId;
    if (config.currentProviderId == providerId) {
      if (nextConnections.isNotEmpty) {
        final fallback = nextConnections.first;
        nextProviderId = fallback.id;
        nextModelId = fallback.models.isNotEmpty
            ? fallback.models.first
            : (state.providerList?.defaultModels[fallback.id] ??
                ModelConfig.defaults().currentModelId);
      } else {
        nextProviderId = ModelConfig.defaults().currentProviderId;
        nextModelId = ModelConfig.defaults().currentModelId;
      }
    }

    final nextRules = [
      for (final item in config.visibilityRules)
        if (item.providerId != providerId) item,
    ];

    await saveModelConfig(
      config.copyWith(
        currentProviderId: nextProviderId,
        currentModelId: nextModelId,
        connections: nextConnections,
        visibilityRules: nextRules,
      ),
    );
  }

  List<String> _extractIdsFromDataList(dynamic decoded) {
    final list = decoded is Map
        ? decoded['data']
        : decoded is List
            ? decoded
            : null;
    if (list is! List) return const [];
    final items = list
        .map((item) => item is Map ? item['id']?.toString() : null)
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return items;
  }

  String _extractProviderErrorMessage(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) return error.trim();
        if (error is Map) {
          final message = error['message'];
          if (message is String && message.trim().isNotEmpty) {
            return message.trim();
          }
        }
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {
      // Fall back to raw response text below.
    }
    return trimmed;
  }

  String _formatProviderDiscoveryHttpError({
    required int statusCode,
    required String body,
  }) {
    final detail = _extractProviderErrorMessage(body);
    if (statusCode == 401 || statusCode == 403) {
      return detail.isNotEmpty
          ? 'Authentication failed ($statusCode): $detail'
          : 'Authentication failed ($statusCode). Check the API key.';
    }
    if (statusCode == 404) {
      return detail.isNotEmpty
          ? 'Model discovery failed ($statusCode): $detail'
          : 'Model discovery endpoint not found ($statusCode). Check the Base URL.';
    }
    return detail.isNotEmpty
        ? 'Model discovery failed ($statusCode): $detail'
        : 'Model discovery failed with HTTP $statusCode.';
  }

  Future<List<String>> _requestModelIds(
    HttpClient client, {
    required Uri uri,
    Map<String, String> headers = const {},
  }) async {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode >= 400) {
      throw ProviderDiscoveryException(
        _formatProviderDiscoveryHttpError(
          statusCode: response.statusCode,
          body: body,
        ),
      );
    }
    if (body.trim().isEmpty) {
      throw ProviderDiscoveryException('Model discovery returned an empty response.');
    }
    final decoded = jsonDecode(body);
    return _extractIdsFromDataList(decoded);
  }

  Future<List<String>> discoverProviderModels({
    required String providerId,
    required String baseUrl,
    required String apiKey,
    bool usePublicToken = false,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      final effectiveApiKey = usePublicToken ? 'public' : apiKey.trim();

      if (providerId == 'anthropic') {
        return await _requestModelIds(
          client,
          uri: Uri.parse('$normalized/models'),
          headers: {
            'x-api-key': effectiveApiKey,
            'anthropic-version': '2023-06-01',
          },
        );
      }

      if (providerId == 'google') {
        final endpoint = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models?key=${Uri.encodeQueryComponent(effectiveApiKey)}',
        );
        final models = await _requestModelIds(client, uri: endpoint);
        return models
            .where((item) => item.startsWith('models/'))
            .map((item) => item.substring('models/'.length))
            .toList();
      }

      if (providerId == 'github_models') {
        return await _requestModelIds(
          client,
          uri: Uri.parse('https://models.github.ai/catalog/models'),
          headers: {
            'Authorization': 'Bearer $effectiveApiKey',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2026-03-10',
          },
        );
      }

      if (providerId == 'ollama') {
        final root = normalized.replaceFirst(RegExp(r'/v1$'), '');
        final request = await client.getUrl(Uri.parse('$root/api/tags'));
        final response = await request.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode >= 400) {
          throw ProviderDiscoveryException(
            _formatProviderDiscoveryHttpError(
              statusCode: response.statusCode,
              body: body,
            ),
          );
        }
        if (body.trim().isEmpty) {
          throw ProviderDiscoveryException('Model discovery returned an empty response.');
        }
        final decoded = jsonDecode(body);
        final models = decoded is Map ? decoded['models'] : null;
        if (models is! List) {
          throw ProviderDiscoveryException('Model discovery returned an invalid response.');
        }
        final items = models
            .map((item) => item is Map ? item['name']?.toString() : null)
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        if (items.isEmpty) {
          throw ProviderDiscoveryException(
            'Connected successfully, but the provider returned no models.',
          );
        }
        return items;
      }

      final headers = <String, String>{};
      if (effectiveApiKey.isNotEmpty) {
        headers[HttpHeaders.authorizationHeader] = 'Bearer $effectiveApiKey';
      }
      final ids = await _requestModelIds(
        client,
        uri: Uri.parse('$normalized/models'),
        headers: headers,
      );
      if (providerId == 'mag') {
        final filtered = filterMagZenFreeModels(ids);
        if (filtered.isEmpty) {
          throw ProviderDiscoveryException(
            'Connected successfully, but no supported models were returned.',
          );
        }
        return filtered;
      }
      if (ids.isEmpty) {
        throw ProviderDiscoveryException(
          'Connected successfully, but the provider returned no models.',
        );
      }
      return ids;
    } on ProviderDiscoveryException {
      rethrow;
    } on SocketException catch (error) {
      throw ProviderDiscoveryException(
        'Could not reach the provider. Check the Base URL and network. ${error.message}',
      );
    } on HandshakeException catch (error) {
      throw ProviderDiscoveryException(
        'TLS/SSL handshake failed. Check the Base URL or certificate. $error',
      );
    } on HttpException catch (error) {
      throw ProviderDiscoveryException('HTTP error during model discovery: ${error.message}');
    } on FormatException catch (error) {
      throw ProviderDiscoveryException(
        'Model discovery returned invalid JSON. ${error.message}',
      );
    } on TimeoutException {
      throw ProviderDiscoveryException(
        'Model discovery timed out. Check the Base URL, network, or provider status.',
      );
    } catch (error) {
      throw ProviderDiscoveryException('Model discovery failed: $error');
    } finally {
      client.close(force: true);
    }
  }

  Future<List<String>> _loadRecentModelKeys() async {
    final data = await _db.getSetting('recent_models');
    final items = data?['items'] as List?;
    if (items == null) return const [];
    return items.whereType<String>().toList();
  }

  Future<List<String>> _saveRecentModelKeys(ModelConfig config) async {
    final next = <String>[
      '${config.provider}/${config.model}',
      ...state.recentModelKeys.where(
        (item) => item != '${config.provider}/${config.model}',
      ),
    ].take(10).toList();
    await _db.putSetting('recent_models', {'items': next});
    return next;
  }
}
