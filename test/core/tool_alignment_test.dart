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

  test('write rejects existing files and asks for edit tool', () async {
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
              error
                  .toString()
                  .contains('Use `edit` or `apply_patch` instead of `write`'),
        ),
      ),
    );
    expect(permissionRequests, isEmpty);
  });

  test('provider list keeps catalog models for connected providers', () {
    final catalog = [
      ProviderInfo(
        id: 'openai',
        name: 'OpenAI',
        api: 'https://api.openai.com/v1',
        env: const [],
        models: {
          'gpt-4.1': const ProviderModelInfo(
            id: 'gpt-4.1',
            name: 'GPT-4.1',
            limit: ProviderModelLimit(context: 1047576, output: 32768),
          ),
          'gpt-4.1-mini': const ProviderModelInfo(
            id: 'gpt-4.1-mini',
            name: 'GPT-4.1 Mini',
            limit: ProviderModelLimit(context: 1047576, output: 32768),
          ),
        },
      ),
    ];
    final config = ModelConfig(
      currentProviderId: 'openai',
      currentModelId: 'gpt-4.1-mini',
      connections: [
        ProviderConnection(
          id: 'openai',
          name: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-test',
          models: const ['gpt-4.1-mini'],
        ),
      ],
      visibilityRules: const [],
    );

    final response = buildProviderListResponse(catalog: catalog, config: config);
    final provider = response.all.singleWhere((item) => item.id == 'openai');

    expect(provider.connected, isTrue);
    expect(provider.models.keys, containsAll(['gpt-4.1', 'gpt-4.1-mini']));
    expect(response.connected, ['openai']);
  });

  test('provider list does not alias alibaba-cn to qwen catalog', () {
    final catalog = [
      ProviderInfo(
        id: 'qwen',
        name: 'Qwen',
        api: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        env: const [],
        models: {
          'qwen3-plus': const ProviderModelInfo(
            id: 'qwen3-plus',
            name: 'Qwen3 Plus',
            limit: ProviderModelLimit(context: 1000000, output: 65536),
          ),
        },
      ),
    ];
    final config = ModelConfig(
      currentProviderId: 'alibaba-cn',
      currentModelId: 'qwen3-plus',
      connections: [
        ProviderConnection(
          id: 'alibaba-cn',
          name: 'Alibaba',
          baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
          apiKey: 'sk-test',
          models: const ['qwen3-plus'],
        ),
      ],
      visibilityRules: const [],
    );

    final response = buildProviderListResponse(catalog: catalog, config: config);
    final provider = response.all.singleWhere((item) => item.id == 'alibaba-cn');
    final match = resolveCatalogModelMatch(
      catalog: catalog,
      providerId: 'alibaba-cn',
      modelId: 'qwen3-plus',
    );

    expect(match.source, 'fallback');
    expect(provider.models['qwen3-plus']?.limit.context,
        inferContextWindow('qwen3-plus'));
    expect(provider.models['qwen3-plus']?.limit.output,
        inferMaxOutputTokens('qwen3-plus'));
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

  test('write accepts empty content for new files', () async {
    final result = await writeTool.execute(
      {
        'path': 'empty.txt',
        'content': '',
      },
      makeContext(),
    );

    expect(await File('${tempDir.path}/empty.txt').readAsString(), '');
    expect(permissionRequests, hasLength(1));
    expect(result.displayOutput, 'Wrote empty.txt');
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
