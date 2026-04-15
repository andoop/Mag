import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'database.dart';
import 'models.dart';

const _kMcpSettingsKey = 'mcp.remoteServers.v1';
const _kMcpProtocolVersions = [
  '2025-11-25',
  '2025-06-18',
  '2025-03-26',
  '2024-11-05',
  '2024-10-07',
];

HttpClient Function() _mcpHttpClientFactory = HttpClient.new;

void _logMcp(String tag, String message, [Map<String, dynamic>? data]) {
  final suffix = data == null ? '' : ' ${jsonEncode(data)}';
  // ignore: avoid_print
  print('[mobile-agent][mcp][$tag] $message$suffix');
}

void debugSetMcpHttpClientFactoryForTests(HttpClient Function() factory) {
  _mcpHttpClientFactory = factory;
}

void debugResetMcpHttpClientFactoryForTests() {
  _mcpHttpClientFactory = HttpClient.new;
}

class McpService {
  McpService({
    required AppDatabase database,
    required void Function(ServerEvent event) emitEvent,
  })  : _database = database,
        _emitEvent = emitEvent;

  final AppDatabase _database;
  final void Function(ServerEvent event) _emitEvent;

  final Map<String, _McpRemoteClient> _clients = {};
  final Map<String, McpServerStatus> _statuses = {};
  final Map<String, List<McpToolDefinition>> _toolCache = {};
  final Map<String, List<McpResourceDefinition>> _resourceCache = {};
  final Map<String, List<McpPromptDefinition>> _promptCache = {};

