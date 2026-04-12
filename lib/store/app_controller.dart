library app_controller;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/database.dart';
import '../core/debug_trace.dart';
import '../core/git/git_settings_store.dart';
import '../core/local_server.dart';
import '../core/mcp_service.dart';
import '../core/models.dart';
import '../core/prompt_system.dart';
import '../core/session_engine.dart';
import '../core/tool_runtime.dart';
import '../core/workspace_bridge.dart';
import '../sdk/local_server_client.dart';
import 'project_recents_store.dart';

part 'app_controller_events.dart';
part 'app_controller_session.dart';
part 'app_controller_provider.dart';
part 'app_controller_mcp.dart';
part 'app_controller_git.dart';
part 'app_controller_workspace.dart';
part 'app_controller_state.dart';

/// 按 [SessionInfo.updatedAt] 选取最近活跃会话，相同则比较 [createdAt]。
SessionInfo? _pickLatestSession(Iterable<SessionInfo> sessions) {
  final list = sessions.toList();
  if (list.isEmpty) return null;
  var best = list.first;
  for (final s in list.skip(1)) {
    if (s.updatedAt > best.updatedAt ||
        (s.updatedAt == best.updatedAt && s.createdAt > best.createdAt)) {
      best = s;
    }
  }
  return best;
}

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
    this.gitSettings,
    this.providerList,
    this.providerAuth = const {},
    this.mcpServers = const [],
    this.mcpStatuses = const {},
    this.mcpTools = const [],
    this.mcpResources = const [],
    this.mcpPrompts = const [],
    this.recentModelKeys = const [],
    this.sessionStatuses = const {},
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
  final GitSettings? gitSettings;
  final ProviderListResponse? providerList;
  final Map<String, List<ProviderAuthMethod>> providerAuth;
  final List<McpServerConfig> mcpServers;
  final Map<String, McpServerStatus> mcpStatuses;
  final List<McpToolDefinition> mcpTools;
  final List<McpResourceDefinition> mcpResources;
  final List<McpPromptDefinition> mcpPrompts;
  final List<String> recentModelKeys;
  final Map<String, SessionRunStatus> sessionStatuses;
  final String? error;

  SessionRunStatus statusForSession(String? sessionId) {
    if (sessionId == null || sessionId.isEmpty) {
      return const SessionRunStatus.idle();
    }
    return sessionStatuses[sessionId] ?? const SessionRunStatus.idle();
  }

  SessionRunStatus get currentSessionStatus => statusForSession(session?.id);
  bool get isBusy => currentSessionStatus.isBusy;
  bool isSessionBusy(String? sessionId) => statusForSession(sessionId).isBusy;

  AppState copyWith({
    Uri? serverUri,
    Object? workspace = _noChange,
    Object? session = _noChange,
    List<AgentDefinition>? agents,
    List<SessionInfo>? sessions,
    List<SessionMessageBundle>? messages,
    List<PermissionRequest>? permissions,
    List<QuestionRequest>? questions,
    List<TodoItem>? todos,
    ModelConfig? modelConfig,
    GitSettings? gitSettings,
    ProviderListResponse? providerList,
    Map<String, List<ProviderAuthMethod>>? providerAuth,
    List<McpServerConfig>? mcpServers,
    Map<String, McpServerStatus>? mcpStatuses,
    List<McpToolDefinition>? mcpTools,
    List<McpResourceDefinition>? mcpResources,
    List<McpPromptDefinition>? mcpPrompts,
    List<String>? recentModelKeys,
    Map<String, SessionRunStatus>? sessionStatuses,
    Object? error = _noChange,
  }) {
    return AppState(
      serverUri: serverUri ?? this.serverUri,
      workspace: identical(workspace, _noChange)
          ? this.workspace
          : workspace as WorkspaceInfo?,
      session: identical(session, _noChange)
          ? this.session
          : session as SessionInfo?,
      agents: agents ?? this.agents,
      sessions: sessions ?? this.sessions,
      messages: messages ?? this.messages,
      permissions: permissions ?? this.permissions,
      questions: questions ?? this.questions,
      todos: todos ?? this.todos,
      modelConfig: modelConfig ?? this.modelConfig,
      gitSettings: gitSettings ?? this.gitSettings,
      providerList: providerList ?? this.providerList,
      providerAuth: providerAuth ?? this.providerAuth,
      mcpServers: mcpServers ?? this.mcpServers,
      mcpStatuses: mcpStatuses ?? this.mcpStatuses,
      mcpTools: mcpTools ?? this.mcpTools,
      mcpResources: mcpResources ?? this.mcpResources,
      mcpPrompts: mcpPrompts ?? this.mcpPrompts,
      recentModelKeys: recentModelKeys ?? this.recentModelKeys,
      sessionStatuses: sessionStatuses ?? this.sessionStatuses,
      error: identical(error, _noChange) ? this.error : error as String?,
    );
  }
}

class AppController extends ChangeNotifier {
  AppController()
      : _db = AppDatabase.instance,
        _workspaceBridge = WorkspaceBridge.instance,
        _events = LocalEventBus(),
        _gitSettingsStore = GitSettingsStore(database: AppDatabase.instance) {
    _mcpService = McpService(database: _db, emitEvent: _events.emit);
    _engine = SessionEngine(
      database: _db,
      events: _events,
      workspaceBridge: _workspaceBridge,
      promptAssembler: PromptAssembler(_workspaceBridge),
      permissionCenter: PermissionCenter(_db, _events),
      questionCenter: QuestionCenter(_db, _events),
      toolRegistry: ToolRegistry.builtins(),
      modelGateway: ModelGateway(),
      mcpService: _mcpService,
    );
    _server = LocalServer(
      database: _db,
      engine: _engine,
      events: _events,
      workspaceBridge: _workspaceBridge,
      mcpService: _mcpService,
    );
  }

