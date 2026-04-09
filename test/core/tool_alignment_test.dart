import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/agents.dart';
import 'package:mobile_agent/core/database.dart';
import 'package:mobile_agent/core/models.dart';
import 'package:mobile_agent/core/prompt_system.dart';
import 'package:mobile_agent/core/session_engine.dart';
import 'package:mobile_agent/core/tool_runtime.dart';
import 'package:mobile_agent/core/workspace_bridge.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeModelGateway extends ModelGateway {
  @override
  Future<ModelResponse> complete({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
    CancelToken? cancelToken,
    FutureOr<void> Function(String delta)? onTextDelta,
    FutureOr<void> Function(String delta)? onReasoningDelta,
  }) async {
    return ModelResponse(
      text: 'summary',
      toolCalls: const [],
      finishReason: 'stop',
      raw: const {},
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDir;

  final registry = ToolRegistry.builtins();
  final readTool = registry['read']!;
  final writeTool = registry['write']!;
  final editTool = registry['edit']!;
  final taskTool = registry['task']!;
  final bridge = WorkspaceBridge.instance;
  final database = AppDatabase.instance;
  final promptAssembler = PromptAssembler(bridge);

  late Directory tempDir;
  late WorkspaceInfo workspace;
  late SessionInfo session;
  late MessageInfo message;
  late List<PermissionRequest> permissionRequests;

  ToolRuntimeContext makeContext({
    Future<ToolExecutionResult> Function({
      required SessionInfo session,
      required String description,
      required String prompt,
      required String subagentType,
      String? taskId,
    })?
        runSubtask,
  }) {
    return ToolRuntimeContext(
      workspace: workspace,
      session: session,
      message: message,
      agent: 'build',
      agentDefinition: AgentRegistry.build,
      bridge: bridge,
      database: database,
      askPermission: (request) async {
        permissionRequests.add(request);
      },
      askQuestion: (_) async => const [],
      resolveInstructionReminder: (_) async => '',
      runSubtask: runSubtask ??
          ({
            required SessionInfo session,
            required String description,
            required String prompt,
            required String subagentType,
            String? taskId,
          }) async {
            throw UnimplementedError('runSubtask should not be used here');
          },
      saveTodos: (_) async {},
    );
  }

  Future<void> seedReadLedger({
    required String filePath,
    required int lastModified,
  }) async {
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: message.id,
        type: PartType.tool,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'tool': 'read',
          'callID': newId('call'),
          'state': {
            'status': ToolStatus.completed.name,
            'metadata': {
              'readLedger': {
                'path': filePath,
                'lastModified': lastModified,
              },
            },
          },
        },
      ),
    );
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    supportDir = await Directory.systemTemp.createTemp('tool_alignment_db_');
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return supportDir.path;
      }
      return null;
    });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance!.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await supportDir.exists()) {
      await supportDir.delete(recursive: true);
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tool_alignment_test_');
    permissionRequests = [];
    final now = DateTime.now().millisecondsSinceEpoch;
    workspace = WorkspaceInfo(
      id: newId('ws'),
      name: 'tool-alignment',
      treeUri: tempDir.path,
      createdAt: now,
    );
    session = SessionInfo(
      id: newId('session'),
      projectId: newId('project'),
      workspaceId: workspace.id,
      title: 'Alignment test',
      agent: 'build',
      createdAt: now,
      updatedAt: now,
    );
    message = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: now,
      text: 'test',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('write requires prior read for existing files', () async {
    final target = File('${tempDir.path}/note.txt');
    await target.writeAsString('old\n');

    await expectLater(
      writeTool.execute(
        {
          'path': 'note.txt',
          'content': 'new\n',
        },
        makeContext(),
      ),
      throwsA(
        predicate(
          (error) =>
              error.toString().contains('you must read the file note.txt'),
        ),
      ),
    );
    expect(permissionRequests, isEmpty);
  });

  test('read returns hashline-tagged text lines', () async {
    final target = File('${tempDir.path}/hashline_read.txt');
    await target.writeAsString('alpha\nbeta\n');

    final result = await readTool.execute(
      {
        'path': 'hashline_read.txt',
      },
      makeContext(),
    );

    expect(result.output, contains(RegExp(r'1#[A-Z]{2}\|alpha')));
    expect(result.output, contains(RegExp(r'2#[A-Z]{2}\|beta')));
  });

  test('write rejects stale read ledger', () async {
    final target = File('${tempDir.path}/stale.txt');
    await target.writeAsString('old\n');
    final initial = await bridge.stat(
      treeUri: workspace.treeUri,
      relativePath: 'stale.txt',
    );
    await seedReadLedger(
      filePath: 'stale.txt',
      lastModified: initial!.lastModified,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await target.writeAsString('changed externally\n');

    await expectLater(
      writeTool.execute(
        {
          'path': 'stale.txt',
          'content': 'agent write\n',
        },
        makeContext(),
      ),
      throwsA(
        predicate(
          (error) => error
              .toString()
              .contains('has been modified since it was last read'),
        ),
      ),
    );
    expect(permissionRequests, isEmpty);
  });

  test('write succeeds with fresh read ledger and records a new ledger',
      () async {
    final target = File('${tempDir.path}/fresh.txt');
    await target.writeAsString('old\n');
    final initial = await bridge.stat(
      treeUri: workspace.treeUri,
      relativePath: 'fresh.txt',
    );
    await seedReadLedger(
      filePath: 'fresh.txt',
      lastModified: initial!.lastModified,
    );

    final result = await writeTool.execute(
      {
        'path': 'fresh.txt',
        'content': 'new\n',
      },
      makeContext(),
    );

    expect(await target.readAsString(), 'new\n');
    expect(permissionRequests, hasLength(1));
    expect(result.metadata['exists'], isTrue);
    final readLedger =
        Map<String, dynamic>.from(result.metadata['readLedger'] as Map);
    expect(readLedger['path'], 'fresh.txt');
    expect((readLedger['lastModified'] as num).toInt(), greaterThan(0));
  });

  test('write accepts contentRef from the same assistant message', () async {
    final assistantMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.assistant,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: '',
    );
    await database.saveMessage(assistantMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: assistantMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'rawText':
              '<write_content id="note-body">\nhello from ref\n</write_content>',
          'text': '[write_content:note-body omitted]',
        },
      ),
    );

    final result = await writeTool.execute(
      {
        'path': 'note.txt',
        'contentRef': 'note-body',
      },
      ToolRuntimeContext(
        workspace: workspace,
        session: session,
        message: assistantMessage,
        agent: 'build',
        agentDefinition: AgentRegistry.build,
        bridge: bridge,
        database: database,
        askPermission: (request) async {
          permissionRequests.add(request);
        },
        askQuestion: (_) async => const [],
        resolveInstructionReminder: (_) async => '',
        runSubtask: ({
          required SessionInfo session,
          required String description,
          required String prompt,
          required String subagentType,
          String? taskId,
        }) async {
          throw UnimplementedError('runSubtask should not be used here');
        },
        saveTodos: (_) async {},
      ),
    );

    expect(await File('${tempDir.path}/note.txt').readAsString(),
        'hello from ref');
    expect(permissionRequests, hasLength(1));
    expect(result.displayOutput, 'Wrote note.txt');
  });

  test('edit failure tells the model to re-read after prior edits', () async {
    final target = File('${tempDir.path}/edit_hint.txt');
    await target.writeAsString('alpha\nbeta\n');
    final initial = await bridge.stat(
      treeUri: workspace.treeUri,
      relativePath: 'edit_hint.txt',
    );
    await seedReadLedger(
      filePath: 'edit_hint.txt',
      lastModified: initial!.lastModified,
    );

    await expectLater(
      editTool.execute(
        {
          'path': 'edit_hint.txt',
          'oldString': 'missing',
          'newString': 'gamma',
        },
        makeContext(),
      ),
      throwsA(
        predicate(
          (error) =>
              error
                  .toString()
                  .contains('call `read` on the file again first') &&
              error
                  .toString()
                  .contains('without the `read` line-number prefixes'),
        ),
      ),
    );
  });

  test('hashline edit updates file content using read anchors', () async {
    final target = File('${tempDir.path}/hashline_edit.txt');
    await target.writeAsString('alpha\nbeta\n');

    final readResult = await readTool.execute(
      {
        'path': 'hashline_edit.txt',
      },
      makeContext(),
    );
    final anchor =
        RegExp(r'1#[A-Z]{2}').firstMatch(readResult.output)?.group(0);
    expect(anchor, isNotNull);

    final result = await editTool.execute(
      {
        'path': 'hashline_edit.txt',
        'edits': [
          {
            'op': 'replace',
            'pos': anchor,
            'lines': ['gamma'],
          }
        ],
      },
      makeContext(),
    );

    expect(await target.readAsString(), 'gamma\nbeta\n');
    expect(result.displayOutput, 'Updated hashline_edit.txt');
    expect(permissionRequests, hasLength(1));
  });

  test('hashline edit rejects stale anchors with updated references', () async {
    final target = File('${tempDir.path}/hashline_stale.txt');
    await target.writeAsString('alpha\nbeta\n');

    final readResult = await readTool.execute(
      {
        'path': 'hashline_stale.txt',
      },
      makeContext(),
    );
    final anchor =
        RegExp(r'1#[A-Z]{2}').firstMatch(readResult.output)?.group(0);
    expect(anchor, isNotNull);

    await target.writeAsString('changed\nbeta\n');

    await expectLater(
      editTool.execute(
        {
          'path': 'hashline_stale.txt',
          'edits': [
            {
              'op': 'replace',
              'pos': anchor,
              'lines': ['gamma'],
            }
          ],
        },
        makeContext(),
      ),
      throwsA(
        predicate(
          (error) =>
              error.toString().contains('changed since last read') &&
              error.toString().contains('>>> 1#'),
        ),
      ),
    );
    expect(permissionRequests, isEmpty);
  });

  test(
      'tool routing prefers apply_patch for gpt models and edit/write otherwise',
      () {
    final gptTools = registry.availableForAgent(
      AgentRegistry.build,
      modelId: 'gpt-5',
    );
    final gptIds = gptTools.map((item) => item.id).toSet();
    expect(gptIds.contains('apply_patch'), isTrue);
    expect(gptIds.contains('write'), isFalse);
    expect(gptIds.contains('edit'), isFalse);

    final claudeTools = registry.availableForAgent(
      AgentRegistry.build,
      modelId: 'claude-sonnet-4',
    );
    final claudeIds = claudeTools.map((item) => item.id).toSet();
    expect(claudeIds.contains('apply_patch'), isFalse);
    expect(claudeIds.contains('write'), isTrue);
    expect(claudeIds.contains('edit'), isTrue);
  });

  test('system prompt lists the model-filtered tool set', () async {
    final prompts = await promptAssembler.buildSystemPrompts(
      PromptContext(
        workspace: workspace,
        agent: 'build',
        agentDefinition: AgentRegistry.build,
        model: 'gpt-5',
        effectiveTools: registry
            .availableForAgent(
              AgentRegistry.build,
              modelId: 'gpt-5',
            )
            .map((item) => item.id)
            .toList(),
        hasSkillTool: true,
        currentStep: 1,
        maxSteps: 5,
        format: null,
      ),
    );

    final envPrompt = prompts.map((item) => item['content'] ?? '').firstWhere(
        (content) =>
            content.contains('Available tools:') || content.contains('可用工具:'));
    final toolsLine = envPrompt.split('\n').firstWhere(
        (line) => line.contains('Available tools:') || line.contains('可用工具:'));
    final advertisedTools = toolsLine
        .split(':')
        .last
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    expect(advertisedTools.contains('apply_patch'), isTrue);
    expect(advertisedTools.contains('write'), isFalse);
    expect(advertisedTools.contains('edit'), isFalse);
    expect(
      envPrompt.contains(
          'If you just changed a file and need to modify the same file again, read it again first.'),
      isTrue,
    );
    expect(envPrompt.contains('@@ replace 12#VK'), isTrue);
  });

  test('engine preview returns the provider request payload', () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'gpt-5',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['gpt-5'],
          ),
        ],
        visibilityRules: const [],
      ).toJson(),
    );
    await database.saveMessage(
      MessageInfo(
        id: newId('message'),
        sessionId: session.id,
        role: SessionRole.user,
        agent: 'build',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        text: 'Preview the current payload',
      ),
    );
    final engine = SessionEngine(
      database: database,
      events: LocalEventBus(),
      workspaceBridge: bridge,
      promptAssembler: promptAssembler,
      permissionCenter: PermissionCenter(database, LocalEventBus()),
      questionCenter: QuestionCenter(database, LocalEventBus()),
      toolRegistry: registry,
      modelGateway: ModelGateway(),
    );

    final payload = await engine.previewModelRequest(
      workspace: workspace,
      session: session,
    );

    expect(payload['model'], 'gpt-5');
    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    expect(
      messages.any((item) =>
          (item['content'] as String?)
              ?.contains('Preview the current payload') ==
          true),
      isTrue,
    );
    final tools = (payload['tools'] as List? ?? const []).cast<Map>();
    final toolNames = tools
        .map((item) => Map<String, dynamic>.from(item)['function'])
        .whereType<Map>()
        .map((fn) => Map<String, dynamic>.from(fn)['name'] as String? ?? '')
        .toSet();
    expect(toolNames.contains('apply_patch'), isTrue);
    expect(toolNames.contains('write'), isFalse);
  });

  test('compacted tool output keeps display summary and metadata', () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'gpt-5',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['gpt-5'],
          ),
        ],
        visibilityRules: const [],
      ).toJson(),
    );
    final eventBus = LocalEventBus();
    final engine = SessionEngine(
      database: database,
      events: eventBus,
      workspaceBridge: bridge,
      promptAssembler: promptAssembler,
      permissionCenter: PermissionCenter(database, eventBus),
      questionCenter: QuestionCenter(database, eventBus),
      toolRegistry: registry,
      modelGateway: _FakeModelGateway(),
    );
    final project = await engine.ensureProject(workspace);
    session = SessionInfo(
      id: session.id,
      projectId: project.id,
      workspaceId: workspace.id,
      title: session.title,
      agent: 'build',
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
    );
    await database.saveSession(session);
    final userMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: 'Summarize this long session',
    );
    await database.saveMessage(userMessage);
    final assistantMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.assistant,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: '',
      model: 'gpt-5',
      provider: 'openai',
    );
    await database.saveMessage(assistantMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: assistantMessage.id,
        type: PartType.tool,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'tool': 'git',
          'callID': newId('call'),
          'state': {
            'status': ToolStatus.completed.name,
            'input': {'command': 'status'},
            'output': 'x' * 300000,
            'displayOutput': '7187 staged, 299 unstaged, 297 untracked',
            'metadata': {
              'branch': 'main',
              'clean': false,
              'staged': 7187,
              'unstaged': 299,
              'untracked': 297,
            },
          },
        },
      ),
    );

    await engine.summarize(
      workspace: workspace,
      session: session,
      modelConfig: ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'gpt-5',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['gpt-5'],
          ),
        ],
        visibilityRules: const [],
      ),
      currentAgent: 'build',
    );

    final parts = await database.listPartsForSession(session.id);
    final compactedToolPart = parts.firstWhere(
      (part) => part.type == PartType.tool && part.data['tool'] == 'git',
    );
    final state =
        Map<String, dynamic>.from(compactedToolPart.data['state'] as Map);
    final compacted = state['output'] as String;
    expect(compacted, contains('[output compacted]'));
    expect(compacted, contains('7187 staged, 299 unstaged, 297 untracked'));
    expect(compacted, contains('"branch":"main"'));
    expect(compacted, contains('"staged":7187'));
  });

  test('task tool forwards task_id for resumable subtasks', () async {
    String? capturedTaskId;
    final result = await taskTool.execute(
      {
        'description': 'Inspect repo',
        'prompt': 'Look around',
        'subagent_type': 'explore',
        'task_id': 'session-123',
      },
      makeContext(
        runSubtask: ({
          required SessionInfo session,
          required String description,
          required String prompt,
          required String subagentType,
          String? taskId,
        }) async {
          capturedTaskId = taskId;
          return ToolExecutionResult(
            title: description,
            output:
                'task_id: ${taskId ?? "none"}\n\n<task_result>ok</task_result>',
            metadata: {'taskSessionId': taskId ?? 'none'},
          );
        },
      ),
    );

    expect(capturedTaskId, 'session-123');
    expect(result.output, contains('task_id: session-123'));
  });
}
