part of '../models.dart';

class McpServerConfig {
  const McpServerConfig({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.headers = const {},
    this.timeoutMs = 30000,
    this.auth,
    this.oauth,
  });

  final String id;
  final String name;
  final String url;
  final bool enabled;
  final Map<String, String> headers;
  final int timeoutMs;
  final McpAuthState? auth;
  final McpOAuthConfig? oauth;

  bool get hasAuth => auth != null && auth!.hasCredentials;
  bool get hasOAuth => oauth != null && oauth!.isConfigured;

  McpServerConfig copyWith({
    String? id,
    String? name,
    String? url,
    bool? enabled,
    Map<String, String>? headers,
    int? timeoutMs,
    Object? auth = _mcpNoChange,
    Object? oauth = _mcpNoChange,
  }) {
    return McpServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      enabled: enabled ?? this.enabled,
      headers: headers ?? this.headers,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      auth: identical(auth, _mcpNoChange) ? this.auth : auth as McpAuthState?,
      oauth: identical(oauth, _mcpNoChange) ? this.oauth : oauth as McpOAuthConfig?,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'enabled': enabled,
        if (headers.isNotEmpty) 'headers': headers,
        'timeoutMs': timeoutMs,
        if (auth != null) 'auth': auth!.toJson(),
        if (oauth != null) 'oauth': oauth!.toJson(),
      };

  factory McpServerConfig.fromJson(JsonMap json) => McpServerConfig(
        id: (json['id'] as String?) ?? newId('mcp'),
        name: (json['name'] as String?) ?? '',
        url: (json['url'] as String?) ?? '',
        enabled: json['enabled'] as bool? ?? true,
        headers: Map<String, String>.from(json['headers'] as Map? ?? const {}),
        timeoutMs: (json['timeoutMs'] as num?)?.toInt() ?? 30000,
        auth: json['auth'] is Map
            ? McpAuthState.fromJson(Map<String, dynamic>.from(json['auth'] as Map))
            : null,
        oauth: json['oauth'] is Map
            ? McpOAuthConfig.fromJson(Map<String, dynamic>.from(json['oauth'] as Map))
            : null,
      );
}

const _mcpNoChange = Object();

class McpOAuthConfig {
  const McpOAuthConfig({
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.clientId,
    this.scope,
    this.redirectUri = 'urn:ietf:wg:oauth:2.0:oob',
    this.pendingCodeVerifier,
    this.pendingState,
  });

  final String authorizationEndpoint;
  final String tokenEndpoint;
  final String clientId;
  final String? scope;
  final String redirectUri;
  final String? pendingCodeVerifier;
  final String? pendingState;

  bool get isConfigured =>
      authorizationEndpoint.trim().isNotEmpty &&
      tokenEndpoint.trim().isNotEmpty &&
      clientId.trim().isNotEmpty;

  McpOAuthConfig copyWith({
    String? authorizationEndpoint,
    String? tokenEndpoint,
    String? clientId,
    Object? scope = _mcpNoChange,
    String? redirectUri,
    Object? pendingCodeVerifier = _mcpNoChange,
    Object? pendingState = _mcpNoChange,
  }) {
    return McpOAuthConfig(
      authorizationEndpoint: authorizationEndpoint ?? this.authorizationEndpoint,
      tokenEndpoint: tokenEndpoint ?? this.tokenEndpoint,
      clientId: clientId ?? this.clientId,
      scope: identical(scope, _mcpNoChange) ? this.scope : scope as String?,
      redirectUri: redirectUri ?? this.redirectUri,
      pendingCodeVerifier: identical(pendingCodeVerifier, _mcpNoChange)
          ? this.pendingCodeVerifier
          : pendingCodeVerifier as String?,
      pendingState: identical(pendingState, _mcpNoChange)
          ? this.pendingState
          : pendingState as String?,
    );
  }

  JsonMap toJson() => {
        'authorizationEndpoint': authorizationEndpoint,
        'tokenEndpoint': tokenEndpoint,
        'clientId': clientId,
        if (scope != null) 'scope': scope,
        'redirectUri': redirectUri,
        if (pendingCodeVerifier != null) 'pendingCodeVerifier': pendingCodeVerifier,
        if (pendingState != null) 'pendingState': pendingState,
      };

