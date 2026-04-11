part of '../session_engine.dart';

/// OpenCode `packages/opencode/src/agent/prompt/title.txt`
const _titleSystemPrompt = '''
You are a title generator. You output ONLY a thread title. Nothing else.

<task>
Generate a brief title that would help the user find this conversation later.

Follow all rules in <rules>
Use the <examples> so you know what a good title looks like.
Your output must be:
- A single line
- ≤50 characters
- No explanations
</task>

<rules>
- you MUST use the same language as the user message you are summarizing
- Title must be grammatically correct and read naturally - no word salad
- Never include tool names in the title (e.g. "read tool", "bash tool", "edit tool")
- Focus on the main topic or question the user needs to retrieve
- Vary your phrasing - avoid repetitive patterns like always starting with "Analyzing"
- When a file is mentioned, focus on WHAT the user wants to do WITH the file, not just that they shared it
- Keep exact: technical terms, numbers, filenames, HTTP codes
- Remove: the, this, my, a, an
- Never assume tech stack
- Never use tools
- NEVER respond to questions, just generate a title for the conversation
- The title should NEVER include "summarizing" or "generating" when generating a title
- DO NOT SAY YOU CANNOT GENERATE A TITLE OR COMPLAIN ABOUT THE INPUT
- Always output something meaningful, even if the input is minimal.
- If the user message is short or conversational (e.g. "hello", "lol", "what's up", "hey"):
  → create a title that reflects the user's tone or intent (such as Greeting, Quick check-in, Light chat, Intro message, etc.)
</rules>

<examples>
"debug 500 errors in production" → Debugging production 500 errors
"refactor user service" → Refactoring user service
"why is app.js failing" → app.js failure investigation
"implement rate limiting" → Rate limiting implementation
"how do I connect postgres to my API" → Postgres API connection
"best practices for React hooks" → React hooks best practices
"@src/auth.ts can you add refresh token support" → Auth refresh token support
"@utils/parser.ts this is broken" → Parser bug fix
"look at @config.json" → Config review
"@App.tsx add dark mode toggle" → Dark mode toggle in App
</examples>
''';

class _PreparedToolExecution {
  const _PreparedToolExecution({
    required this.requestedToolName,
    required this.tool,
    required this.call,
    this.argumentError,
  });

  final String requestedToolName;
  final ToolDefinition tool;
  final ToolCall call;
  final String? argumentError;
}

