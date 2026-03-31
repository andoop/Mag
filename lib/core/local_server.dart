import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'database.dart';
import 'models.dart';
import 'session_engine.dart';
import 'workspace_bridge.dart';

const bool _kDebugServer = false;

void _debugLog(String tag, String message) {
  if (!_kDebugServer) return;
  // ignore: avoid_print
  print('[local-server][$tag] $message');
}

class LocalServer {
  LocalServer({
    required this.database,
    required this.engine,
    required this.events,
    required this.workspaceBridge,
  });

  final AppDatabase database;
  final SessionEngine engine;
  final LocalEventBus events;
  final WorkspaceBridge workspaceBridge;

  HttpServer? _server;
  static const _modelsDevCacheKey = 'models_dev_catalog_v1';
  static const _modelsDevUrl = 'https://models.dev/api.json';
  static const _modelsDevRefreshMs = 60 * 60 * 1000;
  List<ProviderInfo>? _modelsDevCatalogCache;
  int _modelsDevCatalogFetchedAt = 0;
  Future<List<ProviderInfo>>? _modelsDevCatalogLoad;

  Uri? get baseUri {
    final server = _server;
    if (server == null) return null;
    return Uri.parse('http://${server.address.address}:${server.port}');
  }

  Future<Uri> start() async {
    final existing = _server;
    if (existing != null) {
      return Uri.parse('http://${existing.address.address}:${existing.port}');
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_listen());
    return baseUri!;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _listen() async {
    final server = _server;
    if (server == null) return;
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/global/event') {
        await _handleSse(request, global: true);
        return;
      }
      if (path == '/event') {
        await _handleSse(request, global: false);
        return;
      }
      if (path == '/workspace' && request.method == 'GET') {
        final workspaces = await database.listWorkspaces();
        await _json(
            request.response, workspaces.map((item) => item.toJson()).toList());
        return;
      }
      if (path == '/workspace' && request.method == 'POST') {
        final body = await _readJson(request);
        final workspace = WorkspaceInfo.fromJson(body);
        await database.saveWorkspace(workspace);
        await engine.ensureProject(workspace);
        await _json(request.response, workspace.toJson());
        return;
      }
      if (path == '/agent' && request.method == 'GET') {
        await _json(request.response,
            engine.listAgents().map((item) => item.toJson()).toList());
        return;
      }
      if (path == '/provider' && request.method == 'GET') {
        final config = ModelConfig.fromJson(
          await database.getSetting('model_config') ??
              ModelConfig.defaults().toJson(),
        );
        final catalog = await _loadModelsDevCatalog();
        final response = _buildProviderListResponse(
          catalog: catalog,
          config: config,
        );
        await _json(request.response, response.toJson());
        return;
      }
      if (path == '/provider/auth' && request.method == 'GET') {
        final config = ModelConfig.fromJson(
          await database.getSetting('model_config') ??
              ModelConfig.defaults().toJson(),
        );
        final catalog = await _loadModelsDevCatalog();
        final response = _buildProviderListResponse(
          catalog: catalog,
          config: config,
        );
        await _json(
          request.response,
          providerAuthMethodsToJson(_buildProviderAuthResponse(response.all)),
        );
        return;
      }
      if (path == '/session' && request.method == 'GET') {
        final workspaceId = request.uri.queryParameters['workspaceId'] ?? '';
        final sessions = await database.listSessions(workspaceId);
        await _json(
            request.response, sessions.map((item) => item.toJson()).toList());
        return;
      }
      if (path == '/session' && request.method == 'POST') {
        final body = await _readJson(request);
        final workspace = WorkspaceInfo.fromJson(
            Map<String, dynamic>.from(body['workspace'] as Map));
        final session = await engine.createSession(
          workspace: workspace,
          agent: body['agent'] as String? ?? 'build',
        );
        await _json(request.response, session.toJson());
        return;
      }
      if (path == '/permission' && request.method == 'GET') {
        final items = await database.listPermissionRequests();
        await _json(
            request.response, items.map((item) => item.toJson()).toList());
        return;
      }
      if (path == '/question' && request.method == 'GET') {
        final items = await database.listQuestionRequests();
        await _json(
            request.response, items.map((item) => item.toJson()).toList());
        return;
      }
      if (path == '/settings/model' && request.method == 'GET') {
        final config = ModelConfig.fromJson(
          await database.getSetting('model_config') ??
              ModelConfig.defaults().toJson(),
        );
        await _json(request.response, config.toJson());
        return;
      }
      if (path == '/settings/model' && request.method == 'POST') {
        final body = await _readJson(request);
        await database.putSetting('model_config', body);
        await _json(request.response, body);
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.length == 4 &&
          segments.first == 'provider' &&
          segments[2] == 'oauth' &&
          segments[3] == 'authorize' &&
          request.method == 'POST') {
        final body = await _readJson(request);
        final method = (body['method'] as num?)?.toInt() ?? 0;
        final inputs = Map<String, String>.from(
          (body['inputs'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
              ) ??
              const <String, String>{},
        );
        final result = await _authorizeProviderOAuth(
          providerId: segments[1],
          method: method,
          inputs: inputs,
        );
        if (result == null) {
          request.response.statusCode = 400;
          await _json(
            request.response,
            {
              'error':
                  'OAuth is not available for this provider in mobile_agent yet.',
            },
          );
          return;
        }
        await _json(request.response, result.toJson());
        return;
      }
      if (segments.length == 4 &&
          segments.first == 'provider' &&
          segments[2] == 'oauth' &&
          segments[3] == 'callback' &&
          request.method == 'POST') {
        final body = await _readJson(request);
        final method = (body['method'] as num?)?.toInt() ?? 0;
        final code = body['code']?.toString();
        final ok = await _callbackProviderOAuth(
          providerId: segments[1],
          method: method,
          code: code,
        );
        if (!ok) {
          request.response.statusCode = 400;
          await _json(
            request.response,
            {
              'error':
                  'OAuth callback is not available for this provider in mobile_agent yet.',
            },
          );
          return;
        }
        await _json(request.response, true);
        return;
      }
      if (segments.length >= 3 &&
          segments.first == 'workspace-file' &&
          request.method == 'GET') {
        final workspaceId = segments[1];
        final relativePath = segments.sublist(2).join('/');
        final workspace = (await database.listWorkspaces())
            .cast<WorkspaceInfo?>()
            .firstWhere((item) => item?.id == workspaceId, orElse: () => null);
        if (workspace == null) {
          request.response.statusCode = 404;
          await _json(request.response, {'error': 'Workspace not found'});
          return;
        }
        try {
          final bytes = await workspaceBridge.readBytes(
            treeUri: workspace.treeUri,
            relativePath: relativePath,
          );
          request.response.headers.contentType =
              _contentTypeForPath(relativePath);
          request.response.add(bytes);
          await request.response.close();
        } catch (_) {
          request.response.statusCode = 404;
          await _json(request.response, {'error': 'Workspace file not found'});
        }
        return;
      }
      if (segments.length >= 2 &&
          segments.first == 'session' &&
          request.method == 'GET') {
        final sessionId = segments[1];
        if (segments.length == 3 && segments[2] == 'message') {
          final snapshot = await engine.snapshot(sessionId);
          await _json(
            request.response,
            snapshot.messages.map((message) {
              final parts = snapshot.parts
                  .where((item) => item.messageId == message.id)
                  .toList();
              return {
                'info': message.toJson(),
                'parts': parts.map((item) => item.toJson()).toList(),
              };
            }).toList(),
          );
          return;
        }
      }
      if (segments.length >= 3 &&
          segments.first == 'session' &&
          request.method == 'POST') {
        final sessionId = segments[1];
        final session = await database.getSession(sessionId);
        if (session == null) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final workspace = (await database.listWorkspaces())
            .firstWhere((item) => item.id == session.workspaceId);
        final body = await _readJson(request);
        if (segments[2] == 'prompt') {
          final format = body['format'] == null
              ? null
              : MessageFormat.fromJson(
                  Map<String, dynamic>.from(body['format'] as Map));
          final message = await engine.prompt(
            workspace: workspace,
            session: session,
            text: body['text'] as String? ?? '',
            agent: body['agent'] as String?,
            format: format,
          );
          await _json(request.response, message.toJson());
          return;
        }
        if (segments[2] == 'message') {
          final message = MessageInfo(
            id: newId('message'),
            sessionId: session.id,
            role: SessionRole.user,
            agent: body['agent'] as String? ?? session.agent,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            text: body['text'] as String? ?? '',
            format: body['format'] == null
                ? null
                : MessageFormat.fromJson(
                    Map<String, dynamic>.from(body['format'] as Map)),
          );
          await database.saveMessage(message);
          events.emit(ServerEvent(
            type: 'message.updated',
            properties: message.toJson(),
            directory: workspace.treeUri,
          ));
          await _json(request.response, message.toJson());
          return;
        }
        if (segments[2] == 'prompt_async') {
          final format = body['format'] == null
              ? null
              : MessageFormat.fromJson(
                  Map<String, dynamic>.from(body['format'] as Map));
          _debugLog('prompt_async', 'session=${session.id}');
          unawaited(
            engine
                .promptAsync(
              workspace: workspace,
              session: session,
              text: body['text'] as String? ?? '',
              agent: body['agent'] as String?,
              format: format,
            )
                .catchError((error) async {
              events.emit(ServerEvent(
                type: 'session.error',
                properties: {
                  'sessionID': session.id,
                  'message': error.toString(),
                },
                directory: workspace.treeUri,
              ));
            }),
          );
          request.response.statusCode = 204;
          await request.response.close();
          return;
        }
        if (segments[2] == 'compact') {
          final updated = await engine.compactSession(
            workspace: workspace,
            session: session,
          );
          await _json(request.response, updated.toJson());
          return;
        }
      }
      if (segments.length == 3 &&
          segments.first == 'session' &&
          segments[2] == 'cancel' &&
          request.method == 'POST') {
        final sessionId = segments[1];
        final session = await database.getSession(sessionId);
        if (session == null) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final workspace = (await database.listWorkspaces())
            .firstWhere((item) => item.id == session.workspaceId);
        await engine.cancel(sessionId, directory: workspace.treeUri);
        await _json(request.response, {'ok': true});
        return;
      }
      if (segments.length == 3 &&
          segments.first == 'permission' &&
          request.method == 'POST') {
        final body = await _readJson(request);
        final reply = PermissionReply.values
            .firstWhere((item) => item.name == body['reply']);
        await engine.permissionCenter.reply(segments[1], reply);
        await _json(request.response, {'ok': true});
        return;
      }
      if (segments.length == 3 &&
          segments.first == 'question' &&
          request.method == 'POST') {
        final body = await _readJson(request);
        final answers = ((body['answers'] as List?) ?? const [])
            .map((item) => List<String>.from(item as List))
            .toList();
        await engine.questionCenter.reply(segments[1], answers);
        await _json(request.response, {'ok': true});
        return;
      }
      request.response.statusCode = 404;
      await _json(request.response, {'error': 'Not found'});
    } catch (error) {
      request.response.statusCode = 500;
      await _json(request.response, {'error': error.toString()});
    }
  }

