import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/database.dart';
import '../core/debug_trace.dart';
import '../core/local_server.dart';
import '../core/models.dart';
import '../core/prompt_system.dart';
import '../core/session_engine.dart';
import '../core/tool_runtime.dart';
import '../core/workspace_bridge.dart';
import '../sdk/local_server_client.dart';

const bool _kDebugEngine = false;

void _debugLog(String tag, String message, [Map<String, dynamic>? data]) {
  if (!_kDebugEngine) return;
  // ignore: avoid_print
  print(
      '[mobile-agent][$tag] $message${data != null ? ' ${jsonEncode(data)}' : ''}');
}

class AppState {
  const AppState({
    this.serverUri,
    this.workspace,
    this.session,
    this.agents = const [],
    this.sessions = const [],
    this.messages = const [],
    this.permissions = const [],
    this.questions = const [],
    this.todos = const [],
    this.modelConfig,
    this.recentModelKeys = const [],
    this.isBusy = false,
    this.error,
  });

  static const _noChange = Object();

  final Uri? serverUri;
  final WorkspaceInfo? workspace;
  final SessionInfo? session;
  final List<AgentDefinition> agents;
  final List<SessionInfo> sessions;
  final List<SessionMessageBundle> messages;
  final List<PermissionRequest> permissions;
  final List<QuestionRequest> questions;
  final List<TodoItem> todos;
  final ModelConfig? modelConfig;
  final List<String> recentModelKeys;
  final bool isBusy;
  final String? error;

  AppState copyWith({
    Uri? serverUri,
    WorkspaceInfo? workspace,
    SessionInfo? session,
    List<AgentDefinition>? agents,
    List<SessionInfo>? sessions,
    List<SessionMessageBundle>? messages,
    List<PermissionRequest>? permissions,
    List<QuestionRequest>? questions,
    List<TodoItem>? todos,
    ModelConfig? modelConfig,
    List<String>? recentModelKeys,
    bool? isBusy,
    Object? error = _noChange,
  }) {
    return AppState(
      serverUri: serverUri ?? this.serverUri,
      workspace: workspace ?? this.workspace,
      session: session ?? this.session,
      agents: agents ?? this.agents,
      sessions: sessions ?? this.sessions,
      messages: messages ?? this.messages,
      permissions: permissions ?? this.permissions,
      questions: questions ?? this.questions,
      todos: todos ?? this.todos,
      modelConfig: modelConfig ?? this.modelConfig,
      recentModelKeys: recentModelKeys ?? this.recentModelKeys,
      isBusy: isBusy ?? this.isBusy,
      error: identical(error, _noChange) ? this.error : error as String?,
    );
  }
}

class AppController extends ChangeNotifier {
  AppController()
      : _db = AppDatabase.instance,
        _workspaceBridge = WorkspaceBridge.instance,
        _events = LocalEventBus() {
    _engine = SessionEngine(
      database: _db,
      events: _events,
      workspaceBridge: _workspaceBridge,
      promptAssembler: PromptAssembler(_workspaceBridge),
      permissionCenter: PermissionCenter(_db, _events),
      questionCenter: QuestionCenter(_db, _events),
      toolRegistry: ToolRegistry.builtins(),
      modelGateway: ModelGateway(),
    );
    _server = LocalServer(
      database: _db,
      engine: _engine,
      events: _events,
      workspaceBridge: _workspaceBridge,
    );
  }

  final AppDatabase _db;
  final WorkspaceBridge _workspaceBridge;
  final LocalEventBus _events;
  late final SessionEngine _engine;
  late final LocalServer _server;
  LocalServerClient? _client;
  StreamSubscription<ServerEvent>? _subscription;
  final Map<String, Future<Uint8List>> _workspaceBytesCache = {};
  final Map<String, Future<String>> _workspaceTextCache = {};
  final Map<String, JsonMap> _pendingPartDeltas = {};
  Timer? _partDeltaFlushTimer;

  AppState state = const AppState();

  Future<void> initialize() async {
    final serverUri = await _server.start();
    _client = LocalServerClient(serverUri);
    _connectEventStream();
    final workspaces = await _client!.listWorkspaces();
    final agents = await _client!.listAgents();
    final modelConfig = await _client!.loadModelConfig();
    final recentModelKeys = await _loadRecentModelKeys();
    state = state.copyWith(
      serverUri: serverUri,
      modelConfig: modelConfig,
      agents: agents,
      recentModelKeys: recentModelKeys,
    );
    notifyListeners();
    if (workspaces.isNotEmpty) {
      await selectWorkspace(workspaces.first);
    }
  }

