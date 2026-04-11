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
    String? sessionId,
    bool small = false,
    String? variant,
    CancelToken? cancelToken,
    FutureOr<void> Function(String delta)? onTextDelta,
    FutureOr<void> Function(String delta)? onReasoningDelta,
    FutureOr<void> Function({
      required String argumentsDelta,
      required String argumentsText,
      required String toolCallId,
      required String toolName,
    })?
        onToolCallDelta,
  }) async {
    return ModelResponse(
      text: 'summary',
      toolCalls: const [],
      finishReason: 'stop',
      raw: const {},
    );
  }
}

class _QueuedModelGateway extends ModelGateway {
  _QueuedModelGateway(this.outcomes);

  final List<Object> outcomes;
  final List<List<Map<String, dynamic>>> requests = [];
  int _index = 0;

  @override
  Future<ModelResponse> complete({
    required ModelConfig config,
    required List<Map<String, dynamic>> messages,
    required List<ToolDefinitionModel> tools,
    required MessageFormat? format,
    String? sessionId,
    bool small = false,
    String? variant,
    CancelToken? cancelToken,
    FutureOr<void> Function(String delta)? onTextDelta,
    FutureOr<void> Function(String delta)? onReasoningDelta,
    FutureOr<void> Function({
      required String argumentsDelta,
      required String argumentsText,
      required String toolCallId,
      required String toolName,
    })?
        onToolCallDelta,
  }) async {
    requests.add(
      messages
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false),
    );
    if (_index >= outcomes.length) {
      throw StateError('No queued response for call #$_index');
    }
    final next = outcomes[_index++];
    if (next is ModelResponse) return next;
    throw next;
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
      updateToolProgress: (
          {String? title,
          String? displayOutput,
          JsonMap? metadata,
          List<JsonMap>? attachments}) async {},
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
          'filePath': 'note.txt',
          'content': 'new\n',
        },
        makeContext(),
      ),
      throwsA(
        predicate(
          (error) =>
              error.toString().contains('ONLY for creating new files') &&
              error.toString().contains(
                  'call `read` on "note.txt", then use `edit` or `apply_patch`'),
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

    final response =
        buildProviderListResponse(catalog: catalog, config: config);
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

    final response =
        buildProviderListResponse(catalog: catalog, config: config);
    final provider =
        response.all.singleWhere((item) => item.id == 'alibaba-cn');
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
        'filePath': 'empty.txt',
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
          'filePath': 'edit_hint.txt',
          'edits': const [],
        },
        makeContext(),
      ),
      throwsA(
        predicate(
          (error) =>
              error.toString().contains('edits must be a non-empty array'),
        ),
      ),
    );
  });

  test('legacy edit arguments are rejected', () async {
    final target = File('${tempDir.path}/edit_exact.txt');
    await target.writeAsString('  alpha\n  beta\n');
    final initial = await bridge.stat(
      treeUri: workspace.treeUri,
      relativePath: 'edit_exact.txt',
    );
    await seedReadLedger(
      filePath: 'edit_exact.txt',
      lastModified: initial!.lastModified,
    );

    await expectLater(
      editTool.execute(
        {
          'filePath': 'edit_exact.txt',
          'oldString': 'alpha\nbeta',
          'newString': 'gamma',
        },
        makeContext(),
      ),
      throwsA(
        predicate(
          (error) => error.toString().contains(
              'no longer accepts `oldString` / `newString` / `replaceAll`'),
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
    final entry = await bridge.stat(
      treeUri: workspace.treeUri,
      relativePath: 'hashline_edit.txt',
    );
    await seedReadLedger(
      filePath: 'hashline_edit.txt',
      lastModified: entry!.lastModified,
    );

    final result = await editTool.execute(
      {
        'filePath': 'hashline_edit.txt',
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
    final entry = await bridge.stat(
      treeUri: workspace.treeUri,
      relativePath: 'hashline_stale.txt',
    );
    await seedReadLedger(
      filePath: 'hashline_stale.txt',
      lastModified: entry!.lastModified,
    );

    await target.writeAsString('changed\nbeta\n');

    await expectLater(
      editTool.execute(
        {
          'filePath': 'hashline_stale.txt',
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
          'If you just changed a file and need to modify the same file again, call `read` first.'),
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

  test('gpt-5 preview includes opencode-style default reasoning options',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'gpt-5.2',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['gpt-5.2'],
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

    expect(payload['store'], isFalse);
    expect(payload['reasoningEffort'], 'medium');
    expect(payload['reasoningSummary'], 'auto');
    expect(payload['textVerbosity'], 'low');
    expect(payload['promptCacheKey'], session.id);
  });

  test('google reasoning fallback injects thinking config', () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'google',
        currentModelId: 'gemini-3-pro',
        connections: [
          ProviderConnection(
            id: 'google',
            name: 'Google',
            baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
            apiKey: 'test-key',
            models: const ['gemini-3-pro'],
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

    expect(
      payload['thinkingConfig'],
      {
        'includeThoughts': true,
        'thinkingLevel': 'high',
      },
    );
  });

  test('preview injects confirmed session constraints into system prompt',
      () async {
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
        text: 'Do not consider data compatibility.\nUse filePath only.',
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
    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final combinedSystem = messages
        .where((item) => item['role'] == 'system')
        .map((item) => item['content'] as String? ?? '')
        .join('\n\n');

    expect(
      combinedSystem,
      contains('Confirmed constraints and decisions for this session'),
    );
    expect(combinedSystem, contains('Do not consider data compatibility'));
    expect(combinedSystem, contains('Use filePath only'));
  });

  test('fallback variants expose reasoning effort presets', () {
    final variants = resolveProviderModelVariants(
      catalog: const [],
      providerId: 'openai',
      modelId: 'gpt-5',
      capabilities: const ProviderModelCapabilities(reasoning: true),
      limit: const ProviderModelLimit(output: 32000),
    );
    expect(variants['minimal'], {'reasoningEffort': 'minimal'});
    expect(variants['high'], {'reasoningEffort': 'high'});
  });

  test('selected message variant overrides default request options', () async {
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
        currentModelVariants: const {
          'high': {'reasoningEffort': 'high'},
        },
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
        variant: 'high',
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

    expect(payload['reasoningEffort'], 'high');
  });

  test('small payload overrides gpt-5 default reasoning effort', () {
    final gateway = ModelGateway();
    final payload = gateway.buildDebugPayload(
      config: ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'gpt-5.2',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['gpt-5.2'],
          ),
        ],
        visibilityRules: const [],
      ),
      messages: const [],
      tools: const [],
      format: null,
      sessionId: 'session-small',
      small: true,
    );

    expect(payload['store'], isFalse);
    expect(payload['reasoningEffort'], 'low');
    expect(payload['promptCacheKey'], 'session-small');
    expect(payload['textVerbosity'], 'low');
  });

  test('small payload uses minimal google thinking config', () {
    final gateway = ModelGateway();
    final payload = gateway.buildDebugPayload(
      config: ModelConfig(
        currentProviderId: 'google',
        currentModelId: 'gemini-3-pro',
        connections: [
          ProviderConnection(
            id: 'google',
            name: 'Google',
            baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
            apiKey: 'test-key',
            models: const ['gemini-3-pro'],
          ),
        ],
        visibilityRules: const [],
      ),
      messages: const [],
      tools: const [],
      format: null,
      small: true,
    );

    expect(
      payload['thinkingConfig'],
      {
        'thinkingLevel': 'minimal',
      },
    );
  });

  test('tool schemas are normalized before transport encoding', () {
    final gateway = ModelGateway();
    final payload = gateway.buildDebugPayload(
      config: ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'gpt-5.2',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['gpt-5.2'],
          ),
        ],
        visibilityRules: const [],
      ),
      messages: const [],
      tools: [
        ToolDefinitionModel(
          id: 'StructuredOutput',
          description: 'Return structured JSON.',
          parameters: const {
            r'$schema': 'https://json-schema.org/draft/2020-12/schema',
            'type': 'object',
            'title': 'StructuredOutput',
            'required': <String>[],
            'properties': {
              'value': {
                'type': 'string',
                'title': 'Value',
                'default': 'ignored',
                'examples': ['x'],
              },
            },
          },
        ),
      ],
      format: null,
    );

    final tools = (payload['tools'] as List? ?? const []).cast<Map>();
    expect(tools, hasLength(1));
    final function =
        Map<String, dynamic>.from(tools.single['function'] as Map? ?? const {});
    final parameters =
        Map<String, dynamic>.from(function['parameters'] as Map? ?? const {});
    expect(parameters.containsKey(r'$schema'), isFalse);
    expect(parameters.containsKey('title'), isFalse);
    expect(parameters.containsKey('required'), isFalse);
    final properties =
        Map<String, dynamic>.from(parameters['properties'] as Map? ?? const {});
    final value =
        Map<String, dynamic>.from(properties['value'] as Map? ?? const {});
    expect(value.containsKey('title'), isFalse);
    expect(value.containsKey('default'), isFalse);
    expect(value.containsKey('examples'), isFalse);
  });

  test('litellm-style proxies receive a noop tool when history has tool calls',
      () {
    final gateway = ModelGateway();
    final payload = gateway.buildDebugPayload(
      config: ModelConfig(
        currentProviderId: 'openai_compatible',
        currentModelId: 'gpt-4.1',
        connections: [
          ProviderConnection(
            id: 'openai_compatible',
            name: 'Proxy',
            baseUrl: 'https://proxy.example.com/litellm/v1',
            apiKey: 'test-key',
            models: const ['gpt-4.1'],
          ),
        ],
        visibilityRules: const [],
      ),
      messages: const [
        {
          'role': 'assistant',
          'content': '',
          'tool_calls': [
            {
              'id': 'call_1',
              'type': 'function',
              'function': {
                'name': 'read',
                'arguments': '{"path":"lib/main.dart"}',
              },
            },
          ],
        },
        {
          'role': 'tool',
          'tool_call_id': 'call_1',
          'content': 'file contents',
        },
      ],
      tools: const [],
      format: null,
    );

    final tools = (payload['tools'] as List? ?? const []).cast<Map>();
    expect(tools, hasLength(1));
    final function =
        Map<String, dynamic>.from(tools.single['function'] as Map? ?? const {});
    expect(function['name'], '_noop');
  });

  test('anthropic preview preserves user image parts', () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'anthropic',
        currentModelId: 'claude-sonnet-4',
        connections: [
          ProviderConnection(
            id: 'anthropic',
            name: 'Anthropic',
            baseUrl: 'https://api.anthropic.com/v1',
            apiKey: 'test-key',
            models: const ['claude-sonnet-4'],
          ),
        ],
        visibilityRules: const [],
      ).toJson(),
    );
    final userMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: 'Review this image',
    );
    await database.saveMessage(userMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': 'Review this image'},
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.file,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'mime': 'image/png',
          'filename': 'diagram.png',
          'url': 'data:image/png;base64,ZmFrZQ==',
        },
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

    expect(payload['model'], 'claude-sonnet-4');
    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final userPayload = messages.lastWhere((item) => item['role'] == 'user');
    final content = (userPayload['content'] as List? ?? const []).cast<Map>();
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)?.contains('Review this image') == true,
      ),
      isTrue,
    );
    expect(
      content.any(
        (item) =>
            item['type'] == 'image' &&
            ((item['source'] as Map?)?['media_type'] as String?) == 'image/png',
      ),
      isTrue,
    );
  });

  test('model capabilities can suppress inferred temperature parameter',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'qwen3-plus',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['qwen3-plus'],
          ),
        ],
        visibilityRules: const [],
        currentModelCapabilities: const ProviderModelCapabilities(
          temperature: false,
          toolCall: true,
        ),
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

    expect(payload.containsKey('temperature'), isFalse);
    expect(payload['top_p'], 1);
  });

  test('current model request options are merged into openai payload',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'custom-reasoning-model',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['custom-reasoning-model'],
          ),
        ],
        visibilityRules: const [],
        currentModelCapabilities: const ProviderModelCapabilities(
          temperature: false,
          toolCall: true,
          reasoning: true,
        ),
        currentModelOptions: const {
          'enable_thinking': true,
          'top_p': 0.2,
        },
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

    expect(payload['enable_thinking'], isTrue);
    expect(payload['top_p'], 0.2);
    expect(payload.containsKey('temperature'), isFalse);
  });

  test('max steps reminder matches opencode constraints', () {
    final reminder = promptAssembler.maxStepsReminder();
    expect(reminder, contains('CRITICAL - MAXIMUM STEPS REACHED'));
    expect(
      reminder,
      contains(
          'Tools are disabled until next user input. Respond with text only.'),
    );
    expect(reminder, contains('Do NOT make any tool calls'));
    expect(
      reminder,
      contains('MUST provide a text response summarizing work done so far'),
    );
  });

  test('model capabilities can suppress tool payloads', () async {
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
        currentModelCapabilities: const ProviderModelCapabilities(
          temperature: true,
          toolCall: false,
        ),
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

    expect(payload.containsKey('tools'), isFalse);
    expect(payload.containsKey('tool_choice'), isFalse);
  });

  test('interleaved reasoning field is injected into assistant payload',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'custom-reasoning-model',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['custom-reasoning-model'],
          ),
        ],
        visibilityRules: const [],
        currentModelCapabilities: const ProviderModelCapabilities(
          temperature: false,
          toolCall: true,
          reasoning: true,
          interleaved: ProviderModelInterleaved(
            enabled: true,
            field: 'reasoning_content',
          ),
        ),
      ).toJson(),
    );
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
        data: {'text': 'Visible answer'},
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: assistantMessage.id,
        type: PartType.reasoning,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': 'Hidden reasoning'},
      ),
    );
    await database.saveMessage(
      MessageInfo(
        id: newId('message'),
        sessionId: session.id,
        role: SessionRole.user,
        agent: 'build',
        createdAt: DateTime.now().millisecondsSinceEpoch + 1,
        text: 'Continue',
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

    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final assistantPayload = messages.firstWhere(
      (item) => item['role'] == 'assistant',
    );
    expect(assistantPayload['content'], 'Visible answer');
    expect(assistantPayload['reasoning_content'], 'Hidden reasoning');
  });

  test('current model request options are merged into anthropic payload',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'anthropic',
        currentModelId: 'claude-sonnet-4',
        connections: [
          ProviderConnection(
            id: 'anthropic',
            name: 'Anthropic',
            baseUrl: 'https://api.anthropic.com/v1',
            apiKey: 'test-key',
            models: const ['claude-sonnet-4'],
          ),
        ],
        visibilityRules: const [],
        currentModelCapabilities: const ProviderModelCapabilities(
          temperature: false,
          toolCall: true,
          reasoning: true,
        ),
        currentModelOptions: const {
          'thinking': {
            'type': 'enabled',
            'budgetTokens': 1024,
          },
        },
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

    expect(
      payload['thinking'],
      {
        'type': 'enabled',
        'budgetTokens': 1024,
      },
    );
  });

  test('unsupported image input degrades to explicit user-facing error text',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'deepseek',
        currentModelId: 'deepseek-chat',
        connections: [
          ProviderConnection(
            id: 'deepseek',
            name: 'DeepSeek',
            baseUrl: 'https://api.deepseek.com/v1',
            apiKey: 'test-key',
            models: const ['deepseek-chat'],
          ),
        ],
        visibilityRules: const [],
      ).toJson(),
    );
    final userMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: 'Review this image',
    );
    await database.saveMessage(userMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': 'Review this image'},
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.file,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'mime': 'image/png',
          'filename': 'diagram.png',
          'url': 'data:image/png;base64,ZmFrZQ==',
        },
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

    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final userPayload = messages.lastWhere((item) => item['role'] == 'user');
    final content = (userPayload['content'] as List? ?? const []).cast<Map>();
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)?.contains(
                  'does not support image input',
                ) ==
                true,
      ),
      isTrue,
    );
    expect(
      content.any((item) => item['type'] == 'image_url'),
      isFalse,
    );
  });

  test('catalog modalities can enable image input for openai-compatible path',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'deepseek',
        currentModelId: 'deepseek-chat',
        connections: [
          ProviderConnection(
            id: 'deepseek',
            name: 'DeepSeek',
            baseUrl: 'https://api.deepseek.com/v1',
            apiKey: 'test-key',
            models: const ['deepseek-chat'],
          ),
        ],
        visibilityRules: const [],
        currentModelModalities: const ProviderModelModalities(
          input: ['text', 'image'],
          output: ['text'],
        ),
      ).toJson(),
    );
    final userMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: 'Review this image',
    );
    await database.saveMessage(userMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': 'Review this image'},
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.file,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'mime': 'image/png',
          'filename': 'diagram.png',
          'url': 'data:image/png;base64,ZmFrZQ==',
        },
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

    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final userPayload = messages.lastWhere((item) => item['role'] == 'user');
    final content = (userPayload['content'] as List? ?? const []).cast<Map>();
    expect(
      content.any((item) => item['type'] == 'image_url'),
      isTrue,
    );
  });

  test('empty image input degrades to explicit corruption error text',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'gpt-4o',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['gpt-4o'],
          ),
        ],
        visibilityRules: const [],
      ).toJson(),
    );
    final userMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: 'Review this image',
    );
    await database.saveMessage(userMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': 'Review this image'},
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.file,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'mime': 'image/png',
          'filename': 'empty.png',
          'url': 'data:image/png;base64,',
        },
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

    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final userPayload = messages.lastWhere((item) => item['role'] == 'user');
    final content = (userPayload['content'] as List? ?? const []).cast<Map>();
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)?.contains('empty or corrupted') == true,
      ),
      isTrue,
    );
    expect(
      content.any((item) => item['type'] == 'image_url'),
      isFalse,
    );
  });

  test('catalog modalities override heuristic image support', () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'gpt-4o',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['gpt-4o'],
          ),
        ],
        visibilityRules: const [],
        currentModelModalities: const ProviderModelModalities(
          input: ['text'],
          output: ['text'],
        ),
      ).toJson(),
    );
    final userMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: 'Review this image',
    );
    await database.saveMessage(userMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': 'Review this image'},
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.file,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'mime': 'image/png',
          'filename': 'diagram.png',
          'url': 'data:image/png;base64,ZmFrZQ==',
        },
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

    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final userPayload = messages.lastWhere((item) => item['role'] == 'user');
    final content = (userPayload['content'] as List? ?? const []).cast<Map>();
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)
                    ?.contains('does not support image input') ==
                true,
      ),
      isTrue,
    );
    expect(
      content.any((item) => item['type'] == 'image_url'),
      isFalse,
    );
  });

  test(
      'audio and video inputs degrade explicitly when transport path lacks support',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'gpt-4o',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['gpt-4o'],
          ),
        ],
        visibilityRules: const [],
        currentModelModalities: const ProviderModelModalities(
          input: ['text', 'audio', 'video'],
          output: ['text'],
        ),
      ).toJson(),
    );
    final userMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: 'Review these media files',
    );
    await database.saveMessage(userMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': 'Review these media files'},
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.file,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'mime': 'audio/mpeg',
          'filename': 'sample.mp3',
          'url': 'data:audio/mpeg;base64,ZmFrZQ==',
        },
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.file,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'mime': 'video/mp4',
          'filename': 'clip.mp4',
          'url': 'data:video/mp4;base64,ZmFrZQ==',
        },
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

    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final userPayload = messages.lastWhere((item) => item['role'] == 'user');
    final content = (userPayload['content'] as List? ?? const []).cast<Map>();
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)
                    ?.contains('does not support audio input') ==
                true,
      ),
      isTrue,
    );
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)
                    ?.contains('does not support video input') ==
                true,
      ),
      isTrue,
    );
  });

  test('openai-compatible preview preserves supported user image parts',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'openai',
        currentModelId: 'gpt-4o',
        connections: [
          ProviderConnection(
            id: 'openai',
            name: 'OpenAI',
            baseUrl: 'https://api.openai.com/v1',
            apiKey: 'test-key',
            models: const ['gpt-4o'],
          ),
        ],
        visibilityRules: const [],
      ).toJson(),
    );
    final userMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: 'Review this image',
    );
    await database.saveMessage(userMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': 'Review this image'},
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.file,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'mime': 'image/png',
          'filename': 'diagram.png',
          'url': 'data:image/png;base64,ZmFrZQ==',
        },
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

    expect(payload['model'], 'gpt-4o');
    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final userPayload = messages.lastWhere((item) => item['role'] == 'user');
    final content = (userPayload['content'] as List? ?? const []).cast<Map>();
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)?.contains('Review this image') == true,
      ),
      isTrue,
    );
    expect(
      content.any(
        (item) =>
            item['type'] == 'image_url' &&
            ((item['image_url'] as Map?)?['url'] as String?) ==
                'data:image/png;base64,ZmFrZQ==',
      ),
      isTrue,
    );
  });

  test('anthropic preview preserves user pdf parts', () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'anthropic',
        currentModelId: 'claude-sonnet-4',
        connections: [
          ProviderConnection(
            id: 'anthropic',
            name: 'Anthropic',
            baseUrl: 'https://api.anthropic.com/v1',
            apiKey: 'test-key',
            models: const ['claude-sonnet-4'],
          ),
        ],
        visibilityRules: const [],
      ).toJson(),
    );
    final userMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: 'Review this PDF',
    );
    await database.saveMessage(userMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': 'Review this PDF'},
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.file,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'mime': 'application/pdf',
          'filename': 'spec.pdf',
          'url': 'data:application/pdf;base64,ZmFrZQ==',
        },
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

    expect(payload['model'], 'claude-sonnet-4');
    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final userPayload = messages.lastWhere((item) => item['role'] == 'user');
    final content = (userPayload['content'] as List? ?? const []).cast<Map>();
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)?.contains('Review this PDF') == true,
      ),
      isTrue,
    );
    expect(
      content.any(
        (item) =>
            item['type'] == 'document' &&
            ((item['source'] as Map?)?['media_type'] as String?) ==
                'application/pdf',
      ),
      isTrue,
    );
  });

  test('unsupported pdf input degrades to explicit user-facing error text',
      () async {
    await database.putSetting(
      'model_config',
      ModelConfig(
        currentProviderId: 'deepseek',
        currentModelId: 'deepseek-chat',
        connections: [
          ProviderConnection(
            id: 'deepseek',
            name: 'DeepSeek',
            baseUrl: 'https://api.deepseek.com/v1',
            apiKey: 'test-key',
            models: const ['deepseek-chat'],
          ),
        ],
        visibilityRules: const [],
      ).toJson(),
    );
    final userMessage = MessageInfo(
      id: newId('message'),
      sessionId: session.id,
      role: SessionRole.user,
      agent: 'build',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      text: 'Review this PDF',
    );
    await database.saveMessage(userMessage);
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.text,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {'text': 'Review this PDF'},
      ),
    );
    await database.savePart(
      MessagePart(
        id: newId('part'),
        sessionId: session.id,
        messageId: userMessage.id,
        type: PartType.file,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        data: {
          'mime': 'application/pdf',
          'filename': 'spec.pdf',
          'url': 'data:application/pdf;base64,ZmFrZQ==',
        },
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

    final messages = (payload['messages'] as List? ?? const []).cast<Map>();
    final userPayload = messages.lastWhere((item) => item['role'] == 'user');
    final content = (userPayload['content'] as List? ?? const []).cast<Map>();
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)?.contains('does not support pdf input') ==
                true,
      ),
      isTrue,
    );
    expect(
      content.any((item) => item['type'] == 'document'),
      isFalse,
    );
  });

  test('summarize creates an opencode-style compaction boundary', () async {
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

    final compactedSession = await engine.summarize(
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

    final messages = await database.listMessages(session.id);
    final boundary = messages.firstWhere(
      (message) => message.id == compactedSession.summaryMessageId,
    );
    expect(boundary.role, SessionRole.user);

    final payload = await engine.previewModelRequest(
      workspace: workspace,
      session: compactedSession,
    );
    final requestMessages =
        (payload['messages'] as List? ?? const []).cast<Map>();
    expect(
      requestMessages.any(
        (item) =>
            (item['content'] as String?)?.contains('What did we do so far?') ==
            true,
      ),
      isTrue,
    );
    expect(
      requestMessages.any(
        (item) => (item['content'] as String?)?.contains('summary') == true,
      ),
      isTrue,
    );
  });

  test('auto compaction replays the user turn and continues', () async {
    final gateway = _QueuedModelGateway([
      ModelResponse(
        text: 'first pass',
        toolCalls: const [],
        finishReason: 'stop',
        raw: const {},
        usage: const ModelUsage(totalTokensFromApi: 120),
      ),
      ModelResponse(
        text: 'summary',
        toolCalls: const [],
        finishReason: 'stop',
        raw: const {},
        usage: const ModelUsage(totalTokensFromApi: 10),
      ),
      ModelResponse(
        text: 'second pass',
        toolCalls: const [],
        finishReason: 'stop',
        raw: const {},
        usage: const ModelUsage(totalTokensFromApi: 10),
      ),
    ]);
    final engine = SessionEngine(
      database: database,
      events: LocalEventBus(),
      workspaceBridge: bridge,
      promptAssembler: promptAssembler,
      permissionCenter: PermissionCenter(database, LocalEventBus()),
      questionCenter: QuestionCenter(database, LocalEventBus()),
      toolRegistry: registry,
      modelGateway: gateway,
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
    await database.saveMessage(
      MessageInfo(
        id: newId('message'),
        sessionId: session.id,
        role: SessionRole.user,
        agent: 'build',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        text: 'Earlier context',
      ),
    );
    await database.putSetting(
      kModelsDevCatalogCacheKey,
      {
        'all': [
          const ProviderInfo(
            id: 'openai',
            name: 'OpenAI',
            api: 'https://api.openai.com/v1',
            env: [],
            models: {
              'gpt-5': ProviderModelInfo(
                id: 'gpt-5',
                name: 'gpt-5',
                limit: ProviderModelLimit(
                  context: 100,
                  input: 100,
                  output: 20,
                ),
              ),
            },
          ).toJson(),
        ],
      },
    );
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

    final result = await engine.prompt(
      workspace: workspace,
      session: session,
      text: 'Keep fixing the issue',
      agent: 'build',
      variant: 'high',
    );

    expect(gateway.requests.length, 3);
    final replayRequest = gateway.requests.last;
    expect(
      replayRequest.any(
        (item) => (item['content'] as String?) == 'Keep fixing the issue',
      ),
      isTrue,
    );
    expect(
      replayRequest.any(
        (item) => (item['content'] as String?)?.contains('summary') == true,
      ),
      isTrue,
    );

    final messages = await database.listMessages(session.id);
    final replayUsers = messages
        .where((message) =>
            message.role == SessionRole.user &&
            message.text == 'Keep fixing the issue')
        .toList();
    expect(replayUsers.length, 2);
    expect(replayUsers.every((message) => message.variant == 'high'), isTrue);

    final parts = await database.listPartsForSession(session.id);
    for (final replayUser in replayUsers) {
      expect(
        parts.any((part) =>
            part.messageId == replayUser.id &&
            part.type == PartType.text &&
            (part.data['text'] as String?) == 'Keep fixing the issue'),
        isTrue,
      );
    }
    final resultText = parts
        .where(
            (part) => part.messageId == result.id && part.type == PartType.text)
        .map((part) => part.data['text'] as String? ?? '')
        .join('\n');
    expect(resultText, contains('second pass'));
  });

  test('context overflow error compacts and continues', () async {
    final gateway = _QueuedModelGateway([
      Exception(
        'Model request failed: 413 context_length_exceeded: maximum context length is 100 tokens',
      ),
      ModelResponse(
        text: 'summary',
        toolCalls: const [],
        finishReason: 'stop',
        raw: const {},
        usage: const ModelUsage(totalTokensFromApi: 10),
      ),
      ModelResponse(
        text: 'second pass',
        toolCalls: const [],
        finishReason: 'stop',
        raw: const {},
        usage: const ModelUsage(totalTokensFromApi: 10),
      ),
    ]);
    final engine = SessionEngine(
      database: database,
      events: LocalEventBus(),
      workspaceBridge: bridge,
      promptAssembler: promptAssembler,
      permissionCenter: PermissionCenter(database, LocalEventBus()),
      questionCenter: QuestionCenter(database, LocalEventBus()),
      toolRegistry: registry,
      modelGateway: gateway,
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
    await database.saveMessage(
      MessageInfo(
        id: newId('message'),
        sessionId: session.id,
        role: SessionRole.user,
        agent: 'build',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        text: 'Earlier context',
      ),
    );
    await database.putSetting(
      kModelsDevCatalogCacheKey,
      {
        'all': [
          const ProviderInfo(
            id: 'openai',
            name: 'OpenAI',
            api: 'https://api.openai.com/v1',
            env: [],
            models: {
              'gpt-5': ProviderModelInfo(
                id: 'gpt-5',
                name: 'gpt-5',
                limit: ProviderModelLimit(
                  context: 100,
                  input: 100,
                  output: 20,
                ),
              ),
            },
          ).toJson(),
        ],
      },
    );
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

    final result = await engine.prompt(
      workspace: workspace,
      session: session,
      text: 'Keep fixing the issue',
      agent: 'build',
      variant: 'high',
    );

    expect(gateway.requests.length, 3);
    final parts = await database.listPartsForSession(session.id);
    final firstAssistant = (await database.listMessages(session.id))
        .where((message) => message.role == SessionRole.assistant)
        .first;
    final firstFinish = parts.firstWhere(
      (part) =>
          part.messageId == firstAssistant.id &&
          part.type == PartType.stepFinish,
    );
    expect(firstFinish.data['reason'], 'length');
    final replayUsers = (await database.listMessages(session.id))
        .where((message) =>
            message.role == SessionRole.user &&
            message.text == 'Keep fixing the issue')
        .toList();
    expect(replayUsers.length, 2);
    expect(replayUsers.every((message) => message.variant == 'high'), isTrue);
    for (final replayUser in replayUsers) {
      expect(
        parts.any((part) =>
            part.messageId == replayUser.id &&
            part.type == PartType.text &&
            (part.data['text'] as String?) == 'Keep fixing the issue'),
        isTrue,
      );
    }

    final resultText = parts
        .where(
            (part) => part.messageId == result.id && part.type == PartType.text)
        .map((part) => part.data['text'] as String? ?? '')
        .join('\n');
    expect(resultText, contains('second pass'));
  });

  test('auto compaction replays user file parts', () async {
    final gateway = _QueuedModelGateway([
      ModelResponse(
        text: 'first pass',
        toolCalls: const [],
        finishReason: 'stop',
        raw: const {},
        usage: const ModelUsage(totalTokensFromApi: 120),
      ),
      ModelResponse(
        text: 'summary',
        toolCalls: const [],
        finishReason: 'stop',
        raw: const {},
        usage: const ModelUsage(totalTokensFromApi: 10),
      ),
      ModelResponse(
        text: 'second pass',
        toolCalls: const [],
        finishReason: 'stop',
        raw: const {},
        usage: const ModelUsage(totalTokensFromApi: 10),
      ),
    ]);
    final engine = SessionEngine(
      database: database,
      events: LocalEventBus(),
      workspaceBridge: bridge,
      promptAssembler: promptAssembler,
      permissionCenter: PermissionCenter(database, LocalEventBus()),
      questionCenter: QuestionCenter(database, LocalEventBus()),
      toolRegistry: registry,
      modelGateway: gateway,
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
    await database.saveMessage(
      MessageInfo(
        id: newId('message'),
        sessionId: session.id,
        role: SessionRole.user,
        agent: 'build',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        text: 'Earlier context',
      ),
    );
    await database.putSetting(
      kModelsDevCatalogCacheKey,
      {
        'all': [
          const ProviderInfo(
            id: 'openai',
            name: 'OpenAI',
            api: 'https://api.openai.com/v1',
            env: [],
            models: {
              'gpt-5': ProviderModelInfo(
                id: 'gpt-5',
                name: 'gpt-5',
                limit: ProviderModelLimit(
                  context: 100,
                  input: 100,
                  output: 20,
                ),
              ),
            },
          ).toJson(),
        ],
      },
    );
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

    await engine.prompt(
      workspace: workspace,
      session: session,
      text: 'Review this image',
      agent: 'build',
      userParts: [
        {
          'type': 'text',
          'text': 'Review this image',
        },
        {
          'type': 'file',
          'mime': 'image/png',
          'filename': 'diagram.png',
          'url': 'workspace/diagram.png',
        },
      ],
    );

    expect(gateway.requests.length, 3);
    final replayRequest = gateway.requests.last;
    final replayUser = replayRequest.lastWhere(
      (item) => item['role'] == 'user',
    );
    expect(replayUser['content'], isA<List>());
    final content = (replayUser['content'] as List)
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)?.contains('Review this image') == true,
      ),
      isTrue,
    );
    expect(
      content.any(
        (item) =>
            item['type'] == 'text' &&
            (item['text'] as String?)
                    ?.contains('[Attached image/png: diagram.png]') ==
                true,
      ),
      isTrue,
    );

    final messages = await database.listMessages(session.id);
    final users = messages
        .where((message) =>
            message.role == SessionRole.user &&
            message.text == 'Review this image')
        .toList();
    expect(users.length, 2);
    final parts = await database.listPartsForSession(session.id);
    for (final user in users) {
      expect(
        parts.any((part) =>
            part.messageId == user.id &&
            part.type == PartType.file &&
            (part.data['filename'] as String?) == 'diagram.png'),
        isTrue,
      );
    }
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

  test('unknown tool calls are converted into invalid tool results', () async {
    final gateway = _QueuedModelGateway([
      ModelResponse(
        text: '',
        toolCalls: [
          ToolCall(
            id: 'call_unknown',
            name: 'does_not_exist',
            arguments: const {},
          ),
        ],
        finishReason: 'tool_calls',
        raw: const {},
      ),
      ModelResponse(
        text: 'done',
        toolCalls: const [],
        finishReason: 'stop',
        raw: const {},
      ),
    ]);
    final engine = SessionEngine(
      database: database,
      events: LocalEventBus(),
      workspaceBridge: bridge,
      promptAssembler: promptAssembler,
      permissionCenter: PermissionCenter(database, LocalEventBus()),
      questionCenter: QuestionCenter(database, LocalEventBus()),
      toolRegistry: registry,
      modelGateway: gateway,
    );

    final result = await engine.prompt(
      workspace: workspace,
      session: session,
      text: 'Try a tool',
      agent: 'build',
    );

    final parts = await database.listPartsForSession(session.id);
    final toolPart = parts.firstWhere(
      (part) =>
          part.type == PartType.tool && part.data['callID'] == 'call_unknown',
    );
    final state =
        Map<String, dynamic>.from(toolPart.data['state'] as Map? ?? const {});
    expect(state['status'], ToolStatus.completed.name);
    expect(
      state['output'] as String? ?? '',
      contains('The does_not_exist tool call was invalid'),
    );

    final resultText = parts
        .where(
            (part) => part.messageId == result.id && part.type == PartType.text)
        .map((part) => part.data['text'] as String? ?? '')
        .join('\n');
    expect(resultText, contains('done'));
  });

  test('write rejects path alias and requires filePath', () async {
    final gateway = _QueuedModelGateway([
      ModelResponse(
        text: '',
        toolCalls: [
          ToolCall(
            id: 'call_write',
            name: 'write',
            arguments: const {
              'path': 'note.txt',
              'content': 'hello',
            },
          ),
        ],
        finishReason: 'tool_calls',
        raw: const {},
      ),
      ModelResponse(
        text: 'done',
        toolCalls: const [],
        finishReason: 'stop',
        raw: const {},
      ),
    ]);
    final engine = SessionEngine(
      database: database,
      events: LocalEventBus(),
      workspaceBridge: bridge,
      promptAssembler: promptAssembler,
      permissionCenter: PermissionCenter(database, LocalEventBus()),
      questionCenter: QuestionCenter(database, LocalEventBus()),
      toolRegistry: registry,
      modelGateway: gateway,
    );

    await engine.prompt(
      workspace: workspace,
      session: session,
      text: 'Create a file',
      agent: 'build',
    );

    final parts = await database.listPartsForSession(session.id);
    final toolPart = parts.firstWhere(
      (part) =>
          part.type == PartType.tool && part.data['callID'] == 'call_write',
    );
    final state =
        Map<String, dynamic>.from(toolPart.data['state'] as Map? ?? const {});
    expect(state['status'], ToolStatus.error.name);
    expect(
      state['output'] as String? ?? '',
      contains('The write tool requires `filePath` as the target path.'),
    );
  });
}
