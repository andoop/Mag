// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'app_controller.dart';

extension AppControllerSession on AppController {
  /// 打开一个沙盒项目；若尚无项目则自动创建默认项目。
  Future<void> pickAndOpenProject() async {
    try {
      await initialize();
      final existing = await workspacesForHome(limit: 1);
      if (existing.isNotEmpty) {
        await enterWorkspace(existing.first, openSession: null);
        return;
      }
      final created = await _workspaceBridge.createSandboxProject(
        name: _defaultProjectName(),
      );
      await enterWorkspace(created, openSession: null);
    } catch (error) {
      _setError(error);
    }
  }

  /// 返回项目首页（最近项目 / 打开项目）。
  Future<void> leaveProject() async {
    _cancelPendingPartDeltas();
    _clearWorkspacePreviewCaches();
    state = state.copyWith(
      workspace: null,
      session: null,
      sessions: const [],
      messages: const [],
      permissions: const [],
      questions: const [],
      todos: const [],
      sessionStatuses: const {},
      error: null,
    );
    notifyListeners();
  }

  /// 与 [enterWorkspace] 相同路径：解析 treeUri、写入最近、进入落地页。
  Future<void> openSavedProject(WorkspaceInfo workspace) async {
    await enterWorkspace(workspace, openSession: null);
  }