  factory McpOAuthConfig.fromJson(JsonMap json) => McpOAuthConfig(
        authorizationEndpoint: (json['authorizationEndpoint'] as String?) ?? '',
        tokenEndpoint: (json['tokenEndpoint'] as String?) ?? '',
        clientId: (json['clientId'] as String?) ?? '',
        scope: json['scope'] as String?,
        redirectUri:
            (json['redirectUri'] as String?) ?? 'urn:ietf:wg:oauth:2.0:oob',
        pendingCodeVerifier: json['pendingCodeVerifier'] as String?,
        pendingState: json['pendingState'] as String?,
      );
}

class McpOAuthAuthorization {
  const McpOAuthAuthorization({
    required this.url,
    required this.instructions,
  });

  final String url;
  final String instructions;

  JsonMap toJson() => {
        'url': url,
        'instructions': instructions,
      };

  factory McpOAuthAuthorization.fromJson(JsonMap json) => McpOAuthAuthorization(
        url: (json['url'] as String?) ?? '',
        instructions: (json['instructions'] as String?) ?? '',
      );
}

class McpAuthState {
  const McpAuthState({
    this.type = 'none',
    this.accessToken,
    this.refreshToken,
    this.idToken,
    this.tokenType,
    this.expiresAtMs,
    this.scope,
  });

  final String type;
  final String? accessToken;
  final String? refreshToken;
  final String? idToken;
  final String? tokenType;
  final int? expiresAtMs;
  final String? scope;

  bool get hasCredentials => (accessToken ?? '').isNotEmpty;
  bool get isBearer => type == 'bearer' || (tokenType ?? '').toLowerCase() == 'bearer';
  bool get isExpired =>
      expiresAtMs != null && expiresAtMs! <= DateTime.now().millisecondsSinceEpoch;

  McpAuthState copyWith({
    String? type,
    Object? accessToken = _mcpNoChange,
    Object? refreshToken = _mcpNoChange,
    Object? idToken = _mcpNoChange,
    Object? tokenType = _mcpNoChange,
    Object? expiresAtMs = _mcpNoChange,
    Object? scope = _mcpNoChange,
  }) {
    return McpAuthState(
      type: type ?? this.type,
      accessToken: identical(accessToken, _mcpNoChange)
          ? this.accessToken
          : accessToken as String?,
      refreshToken: identical(refreshToken, _mcpNoChange)
          ? this.refreshToken
          : refreshToken as String?,
      idToken:
          identical(idToken, _mcpNoChange) ? this.idToken : idToken as String?,
      tokenType: identical(tokenType, _mcpNoChange)
          ? this.tokenType
          : tokenType as String?,
      expiresAtMs: identical(expiresAtMs, _mcpNoChange)
          ? this.expiresAtMs
          : expiresAtMs as int?,
      scope: identical(scope, _mcpNoChange) ? this.scope : scope as String?,
    );
  }

  JsonMap toJson() => {
        'type': type,
        if (accessToken != null) 'accessToken': accessToken,
        if (refreshToken != null) 'refreshToken': refreshToken,
        if (idToken != null) 'idToken': idToken,
        if (tokenType != null) 'tokenType': tokenType,
        if (expiresAtMs != null) 'expiresAtMs': expiresAtMs,
        if (scope != null) 'scope': scope,
      };

  factory McpAuthState.fromJson(JsonMap json) => McpAuthState(
        type: (json['type'] as String?) ?? 'none',
        accessToken: json['accessToken'] as String?,
        refreshToken: json['refreshToken'] as String?,
        idToken: json['idToken'] as String?,
        tokenType: json['tokenType'] as String?,
        expiresAtMs: (json['expiresAtMs'] as num?)?.toInt(),
        scope: json['scope'] as String?,
      );
}

class McpServerStatus {
  const McpServerStatus({
    required this.serverId,
    this.connected = false,
    this.connecting = false,
    this.error,
    this.serverName,
    this.serverVersion,
    this.protocolVersion,
    this.capabilities = const {},
    this.toolCount = 0,
    this.resourceCount = 0,
    this.promptCount = 0,
    this.lastSyncAtMs,
  });