extension SessionEngineTools on SessionEngine {
  Future<ToolExecutionResult> _executeTool({
    required WorkspaceInfo workspace,
    required SessionInfo session,
    required MessageInfo message,
    required String agent,
    required ToolCall call,
    CancelToken? cancelToken,
    Map<String, MessagePart>? toolPartCache,
    void Function(MessagePart part)? onPartSaved,
  }) async {
    cancelToken?.throwIfCancelled();
    final prepared = _prepareToolExecution(call);
    final tool = prepared.tool;
    final executableCall = prepared.call;
    final argumentError = prepared.argumentError;
    final ctx = ToolRuntimeContext(
      workspace: workspace,
      session: session,
      message: message,
      agent: agent,
      agentDefinition: agentDefinition(agent),
      bridge: workspaceBridge,
      database: database,
      callId: call.id,
      askPermission: (request) async {
        await _updateToolState(
          workspace: workspace,
          sessionId: session.id,
          callId: call.id,
          status: ToolStatus.running,
          metadata: {
            'phase': 'awaiting_approval',
            'permission': request.permission,
            'patterns': request.patterns,
          },
          toolPartCache: toolPartCache,
          onPartSaved: onPartSaved,
        );
        await permissionCenter.ask(
          workspace: workspace,
          request: request,
          rules: agentDefinition(agent).permissionRules,
          cancelToken: cancelToken,
        );
        await _updateToolState(
          workspace: workspace,
          sessionId: session.id,
          callId: call.id,
          status: ToolStatus.running,
          metadata: {
            'phase': 'applying',
          },
          toolPartCache: toolPartCache,
          onPartSaved: onPartSaved,
        );
      },
      askQuestion: (request) async {
        await _updateToolState(
          workspace: workspace,
          sessionId: session.id,
          callId: call.id,
          status: ToolStatus.running,
          metadata: {
            'phase': 'awaiting_input',
          },
          toolPartCache: toolPartCache,
          onPartSaved: onPartSaved,
        );
        final answers = await questionCenter.ask(
          workspace: workspace,
          request: request,
          cancelToken: cancelToken,
        );
        await _updateToolState(
          workspace: workspace,
          sessionId: session.id,
          callId: call.id,
          status: ToolStatus.running,
          metadata: {
            'phase': 'processing',
          },
          toolPartCache: toolPartCache,
          onPartSaved: onPartSaved,
        );
        return answers;
      },
      resolveInstructionReminder: (relativePath) =>
          promptAssembler.directoryInstructionReminder(
        workspace: workspace,
        relativePath: relativePath,
      ),
      runSubtask: ({
        required SessionInfo session,
        required String description,
        required String prompt,
        required String subagentType,
        String? taskId,
      }) async {
        SessionInfo subSession;
        if (taskId != null && taskId.trim().isNotEmpty) {
          final existing = await database.getSession(taskId.trim());
          if (existing != null) {
            subSession = existing;
          } else {
            subSession = await createSession(
              workspace: workspace,
              agent: subagentType,
              isChildSession: true,
            );
          }
        } else {
          subSession = await createSession(
            workspace: workspace,
            agent: subagentType,
            isChildSession: true,
          );
        }
        await this.prompt(
          workspace: workspace,
          session: subSession,
          text: prompt,
          agent: subagentType,
        );
        final messages = await database.listMessages(subSession.id);
        final parts = await database.listPartsForSession(subSession.id);
        final lastAssistant =
            messages.lastWhere((item) => item.role == SessionRole.assistant);
        final output = parts
            .where((item) =>
                item.messageId == lastAssistant.id &&
                item.type == PartType.text)
            .map((item) => item.data['text'] as String? ?? '')
            .join('\n');
        return ToolExecutionResult(
          title: description,
          output:
              'task_id: ${subSession.id} (reuse this with task_id to continue the same subtask)\n\n<task_result>$output</task_result>',
          metadata: {'taskSessionId': subSession.id},
        );
      },
      saveTodos: (items) async {
        await database.deleteTodosForSession(session.id);
        for (final item in items) {
          await database.saveTodo(item);
        }
        events.emit(ServerEvent(
          type: 'todo.updated',
          properties: {
            'sessionID': session.id,
            'todos': items.map((item) => item.toJson()).toList()
          },
          directory: workspace.treeUri,
        ));
      },
      updateToolProgress: ({
        String? title,
        String? displayOutput,
        JsonMap? metadata,
        List<JsonMap>? attachments,
      }) async {
        await _updateToolState(
          workspace: workspace,
          sessionId: session.id,
          callId: call.id,
          status: ToolStatus.running,
          title: title,
          displayOutput: displayOutput,
          metadata: metadata,
          attachments: attachments,
          toolPartCache: toolPartCache,
          onPartSaved: onPartSaved,
        );
      },
    );
    try {
      _debugLog('tool', 'execute ${call.name}');
      _debugLog('tool-start', 'tool execution starting', {
        'callId': call.id,
        'tool': executableCall.name,
        'requestedTool': prepared.requestedToolName,
        'argKeys': executableCall.arguments.keys.toList(),
        'args': executableCall.arguments,
      });
      await _updateToolState(
        workspace: workspace,
        sessionId: session.id,
        callId: call.id,
        status: ToolStatus.running,
        toolPartCache: toolPartCache,
        onPartSaved: onPartSaved,
      );
      if (argumentError != null) {
        throw Exception(argumentError);
      }
      final result = await tool.execute(executableCall.arguments, ctx);
      _invalidatePromptContextForToolResult(
        workspace: workspace,
        toolName: executableCall.name,
        metadata: result.metadata,
      );
      await _updateToolState(
        workspace: workspace,
        sessionId: session.id,
        callId: call.id,
        status: ToolStatus.completed,
        output: result.output,
        displayOutput: result.displayOutput,
        title: result.title,
        metadata: result.metadata,
        attachments: result.attachments,
        toolPartCache: toolPartCache,
        onPartSaved: onPartSaved,
      );
      _debugLog('tool-done', 'tool execution completed', {
        'callId': call.id,
        'tool': executableCall.name,
        'title': result.title,
        'metadata': result.metadata,
        'outputPreview': result.output.length > 200
            ? '${result.output.substring(0, 200)}...'
            : result.output,
      });
      return result;
    } on CancelledException {
      rethrow;
    } catch (error) {
      _debugLog('tool', 'error ${prepared.requestedToolName}: $error');
      _debugLog('tool-fail', 'tool execution failed', {
        'callId': call.id,
        'tool': executableCall.name,
        'requestedTool': prepared.requestedToolName,
        'error': error.toString(),
        'args': executableCall.arguments,
      });
      final errText = error.toString();
      final recovery =
          _toolErrorRecoveryHint(prepared.requestedToolName, errText);
      final toolOutput =
          '<tool_error tool="${prepared.requestedToolName}">\n$errText\n</tool_error>\n\n<recovery_instructions>\n$recovery\n</recovery_instructions>';
      await _updateToolState(
        workspace: workspace,
        sessionId: session.id,
        callId: call.id,
        status: ToolStatus.error,
        error: errText,
        output: toolOutput,
        displayOutput: '${call.name} failed: $errText',
        toolPartCache: toolPartCache,
        onPartSaved: onPartSaved,
      );
      return ToolExecutionResult(
        title: prepared.requestedToolName,
        output: toolOutput,
        displayOutput: '${prepared.requestedToolName} failed',
        metadata: {
          'failed': true,
          'error': errText,
        },
      );
    }
  }