  /// 打开已有工作区。`openSession == null` 时：若有会话则进入 [updatedAt] 最新的一条，否则展示新建会话落地页。
  Future<void> enterWorkspace(
    WorkspaceInfo picked, {
    SessionInfo? openSession,
  }) async {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      await initialize();
      _cancelPendingPartDeltas();
      _clearWorkspacePreviewCaches();
      final resolved = await _resolveWorkspace(picked);
      await ProjectRecentsStore.touch(resolved.id, resolved.name);
      final sessions = await _client!.listSessions(resolved.id);
      final statuses = await _loadSessionStatuses(resolved.id);
      if (openSession != null) {
        SessionInfo? resolvedSession;
        for (final s in sessions) {
          if (s.id == openSession.id) {
            resolvedSession = s;
            break;
          }
        }
        if (resolvedSession == null) {
          state = state.copyWith(
            workspace: resolved,
            sessions: sessions,
            session: null,
            messages: const [],
            permissions: const [],
            questions: const [],
            todos: const [],
            sessionStatuses: statuses,
            error: null,
          );
          notifyListeners();
        } else {
          state = state.copyWith(
            workspace: resolved,
            sessions: sessions,
            session: resolvedSession,
            sessionStatuses: statuses,
            error: null,
          );
          notifyListeners();
          await refreshSession();
        }
      } else {
        final latest = _pickLatestSession(sessions);
        if (latest != null) {
          state = state.copyWith(
            workspace: resolved,
            sessions: sessions,
            session: latest,
            sessionStatuses: statuses,
            error: null,
          );
          notifyListeners();
          await refreshSession();
        } else {
          state = state.copyWith(
            workspace: resolved,
            sessions: sessions,
            session: null,
            messages: const [],
            permissions: const [],
            questions: const [],
            todos: const [],
            sessionStatuses: statuses,
            error: null,
          );
          notifyListeners();
        }
      }
      debugTrace(
        runId: 'workspace-enter',
        hypothesisId: 'H2',
        location: 'app_controller.dart:enterWorkspace',
        message: 'enterWorkspace completed',
        data: {
          'workspaceId': resolved.id,
          'sessionId': openSession?.id,
          'sessions': sessions.length,
          'elapsedMs': DateTime.now().millisecondsSinceEpoch - startedAt,
        },
      );
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> createAndOpenProject(String name) async {
    try {
      await initialize();
      final workspace = await _workspaceBridge.createSandboxProject(name: name);
      await enterWorkspace(workspace, openSession: null);
    } catch (error) {
      _setError(error);
    }
  }

  Future<WorkspaceInfo?> renameProject(
    WorkspaceInfo workspace,
    String newName,
  ) async {
    try {
      await initialize();
      final renamed = await _workspaceBridge.renameSandboxProject(
        workspace: workspace,
        newName: newName,
      );
      if (renamed.id != workspace.id) {
        await _db.migrateWorkspace(workspace, renamed);
        await ProjectRecentsStore.replaceWorkspaceId(
          oldWorkspaceId: workspace.id,
          newWorkspaceId: renamed.id,
          displayName: renamed.name,
        );
      } else {
        await _client!.saveWorkspace(renamed);
        await ProjectRecentsStore.touch(renamed.id, renamed.name);
      }
      if (state.workspace?.id == workspace.id) {
        final sessions = await _client!.listSessions(renamed.id);
        state = state.copyWith(
          workspace: renamed,
          sessions: sessions,
        );
        notifyListeners();
      }
      return renamed;
    } catch (error) {
      _setError(error);
      return null;
    }
  }

  Future<void> deleteProject(WorkspaceInfo workspace) async {
    try {
      await initialize();
      if (state.workspace?.id == workspace.id) {
        await leaveProject();
      }
      await _workspaceBridge.deleteSandboxProject(workspace);
      await _db.deleteWorkspaceCascade(workspace.id);
      await ProjectRecentsStore.remove(workspace.id);
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> enterNewSessionLanding() async {
    final workspace = state.workspace;
    if (workspace == null) return;
    try {
      _cancelPendingPartDeltas();
      _clearWorkspacePreviewCaches();
      final sessions = await _client!.listSessions(workspace.id);
      final statuses = await _loadSessionStatuses(workspace.id);
      state = state.copyWith(
        session: null,
        sessions: sessions,
        messages: const [],
        permissions: const [],
        questions: const [],
        todos: const [],
        sessionStatuses: statuses,
        error: null,
      );
      notifyListeners();
    } catch (error) {
      _setError(error);
    }
  }

  Future<WorkspaceInfo> _resolveWorkspace(WorkspaceInfo picked) async {
    await _workspaceBridge.getSandboxRootPath();
    if (!_workspaceBridge.isSandboxWorkspace(picked.treeUri)) {
      throw Exception(
          'Unsupported workspace outside sandbox: ${picked.treeUri}');
    }
    await _client!.saveWorkspace(picked);
    return picked;
  }

  /// 供项目首页：已保存的工作区按最近打开时间排序，最多 [limit] 条。
  Future<List<WorkspaceInfo>> workspacesForHome({int limit = 5}) async {
    try {
      await initialize();
    } catch (_) {
      return const [];
    }
    final c = _client;
    if (c == null) return const [];
    final all = await _workspaceBridge.listSandboxProjects();
    if (all.isEmpty) return const [];
    await Future.wait(all.map(c.saveWorkspace));
    final recent = await ProjectRecentsStore.lastOpenedMap();
    int rank(WorkspaceInfo w) {
      return recent[w.id] ?? w.createdAt;
    }

    final sorted = [...all]..sort((a, b) => rank(b).compareTo(rank(a)));
    return sorted.take(limit).toList();
  }

  void _cancelPendingPartDeltas() {
    _partDeltaFlushTimer?.cancel();
    _partDeltaFlushTimer = null;
    _pendingPartDeltas.clear();
  }

  @Deprecated('Use enterWorkspace or pickAndOpenProject')
  Future<void> selectWorkspace(WorkspaceInfo workspace) async {
    await enterWorkspace(workspace, openSession: null);
  }

  String _defaultProjectName() {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return 'Project $stamp';
  }

  Future<void> createSession({String agent = 'build'}) async {
    final workspace = state.workspace;
    if (workspace == null) return;
    try {
      _cancelPendingPartDeltas();
      _clearWorkspacePreviewCaches();
      final session = await _client!.createSession(workspace, agent: agent);
      final sessions = await _client!.listSessions(workspace.id);
      final statuses = await _loadSessionStatuses(workspace.id);
      state = state.copyWith(
          session: session,
          sessions: sessions,
          messages: const [],
          todos: const [],
          permissions: const [],
          questions: const [],
          sessionStatuses: statuses);
      notifyListeners();
      await refreshSession();
    } catch (error) {
      _setError(error);
    }
  }

  /// OpenCode `Session.setTitle`：重命名后由 `session.updated` 同步列表与顶栏。
  Future<void> renameSession(SessionInfo session, String newTitle) async {
    if (state.workspace == null) return;
    try {
      await initialize();
      await _client!.updateSessionTitle(session.id, newTitle);
    } catch (error) {
      _setError(error);
    }
  }

  /// OpenCode `Session.remove`：删除后由 `session.deleted` 更新列表；若删的是当前会话则回到空白落地页。
  Future<void> removeSession(SessionInfo session) async {
    if (state.workspace == null) return;
    try {
      await initialize();
      await _client!.deleteSession(session.id);
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
    final statuses = await _loadSessionStatuses(workspace.id);
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
      sessionStatuses: statuses,
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
    final workspace = state.workspace;
    if (workspace == null) return;
    var session = state.session;
    if (session == null) {
      final useAgent = agent ?? 'build';
      await createSession(agent: useAgent);
      session = state.session;
      if (session == null) return;
    }
    if (state.isSessionBusy(session.id)) {
      state = state.copyWith(
        error: 'Session is already running. 当前会话仍在执行，请稍后再发送。',
      );
      notifyListeners();
      return;
    }
    final modelConfig = state.modelConfig ?? ModelConfig.defaults();
    _debugLog('sendPrompt',
        'provider=${modelConfig.provider} model=${modelConfig.model}');
    final mag = modelConfig.isMagProvider;
    final hasKey = modelConfig.apiKey.trim().isNotEmpty;
    final freeMag = mag && modelConfig.isMagZenFreeModel;
    final needsKey = mag ? (!freeMag && !hasKey) : !hasKey;
    if (needsKey) {
      state = state.copyWith(
        error: 'Missing API key. 请先在设置里配置模型 API Key。',
      );
      notifyListeners();
      return;
    }
    _setSessionStatus(
        session.id, const SessionRunStatus(phase: SessionRunPhase.busy));
    state = state.copyWith(error: null);
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
    if (session == null || state.isSessionBusy(session.id)) return;
    await sendPrompt(
      magMemoryInitializationPrompt,
      agent: session.agent,
    );
  }

  Future<void> compactSession() async {
    final session = state.session;
    if (session == null || state.isSessionBusy(session.id)) return;
    _setSessionStatus(
      session.id,
      const SessionRunStatus(phase: SessionRunPhase.compacting),
    );
    state = state.copyWith(error: null);
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
      _removeSessionStatus(session.id);
      state = state.copyWith(error: null);
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

  Future<Map<String, SessionRunStatus>> _loadSessionStatuses(
    String workspaceId,
  ) async {
    final client = _client;
    if (client == null) {
      return const {};
    }
    return client.listSessionStatuses(workspaceId);
  }
}