  final String serverId;
  final bool connected;
  final bool connecting;
  final String? error;
  final String? serverName;
  final String? serverVersion;
  final String? protocolVersion;
  final JsonMap capabilities;
  final int toolCount;
  final int resourceCount;
  final int promptCount;
  final int? lastSyncAtMs;

  McpServerStatus copyWith({
    bool? connected,
    bool? connecting,
    Object? error = _mcpNoChange,
    Object? serverName = _mcpNoChange,
    Object? serverVersion = _mcpNoChange,
    Object? protocolVersion = _mcpNoChange,
    JsonMap? capabilities,
    int? toolCount,
    int? resourceCount,
    int? promptCount,
    Object? lastSyncAtMs = _mcpNoChange,
  }) {
    return McpServerStatus(
      serverId: serverId,
      connected: connected ?? this.connected,
      connecting: connecting ?? this.connecting,
      error: identical(error, _mcpNoChange) ? this.error : error as String?,
      serverName: identical(serverName, _mcpNoChange)
          ? this.serverName
          : serverName as String?,
      serverVersion: identical(serverVersion, _mcpNoChange)
          ? this.serverVersion
          : serverVersion as String?,
      protocolVersion: identical(protocolVersion, _mcpNoChange)
          ? this.protocolVersion
          : protocolVersion as String?,
      capabilities: capabilities ?? this.capabilities,
      toolCount: toolCount ?? this.toolCount,
      resourceCount: resourceCount ?? this.resourceCount,
      promptCount: promptCount ?? this.promptCount,
      lastSyncAtMs: identical(lastSyncAtMs, _mcpNoChange)
          ? this.lastSyncAtMs
          : lastSyncAtMs as int?,
    );
  }

  JsonMap toJson() => {
        'serverId': serverId,
        'connected': connected,
        'connecting': connecting,
        if (error != null) 'error': error,
        if (serverName != null) 'serverName': serverName,
        if (serverVersion != null) 'serverVersion': serverVersion,
        if (protocolVersion != null) 'protocolVersion': protocolVersion,
        if (capabilities.isNotEmpty) 'capabilities': capabilities,
        'toolCount': toolCount,
        'resourceCount': resourceCount,
        'promptCount': promptCount,
        if (lastSyncAtMs != null) 'lastSyncAtMs': lastSyncAtMs,
      };

  factory McpServerStatus.fromJson(JsonMap json) => McpServerStatus(
        serverId: (json['serverId'] as String?) ?? '',
        connected: json['connected'] as bool? ?? false,
        connecting: json['connecting'] as bool? ?? false,
        error: json['error'] as String?,
        serverName: json['serverName'] as String?,
        serverVersion: json['serverVersion'] as String?,
        protocolVersion: json['protocolVersion'] as String?,
        capabilities:
            Map<String, dynamic>.from(json['capabilities'] as Map? ?? const {}),
        toolCount: (json['toolCount'] as num?)?.toInt() ?? 0,
        resourceCount: (json['resourceCount'] as num?)?.toInt() ?? 0,
        promptCount: (json['promptCount'] as num?)?.toInt() ?? 0,
        lastSyncAtMs: (json['lastSyncAtMs'] as num?)?.toInt(),
      );
}

class McpToolDefinition {
  const McpToolDefinition({
    required this.serverId,
    required this.name,
    required this.description,
    this.inputSchema = const {},
    this.outputSchema = const {},
    this.annotations = const {},
    this.title,
  });

  final String serverId;
  final String name;
  final String description;
  final JsonMap inputSchema;
  final JsonMap outputSchema;
  final JsonMap annotations;
  final String? title;

  String get qualifiedName => 'mcp.$serverId.$name';

  ToolDefinitionModel toToolModel() => ToolDefinitionModel(
        id: qualifiedName,
        description: description,
        parameters: inputSchema.isEmpty ? const {'type': 'object'} : inputSchema,
      );