  _PreparedToolExecution _prepareToolExecution(ToolCall call) {
    final requestedToolName =
        call.name.trim().isEmpty ? 'unknown' : call.name.trim();
    final resolvedTool = toolRegistry[requestedToolName];
    if (resolvedTool == null) {
      return _PreparedToolExecution(
        requestedToolName: requestedToolName,
        tool: toolRegistry['invalid']!,
        call: ToolCall(
          id: call.id,
          name: 'invalid',
          arguments: {
            'tool': requestedToolName,
            'error':
                'Unknown tool `$requestedToolName`. Re-read the available tool list and call one of the advertised tool names exactly.',
          },
        ),
      );
    }
    final args = _normalizedToolArguments(
      requestedToolName: requestedToolName,
      args: call.arguments,
    );
    return _PreparedToolExecution(
      requestedToolName: requestedToolName,
      tool: resolvedTool,
      call: ToolCall(id: call.id, name: resolvedTool.id, arguments: args),
      argumentError: _validateToolArguments(
        tool: resolvedTool,
        requestedToolName: requestedToolName,
        args: args,
      ),
    );
  }

  JsonMap _normalizedToolArguments({
    required String requestedToolName,
    required JsonMap args,
  }) {
    final out = Map<String, dynamic>.from(args);
    if (_usesStrictFilePath(requestedToolName)) {
      return out;
    }
    if (!out.containsKey('filePath') && out.containsKey('path')) {
      out['filePath'] = out['path'];
    }
    if (!out.containsKey('path') && out.containsKey('filePath')) {
      out['path'] = out['filePath'];
    }
    return out;
  }

  bool _usesStrictFilePath(String toolName) =>
      toolName == 'edit' || toolName == 'write';

  String? _validateToolArguments({
    required ToolDefinition tool,
    required String requestedToolName,
    required JsonMap args,
  }) {
    if (args.containsKey('raw')) {
      final raw = (args['raw'] as String? ?? '').trim();
      final preview = raw.length > 200 ? '${raw.substring(0, 200)}...' : raw;
      return 'The $requestedToolName tool was called with invalid arguments: '
          'expected a valid JSON object matching the tool schema.\n'
          'Please rewrite the input so it satisfies the expected schema.\n'
          '${preview.isNotEmpty ? 'Received (truncated): $preview' : ''}';
    }
    if (_usesStrictFilePath(requestedToolName) && args.containsKey('path')) {
      return 'The $requestedToolName tool requires `filePath` as the target path.\n'
          'Do NOT send `path` for this tool.\n'
          'Rewrite the call with `filePath` and retry.';
    }
    final required =
        ((tool.parameters['required'] as List?) ?? const <dynamic>[])
            .whereType<String>();
    final missing = <String>[];
    for (final key in required) {
      final value = args[key];
      final allowsEmptyString =
          requestedToolName == 'write' && key == 'content';
      if (value == null ||
          (value is String && value.trim().isEmpty && !allowsEmptyString)) {
        missing.add(key);
      }
    }
    if (missing.isNotEmpty) {
      final props = tool.parameters['properties'] as Map? ?? const {};
      final hints = missing.map((key) {
        final prop = props[key] as Map?;
        final desc = prop?['description'] as String? ?? '';
        return desc.isNotEmpty ? '  - `$key`: $desc' : '  - `$key`';
      }).join('\n');
      return 'The $requestedToolName tool was called with missing required arguments: '
          '${missing.join(", ")}.\n'
          'Please rewrite the input with all required parameters:\n$hints';
    }
    return null;
  }