  Future<List<McpServerConfig>> listServers() async {
    final json = await _database.getSetting(_kMcpSettingsKey);
    final list = (json?['servers'] as List? ?? const [])
        .map((item) => McpServerConfig.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<Map<String, McpServerStatus>> listStatuses() async {
    final servers = await listServers();
    final result = <String, McpServerStatus>{};
    for (final server in servers) {
      result[server.id] = _statusFor(server.id);
    }
    return result;
  }

  Future<McpServerConfig?> getServer(String serverId) async {
    final servers = await listServers();
    for (final server in servers) {
      if (server.id == serverId) return server;
    }
    return null;
  }

  Future<List<McpServerConfig>> saveServer(McpServerConfig server) async {
    final servers = await listServers();
    final next = [
      for (final item in servers)
        if (item.id != server.id) item,
      server,
    ];
    await _writeServers(next);
    if (server.enabled) {
      unawaited(refreshServerToolsOnly(server.id));
    } else {
      await disconnect(server.id);
    }
    return listServers();
  }

  Future<List<McpServerConfig>> deleteServer(String serverId) async {
    await disconnect(serverId);
    final servers = await listServers();
    final next = [for (final item in servers) if (item.id != serverId) item];
    await _writeServers(next);
    _statuses.remove(serverId);
    _toolCache.remove(serverId);
    _resourceCache.remove(serverId);
    _promptCache.remove(serverId);
    _emitStatus(serverId);
    return listServers();
  }

  Future<McpOAuthAuthorization> authorizeOAuth(String serverId) async {
    final server = await getServer(serverId);
    if (server == null) {
      throw StateError('Unknown MCP server: $serverId');
    }
    final oauth = server.oauth;
    if (oauth == null || !oauth.isConfigured) {
      throw StateError('OAuth is not configured for MCP server: $serverId');
    }
    final codeVerifier = _randomBase64Url(48);
    final state = _randomBase64Url(24);
    final codeChallenge = _codeChallengeS256(codeVerifier);
    final uri = Uri.parse(oauth.authorizationEndpoint).replace(
      queryParameters: {
        ...Uri.parse(oauth.authorizationEndpoint).queryParameters,
        'response_type': 'code',
        'client_id': oauth.clientId,
        'redirect_uri': oauth.redirectUri,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
        if ((oauth.scope ?? '').trim().isNotEmpty) 'scope': oauth.scope!.trim(),
      },
    );
    await saveServer(
      server.copyWith(
        oauth: oauth.copyWith(
          pendingCodeVerifier: codeVerifier,
          pendingState: state,
        ),
      ),
    );
    return McpOAuthAuthorization(
      url: uri.toString(),
      instructions:
          'Complete the authorization page. If the provider redirects back with a `code` parameter it will be captured automatically; otherwise copy the code and submit it manually.',
    );
  }

  Future<void> callbackOAuth(
    String serverId, {
    required String code,
  }) async {
    final server = await getServer(serverId);
    if (server == null) {
      throw StateError('Unknown MCP server: $serverId');
    }
    final oauth = server.oauth;
    if (oauth == null || !oauth.isConfigured) {
      throw StateError('OAuth is not configured for MCP server: $serverId');
    }
    final verifier = oauth.pendingCodeVerifier;
    if ((verifier ?? '').isEmpty) {
      throw StateError('OAuth authorization was not started for MCP server: $serverId');
    }
    final tokenUri = Uri.parse(oauth.tokenEndpoint);
    final request = await _postForm(
      tokenUri,
      {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': oauth.clientId,
        'redirect_uri': oauth.redirectUri,
        'code_verifier': verifier!,
      },
      headers: server.headers,
    );
    final accessToken = request['access_token'] as String? ?? '';
    if (accessToken.trim().isEmpty) {
      throw StateError('OAuth token response did not include an access_token.');
    }
    final expiresIn = (request['expires_in'] as num?)?.toInt();
    final nextServer = server.copyWith(
      auth: McpAuthState(
        type: 'bearer',
        accessToken: accessToken,
        refreshToken: request['refresh_token'] as String?,
        idToken: request['id_token'] as String?,
        tokenType: request['token_type'] as String? ?? 'Bearer',
        expiresAtMs: expiresIn == null
            ? null
            : DateTime.now().millisecondsSinceEpoch + (expiresIn * 1000),
        scope: request['scope'] as String? ?? oauth.scope,
      ),
      oauth: oauth.copyWith(
        pendingCodeVerifier: null,
        pendingState: null,
      ),
    );
    await saveServer(nextServer);
    await refreshServer(serverId);
  }

  Future<void> refreshAll() async {
    final servers = await listServers();
    final enabledIds = [
      for (final server in servers)
        if (server.enabled) server.id,
    ];
    if (enabledIds.isEmpty) return;
    await Future.wait(enabledIds.map((id) => refreshServerToolsOnly(id)));
  }

  /// OpenCode-style cold path: connect + [listTools] only. Resources/prompts load via [ensureExtendedCatalog].
  Future<McpServerStatus> refreshServerToolsOnly(String serverId) {
    return _refreshServerCatalog(serverId, extended: false);
  }

  /// Full catalog (tools, resources, prompts), e.g. manual refresh in settings.
  Future<McpServerStatus> refreshServer(String serverId) {
    return _refreshServerCatalog(serverId, extended: true);
  }

  Future<McpServerStatus> _refreshServerCatalog(
    String serverId, {
    required bool extended,
  }) async {
    final server = await getServer(serverId);
    if (server == null) {
      throw StateError('Unknown MCP server: $serverId');
    }
    if (!server.enabled) {
      await disconnect(serverId);
      return _statusFor(serverId).copyWith(
        connected: false,
        connecting: false,
        error: 'Disabled',
      );
    }
    _setStatus(serverId, _statusFor(serverId).copyWith(connecting: true, error: null));
    try {
      final client = await _connect(server);
      final init = await client.ensureInitialized();
      final tools = await client.listTools();
      _toolCache[serverId] = tools
          .map((item) => McpToolDefinition(
                serverId: serverId,
                name: item.name,
                description: item.description,
                title: item.title,
                inputSchema: item.inputSchema,
                outputSchema: item.outputSchema,
                annotations: item.annotations,
              ))
          .toList();

      if (extended) {
        final resources = await _listResourcesSafe(client, serverId);
        final prompts = await _listPromptsSafe(client, serverId);
        _resourceCache[serverId] = resources
            .map((item) => McpResourceDefinition(
                  serverId: serverId,
                  uri: item.uri,
                  name: item.name,
                  description: item.description,
                  mimeType: item.mimeType,
                ))
            .toList();
        _promptCache[serverId] = prompts
            .map((item) => McpPromptDefinition(
                  serverId: serverId,
                  name: item.name,
                  description: item.description,
                  arguments: item.arguments
                      .map((arg) => McpPromptArgument(
                            name: arg.name,
                            description: arg.description,
                            required: arg.required,
                          ))
                      .toList(),
                ))
            .toList();
      } else {
        _resourceCache.remove(serverId);
        _promptCache.remove(serverId);
      }

      final status = _statusFor(serverId).copyWith(
        connected: true,
        connecting: false,
        error: null,
        serverName: init.serverInfoName,
        serverVersion: init.serverInfoVersion,
        protocolVersion: init.protocolVersion,
        capabilities: init.capabilities,
        toolCount: _toolCache[serverId]!.length,
        resourceCount: _resourceCache[serverId]?.length ?? 0,
        promptCount: _promptCache[serverId]?.length ?? 0,
        lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _setStatus(serverId, status);
      _emitCatalogChanged(serverId);
      return status;
    } catch (error) {
      _logMcp('refresh.failed', 'Failed to refresh MCP catalog.', {
        'serverId': serverId,
        'extended': extended,
        'error': error.toString(),
      });
      await disconnect(serverId);
      final status = _statusFor(serverId).copyWith(
        connected: false,
        connecting: false,
        error: error.toString(),
      );
      _setStatus(serverId, status);
      return status;
    }
  }

  /// Fetches resources/prompts when tools are already cached (after [refreshServerToolsOnly]).
  Future<void> ensureExtendedCatalog(String serverId) async {
    if (_resourceCache.containsKey(serverId) && _promptCache.containsKey(serverId)) {
      return;
    }
    final server = await getServer(serverId);
    if (server == null || !server.enabled) return;
    if (!_toolCache.containsKey(serverId)) {
      await _refreshServerCatalog(serverId, extended: true);
      return;
    }
    try {
      final client = await _connect(server);
      await client.ensureInitialized();
      if (!_resourceCache.containsKey(serverId)) {
        final resources = await _listResourcesSafe(client, serverId);
        _resourceCache[serverId] = resources
            .map((item) => McpResourceDefinition(
                  serverId: serverId,
                  uri: item.uri,
                  name: item.name,
                  description: item.description,
                  mimeType: item.mimeType,
                ))
            .toList();
      }
      if (!_promptCache.containsKey(serverId)) {
        final prompts = await client.listPrompts();
        _promptCache[serverId] = prompts
            .map((item) => McpPromptDefinition(
                  serverId: serverId,
                  name: item.name,
                  description: item.description,
                  arguments: item.arguments
                      .map((arg) => McpPromptArgument(
                            name: arg.name,
                            description: arg.description,
                            required: arg.required,
                          ))
                      .toList(),
                ))
            .toList();
      }
      final prev = _statusFor(serverId);
      _setStatus(
        serverId,
        prev.copyWith(
          resourceCount: _resourceCache[serverId]!.length,
          promptCount: _promptCache[serverId]!.length,
          lastSyncAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _emitCatalogChanged(serverId);
    } catch (error) {
      _logMcp('catalog.extend.failed', 'Failed to extend MCP catalog.', {
        'serverId': serverId,
        'error': error.toString(),
      });
      _resourceCache.putIfAbsent(serverId, () => const []);
      _promptCache.putIfAbsent(serverId, () => const []);
      _emitCatalogChanged(serverId);
    }
  }

  Future<void> disconnect(String serverId) async {
    await _clients.remove(serverId)?.close();
    _setStatus(
      serverId,
      _statusFor(serverId).copyWith(
        connected: false,
        connecting: false,
        error: null,
      ),
    );
  }

  Future<List<McpToolDefinition>> listTools([String? serverId]) async {
    if (serverId != null) {
      if (_toolCache.containsKey(serverId)) return _toolCache[serverId]!;
      await refreshServerToolsOnly(serverId);
      return _toolCache[serverId] ?? const [];
    }
    final servers = await listServers();
    final enabledIds = [
      for (final server in servers)
        if (server.enabled) server.id,
    ];
    if (enabledIds.isEmpty) return const [];
    await Future.wait(
      enabledIds.map((id) async {
        if (!_toolCache.containsKey(id)) {
          await refreshServerToolsOnly(id);
        }
      }),
    );
    final result = <McpToolDefinition>[];
    for (final id in enabledIds) {
      result.addAll(_toolCache[id] ?? const []);
    }
    return result;
  }

  Future<List<McpResourceDefinition>> listResources([String? serverId]) async {
    if (serverId != null) {
      if (_resourceCache.containsKey(serverId)) return _resourceCache[serverId]!;
      if (_toolCache.containsKey(serverId)) {
        await ensureExtendedCatalog(serverId);
      } else {
        await refreshServer(serverId);
      }
      return _resourceCache[serverId] ?? const [];
    }
    final servers = await listServers();
    final enabledIds = [
      for (final server in servers)
        if (server.enabled) server.id,
    ];
    if (enabledIds.isEmpty) return const [];
    await Future.wait(
      enabledIds.map((id) async {
        if (!_resourceCache.containsKey(id)) {
          if (_toolCache.containsKey(id)) {
            await ensureExtendedCatalog(id);
          } else {
            await refreshServer(id);
          }
        }
      }),
    );
    final result = <McpResourceDefinition>[];
    for (final id in enabledIds) {
      result.addAll(_resourceCache[id] ?? const []);
    }
    return result;
  }

  Future<List<McpPromptDefinition>> listPrompts([String? serverId]) async {
    if (serverId != null) {
      if (_promptCache.containsKey(serverId)) return _promptCache[serverId]!;
      if (_toolCache.containsKey(serverId)) {
        await ensureExtendedCatalog(serverId);
      } else {
        await refreshServer(serverId);
      }
      return _promptCache[serverId] ?? const [];
    }
    final servers = await listServers();
    final enabledIds = [
      for (final server in servers)
        if (server.enabled) server.id,
    ];
    if (enabledIds.isEmpty) return const [];
    await Future.wait(
      enabledIds.map((id) async {
        if (!_promptCache.containsKey(id)) {
          if (_toolCache.containsKey(id)) {
            await ensureExtendedCatalog(id);
          } else {
            await refreshServer(id);
          }
        }
      }),
    );
    final result = <McpPromptDefinition>[];
    for (final id in enabledIds) {
      result.addAll(_promptCache[id] ?? const []);
    }
    return result;
  }

  Future<McpToolCallResult> callTool(
    String serverId,
    String toolName,
    JsonMap arguments,
  ) async {
    final server = await getServer(serverId);
    if (server == null) {
      throw StateError('Unknown MCP server: $serverId');
    }
    final client = await _connect(server);
    await client.ensureInitialized();
    final result = await client.callTool(toolName, arguments);
    return McpToolCallResult(
      content: result.content,
      structuredContent: result.structuredContent,
      isError: result.isError,
    );
  }

  Future<List<McpResourceContent>> readResource(String serverId, String uri) async {
    final server = await getServer(serverId);
    if (server == null) {
      throw StateError('Unknown MCP server: $serverId');
    }
    final client = await _connect(server);
    await client.ensureInitialized();
    final result = await client.readResource(uri);
    return result
        .map((item) => McpResourceContent(
              uri: item.uri,
              mimeType: item.mimeType,
              text: item.text,
              blob: item.blob,
            ))
        .toList();
  }

  Future<List<McpPromptMessage>> getPrompt(
    String serverId,
    String promptName, {
    Map<String, String> arguments = const {},
  }) async {
    final server = await getServer(serverId);
    if (server == null) {
      throw StateError('Unknown MCP server: $serverId');
    }
    final client = await _connect(server);
    await client.ensureInitialized();
    final result = await client.getPrompt(promptName, arguments);
    return result
        .map((item) => McpPromptMessage(role: item.role, content: item.content))
        .toList();
  }

  McpServerStatus _statusFor(String serverId) {
    return _statuses[serverId] ?? McpServerStatus(serverId: serverId);
  }

  void _setStatus(String serverId, McpServerStatus status) {
    _statuses[serverId] = status;
    _emitStatus(serverId);
  }

  void _emitStatus(String serverId) {
    final status = _statuses[serverId];
    if (status == null) return;
    _emitEvent(ServerEvent(
      type: 'mcp.status.changed',
      properties: status.toJson(),
    ));
  }

  void _emitCatalogChanged(String serverId) {
    _emitEvent(ServerEvent(
      type: 'mcp.catalog.changed',
      properties: {
        'serverId': serverId,
        'tools': (_toolCache[serverId] ?? const []).map((e) => e.toJson()).toList(),
        'resources': (_resourceCache[serverId] ?? const []).map((e) => e.toJson()).toList(),
        'prompts': (_promptCache[serverId] ?? const []).map((e) => e.toJson()).toList(),
      },
    ));
  }

  Future<void> _writeServers(List<McpServerConfig> servers) {
    return _database.putSetting(_kMcpSettingsKey, {
      'servers': servers.map((item) => item.toJson()).toList(),
    });
  }

  Future<_McpRemoteClient> _connect(McpServerConfig server) async {
    final existing = _clients[server.id];
    if (existing != null && existing.matches(server)) {
      return existing;
    }
    await _clients.remove(server.id)?.close();
    final client = _McpRemoteClient(server);
    _clients[server.id] = client;
    return client;
  }

  Future<List<_McpRemoteResource>> _listResourcesSafe(
    _McpRemoteClient client,
    String serverId,
  ) async {
    try {
      return await client.listResources();
    } catch (error) {
      if (_isOptionalMethodMissing(error, 'resources/list')) {
        _logMcp('capability.missing', 'Server does not support resources/list.', {
          'serverId': serverId,
          'error': error.toString(),
        });
        return const [];
      }
      rethrow;
    }
  }

  Future<List<_McpRemotePrompt>> _listPromptsSafe(
    _McpRemoteClient client,
    String serverId,
  ) async {
    try {
      return await client.listPrompts();
    } catch (error) {
      if (_isOptionalMethodMissing(error, 'prompts/list')) {
        _logMcp('capability.missing', 'Server does not support prompts/list.', {
          'serverId': serverId,
          'error': error.toString(),
        });
        return const [];
      }
      rethrow;
    }
  }

  Future<JsonMap> _postForm(
    Uri uri,
    Map<String, String> body, {
    Map<String, String> headers = const {},
  }) async {
    final client = _mcpHttpClientFactory();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      headers.forEach(request.headers.set);
      request.write(Uri(queryParameters: body).query);
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'OAuth HTTP ${response.statusCode}: ${text.trim()}',
          uri: uri,
        );
      }
      return Map<String, dynamic>.from(jsonDecode(text) as Map);
    } finally {
      client.close(force: true);
    }
  }
}

String _randomBase64Url(int length) {
  final random = Random.secure();
  final bytes = List<int>.generate(length, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _codeChallengeS256(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

class _McpRemoteClient {
  _McpRemoteClient(this._config) : _client = _mcpHttpClientFactory();

  final McpServerConfig _config;
  final HttpClient _client;
  int _nextId = 1;
  String? _sessionId;
  _McpInitializeResponse? _initialize;

  bool matches(McpServerConfig other) {
    return _config.url == other.url &&
        _config.timeoutMs == other.timeoutMs &&
        _stringMapsEqual(_config.headers, other.headers) &&
        jsonEncode(_config.auth?.toJson()) == jsonEncode(other.auth?.toJson());
  }

  Future<void> close() async {
    _client.close(force: true);
  }

  Future<_McpInitializeResponse> ensureInitialized() async {
    final cached = _initialize;
    if (cached != null) return cached;
    final result = await _initializeRequest();
    _initialize = result;
    await _notifyInitialized();
    return result;
  }

  Future<List<_McpRemoteTool>> listTools() async {
    final result = await _request('tools/list', const {});
    return (result['tools'] as List? ?? const [])
        .map((item) => _McpRemoteTool.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<_McpRemoteResource>> listResources() async {
    final result = await _request('resources/list', const {});
    return (result['resources'] as List? ?? const [])
        .map((item) => _McpRemoteResource.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<_McpRemotePrompt>> listPrompts() async {
    final result = await _request('prompts/list', const {});
    return (result['prompts'] as List? ?? const [])
        .map((item) => _McpRemotePrompt.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<_McpRemoteToolResult> callTool(String name, JsonMap arguments) async {
    final result = await _request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    return _McpRemoteToolResult.fromJson(result);
  }

  Future<List<_McpRemoteResourceContent>> readResource(String uri) async {
    final result = await _request('resources/read', {
      'uri': uri,
    });
    return (result['contents'] as List? ?? const [])
        .map((item) =>
            _McpRemoteResourceContent.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<_McpRemotePromptMessage>> getPrompt(
    String name,
    Map<String, String> arguments,
  ) async {
    final result = await _request('prompts/get', {
      'name': name,
      if (arguments.isNotEmpty) 'arguments': arguments,
    });
    return (result['messages'] as List? ?? const [])
        .map((item) =>
            _McpRemotePromptMessage.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<_McpInitializeResponse> _initializeRequest() async {
    final result = await _request('initialize', {
      'protocolVersion': _kMcpProtocolVersions.first,
      'capabilities': {
        'roots': {'listChanged': false},
        'sampling': {},
        'elicitation': {},
      },
      'clientInfo': {
        'name': 'mobile_agent',
        'version': '1.0.0',
      },
    }, skipInitializeCheck: true);
    return _McpInitializeResponse.fromJson(result);
  }

  Future<void> _notifyInitialized() async {
    try {
      await _post({
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      });
    } catch (_) {
      // Some servers ignore or reject notification-only POSTs; keep the session.
    }
  }

  Future<JsonMap> _request(
    String method,
    JsonMap params, {
    bool skipInitializeCheck = false,
  }) async {
    final requestId = _nextId++;
    if (!skipInitializeCheck && _initialize == null) {
      await ensureInitialized();
    }
    final response = await _post({
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      'params': params,
    });
    final map = _extractResponseEnvelope(response, requestId: requestId);
    final error = map['error'];
    if (error is Map) {
      final code = error['code'];
      final message = error['message'];
      throw StateError('MCP $method failed (${code ?? 'unknown'}): ${message ?? error}');
    }
    final result = map['result'];
    if (result is! Map) {
      return <String, dynamic>{};
    }
    return Map<String, dynamic>.from(result);
  }

  JsonMap _extractResponseEnvelope(
    dynamic response, {
    required int requestId,
  }) {
    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }
    if (response is List) {
      for (final item in response.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        if (map['id'] == requestId) return map;
      }
      for (final item in response.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        if (map.containsKey('result') || map.containsKey('error')) return map;
      }
    }
    throw StateError('Invalid MCP response payload for request $requestId.');
  }

  Future<dynamic> _post(JsonMap payload) async {
    final uri = Uri.parse(_config.url);
    final request = await _client.postUrl(uri).timeout(
          Duration(milliseconds: _config.timeoutMs),
        );
    request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json, text/event-stream');
    if (_sessionId != null && _sessionId!.isNotEmpty) {
      request.headers.set('mcp-session-id', _sessionId!);
    }
    _config.headers.forEach(request.headers.set);
    final auth = _config.auth;
    if (auth != null && auth.hasCredentials) {
      final type = (auth.tokenType ?? 'Bearer').trim();
      request.headers.set(HttpHeaders.authorizationHeader, '$type ${auth.accessToken}');
    }
    request.write(jsonEncode(payload));
    final response = await request.close().timeout(
          Duration(milliseconds: _config.timeoutMs),
        );
    final sessionId = response.headers.value('mcp-session-id');
    if (sessionId != null && sessionId.isNotEmpty) {
      _sessionId = sessionId;
    }
    final body = await utf8
        .decodeStream(response)
        .timeout(Duration(milliseconds: _config.timeoutMs));
    if (response.statusCode >= 400) {
      throw HttpException(
        'MCP HTTP ${response.statusCode}: ${body.trim().isEmpty ? response.reasonPhrase : body.trim()}',
        uri: uri,
      );
    }
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final contentType = response.headers.contentType?.mimeType ?? '';
    return _decodeMcpResponseBody(body, contentType: contentType);
  }
}

dynamic _decodeMcpResponseBody(
  String body, {
  String contentType = '',
}) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) return <String, dynamic>{};
  final looksSse =
      contentType.contains('text/event-stream') ||
      trimmed.startsWith('event:') ||
      trimmed.startsWith('data:');
  if (!looksSse) {
    return jsonDecode(trimmed);
  }
  final messages = <dynamic>[];
  final lines = const LineSplitter().convert(body);
  final dataLines = <String>[];
  void flush() {
    if (dataLines.isEmpty) return;
    final joined = dataLines.join('\n').trim();
    dataLines.clear();
    if (joined.isEmpty) return;
    messages.add(jsonDecode(joined));
  }

  for (final line in lines) {
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (line.startsWith(':')) {
      continue;
    }
    if (line.startsWith('data:')) {
      dataLines.add(line.substring(5).trimLeft());
    }
  }
  flush();
  if (messages.isEmpty) {
    throw const FormatException('No JSON payload found in MCP event stream.');
  }
  if (messages.length == 1) return messages.first;
  return messages;
}

bool _stringMapsEqual(Map<String, String> a, Map<String, String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

bool _isOptionalMethodMissing(Object error, String method) {
  final text = error.toString();
  return text.contains('MCP $method failed (-32601)') && text.contains('Method not found');
}

class _McpInitializeResponse {
  const _McpInitializeResponse({
    required this.protocolVersion,
    required this.serverInfoName,
    required this.serverInfoVersion,
    required this.capabilities,
  });

  final String protocolVersion;
  final String serverInfoName;
  final String serverInfoVersion;
  final JsonMap capabilities;

  factory _McpInitializeResponse.fromJson(JsonMap json) {
    final serverInfo = Map<String, dynamic>.from(json['serverInfo'] as Map? ?? const {});
    return _McpInitializeResponse(
      protocolVersion: (json['protocolVersion'] as String?) ?? '',
      serverInfoName: (serverInfo['name'] as String?) ?? '',
      serverInfoVersion: (serverInfo['version'] as String?) ?? '',
      capabilities: Map<String, dynamic>.from(json['capabilities'] as Map? ?? const {}),
    );
  }
}

class _McpRemoteTool {
  const _McpRemoteTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.outputSchema,
    required this.annotations,
    this.title,
  });

  final String name;
  final String description;
  final JsonMap inputSchema;
  final JsonMap outputSchema;
  final JsonMap annotations;
  final String? title;

  factory _McpRemoteTool.fromJson(JsonMap json) => _McpRemoteTool(
        name: (json['name'] as String?) ?? '',
        description: (json['description'] as String?) ?? '',
        title: json['title'] as String?,
        inputSchema:
            Map<String, dynamic>.from(json['inputSchema'] as Map? ?? const {}),
        outputSchema:
            Map<String, dynamic>.from(json['outputSchema'] as Map? ?? const {}),
        annotations:
            Map<String, dynamic>.from(json['annotations'] as Map? ?? const {}),
      );
}

class _McpRemoteResource {
  const _McpRemoteResource({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
  });

  final String uri;
  final String name;
  final String? description;
  final String? mimeType;

  factory _McpRemoteResource.fromJson(JsonMap json) => _McpRemoteResource(
        uri: (json['uri'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        description: json['description'] as String?,
        mimeType: json['mimeType'] as String?,
      );
}

class _McpRemotePrompt {
  const _McpRemotePrompt({
    required this.name,
    required this.arguments,
    this.description,
  });

  final String name;
  final String? description;
  final List<_McpRemotePromptArgument> arguments;

  factory _McpRemotePrompt.fromJson(JsonMap json) => _McpRemotePrompt(
        name: (json['name'] as String?) ?? '',
        description: json['description'] as String?,
        arguments: (json['arguments'] as List? ?? const [])
            .map((item) => _McpRemotePromptArgument.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

class _McpRemotePromptArgument {
  const _McpRemotePromptArgument({
    required this.name,
    this.description,
    this.required = false,
  });

  final String name;
  final String? description;
  final bool required;

  factory _McpRemotePromptArgument.fromJson(JsonMap json) =>
      _McpRemotePromptArgument(
        name: (json['name'] as String?) ?? '',
        description: json['description'] as String?,
        required: json['required'] as bool? ?? false,
      );
}

class _McpRemoteToolResult {
  const _McpRemoteToolResult({
    required this.content,
    required this.structuredContent,
    required this.isError,
  });

  final List<JsonMap> content;
  final JsonMap structuredContent;
  final bool isError;

  factory _McpRemoteToolResult.fromJson(JsonMap json) => _McpRemoteToolResult(
        content: (json['content'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        structuredContent:
            Map<String, dynamic>.from(json['structuredContent'] as Map? ?? const {}),
        isError: json['isError'] as bool? ?? false,
      );
}

class _McpRemoteResourceContent {
  const _McpRemoteResourceContent({
    required this.uri,
    this.mimeType,
    this.text,
    this.blob,
  });

  final String uri;
  final String? mimeType;
  final String? text;
  final String? blob;

  factory _McpRemoteResourceContent.fromJson(JsonMap json) =>
      _McpRemoteResourceContent(
        uri: (json['uri'] as String?) ?? '',
        mimeType: json['mimeType'] as String?,
        text: json['text'] as String?,
        blob: json['blob'] as String?,
      );
}

class _McpRemotePromptMessage {
  const _McpRemotePromptMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final JsonMap content;

  factory _McpRemotePromptMessage.fromJson(JsonMap json) =>
      _McpRemotePromptMessage(
        role: (json['role'] as String?) ?? 'user',
        content: Map<String, dynamic>.from(json['content'] as Map? ?? const {}),
      );
}
