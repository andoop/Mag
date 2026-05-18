import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/agents.dart';
import 'package:mobile_agent/core/database.dart';
import 'package:mobile_agent/core/mcp_service.dart';
import 'package:mobile_agent/core/models.dart';
import 'package:mobile_agent/core/qr_code_generator.dart';
import 'package:mobile_agent/core/tool_runtime.dart';
import 'package:mobile_agent/core/workspace_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QrCodeGenerator', () {
    test('generates SVG and data URL for a short payload', () {
      final artifact = QrCodeGenerator.generate(
        const QrCodeOptions(
          text: 'https://example.com',
          size: 256,
          margin: 4,
          foregroundColor: '#000000',
          backgroundColor: '#FFFFFF',
        ),
      );

      expect(artifact.mimeType, kQrCodeMimeType);
      expect(artifact.size, 256);
      expect(artifact.moduleCount, greaterThan(0));
      expect(artifact.svg, startsWith('<svg '));
      expect(artifact.svg, contains('width="256" height="256"'));
      expect(artifact.svg, contains('<path fill="#000000"'));
      expect(artifact.dataUrl, startsWith('data:image/svg+xml;base64,'));
    });

    test('rejects invalid QR inputs before rendering', () {
      expect(
        () => QrCodeGenerator.generate(const QrCodeOptions(text: '')),
        throwsArgumentError,
      );
      expect(
        () => QrCodeGenerator.generate(
          const QrCodeOptions(text: 'hello', size: 80),
        ),
        throwsArgumentError,
      );
      expect(
        () => QrCodeGenerator.generate(
          const QrCodeOptions(text: 'hello', foregroundColor: 'black'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('create_qr_code tool', () {
    late Directory tempDir;
    late WorkspaceInfo workspace;
    late SessionInfo session;
    late MessageInfo message;
    late List<PermissionRequest> permissions;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('qr_code_tool_test_');
      final now = DateTime.now().millisecondsSinceEpoch;
      workspace = WorkspaceInfo(
        id: newId('ws'),
        name: 'qr-code-tool-test',
        treeUri: tempDir.path,
        createdAt: now,
      );
      session = SessionInfo(
        id: newId('session'),
        projectId: newId('project'),
        workspaceId: workspace.id,
        title: 'QR code test',
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
        text: 'create QR code',
      );
      permissions = [];
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('is available to the build agent', () {
      expect(AgentRegistry.build.availableTools, contains('create_qr_code'));
      expect(ToolRegistry.builtins()['create_qr_code'], isNotNull);
    });

    test('writes an SVG file and returns an attachment', () async {
      final tool = ToolRegistry.builtins()['create_qr_code']!;

      final result = await tool.execute(
        {
          'filePath': 'outputs/share-qr',
          'text': 'https://example.com/share',
          'size': 192,
          'errorCorrectionLevel': 'M',
        },
        _context(
          workspace: workspace,
          session: session,
          message: message,
          permissions: permissions,
        ),
      );

      final file = File('${tempDir.path}/outputs/share-qr.svg');
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), contains('<svg '));
      expect(permissions, hasLength(1));
      expect(permissions.single.permission, 'write');
      expect(result.displayOutput, 'Created outputs/share-qr.svg');
      expect(result.metadata['format'], 'svg');
      expect(result.metadata['mime'], kQrCodeMimeType);
      expect(result.attachments, hasLength(1));
      expect(result.attachments.single['mime'], kQrCodeMimeType);
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
      throw UnimplementedError('Subtasks are not used by QR code tools.');
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