  Future<void> _updateToolState({
    required WorkspaceInfo workspace,
    required String sessionId,
    required String callId,
    required ToolStatus status,
    String? error,
    String? output,
    String? displayOutput,
    String? title,
    JsonMap? metadata,
    List<JsonMap>? attachments,
    Map<String, MessagePart>? toolPartCache,
    void Function(MessagePart part)? onPartSaved,
  }) async {
    final part = toolPartCache?[callId] ??
        (await database.listPartsForSession(sessionId)).lastWhere(
          (item) => item.type == PartType.tool && item.data['callID'] == callId,
        );
    final state =
        Map<String, dynamic>.from(part.data['state'] as Map? ?? const {});
    final time = Map<String, dynamic>.from(state['time'] as Map? ?? const {});
    state['status'] = status.name;
    if (output != null) {
      state['output'] = output;
    }
    if (displayOutput != null) {
      state['displayOutput'] = displayOutput;
    }
    if (title != null) {
      state['title'] = title;
    }
    if (metadata != null) {
      final existingMetadata =
          Map<String, dynamic>.from(state['metadata'] as Map? ?? const {});
      final mergedMetadata = <String, dynamic>{
        ...existingMetadata,
        ...metadata,
      };
      if ((status == ToolStatus.completed || status == ToolStatus.error) &&
          !metadata.containsKey('phase')) {
        mergedMetadata.remove('phase');
      }
      state['metadata'] = mergedMetadata;
    }
    if (attachments != null) {
      state['attachments'] = attachments;
    }
    if ((status == ToolStatus.completed || status == ToolStatus.error) &&
        state['metadata'] is Map) {
      final clearedMetadata =
          Map<String, dynamic>.from(state['metadata'] as Map);
      clearedMetadata.remove('phase');
      state['metadata'] = clearedMetadata;
    }
    if (error != null) {
      state['error'] = error;
    } else if (status != ToolStatus.error) {
      state.remove('error');
    }
    if (status == ToolStatus.running) {
      time['start'] ??= DateTime.now().millisecondsSinceEpoch;
    }
    if (status == ToolStatus.completed || status == ToolStatus.error) {
      time['start'] ??= DateTime.now().millisecondsSinceEpoch;
      time['end'] = DateTime.now().millisecondsSinceEpoch;
    }
    if (time.isNotEmpty) {
      state['time'] = time;
    }
    final updated = MessagePart(
      id: part.id,
      sessionId: part.sessionId,
      messageId: part.messageId,
      type: part.type,
      createdAt: part.createdAt,
      data: {...part.data, 'state': state},
    );
    await _savePart(workspace: workspace, part: updated);
    if (toolPartCache != null) {
      toolPartCache[callId] = updated;
    }
    onPartSaved?.call(updated);
  }

  Future<void> _savePart({
    required WorkspaceInfo workspace,
    required MessagePart part,
  }) async {
    await database.savePart(part);
    events.emit(ServerEvent(
      type: 'message.part.updated',
      properties: part.toJson(),
      directory: workspace.treeUri,
    ));
  }

  Future<void> _saveSession({
    required WorkspaceInfo workspace,
    required SessionInfo session,
  }) async {
    await database.saveSession(session);
    events.emit(ServerEvent(
      type: 'session.updated',
      properties: session.toJson(),
      directory: workspace.treeUri,
    ));
  }