  void _connectEventStream() {
    _subscription?.cancel();
    _subscription = _client!.globalEvents().listen(
      _handleEvent,
      onError: (error) {
        _debugLog('sse', 'error: $error');
        Future.delayed(const Duration(seconds: 2), _connectEventStream);
      },
      onDone: () {
        _debugLog('sse', 'stream closed, reconnecting');
        Future.delayed(const Duration(milliseconds: 500), _connectEventStream);
      },
    );
  }

  Future<void> disposeController() async {
    _partDeltaFlushTimer?.cancel();
    await _subscription?.cancel();
    await _events.close();
    await _server.stop();
  }

  Future<void> pickWorkspace() async {
    try {
      final workspace = await _workspaceBridge.pickWorkspace();
      if (workspace == null) return;
      await _client!.saveWorkspace(workspace);
      await selectWorkspace(workspace);
    } catch (error) {
      _setError(error);
    }
  }

  void _cancelPendingPartDeltas() {
    _partDeltaFlushTimer?.cancel();
    _partDeltaFlushTimer = null;
    _pendingPartDeltas.clear();
  }

  Future<void> selectWorkspace(WorkspaceInfo workspace) async {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      _cancelPendingPartDeltas();
      _clearWorkspacePreviewCaches();
      var sessions = await _client!.listSessions(workspace.id);
      final session = sessions.isNotEmpty
          ? sessions.first
          : await _client!.createSession(workspace);
      if (sessions.isEmpty) {
        sessions = await _client!.listSessions(workspace.id);
      }
      state = state.copyWith(
          workspace: workspace,
          session: session,
          sessions: sessions,
          error: null);
      notifyListeners();
      await refreshSession();
      // #region agent log
      debugTrace(
        runId: 'workspace-select',
        hypothesisId: 'H2',
        location: 'app_controller.dart:180',
        message: 'selectWorkspace completed',
        data: {
          'workspaceId': workspace.id,
          'sessionId': session.id,
          'sessions': sessions.length,
          'elapsedMs': DateTime.now().millisecondsSinceEpoch - startedAt,
        },
      );
      // #endregion
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> createSession({String agent = 'build'}) async {
    final workspace = state.workspace;
    if (workspace == null) return;
    try {
      _cancelPendingPartDeltas();
      _clearWorkspacePreviewCaches();
      final session = await _client!.createSession(workspace, agent: agent);
      final sessions = await _client!.listSessions(workspace.id);
      state = state.copyWith(
          session: session,
          sessions: sessions,
          messages: const [],
          todos: const [],
          permissions: const [],
          questions: const []);
      notifyListeners();
      await refreshSession();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> refreshSession() async {
    final session = state.session;
    if (session == null) return;
    final workspace = state.workspace;
    if (workspace == null) return;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    final messages = await _client!.listSessionMessages(session.id);
    final sessions = await _client!.listSessions(workspace.id);
    final permissions = await _client!.listPermissions();
    final questions = await _client!.listQuestions();
    final todos = await _db.listTodos(session.id);
    state = state.copyWith(
      messages: messages,
      sessions: sessions,
      permissions:
          permissions.where((item) => item.sessionId == session.id).toList(),
      questions:
          questions.where((item) => item.sessionId == session.id).toList(),
      todos: todos,
    );
    notifyListeners();
    // #region agent log
    debugTrace(
      runId: 'workspace-refresh',
      hypothesisId: 'H2',
      location: 'app_controller.dart:221',
      message: 'refreshSession completed',
      data: {
        'sessionId': session.id,
        'messages': messages.length,
        'parts': messages.fold<int>(0, (sum, item) => sum + item.parts.length),
        'permissions': state.permissions.length,
        'questions': state.questions.length,
        'todos': todos.length,
        'elapsedMs': DateTime.now().millisecondsSinceEpoch - startedAt,
      },
    );
    // #endregion
  }

  Future<void> sendPrompt(String text,
      {String? agent, MessageFormat? format}) async {
    if (text.trim().isEmpty) return;
    final session = state.session;
    if (session == null) return;
    final modelConfig = state.modelConfig ?? ModelConfig.defaults();
    _debugLog('sendPrompt',
        'provider=${modelConfig.provider} model=${modelConfig.model}');
    final mag = modelConfig.isMagProvider;
    final hasKey = modelConfig.apiKey.trim().isNotEmpty;
    final freeMag = mag && modelConfig.isMagZenFreeModel;
    final needsKey = mag ? (!freeMag && !hasKey) : !hasKey;
    if (needsKey) {
      state = state.copyWith(
        isBusy: false,
        error: 'Missing API key. 请先在设置里配置模型 API Key。',
      );
      notifyListeners();
      return;
    }
    state = state.copyWith(
      isBusy: true,
      error: null,
    );
    notifyListeners();
    try {
      await _client!
          .sendPromptAsync(session.id, text, agent: agent, format: format);
      if (agent != null && agent != session.agent) {
        state = state.copyWith(session: session.copyWith(agent: agent));
        notifyListeners();
      }
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> initializeProjectMemory() async {
    final session = state.session;
    if (session == null || state.isBusy) return;
    await sendPrompt(
      magMemoryInitializationPrompt,
      agent: session.agent,
    );
  }

  Future<void> compactSession() async {
    final session = state.session;
    if (session == null || state.isBusy) return;
    state = state.copyWith(isBusy: true, error: null);
    notifyListeners();
    try {
      final updated = await _client!.compactSession(session.id);
      state = state.copyWith(
        session: updated,
        sessions: _upsertSession(state.sessions, updated),
      );
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> cancelPrompt() async {
    final session = state.session;
    if (session == null) return;
    try {
      await _client!.cancelSession(session.id);
      state = state.copyWith(isBusy: false, error: null);
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> replyPermission(String requestId, PermissionReply reply) async {
    await _client!.replyPermission(requestId, reply);
  }

  Future<void> replyQuestion(
      String requestId, List<List<String>> answers) async {
    await _client!.replyQuestion(requestId, answers);
  }

  Future<void> saveModelConfig(ModelConfig config) async {
    await _client!.saveModelConfig(normalizeMagFreeModelsOnly(config));
    final recentModelKeys = await _saveRecentModelKeys(config);
    state = state.copyWith(
      modelConfig: config,
      recentModelKeys: recentModelKeys,
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

  Future<List<String>> _requestModelIds(
    HttpClient client, {
    required Uri uri,
    Map<String, String> headers = const {},
  }) async {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode >= 400) return const [];
    final body = await response.transform(utf8.decoder).join();
    if (body.trim().isEmpty) return const [];
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
        if (response.statusCode >= 400) return const [];
        final body = await response.transform(utf8.decoder).join();
        if (body.trim().isEmpty) return const [];
        final decoded = jsonDecode(body);
        final models = decoded is Map ? decoded['models'] : null;
        if (models is! List) return const [];
        final items = models
            .map((item) => item is Map ? item['name']?.toString() : null)
            .whereType<String>()
            .where((item) => item.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
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
        return filterMagZenFreeModels(ids);
      }
      return ids;
    } catch (_) {
      return const [];
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

  Future<void> switchSession(SessionInfo session) async {
    _cancelPendingPartDeltas();
    _clearWorkspacePreviewCaches();
    state = state.copyWith(
      session: session,
      messages: const [],
      todos: const [],
      permissions: const [],
      questions: const [],
    );
    notifyListeners();
    await refreshSession();
  }

  Future<Uint8List> loadWorkspaceBytes({
    required String treeUri,
    required String relativePath,
    bool refresh = false,
  }) {
    final key = _workspacePreviewKey(treeUri, relativePath);
    if (refresh) {
      _workspaceBytesCache.remove(key);
    }
    return _workspaceBytesCache.putIfAbsent(key, () async {
      try {
        return await _workspaceBridge.readBytes(
          treeUri: treeUri,
          relativePath: relativePath,
        );
      } catch (_) {
        _workspaceBytesCache.remove(key);
        rethrow;
      }
    });
  }

  Future<String> loadWorkspaceText({
    required String treeUri,
    required String relativePath,
    bool refresh = false,
  }) {
    final key = _workspacePreviewKey(treeUri, relativePath);
    if (refresh) {
      _workspaceTextCache.remove(key);
    }
    return _workspaceTextCache.putIfAbsent(key, () async {
      try {
        return await _workspaceBridge.readText(
          treeUri: treeUri,
          relativePath: relativePath,
        );
      } catch (_) {
        _workspaceTextCache.remove(key);
        rethrow;
      }
    });
  }

  void invalidateWorkspacePreview({
    String? treeUri,
    String? relativePath,
  }) {
    if (treeUri == null) {
      _clearWorkspacePreviewCaches();
      return;
    }
    if (relativePath == null || relativePath.isEmpty) {
      _workspaceBytesCache
          .removeWhere((key, _) => key.startsWith('$treeUri::'));
      _workspaceTextCache.removeWhere((key, _) => key.startsWith('$treeUri::'));
      return;
    }
    final key = _workspacePreviewKey(treeUri, relativePath);
    _workspaceBytesCache.remove(key);
    _workspaceTextCache.remove(key);
  }

  void _handleEvent(ServerEvent event) {
    if (!_matchesWorkspace(event) &&
        !_sessionLifecycleEventForCurrentSession(event)) {
      return;
    }
    if (event.type != 'message.part.delta') {
      _flushPendingPartDeltas();
    }
    if (event.type == 'session.status' || event.type == 'session.error') {
      _debugLog('event', '${event.type} status=${event.properties['status']}');
    }
    switch (event.type) {
      case 'session.updated':
        final session =
            SessionInfo.fromJson(Map<String, dynamic>.from(event.properties));
        if (state.workspace?.id != session.workspaceId) return;
        state = state.copyWith(
          sessions: _upsertSession(state.sessions, session),
          session: state.session?.id == session.id ? session : state.session,
        );
        notifyListeners();
        return;
      case 'session.status':
        if (!_isCurrentSession(event.properties['sessionID'] as String?)) {
          return;
        }
        final status = event.properties['status'] as String?;
        state = state.copyWith(
          isBusy:
              status == 'busy' || status == 'retry' || status == 'compacting',
        );
        notifyListeners();
        return;
      case 'session.error':
        if (!_isCurrentSession(event.properties['sessionID'] as String?)) {
          return;
        }
        state = state.copyWith(
          isBusy: false,
          error:
              event.properties['message'] as String? ?? 'Unknown session error',
        );
        notifyListeners();
        return;
      case 'message.updated':
        final message =
            MessageInfo.fromJson(Map<String, dynamic>.from(event.properties));
        if (!_isCurrentSession(message.sessionId)) return;
        state = state.copyWith(
          messages: _upsertMessage(state.messages, message),
          error: null,
        );
        notifyListeners();
        return;
      case 'message.part.updated':
        final part =
            MessagePart.fromJson(Map<String, dynamic>.from(event.properties));
        if (!_isCurrentSession(part.sessionId)) return;
        _invalidatePreviewCacheForPart(part);
        state = state.copyWith(messages: _upsertPart(state.messages, part));
        notifyListeners();
        return;
      case 'message.part.delta':
        if (!_isCurrentSession(event.properties['sessionID'] as String?)) {
          return;
        }
        _queuePartDelta(Map<String, dynamic>.from(event.properties));
        return;
      case 'permission.asked':
        final request = PermissionRequest.fromJson(
            Map<String, dynamic>.from(event.properties));
        if (!_isCurrentSession(request.sessionId)) return;
        state = state.copyWith(
            permissions: _upsertPermission(state.permissions, request));
        notifyListeners();
        return;
      case 'permission.replied':
        if (!_isCurrentSession(event.properties['sessionID'] as String?)) {
          return;
        }
        final requestId = event.properties['requestID'] as String?;
        state = state.copyWith(
          permissions:
              state.permissions.where((item) => item.id != requestId).toList(),
        );
        notifyListeners();
        return;
      case 'question.asked':
        final request = QuestionRequest.fromJson(
            Map<String, dynamic>.from(event.properties));
        if (!_isCurrentSession(request.sessionId)) return;
        state = state.copyWith(
            questions: _upsertQuestion(state.questions, request));
        notifyListeners();
        return;
      case 'question.replied':
        if (!_isCurrentSession(event.properties['sessionID'] as String?)) {
          return;
        }
        final requestId = event.properties['requestID'] as String?;
        state = state.copyWith(
          questions:
              state.questions.where((item) => item.id != requestId).toList(),
        );
        notifyListeners();
        return;
      case 'todo.updated':
        if (!_isCurrentSession(event.properties['sessionID'] as String?)) {
          return;
        }
        final todos = (event.properties['todos'] as List? ?? const [])
            .map((item) =>
                TodoItem.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        state = state.copyWith(todos: todos);
        notifyListeners();
        return;
      default:
        return;
    }
  }

  void _setError(Object error) {
    state = state.copyWith(isBusy: false, error: error.toString());
    notifyListeners();
  }

  /// 终止/错误等只带 sessionID 的事件：directory 与 workspace 略有不一致时仍应更新 isBusy，否则点停止后界面一直转圈。
  bool _sessionLifecycleEventForCurrentSession(ServerEvent event) {
    if (event.type != 'session.status' && event.type != 'session.error') {
      return false;
    }
    return _isCurrentSession(event.properties['sessionID'] as String?);
  }

  bool _matchesWorkspace(ServerEvent event) {
    final workspace = state.workspace;
    if (workspace == null) return true;
    if (event.directory == null) return true;
    final d = event.directory!;
    final w = workspace.treeUri;
    if (d == w) return true;
    // file: URI 可能因编码或尾部斜杠不一致，避免 SSE 全部被丢弃导致界面一直 busy、无回复
    try {
      final ud = Uri.parse(d);
      final uw = Uri.parse(w);
      if (ud.scheme == 'file' && uw.scheme == 'file') {
        var pd = ud.path;
        var pw = uw.path;
        if (pd.endsWith('/')) pd = pd.substring(0, pd.length - 1);
        if (pw.endsWith('/')) pw = pw.substring(0, pw.length - 1);
        if (pd == pw) return true;
      }
    } catch (_) {}
    return false;
  }

  bool _isCurrentSession(String? sessionId) {
    final current = state.session?.id;
    if (current == null || sessionId == null) return false;
    return current == sessionId;
  }

  void _invalidatePreviewCacheForPart(MessagePart part) {
    if (part.type != PartType.tool) return;
    final workspaceTree = state.workspace?.treeUri;
    if (workspaceTree == null) return;
    final stateMap = Map<String, dynamic>.from(
      part.data['state'] as Map? ?? const <String, dynamic>{},
    );
    final attachments = (stateMap['attachments'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    for (final attachment in attachments) {
      final path =
          attachment['path'] as String? ?? attachment['sourcePath'] as String?;
      if (path == null || path.isEmpty) continue;
      invalidateWorkspacePreview(treeUri: workspaceTree, relativePath: path);
    }
    final filePath = stateMap['filepath'] as String? ??
        stateMap['path'] as String? ??
        part.data['filePath'] as String?;
    if (filePath != null && filePath.isNotEmpty) {
      invalidateWorkspacePreview(
          treeUri: workspaceTree, relativePath: filePath);
    }
  }

  String _workspacePreviewKey(String treeUri, String relativePath) =>
      '$treeUri::${relativePath.trim()}';

  void _clearWorkspacePreviewCaches() {
    _workspaceBytesCache.clear();
    _workspaceTextCache.clear();
  }

  void _queuePartDelta(JsonMap payload) {
    final sid = payload['sessionID'] as String?;
    if (!_isCurrentSession(sid)) {
      return;
    }
    final partId = payload['partID'] as String?;
    if (partId == null || partId.isEmpty) {
      state =
          state.copyWith(messages: _applyPartDelta(state.messages, payload));
      notifyListeners();
      return;
    }
    final existing = _pendingPartDeltas[partId];
    if (existing == null) {
      _pendingPartDeltas[partId] = payload;
    } else {
      final merged = Map<String, dynamic>.from(existing);
      final existingDelta =
          Map<String, dynamic>.from(existing['delta'] as Map? ?? const {});
      final nextDelta =
          Map<String, dynamic>.from(payload['delta'] as Map? ?? const {});
      merged['delta'] = _mergeDelta(existingDelta, nextDelta);
      _pendingPartDeltas[partId] = merged;
    }
    _partDeltaFlushTimer ??=
        Timer(const Duration(milliseconds: 48), _flushPendingPartDeltas);
  }

  void _flushPendingPartDeltas() {
    final pendingCount = _pendingPartDeltas.length;
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    _partDeltaFlushTimer?.cancel();
    _partDeltaFlushTimer = null;
    if (_pendingPartDeltas.isEmpty) return;
    var messages = state.messages;
    for (final payload in _pendingPartDeltas.values) {
      final deltaSid = payload['sessionID'] as String?;
      if (!_isCurrentSession(deltaSid)) {
        continue;
      }
      messages = _applyPartDelta(messages, payload);
    }
    _pendingPartDeltas.clear();
    state = state.copyWith(messages: messages);
    notifyListeners();
    // #region agent log
    debugTrace(
      runId: 'delta-flush',
      hypothesisId: 'H5',
      location: 'app_controller.dart:620',
      message: 'delta flush applied',
      data: {
        'pendingCount': pendingCount,
        'messageCount': messages.length,
        'elapsedMs': DateTime.now().millisecondsSinceEpoch - startedAt,
      },
    );
    // #endregion
  }

  List<SessionInfo> _upsertSession(
      List<SessionInfo> sessions, SessionInfo session) {
    final items = [...sessions];
    final index = items.indexWhere((item) => item.id == session.id);
    if (index >= 0) {
      items[index] = session;
    } else {
      items.add(session);
    }
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  List<SessionMessageBundle> _upsertMessage(
    List<SessionMessageBundle> bundles,
    MessageInfo message,
  ) {
    final items = [...bundles];
    final index = items.indexWhere((item) => item.message.id == message.id);
    if (index >= 0) {
      items[index] =
          SessionMessageBundle(message: message, parts: items[index].parts);
    } else {
      items.add(SessionMessageBundle(message: message, parts: const []));
    }
    items.sort((a, b) => a.message.createdAt.compareTo(b.message.createdAt));
    return items;
  }

  List<SessionMessageBundle> _upsertPart(
    List<SessionMessageBundle> bundles,
    MessagePart part,
  ) {
    final items = [...bundles];
    final index = items.indexWhere((item) => item.message.id == part.messageId);
    if (index < 0) return items;
    final parts = [...items[index].parts];
    final partIndex = parts.indexWhere((item) => item.id == part.id);
    if (partIndex >= 0) {
      parts[partIndex] = part;
    } else {
      parts.add(part);
    }
    parts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    items[index] =
        SessionMessageBundle(message: items[index].message, parts: parts);
    return items;
  }

  List<SessionMessageBundle> _applyPartDelta(
    List<SessionMessageBundle> bundles,
    JsonMap payload,
  ) {
    final messageId = payload['messageID'] as String?;
    final partId = payload['partID'] as String?;
    final sessionId = payload['sessionID'] as String?;
    final typeName = payload['type'] as String?;
    final createdAt =
        payload['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    if (messageId == null ||
        partId == null ||
        sessionId == null ||
        typeName == null) {
      return bundles;
    }
    final delta =
        Map<String, dynamic>.from(payload['delta'] as Map? ?? const {});
    final items = [...bundles];
    final index = items.indexWhere((item) => item.message.id == messageId);
    if (index < 0) return items;
    final parts = [...items[index].parts];
    final partIndex = parts.indexWhere((item) => item.id == partId);
    if (partIndex < 0) {
      parts.add(
        MessagePart(
          id: partId,
          sessionId: sessionId,
          messageId: messageId,
          type: PartType.values.firstWhere((item) => item.name == typeName),
          createdAt: createdAt,
          data: delta,
        ),
      );
    } else {
      final existing = parts[partIndex];
      parts[partIndex] = MessagePart(
        id: existing.id,
        sessionId: existing.sessionId,
        messageId: existing.messageId,
        type: existing.type,
        createdAt: existing.createdAt,
        data: _mergeDelta(existing.data, delta),
      );
    }
    parts.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    items[index] =
        SessionMessageBundle(message: items[index].message, parts: parts);
    return items;
  }

  JsonMap _mergeDelta(JsonMap existing, JsonMap delta) {
    final merged = Map<String, dynamic>.from(existing);
    for (final entry in delta.entries) {
      final previous = merged[entry.key];
      final next = entry.value;
      if (previous is String && next is String) {
        merged[entry.key] = '$previous$next';
      } else {
        merged[entry.key] = next;
      }
    }
    return merged;
  }

  List<PermissionRequest> _upsertPermission(
    List<PermissionRequest> items,
    PermissionRequest request,
  ) {
    final next = [...items];
    final index = next.indexWhere((item) => item.id == request.id);
    if (index >= 0) {
      next[index] = request;
    } else {
      next.add(request);
    }
    return next;
  }

  List<QuestionRequest> _upsertQuestion(
    List<QuestionRequest> items,
    QuestionRequest request,
  ) {
    final next = [...items];
    final index = next.indexWhere((item) => item.id == request.id);
    if (index >= 0) {
      next[index] = request;
    } else {
      next.add(request);
    }
    return next;
  }
}
