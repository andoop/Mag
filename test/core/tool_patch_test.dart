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
  final readTool = registry['read']!;
  final tool = registry['apply_patch']!;
  final bridge = WorkspaceBridge.instance;

  late Directory tempDir;
  late WorkspaceInfo workspace;
  late SessionInfo session;
  late MessageInfo message;
  late List<PermissionRequest> permissionRequests;

  Future<ToolExecutionResult> executePatch(String patchText) {
    return tool.execute(
      {'patchText': patchText},
      ToolRuntimeContext(
        workspace: workspace,
        session: session,
        message: message,
        agent: 'build',
        agentDefinition: AgentRegistry.build,
        bridge: bridge,
        database: AppDatabase.instance,
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
          throw UnimplementedError(
              'runSubtask should not be used in patch tests');
        },
        saveTodos: (_) async {},
      ),
    );
  }

  Future<void> seedReadLedger(String filePath) async {
    final entry = await bridge.stat(
      treeUri: workspace.treeUri,
      relativePath: filePath,
    );
    await AppDatabase.instance.savePart(
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
                'lastModified': entry?.lastModified ?? 0,
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
    supportDir = await Directory.systemTemp.createTemp('tool_patch_db_');
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
    tempDir = await Directory.systemTemp.createTemp('tool_patch_test_');
    permissionRequests = [];
    final now = DateTime.now().millisecondsSinceEpoch;
    workspace = WorkspaceInfo(
      id: newId('ws'),
      name: 'test-workspace',
      treeUri: tempDir.path,
      createdAt: now,
    );
    session = SessionInfo(
      id: newId('session'),
      projectId: newId('project'),
      workspaceId: workspace.id,
      title: 'Patch test',
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
      text: 'apply patch',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('rejects empty patch', () async {
    await expectLater(
      executePatch('*** Begin Patch\n*** End Patch'),
      throwsA(isA<Exception>()),
    );
  });

  test('supports heredoc wrapped patch text', () async {
    await executePatch("""cat <<'EOF'
*** Begin Patch
*** Add File: heredoc.txt
+hello
*** End Patch
EOF""");

    final content = await File('${tempDir.path}/heredoc.txt').readAsString();
    expect(content, 'hello\n');
    expect(permissionRequests, hasLength(1));
  });

  test('uses context header to disambiguate repeated blocks', () async {
    final target = File('${tempDir.path}/multi_ctx.txt');
    await target.writeAsString('fn a\nx=10\ny=2\nfn b\nx=10\ny=20\n');
    await seedReadLedger('multi_ctx.txt');

    await executePatch(
      '*** Begin Patch\n'
      '*** Update File: multi_ctx.txt\n'
      '@@ fn b\n'
      '-x=10\n'
      '+x=11\n'
      '*** End Patch',
    );

    expect(await target.readAsString(), 'fn a\nx=10\ny=2\nfn b\nx=11\ny=20\n');
  });

  test('matches end of file hunks from the end first', () async {
    final target = File('${tempDir.path}/eof_anchor.txt');
    await target.writeAsString('start\nmarker\nmiddle\nmarker\nend\n');
    await seedReadLedger('eof_anchor.txt');

    await executePatch(
      '*** Begin Patch\n'
      '*** Update File: eof_anchor.txt\n'
      '@@\n'
      '-marker\n'
      '-end\n'
      '+marker-changed\n'
      '+end\n'
      '*** End of File\n'
      '*** End Patch',
    );

    expect(
      await target.readAsString(),
      'start\nmarker\nmiddle\nmarker-changed\nend\n',
    );
  });

  test('matches even when patch omits surrounding whitespace differences',
      () async {
    final target = File('${tempDir.path}/whitespace.txt');
    await target.writeAsString('  line1\nline2  \n  line3\n');
    await seedReadLedger('whitespace.txt');

    await executePatch(
      '*** Begin Patch\n'
      '*** Update File: whitespace.txt\n'
      '@@\n'
      '-line2\n'
      '+changed\n'
      '*** End Patch',
    );

    expect(await target.readAsString(), '  line1\nchanged\n  line3\n');
  });

  test('supports hashline-anchored replace hunks', () async {
    final target = File('${tempDir.path}/hash_patch.txt');
    await target.writeAsString('alpha\nbeta\n');
    await seedReadLedger('hash_patch.txt');

    final readResult = await readTool.execute(
      {'path': 'hash_patch.txt'},
      ToolRuntimeContext(
        workspace: workspace,
        session: session,
        message: message,
        agent: 'build',
        agentDefinition: AgentRegistry.build,
        bridge: bridge,
        database: AppDatabase.instance,
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
          throw UnimplementedError(
              'runSubtask should not be used in patch tests');
        },
        saveTodos: (_) async {},
      ),
    );
    final anchor =
        RegExp(r'1#[A-Z]{2}').firstMatch(readResult.output)?.group(0);
    expect(anchor, isNotNull);

    await executePatch(
      '*** Begin Patch\n'
      '*** Update File: hash_patch.txt\n'
      '@@ replace $anchor\n'
      '-alpha\n'
      '+gamma\n'
      '*** End Patch',
    );

    expect(await target.readAsString(), 'gamma\nbeta\n');
  });

  test('rejects stale hashline patch anchors', () async {
    final target = File('${tempDir.path}/hash_patch_stale.txt');
    await target.writeAsString('alpha\nbeta\n');
    await seedReadLedger('hash_patch_stale.txt');

    final readResult = await readTool.execute(
      {'path': 'hash_patch_stale.txt'},
      ToolRuntimeContext(
        workspace: workspace,
        session: session,
        message: message,
        agent: 'build',
        agentDefinition: AgentRegistry.build,
        bridge: bridge,
        database: AppDatabase.instance,
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
          throw UnimplementedError(
              'runSubtask should not be used in patch tests');
        },
        saveTodos: (_) async {},
      ),
    );
    final anchor =
        RegExp(r'1#[A-Z]{2}').firstMatch(readResult.output)?.group(0);
    expect(anchor, isNotNull);

    await target.writeAsString('changed\nbeta\n');
    await seedReadLedger('hash_patch_stale.txt');

    await expectLater(
      executePatch(
        '*** Begin Patch\n'
        '*** Update File: hash_patch_stale.txt\n'
        '@@ replace $anchor\n'
        '-alpha\n'
        '+gamma\n'
        '*** End Patch',
      ),
      throwsA(
        predicate(
          (error) =>
              error.toString().contains('changed since last read') &&
              error.toString().contains('>>> 1#'),
        ),
      ),
    );
  });

  test('verifies all sections before writing files', () async {
    final existing = File('${tempDir.path}/existing.txt');
    await existing.writeAsString('old\n');

    await expectLater(
      executePatch(
        '*** Begin Patch\n'
        '*** Add File: created.txt\n'
        '+hello\n'
        '*** Update File: missing.txt\n'
        '@@\n'
        '-old\n'
        '+new\n'
        '*** End Patch',
      ),
      throwsA(isA<Exception>()),
    );

    expect(await existing.readAsString(), 'old\n');
    expect(await File('${tempDir.path}/created.txt').exists(), isFalse);
    expect(permissionRequests, isEmpty);
  });
}