  /// Aligned with OpenCode `SessionPrompt.ensureTitle`:
  /// Only fires for parent sessions whose title still matches the default
  /// pattern. Sends the full conversation context (up to and including the
  /// first user message) so the model can generate a meaningful short title.
  Future<void> _ensureSessionTitle({
    required WorkspaceInfo workspace,
    required String sessionId,
    required List<MessageInfo> history,
    required List<MessagePart> historyParts,
  }) async {
    try {
      final current = await database.getSession(sessionId);
      if (current == null) return;
      if (!SessionTitlePolicy.shouldAutoGenerateFromModel(current.title)) {
        return;
      }

      final firstUserIdx =
          history.indexWhere((m) => m.role == SessionRole.user);
      if (firstUserIdx == -1) return;
      final userCount = history.where((m) => m.role == SessionRole.user).length;
      if (userCount != 1) return;

      final context = history.sublist(0, firstUserIdx + 1);
      final firstUser = context[firstUserIdx];
      if (firstUser.role != SessionRole.user) return;
      if (firstUser.text.trim().isEmpty) return;

      final modelConfig = await _loadResolvedModelConfig();
      final mag = modelConfig.isMagProvider;
      final hasKey = modelConfig.apiKey.trim().isNotEmpty;
      final freeMag = mag && modelConfig.isMagZenFreeModel;
      final needsKey = mag ? (!freeMag && !hasKey) : !hasKey;
      if (needsKey) return;

      final contextMsgs = _messagesToConversation(
        messages: context,
        parts: historyParts,
        currentAgent: firstUser.agent,
      );

      final messages = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content': _titleSystemPrompt,
        },
        {
          'role': 'user',
          'content': 'Generate a title for this conversation:\n',
        },
        ...contextMsgs,
      ];
      final response = await modelGateway.complete(
        config: modelConfig,
        messages: messages,
        tools: const [],
        format: null,
        sessionId: sessionId,
        small: true,
        cancelToken: null,
      );
      final cleaned = _cleanGeneratedSessionTitle(response.text);
      if (cleaned.isEmpty) return;
      final title =
          cleaned.length > 100 ? '${cleaned.substring(0, 97)}...' : cleaned;

      final again = await database.getSession(sessionId);
      if (again == null) return;
      if (!SessionTitlePolicy.shouldAutoGenerateFromModel(again.title)) return;

      await _saveSession(
        workspace: workspace,
        session: again.copyWith(
          title: title,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      // Best-effort: failure must not interrupt the main prompt flow.
    }
  }

