import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/agents.dart';
import 'package:mobile_agent/core/database.dart';
import 'package:mobile_agent/core/mcp_service.dart';
import 'package:mobile_agent/core/models.dart';
import 'package:mobile_agent/core/prompt_system.dart';
import 'package:mobile_agent/core/session_engine.dart';
import 'package:mobile_agent/core/tool_runtime.dart';
import 'package:mobile_agent/core/workspace_bridge.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _StubMcpResponseData {
  const _StubMcpResponseData({
    required this.statusCode,
    required this.body,
    required this.contentType,
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final String contentType;
  final Map<String, String> headers;
}

class _FakeMcpHttpClient implements HttpClient {
  _FakeMcpHttpClient(this._resolver);

  final _StubMcpResponseData Function({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) _resolver;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return _FakeMcpHttpClientRequest(url, _resolver);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMcpHttpClientRequest implements HttpClientRequest {
  _FakeMcpHttpClientRequest(this._uri, this._resolver);

  final Uri _uri;
  final _StubMcpResponseData Function({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) _resolver;
  final _FakeMcpHttpHeaders _headers = _FakeMcpHttpHeaders();
  final StringBuffer _buffer = StringBuffer();

  @override
  HttpHeaders get headers => _headers;

  @override
  void write(Object? obj) {
    if (obj != null) _buffer.write(obj);
  }

  @override
  Future<HttpClientResponse> close() async {
    final response = _resolver(
      uri: _uri,
      headers: _headers.values,
      body: _buffer.toString(),
    );
    return _FakeMcpHttpClientResponse(response);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMcpHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeMcpHttpClientResponse(this._response);

  final _StubMcpResponseData _response;

  @override
  int get statusCode => _response.statusCode;

  @override
  HttpHeaders get headers => _FakeMcpHttpHeaders.fromResponse(_response);

  @override
  String get reasonPhrase => '';

  @override
  int get contentLength => utf8.encode(_response.body).length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([utf8.encode(_response.body)]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMcpHttpHeaders implements HttpHeaders {
  _FakeMcpHttpHeaders();

  factory _FakeMcpHttpHeaders.fromResponse(_StubMcpResponseData response) {
    final headers = _FakeMcpHttpHeaders();
    headers.contentType = ContentType.parse(response.contentType);
    response.headers.forEach(headers.set);
    return headers;
  }

  final Map<String, String> values = {};
  ContentType? _contentType;

  @override
  ContentType? get contentType => _contentType;

  @override
  set contentType(ContentType? value) {
    _contentType = value;
    if (value != null) {
      values[HttpHeaders.contentTypeHeader.toLowerCase()] = value.toString();
    }
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
    if (name.toLowerCase() == HttpHeaders.contentTypeHeader) {
      _contentType = ContentType.parse(value.toString());
    }
  }

  @override
  String? value(String name) => values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel =
      MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDir;
  late McpService service;
  late List<ServerEvent> emittedEvents;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    supportDir = await Directory.systemTemp.createTemp('mcp_service_db_');
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
    emittedEvents = [];
    debugSetMcpHttpClientFactoryForTests(() {
      return _FakeMcpHttpClient(({
        required Uri uri,
        required Map<String, String> headers,
        required String body,
      }) {
        final payload = body.trim().isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(body) as Map);
        final method = payload['method'] as String?;
        final id = payload['id'];
        final serverMode = uri.host;
        Map<String, dynamic> jsonResponse(Map<String, dynamic> result) => {
              'jsonrpc': '2.0',
              'id': id,
              'result': result,
            };
        Map<String, dynamic> jsonError(int code, String message) => {
              'jsonrpc': '2.0',
              'id': id,
              'error': {
                'code': code,
                'message': message,
              },
            };
        if (method == 'initialize') {
          return _StubMcpResponseData(
            statusCode: 200,
            contentType: 'application/json',
            headers: const {'mcp-session-id': 'session-demo'},
            body: jsonEncode(jsonResponse({
              'protocolVersion': '2025-11-25',
              'capabilities': {
                'tools': {},
                if (serverMode != 'mcp-no-resources.example.test') 'resources': {},
                'prompts': {},
              },
              'serverInfo': {
                'name': 'demo-mcp',
                'version': '1.0.0',
              },
            })),
          );
        }
        if (method == 'notifications/initialized') {
          return const _StubMcpResponseData(
            statusCode: 202,
            contentType: 'application/json',
            body: '',
          );
        }
        if (method == 'tools/list') {
          return _StubMcpResponseData(
            statusCode: 200,
            contentType: 'text/event-stream',
            body: 'data: ${jsonEncode(jsonResponse({
                  'tools': [
                    {
                      'name': 'echo',
                      'description': 'Echo text',
                      'inputSchema': {
                        'type': 'object',
                        'properties': {
                          'text': {'type': 'string'}
                        },
                        'required': ['text']
                      }
                    }
                  ]
                }))}\n\n',
          );
        }
        if (method == 'resources/list') {
          if (serverMode == 'mcp-no-resources.example.test') {
            return _StubMcpResponseData(
              statusCode: 200,
              contentType: 'application/json',
              body: jsonEncode(jsonError(-32601, 'Method not found')),
            );
          }
          return _StubMcpResponseData(
            statusCode: 200,
            contentType: 'application/json',
            body: jsonEncode(jsonResponse({
              'resources': [
                {
                  'uri': 'demo://readme',
                  'name': 'README',
                  'description': 'Demo resource',
                  'mimeType': 'text/plain',
                }
              ]
            })),
          );
        }
        if (method == 'prompts/list') {
          return _StubMcpResponseData(
            statusCode: 200,
            contentType: 'text/event-stream',
            body: 'data: ${jsonEncode(jsonResponse({
                  'prompts': [
                    {
                      'name': 'summarize',
                      'description': 'Summarize input',
                      'arguments': [
                        {'name': 'topic', 'required': true}
                      ]
                    }
                  ]
                }))}\n\n',
          );
        }
        if (method == 'tools/call') {
          final params = Map<String, dynamic>.from(payload['params'] as Map);
          return _StubMcpResponseData(
            statusCode: 200,
            contentType: 'application/json',
            body: jsonEncode(jsonResponse({
              'content': [
                {'type': 'text', 'text': 'echo:${params['arguments']['text']}'}
              ],
              'structuredContent': {'ok': true},
              'isError': false,
            })),
          );
        }
        if (method == 'resources/read') {
          return _StubMcpResponseData(
            statusCode: 200,
            contentType: 'application/json',
            body: jsonEncode(jsonResponse({
              'contents': [
                {
                  'uri': 'demo://readme',
                  'mimeType': 'text/plain',
                  'text': 'hello resource',
                }
              ]
            })),
          );
        }
        if (method == 'prompts/get') {
          final params = Map<String, dynamic>.from(payload['params'] as Map);
          return _StubMcpResponseData(
            statusCode: 200,
            contentType: 'application/json',
            body: jsonEncode(jsonResponse({
              'messages': [
                {
                  'role': 'user',
                  'content': {
                    'type': 'text',
                    'text': 'topic=${params['arguments']['topic']}',
                  }
                }
              ]
            })),
          );
        }
        return const _StubMcpResponseData(
          statusCode: 500,
          contentType: 'application/json',
          body: '{"error":"unhandled"}',
        );
      });
    });
    service = McpService(
      database: AppDatabase.instance,
      emitEvent: emittedEvents.add,
    );
  });

  tearDown(() async {
    debugResetMcpHttpClientFactoryForTests();
  });

  test('refreshes catalog from JSON and SSE MCP responses', () async {
    const config = McpServerConfig(
      id: 'demo',
      name: 'Demo',
      url: 'https://mcp.example.test/mcp',
    );

    await service.saveServer(config);
    final status = await service.refreshServer('demo');
    final tools = await service.listTools('demo');
    final resources = await service.listResources('demo');
    final prompts = await service.listPrompts('demo');

    expect(status.connected, isTrue);
    expect(status.toolCount, 1);
    expect(status.resourceCount, 1);
    expect(status.promptCount, 1);
    expect(tools.single.name, 'echo');
    expect(resources.single.uri, 'demo://readme');
    expect(prompts.single.name, 'summarize');
    expect(
      emittedEvents.any((event) => event.type == 'mcp.catalog.changed'),
      isTrue,
    );
  });

  test('refresh tolerates unsupported resources/list and keeps prompts', () async {
    const config = McpServerConfig(
      id: 'demo-no-resources',
      name: 'Demo no resources',
      url: 'https://mcp-no-resources.example.test/mcp',
    );

    await service.saveServer(config);
    final status = await service.refreshServer('demo-no-resources');
    final tools = await service.listTools('demo-no-resources');
    final resources = await service.listResources('demo-no-resources');
    final prompts = await service.listPrompts('demo-no-resources');

    expect(status.connected, isTrue);
    expect(status.error, isNull);
    expect(status.toolCount, 1);
    expect(status.resourceCount, 0);
    expect(status.promptCount, 1);
    expect(tools.single.name, 'echo');
    expect(resources, isEmpty);
    expect(prompts.single.name, 'summarize');
  });

  test('tools-only refresh then extended catalog fills resources and prompts', () async {
    const config = McpServerConfig(
      id: 'demo-tools-only',
      name: 'Demo tools-only',
      url: 'https://mcp.example.test/mcp',
    );
    await service.saveServer(config);
    final s1 = await service.refreshServerToolsOnly('demo-tools-only');
    expect(s1.connected, isTrue);
    expect(s1.toolCount, 1);
    expect(s1.resourceCount, 0);
    expect(s1.promptCount, 0);

    final resources = await service.listResources('demo-tools-only');
    final prompts = await service.listPrompts('demo-tools-only');
    expect(resources.single.uri, 'demo://readme');
    expect(prompts.single.name, 'summarize');

    final statuses = await service.listStatuses();
    expect(statuses['demo-tools-only']?.resourceCount, 1);
    expect(statuses['demo-tools-only']?.promptCount, 1);
  });

  test('calls MCP tools and reads resources/prompts', () async {
    const config = McpServerConfig(
      id: 'demo2',
      name: 'Demo 2',
      url: 'https://mcp.example.test/mcp',
    );
    await service.saveServer(config);
    await service.refreshServer('demo2');

    final toolResult = await service.callTool('demo2', 'echo', {'text': 'hi'});
    final resource = await service.readResource('demo2', 'demo://readme');
    final prompt = await service.getPrompt(
      'demo2',
      'summarize',
      arguments: {'topic': 'mcp'},
    );

    expect(toolResult.isError, isFalse);
    expect(toolResult.content.single['text'], 'echo:hi');
    expect(resource.single.text, 'hello resource');
    expect(prompt.single.content['text'], 'topic=mcp');
  });

  test('session engine exposes builtin and dynamic MCP tools', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final tempDir = await Directory.systemTemp.createTemp('mcp_engine_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final workspace = WorkspaceInfo(
      id: newId('ws'),
      name: 'mcp-workspace',
      treeUri: tempDir.path,
      createdAt: now,
    );
    const config = McpServerConfig(
      id: 'demo3',
      name: 'Demo 3',
      url: 'https://mcp.example.test/mcp',
    );
    await service.saveServer(config);
    await service.refreshServer('demo3');

    final engine = SessionEngine(
      database: AppDatabase.instance,
      events: LocalEventBus(),
      workspaceBridge: WorkspaceBridge.instance,
      promptAssembler: PromptAssembler(WorkspaceBridge.instance),
      permissionCenter: PermissionCenter(AppDatabase.instance, LocalEventBus()),
      questionCenter: QuestionCenter(AppDatabase.instance, LocalEventBus()),
      toolRegistry: ToolRegistry.builtins(),
      modelGateway: ModelGateway(),
      mcpService: service,
    );

    final tools = await engine.availableToolModels(workspace, AgentRegistry.build);
    final ids = tools.map((item) => item.id).toSet();

    expect(ids.contains('mcp.demo3.echo'), isTrue);
    expect(ids.contains('list_mcp_resources'), isTrue);
    expect(ids.contains('read_mcp_resource'), isTrue);
    expect(ids.contains('list_mcp_prompts'), isTrue);
    expect(ids.contains('get_mcp_prompt'), isTrue);
  });
}