  JsonMap toJson() => {
        'serverId': serverId,
        'name': name,
        'description': description,
        if (title != null) 'title': title,
        if (inputSchema.isNotEmpty) 'inputSchema': inputSchema,
        if (outputSchema.isNotEmpty) 'outputSchema': outputSchema,
        if (annotations.isNotEmpty) 'annotations': annotations,
      };

  factory McpToolDefinition.fromJson(JsonMap json) => McpToolDefinition(
        serverId: (json['serverId'] as String?) ?? '',
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

class McpResourceDefinition {
  const McpResourceDefinition({
    required this.serverId,
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
  });

  final String serverId;
  final String uri;
  final String name;
  final String? description;
  final String? mimeType;

  JsonMap toJson() => {
        'serverId': serverId,
        'uri': uri,
        'name': name,
        if (description != null) 'description': description,
        if (mimeType != null) 'mimeType': mimeType,
      };

  factory McpResourceDefinition.fromJson(JsonMap json) => McpResourceDefinition(
        serverId: (json['serverId'] as String?) ?? '',
        uri: (json['uri'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        description: json['description'] as String?,
        mimeType: json['mimeType'] as String?,
      );
}

class McpPromptDefinition {
  const McpPromptDefinition({
    required this.serverId,
    required this.name,
    this.description,
    this.arguments = const [],
  });

  final String serverId;
  final String name;
  final String? description;
  final List<McpPromptArgument> arguments;

  JsonMap toJson() => {
        'serverId': serverId,
        'name': name,
        if (description != null) 'description': description,
        if (arguments.isNotEmpty) 'arguments': arguments.map((e) => e.toJson()).toList(),
      };

  factory McpPromptDefinition.fromJson(JsonMap json) => McpPromptDefinition(
        serverId: (json['serverId'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        description: json['description'] as String?,
        arguments: (json['arguments'] as List? ?? const [])
            .map((item) => McpPromptArgument.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
}

class McpPromptArgument {
  const McpPromptArgument({
    required this.name,
    this.description,
    this.required = false,
  });

  final String name;
  final String? description;
  final bool required;

  JsonMap toJson() => {
        'name': name,
        if (description != null) 'description': description,
        'required': required,
      };

  factory McpPromptArgument.fromJson(JsonMap json) => McpPromptArgument(
        name: (json['name'] as String?) ?? '',
        description: json['description'] as String?,
        required: json['required'] as bool? ?? false,
      );
}

class McpResourceContent {
  const McpResourceContent({
    required this.uri,
    this.mimeType,
    this.text,
    this.blob,
  });

  final String uri;
  final String? mimeType;
  final String? text;
  final String? blob;

  JsonMap toJson() => {
        'uri': uri,
        if (mimeType != null) 'mimeType': mimeType,
        if (text != null) 'text': text,
        if (blob != null) 'blob': blob,
      };

  factory McpResourceContent.fromJson(JsonMap json) => McpResourceContent(
        uri: (json['uri'] as String?) ?? '',
        mimeType: json['mimeType'] as String?,
        text: json['text'] as String?,
        blob: json['blob'] as String?,
      );
}

class McpPromptMessage {
  const McpPromptMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final JsonMap content;

  JsonMap toJson() => {
        'role': role,
        'content': content,
      };

  factory McpPromptMessage.fromJson(JsonMap json) => McpPromptMessage(
        role: (json['role'] as String?) ?? 'user',
        content: Map<String, dynamic>.from(json['content'] as Map? ?? const {}),
      );
}

class McpToolCallResult {
  const McpToolCallResult({
    required this.content,
    this.structuredContent = const {},
    this.isError = false,
  });

  final List<JsonMap> content;
  final JsonMap structuredContent;
  final bool isError;

  JsonMap toJson() => {
        'content': content,
        if (structuredContent.isNotEmpty) 'structuredContent': structuredContent,
        'isError': isError,
      };

  factory McpToolCallResult.fromJson(JsonMap json) => McpToolCallResult(
        content: (json['content'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        structuredContent: Map<String, dynamic>.from(
          json['structuredContent'] as Map? ?? const {},
        ),
        isError: json['isError'] as bool? ?? false,
      );
}