  String _cleanGeneratedSessionTitle(String text) {
    var t = text.trim();
    t = t.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>\s*', multiLine: true),
      '',
    );
    t = t.replaceAll(
      RegExp(
        r'<redacted_thinking>[\s\S]*?</redacted_thinking>\s*',
        multiLine: true,
      ),
      '',
    );
    for (final raw in t.split('\n')) {
      var line = raw.trim();
      if (line.isEmpty) continue;
      if (line.length >= 2 &&
          ((line.startsWith('"') && line.endsWith('"')) ||
              (line.startsWith("'") && line.endsWith("'")))) {
        line = line.substring(1, line.length - 1).trim();
      }
      if (line.isNotEmpty) return _stripMarkdown(line);
    }
    return '';
  }

  String _stripMarkdown(String line) {
    var s = line;
    // heading prefix: # / ## / ### ...
    s = s.replaceFirst(RegExp(r'^#{1,6}\s+'), '');
    // bold/italic: ***x***, **x**, *x*, ___x___, __x__, _x_
    s = s.replaceAllMapped(
      RegExp(r'(\*{1,3}|_{1,3})(.+?)\1'),
      (m) => m.group(2)!,
    );
    // inline code: `x`
    s = s.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => m.group(1)!);
    // links: [text](url)
    s = s.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1)!);
    // images: ![alt](url)
    s = s.replaceAllMapped(
        RegExp(r'!\[([^\]]*)\]\([^)]+\)'), (m) => m.group(1)!);
    // blockquote prefix
    s = s.replaceFirst(RegExp(r'^>\s+'), '');
    // strikethrough: ~~x~~
    s = s.replaceAllMapped(RegExp(r'~~(.+?)~~'), (m) => m.group(1)!);
    return s.trim();
  }

  Future<void> _saveMessage({
    required WorkspaceInfo workspace,
    required MessageInfo message,
  }) async {
    await database.saveMessage(message);
    events.emit(ServerEvent(
      type: 'message.updated',
      properties: message.toJson(),
      directory: workspace.treeUri,
    ));
  }

  void _emitPartDelta({
    required WorkspaceInfo workspace,
    required String sessionId,
    required String messageId,
    required String partId,
    required PartType partType,
    required int createdAt,
    required JsonMap delta,
  }) {
    events.emit(ServerEvent(
      type: 'message.part.delta',
      properties: {
        'sessionID': sessionId,
        'messageID': messageId,
        'partID': partId,
        'type': partType.name,
        'createdAt': createdAt,
        'delta': delta,
      },
      directory: workspace.treeUri,
    ));
  }

  String _toolErrorRecoveryHint(String toolName, String errorText) {
    final lower = errorText.toLowerCase();
    if (toolName == 'write' && lower.contains('already exists')) {
      return 'STOP using `write` for this file. The file already exists.\n'
          'Step 1: Call `read` on the file to get its current contents.\n'
          'Step 2: Use `edit` (with oldString/newString or LINE#ID edits) to make changes.\n'
          'Do NOT call `write` again on this file.';
    }
    if ((toolName == 'edit' || toolName == 'apply_patch') &&
        lower.contains('must read')) {
      return 'You have not read this file yet.\n'
          'Step 1: Call `read` on the file path mentioned in the error.\n'
          'Step 2: Then retry your `$toolName` call using the fresh content from `read`.\n'
          'Do NOT retry `$toolName` without reading first.';
    }
    if ((toolName == 'edit' || toolName == 'apply_patch') &&
        lower.contains('modified since')) {
      return 'The file has changed since you last read it (possibly by another edit).\n'
          'Step 1: Call `read` on the file to get the latest contents.\n'
          'Step 2: Rebuild your edit using the new content and line anchors.\n'
          'Do NOT reuse old content or anchors.';
    }
    if (toolName == 'edit' && lower.contains('oldstring not found')) {
      return 'The oldString you provided does not match any text in the file.\n'
          'Step 1: Call `read` on the file to see its actual current contents.\n'
          'Step 2: Copy the exact text from `read` output (without line-number prefixes) into oldString.\n'
          'Do NOT guess or slightly modify the text. It must match exactly.';
    }
    if (toolName == 'edit' &&
        lower.contains(
            'no longer accepts `oldstring` / `newstring` / `replaceall`')) {
      return 'The legacy string-based edit format is disabled.\n'
          'Step 1: Call `read` on the file.\n'
          'Step 2: Copy the exact LINE#ID anchors from the `read` output.\n'
          'Step 3: Retry `edit` with `edits` operations only.';
    }
    if ((toolName == 'edit' || toolName == 'apply_patch') &&
        lower.contains('changed since last read')) {
      return 'Your LINE#ID anchors are stale — the file content has changed.\n'
          'Step 1: Copy the updated LINE#ID anchors shown in the `>>>` error output directly.\n'
          'Step 2: If the target line you want to edit is not covered by those updated anchors, call `read` for the correct range first.\n'
          'Step 3: Retry your `$toolName` call using anchors from the newest output that actually covers the target lines.\n'
          'Do not reuse anchors from an older `read` window.';
    }
    if (toolName == 'edit' &&
        lower.contains('no changes made to') &&
        lower.contains('no-op edits')) {
      return 'Your `edit` call was a no-op — the replacement content is identical to the current file.\n'
          'Step 1: Do NOT repeat the same `edit` call.\n'
          'Step 2: If the file already matches your intent, stop editing this section.\n'
          'Step 3: If you intended a different change, call `read` and submit only lines that actually differ.\n'
          'For the same file, prefer one batched `edit` call instead of several sequential calls.';
    }
    if (lower.contains('missing required')) {
      return 'You omitted required parameters. Re-read the error message carefully, '
          'provide ALL required parameters listed above, and retry the call.';
    }
    if (lower.contains('invalid') && lower.contains('arguments')) {
      return 'Your tool arguments are malformed. Check the JSON syntax and '
          'ensure all parameter types match the schema. Then retry.';
    }
    if (lower.contains('unknown tool')) {
      return 'You called a tool that is not available.\n'
          'Re-read the advertised tool list from the system prompt and retry using an exact tool name.';
    }
    return 'Read the error message above carefully. Fix the issue it describes, '
        'then retry. Do NOT repeat the exact same call — that will produce the same error.';
  }

  void _invalidatePromptContextForToolResult({
    required WorkspaceInfo workspace,
    required String toolName,
    JsonMap? metadata,
  }) {
    final writeLikeTools = {'write', 'edit', 'apply_patch'};
    if (!writeLikeTools.contains(toolName)) return;
    final paths = <String>{};
    final singlePath =
        metadata?['filepath'] as String? ?? metadata?['path'] as String?;
    if (singlePath != null && singlePath.trim().isNotEmpty) {
      paths.add(singlePath.trim());
    }
    final files = (metadata?['files'] as List? ?? const [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty);
    paths.addAll(files);
    promptAssembler.invalidateWorkspaceContext(
      workspace.treeUri,
      paths: paths.isEmpty ? null : paths,
    );
  }
}
