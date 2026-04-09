import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/agents.dart';
import 'package:mobile_agent/core/database.dart';
import 'package:mobile_agent/core/models.dart';
import 'package:mobile_agent/core/tool_runtime.dart';
import 'package:mobile_agent/core/workspace_bridge.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDir;

  final registry = ToolRegistry.builtins();
  final writeTool = registry['write']!;
  final taskTool = registry['task']!;
  final bridge = WorkspaceBridge.instance;
  final database = AppDatabase.instance;

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
