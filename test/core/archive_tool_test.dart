import 'dart:io';

import 'package:archive/archive.dart' as archive_pkg;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/agents.dart';
import 'package:mobile_agent/core/database.dart';
import 'package:mobile_agent/core/mcp_service.dart';
import 'package:mobile_agent/core/models.dart';
import 'package:mobile_agent/core/tool_runtime.dart';
import 'package:mobile_agent/core/workspace_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('archive tools', () {
    late Directory tempDir;
    late WorkspaceInfo workspace;
    late SessionInfo session;
    late MessageInfo message;
    late List<PermissionRequest> permissions;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('archive_tool_test_');
      final now = DateTime.now().millisecondsSinceEpoch;
      workspace = WorkspaceInfo(
        id: newId('ws'),
        name: 'archive-tool-test',
        treeUri: tempDir.path,
        createdAt: now,
      );
      session = SessionInfo(
        id: newId('session'),
        projectId: newId('project'),
        workspaceId: workspace.id,
        title: 'Archive test',
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
        text: 'zip files',
      );
      permissions = [];
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('are available to the build agent', () {
      final registry = ToolRegistry.builtins();

      expect(AgentRegistry.build.availableTools, contains('zip'));
      expect(AgentRegistry.build.availableTools, contains('unzip'));
      expect(registry['zip'], isNotNull);
      expect(registry['unzip'], isNotNull);
    });

    test('zips a directory and unzips it into another directory', () async {
      await File('${tempDir.path}/src/a.txt').create(recursive: true);
      await File('${tempDir.path}/src/a.txt').writeAsString('alpha');
      await File('${tempDir.path}/src/nested/b.txt').create(recursive: true);
      await File('${tempDir.path}/src/nested/b.txt').writeAsString('beta');

      final registry = ToolRegistry.builtins();
      final zipResult = await registry['zip']!.execute(
        {
          'sourcePath': 'src',
          'filePath': 'out/archive',
        },
        _context(
          workspace: workspace,
          session: session,
          message: message,
          permissions: permissions,
        ),
      );

      final archiveFile = File('${tempDir.path}/out/archive.zip');
      expect(await archiveFile.exists(), isTrue);
      expect(zipResult.displayOutput, 'Created out/archive.zip');
      expect(zipResult.metadata['files'], 2);
      expect(permissions.single.permission, 'write');

      await registry['unzip']!.execute(
        {
          'filePath': 'out/archive.zip',
          'destinationPath': 'unzipped',
        },
        _context(
          workspace: workspace,
          session: session,
          message: message,
          permissions: permissions,
        ),
      );

      expect(
        await File('${tempDir.path}/unzipped/src/a.txt').readAsString(),
        'alpha',
      );
      expect(
        await File('${tempDir.path}/unzipped/src/nested/b.txt').readAsString(),
        'beta',
      );
      expect(permissions, hasLength(2));
      expect(permissions.last.permission, 'write');
    });

    test('unzip rejects existing files unless overwrite is true', () async {
      final archive = archive_pkg.Archive()
        ..addFile(archive_pkg.ArchiveFile('a.txt', 5, 'hello'));
      final encoded = archive_pkg.ZipEncoder().encode(archive)!;
      await File('${tempDir.path}/archive.zip').writeAsBytes(encoded);
      await File('${tempDir.path}/dest/a.txt').create(recursive: true);
      await File('${tempDir.path}/dest/a.txt').writeAsString('old');

      final unzip = ToolRegistry.builtins()['unzip']!;

      await expectLater(
        unzip.execute(
          {
            'filePath': 'archive.zip',
            'destinationPath': 'dest',
          },
          _context(
            workspace: workspace,
            session: session,
            message: message,
            permissions: permissions,
          ),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Destination already exists: dest/a.txt'),
          ),
        ),
      );

      await unzip.execute(
        {
          'filePath': 'archive.zip',
          'destinationPath': 'dest',
          'overwrite': true,
        },
        _context(
          workspace: workspace,
          session: session,
          message: message,
          permissions: permissions,
        ),
      );

      expect(await File('${tempDir.path}/dest/a.txt').readAsString(), 'hello');
    });

    test('unzip blocks entries that escape the workspace', () async {
      final archive = archive_pkg.Archive()
        ..addFile(archive_pkg.ArchiveFile('../escape.txt', 4, 'nope'));
      final encoded = archive_pkg.ZipEncoder().encode(archive)!;
      await File('${tempDir.path}/bad.zip').writeAsBytes(encoded);

      await expectLater(
        ToolRegistry.builtins()['unzip']!.execute(
          {
            'filePath': 'bad.zip',
            'destinationPath': 'dest',
          },
          _context(
            workspace: workspace,
            session: session,
            message: message,
            permissions: permissions,
          ),
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Path escapes workspace root'),
          ),
        ),
      );
    });
  });
}

ToolRuntimeContext _context({
  required WorkspaceInfo workspace,
  required SessionInfo session,
  required MessageInfo message,
  required List<PermissionRequest> permissions,
}) {
  return ToolRuntimeContext(
    workspace: workspace,
    session: session,
    message: message,
    agent: 'build',
    agentDefinition: AgentRegistry.build,
    bridge: WorkspaceBridge.instance,
    database: AppDatabase.instance,
    mcpService: McpService(database: AppDatabase.instance, emitEvent: (_) {}),
    askPermission: (request) async {
      permissions.add(request);
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
      throw UnimplementedError('Subtasks are not used by archive tools.');
    },
    saveTodos: (_) async {},
    updateToolProgress: ({
      String? title,
      String? displayOutput,
      JsonMap? metadata,
      List<JsonMap>? attachments,
    }) async {},
  );
}