  Future<void> _handleSse(HttpRequest request, {required bool global}) async {
    request.response.bufferOutput = false;
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.headers
        .set(HttpHeaders.cacheControlHeader, 'no-cache, no-transform');
    request.response.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
    request.response.headers.set('X-Accel-Buffering', 'no');
    request.response.headers.set('X-Content-Type-Options', 'nosniff');
    final directory = request.uri.queryParameters['directory'];
    var closed = false;
    var writeQueue = Future<void>.value();

    Future<void> writeEvent(ServerEvent event) {
      if (closed) return Future.value();
      writeQueue = writeQueue.then((_) async {
        if (closed) return;
        request.response.write('data: ${jsonEncode(event.toJson())}\n\n');
        await request.response.flush();
      }).catchError((_) {});
      return writeQueue;
    }

    final heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(writeEvent(
          ServerEvent(type: 'server.heartbeat', properties: const {})));
    });
    final subscription = events.stream.listen((event) {
      if (!global && directory != null && event.directory != directory) {
        return;
      }
      unawaited(writeEvent(event));
    });
    await writeEvent(
        ServerEvent(type: 'server.connected', properties: const {}));
    try {
      await request.response.done.catchError((_) {});
    } finally {
      closed = true;
      heartbeat.cancel();
      await subscription.cancel();
      await writeQueue.catchError((_) {});
    }
  }

  Future<List<ProviderInfo>> _loadModelsDevCatalog({bool refresh = false}) async {
    if (!refresh && _modelsDevCatalogCache != null) {
      final age = DateTime.now().millisecondsSinceEpoch - _modelsDevCatalogFetchedAt;
      if (age > _modelsDevRefreshMs) {
        unawaited(_loadModelsDevCatalog(refresh: true));
      }
      return _modelsDevCatalogCache!;
    }
    if (!refresh && _modelsDevCatalogLoad != null) {
      return _modelsDevCatalogLoad!;
    }
    final future = _loadModelsDevCatalogImpl(refresh: refresh);
    if (!refresh) {
      _modelsDevCatalogLoad = future;
    }
    try {
      return await future;
    } finally {
      if (!refresh) {
        _modelsDevCatalogLoad = null;
      }
    }
  }

  Future<List<ProviderInfo>> _loadModelsDevCatalogImpl({bool refresh = false}) async {
    if (!refresh) {
      final cached = await database.getSetting(_modelsDevCacheKey);
      if (cached != null) {
        final providers = (cached['all'] as List? ?? const [])
            .map((item) => ProviderInfo.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        if (providers.isNotEmpty) {
          _modelsDevCatalogCache = normalizeProviderCatalog(providers);
          _modelsDevCatalogFetchedAt = (cached['fetchedAt'] as num?)?.toInt() ?? 0;
          final age =
              DateTime.now().millisecondsSinceEpoch - _modelsDevCatalogFetchedAt;
          if (age > _modelsDevRefreshMs) {
            unawaited(_loadModelsDevCatalog(refresh: true));
          }
          return _modelsDevCatalogCache!;
        }
      }
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(Uri.parse(_modelsDevUrl));
      final response = await request.close();
      if (response.statusCode >= 400) {
        throw HttpException('models.dev ${response.statusCode}');
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Invalid models.dev payload');
      }
      final providers = normalizeProviderCatalog(
        Map<String, dynamic>.from(decoded).entries
            .map(
              (entry) => ProviderInfo.fromModelsDevJson(
                entry.key,
                Map<String, dynamic>.from(entry.value as Map),
              ),
            )
            .toList(),
      );
      _modelsDevCatalogCache = providers;
      _modelsDevCatalogFetchedAt = DateTime.now().millisecondsSinceEpoch;
      await database.putSetting(_modelsDevCacheKey, {
        'fetchedAt': _modelsDevCatalogFetchedAt,
        'all': providers.map((item) => item.toJson()).toList(),
      });
      return providers;
    } catch (_) {
      if (_modelsDevCatalogCache != null) {
        return _modelsDevCatalogCache!;
      }
      final cached = await database.getSetting(_modelsDevCacheKey);
      if (cached != null) {
        final providers = (cached['all'] as List? ?? const [])
            .map((item) => ProviderInfo.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        if (providers.isNotEmpty) {
          _modelsDevCatalogCache = normalizeProviderCatalog(providers);
          return _modelsDevCatalogCache!;
        }
      }
      final fallback = fallbackProviderCatalog();
      _modelsDevCatalogCache = fallback;
      _modelsDevCatalogFetchedAt = DateTime.now().millisecondsSinceEpoch;
      return fallback;
    } finally {
      client.close(force: true);
    }
  }

  ProviderListResponse _buildProviderListResponse({
    required List<ProviderInfo> catalog,
    required ModelConfig config,
  }) {
    final connectedIds = config.connections.map((item) => item.id).toSet();
    final merged = <String, ProviderInfo>{
      for (final provider in catalog) provider.id: provider,
    };

    for (final connection in config.connections) {
      final existing = merged[connection.id];
      final mergedModels = <String, ProviderModelInfo>{};
      if (existing != null) {
        mergedModels.addAll(existing.models);
      }
      final modelIds = connection.id == 'mag'
          ? filterMagZenFreeModels(connection.models)
          : connection.models;
      for (final modelId in modelIds) {
        final known = existing?.models[modelId];
        mergedModels[modelId] = known ??
            ProviderModelInfo(
              id: modelId,
              name: modelId,
              cost: connection.id == 'mag'
                  ? const ProviderModelCost(input: 0, output: 0)
                  : const ProviderModelCost(),
              limit: ProviderModelLimit(context: inferContextWindow(modelId)),
            );
      }
      merged[connection.id] = (existing ??
              ProviderInfo(
                id: connection.id,
                name: connection.name,
                api: connection.baseUrl,
                env: const [],
                models: const {},
                custom: connection.custom,
              ))
          .copyWith(
        name: connection.name,
        api: connection.baseUrl,
        models: mergedModels,
        custom: connection.custom,
        connected: true,
      );
    }

    final all = normalizeProviderCatalog(merged.values.toList())
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final defaults = <String, String>{};
    for (final provider in all) {
      final defaultModel = defaultModelIdForProvider(provider);
      if (defaultModel != null) {
        defaults[provider.id] = defaultModel;
      }
    }
    return ProviderListResponse(
      all: all,
      connected: connectedIds.toList()..sort(),
      defaultModels: defaults,
    );
  }

  Map<String, List<ProviderAuthMethod>> _buildProviderAuthResponse(
    List<ProviderInfo> providers,
  ) {
    final result = <String, List<ProviderAuthMethod>>{};
    for (final provider in providers) {
      final methods = _authMethodsForProvider(provider);
      if (methods.isNotEmpty) {
        result[provider.id] = methods;
      }
    }
    return result;
  }

  List<ProviderAuthMethod> _authMethodsForProvider(ProviderInfo provider) {
    if (!_providerRequiresApiKey(provider.id)) {
      return const [];
    }
    final promptLabel = _authPromptLabelForProvider(provider);
    final placeholder = provider.env.isNotEmpty
        ? provider.env.join(', ')
        : _authPlaceholderForProvider(provider.id);
    return [
      ProviderAuthMethod(
        type: 'api',
        label: promptLabel,
        prompts: [
          ProviderAuthPrompt(
            type: 'text',
            key: 'apiKey',
            message: promptLabel,
            placeholder: placeholder,
          ),
        ],
      ),
    ];
  }

  String _authPromptLabelForProvider(ProviderInfo provider) {
    final env = provider.env.join(' ').toUpperCase();
    if (env.contains('GITHUB')) return 'GitHub Token';
    if (env.contains('ACCESS_TOKEN')) return 'Access Token';
    if (env.contains('TOKEN')) return 'Token';
    return 'API Key';
  }

  String _authPlaceholderForProvider(String providerId) {
    switch (providerId) {
      case 'github_models':
        return 'ghp_...';
      default:
        return 'sk-...';
    }
  }

  Future<ProviderAuthAuthorization?> _authorizeProviderOAuth({
    required String providerId,
    required int method,
    required Map<String, String> inputs,
  }) async {
    final methods = _buildProviderAuthResponse(await _loadModelsDevCatalog())[providerId] ??
        const <ProviderAuthMethod>[];
    if (method < 0 || method >= methods.length) return null;
    final selected = methods[method];
    if (!selected.isOauth) return null;
    return null;
  }

  Future<bool> _callbackProviderOAuth({
    required String providerId,
    required int method,
    required String? code,
  }) async {
    final methods = _buildProviderAuthResponse(await _loadModelsDevCatalog())[providerId] ??
        const <ProviderAuthMethod>[];
    if (method < 0 || method >= methods.length) return false;
    final selected = methods[method];
    if (!selected.isOauth) return false;
    if (code != null && code.trim().isEmpty) return false;
    return false;
  }

  Future<JsonMap> _readJson(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.isEmpty) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(body) as Map);
  }

  Future<void> _json(HttpResponse response, Object body) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}

bool _providerRequiresApiKey(String providerId) {
  return providerId != 'mag' && providerId != 'ollama';
}

ContentType _contentTypeForPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html') || lower.endsWith('.htm')) {
    return ContentType.html;
  }
  if (lower.endsWith('.css')) {
    return ContentType('text', 'css', charset: 'utf-8');
  }
  if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
    return ContentType('application', 'javascript', charset: 'utf-8');
  }
  if (lower.endsWith('.json')) {
    return ContentType.json;
  }
  if (lower.endsWith('.svg')) {
    return ContentType('image', 'svg+xml');
  }
  if (lower.endsWith('.png')) {
    return ContentType('image', 'png');
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return ContentType('image', 'jpeg');
  }
  if (lower.endsWith('.gif')) {
    return ContentType('image', 'gif');
  }
  if (lower.endsWith('.webp')) {
    return ContentType('image', 'webp');
  }
  if (lower.endsWith('.wasm')) {
    return ContentType('application', 'wasm');
  }
  return ContentType('text', 'plain', charset: 'utf-8');
}