  final AppDatabase _db;
  final WorkspaceBridge _workspaceBridge;
  final LocalEventBus _events;
  final GitSettingsStore _gitSettingsStore;
  late final McpService _mcpService;
  late final SessionEngine _engine;
  late final LocalServer _server;
  LocalServerClient? _client;
  StreamSubscription<ServerEvent>? _subscription;
  final Map<String, Future<Uint8List>> _workspaceBytesCache = {};
  final Map<String, Future<String>> _workspaceTextCache = {};
  final Map<String, List<WorkspaceEntry>> _workspaceSearchIndexCache = {};
  final Map<String, Future<List<WorkspaceEntry>>> _workspaceSearchIndexInflight =
      {};
  final Map<String, JsonMap> _pendingPartDeltas = {};
  Timer? _partDeltaFlushTimer;
  int _lastFlushDurationMs = 0; // ignore: prefer_final_fields
  static const int _kBaseFlushIntervalMs = 80;
  static const int _kMaxFlushIntervalMs = 160;

  AppState state = const AppState();
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// 与首屏 [ProjectHomePage] 等并发时，必须先等本地服务与 [_client] 就绪，否则会请求失败并被当成「无项目」。
  Future<void>? _initializeFuture;

  Future<void> initialize() {
    return _initializeFuture ??= _runInitialize();
  }

  Future<void> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('theme_mode') ?? 'system';
    _themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  void toggleThemeMode() {
    setThemeMode(
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> _runInitialize() async {
    await loadThemeMode();
    notifyListeners();
    final serverUri = await _server.start();
    _client = LocalServerClient(serverUri);
    _connectEventStream();
    final agents = await _client!.listAgents();
    final modelConfig = await _client!.loadModelConfig();
    final providerList = await _client!.listProviders();
    final providerAuth = await _client!.listProviderAuth();
    final mcpServers = await _client!.listMcpServers();
    final mcpStatuses = await _client!.listMcpStatuses();
    final mcpTools = await _client!.listMcpTools();
    final mcpResources = await _client!.listMcpResources();
    final mcpPrompts = await _client!.listMcpPrompts();
    final gitSettings = await _gitSettingsStore.load();
    final recentModelKeys = await _loadRecentModelKeys();
    state = state.copyWith(
      serverUri: serverUri,
      modelConfig: modelConfig,
      gitSettings: gitSettings,
      providerList: providerList,
      providerAuth: providerAuth,
      mcpServers: mcpServers,
      mcpStatuses: mcpStatuses,
      mcpTools: mcpTools,
      mcpResources: mcpResources,
      mcpPrompts: mcpPrompts,
      agents: agents,
      recentModelKeys: recentModelKeys,
    );
    notifyListeners();
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
      case 'session.deleted':
        final deleted =
            SessionInfo.fromJson(Map<String, dynamic>.from(event.properties));
        if (state.workspace?.id != deleted.workspaceId) return;
        final removedId = deleted.id;
        final sessions =
            state.sessions.where((s) => s.id != removedId).toList();
        final wasCurrent = state.session?.id == removedId;
        state = state.copyWith(
          sessions: sessions,
          session: wasCurrent ? null : state.session,
          messages: wasCurrent ? const [] : state.messages,
          todos: wasCurrent ? const [] : state.todos,
          permissions: wasCurrent ? const [] : state.permissions,
          questions: wasCurrent ? const [] : state.questions,
          error: wasCurrent ? null : state.error,
        );
        _removeSessionStatus(removedId);
        notifyListeners();
        return;
      case 'session.status':
        final sessionId = event.properties['sessionID'] as String?;
        if (sessionId == null || sessionId.isEmpty) {
          return;
        }
        final status = SessionRunStatus.fromJson(
          Map<String, dynamic>.from(event.properties),
        );
        _setSessionStatus(sessionId, status);
        if (_isCurrentSession(sessionId) &&
            status.phase != SessionRunPhase.error) {
          state = state.copyWith(error: null);
        }
        notifyListeners();
        return;
      case 'session.error':
        final sessionId = event.properties['sessionID'] as String?;
        if (sessionId == null || sessionId.isEmpty) {
          return;
        }
        _setSessionError(
          sessionId,
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
      case 'mcp.status.changed':
        final status =
            McpServerStatus.fromJson(Map<String, dynamic>.from(event.properties));
        state = state.copyWith(
          mcpStatuses: {
            ...state.mcpStatuses,
            status.serverId: status,
          },
        );
        notifyListeners();
        return;
      case 'mcp.catalog.changed':
        final serverId = event.properties['serverId'] as String? ?? '';
        final tools = (event.properties['tools'] as List? ?? const [])
            .map((item) => McpToolDefinition.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        final resources = (event.properties['resources'] as List? ?? const [])
            .map((item) =>
                McpResourceDefinition.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        final prompts = (event.properties['prompts'] as List? ?? const [])
            .map((item) => McpPromptDefinition.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
        state = state.copyWith(
          mcpTools: [
            for (final item in state.mcpTools)
              if (item.serverId != serverId) item,
            ...tools,
          ],
          mcpResources: [
            for (final item in state.mcpResources)
              if (item.serverId != serverId) item,
            ...resources,
          ],
          mcpPrompts: [
            for (final item in state.mcpPrompts)
              if (item.serverId != serverId) item,
            ...prompts,
          ],
        );
        notifyListeners();
        return;
      default:
        return;
    }
  }

  Future<void> disposeController() async {
    _partDeltaFlushTimer?.cancel();
    await _subscription?.cancel();
    await _events.close();
    await _server.stop();
  }
}
