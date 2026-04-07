part of '../session_engine.dart';

class SessionEngine {
  SessionEngine({
    required this.database,
    required this.events,
    required this.workspaceBridge,
    required this.promptAssembler,
    required this.permissionCenter,
    required this.questionCenter,
    required this.toolRegistry,
    required this.modelGateway,
  });

  final AppDatabase database;
  final LocalEventBus events;
  final WorkspaceBridge workspaceBridge;
  final PromptAssembler promptAssembler;
  final PermissionCenter permissionCenter;
  final QuestionCenter questionCenter;
  final ToolRegistry toolRegistry;
  final ModelGateway modelGateway;

  final Map<String, bool> _busy = {};
  final Map<String, CancelToken> _cancelTokens = {};

  AgentDefinition agentDefinition(String name) => AgentRegistry.resolve(name);

  List<AgentDefinition> listAgents() =>
      AgentRegistry.all().where((item) => !item.hidden).toList();

  Future<ProjectInfo> ensureProject(WorkspaceInfo workspace) async {
    final existing = await database.projectForWorkspace(workspace.id);
    if (existing != null) return existing;
    final project = ProjectInfo(
      id: newId('project'),
      workspaceId: workspace.id,
      name: workspace.name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await database.saveProject(project);
    return project;
  }

  Future<SessionInfo> createSession({
    required WorkspaceInfo workspace,
    String agent = 'build',
    bool isChildSession = false,
  }) async {
    final project = await ensureProject(workspace);
    final now = DateTime.now().millisecondsSinceEpoch;
    final session = SessionInfo(
      id: newId('session'),
      projectId: project.id,
      workspaceId: workspace.id,
      title: SessionTitlePolicy.defaultTitle(isChild: isChildSession),
      agent: agent,
      createdAt: now,
      updatedAt: now,
    );
    await _saveSession(workspace: workspace, session: session);
    return session;
  }

  Future<EngineSnapshot> snapshot(String sessionId) async {
    final messages = await database.listMessages(sessionId);
    final parts = await database.listPartsForSession(sessionId);
    final permissions = await database.listPermissionRequests();
    final questions = await database.listQuestionRequests();
    final todos = await database.listTodos(sessionId);
    return EngineSnapshot(
      messages: messages,
      parts: parts,
      permissions:
          permissions.where((item) => item.sessionId == sessionId).toList(),
      questions:
          questions.where((item) => item.sessionId == sessionId).toList(),
      todos: todos,
    );
  }

  /// Mirrors mag's `SessionPrompt.cancel()`.
  /// Aborts the cancel token, cleans up pending permissions/questions,
  /// and forces idle status.
  Future<void> cancel(String sessionId, {String? directory}) async {
    _debugLog('cancel', 'session=$sessionId');
    final token = _cancelTokens.remove(sessionId);
    token?.cancel();
    permissionCenter.cancelSession(sessionId);
    questionCenter.cancelSession(sessionId);
    _busy.remove(sessionId);
    events.emit(ServerEvent(
      type: 'session.status',
      properties: {'sessionID': sessionId, 'status': 'idle'},
      directory: directory,
    ));
  }

  Future<WorkspaceInfo> _workspaceForSession(SessionInfo session) async {
    final all = await database.listWorkspaces();
    return all.firstWhere((w) => w.id == session.workspaceId);
  }

  /// OpenCode `Session.setTitle`：用户重命名；会发出 `session.updated`。
  Future<SessionInfo> setSessionTitle(String sessionId, String title) async {
    final session = await database.getSession(sessionId);
    if (session == null) {
      throw StateError('Session not found: $sessionId');
    }
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('title must not be empty');
    }
    const maxLen = 256;
    final nextTitle =
        trimmed.length > maxLen ? trimmed.substring(0, maxLen) : trimmed;
    final workspace = await _workspaceForSession(session);
    final next = session.copyWith(
      title: nextTitle,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _saveSession(workspace: workspace, session: next);
    return next;
  }

  /// OpenCode `Session.remove`：取消进行中的任务后级联删除数据并发出 `session.deleted`。
  Future<void> removeSession(String sessionId) async {
    final session = await database.getSession(sessionId);
    if (session == null) return;
    final workspace = await _workspaceForSession(session);
    final snapshot = session;
    await cancel(sessionId, directory: workspace.treeUri);
    await database.deleteSessionCascade(sessionId);
    events.emit(ServerEvent(
      type: 'session.deleted',
      properties: snapshot.toJson(),
      directory: workspace.treeUri,
    ));
  }

  /// Mirrors mag's fire-and-forget pattern in local_server prompt_async.
  Future<void> promptAsync({
    required WorkspaceInfo workspace,
    required SessionInfo session,
    required String text,
    String? agent,
    MessageFormat? format,
  }) {
    return prompt(
      workspace: workspace,
      session: session,
      text: text,
      agent: agent,
      format: format,
    ).then((_) {});
  }

  Future<void> prewarmWorkspaceContext(WorkspaceInfo workspace) {
    return promptAssembler.prewarmWorkspaceContext(workspace);
  }

  Future<SessionInfo> compactSession({
    required WorkspaceInfo workspace,
    required SessionInfo session,
  }) async {
    if (_busy[session.id] == true) {
      throw Exception('Session is already running');
    }
    final modelConfig = ModelConfig.fromJson(
      await database.getSetting('model_config') ??
          ModelConfig.defaults().toJson(),
    );
    final cancelToken = CancelToken();
    _cancelTokens[session.id] = cancelToken;
    _busy[session.id] = true;
    events.emit(ServerEvent(
      type: 'session.status',
      properties: {'sessionID': session.id, 'status': 'compacting'},
      directory: workspace.treeUri,
    ));
    try {
      return await summarize(
        workspace: workspace,
        session: session,
        modelConfig: modelConfig,
        currentAgent: session.agent,
      );
    } catch (error) {
      events.emit(ServerEvent(
        type: 'session.error',
        properties: {
          'sessionID': session.id,
          'message': error.toString(),
        },
        directory: workspace.treeUri,
      ));
      rethrow;
    } finally {
      _cancelTokens.remove(session.id);
      _busy.remove(session.id);
      events.emit(ServerEvent(
        type: 'session.status',
        properties: {'sessionID': session.id, 'status': 'idle'},
        directory: workspace.treeUri,
      ));
    }
  }
}
