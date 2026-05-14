import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/agents.dart';
import 'package:mobile_agent/core/database.dart';
import 'package:mobile_agent/core/mcp_service.dart';
import 'package:mobile_agent/core/models.dart';
import 'package:mobile_agent/core/office_renderer.dart';
import 'package:mobile_agent/core/tool_runtime.dart';
import 'package:mobile_agent/core/workspace_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OfficeRenderer', () {
    test('renders a DOCX package with escaped document content', () {
      final result = OfficeRenderer.renderDocument({
        'title': 'R&D <Plan>',
        'blocks': [
          {'type': 'heading', 'level': 1, 'text': 'Summary'},
          {'type': 'paragraph', 'text': '5 < 7 & ready'},
          {
            'type': 'list',
            'items': ['Alpha', 'Beta'],
          },
          {
            'type': 'table',
            'rows': [
              ['Metric', 'Value'],
              ['Users', '1200'],
            ],
          },
        ],
      });

      expect(result.extension, 'docx');
      expect(result.mime, contains('wordprocessingml.document'));
      final files = _decodeFiles(result.bytes);
      expect(files.keys,
          containsAll(['[Content_Types].xml', 'word/document.xml']));
      expect(files['word/document.xml'], contains('R&amp;D &lt;Plan&gt;'));
      expect(files['word/document.xml'], contains('5 &lt; 7 &amp; ready'));
      expect(files['word/document.xml'], contains('• Alpha'));
    });

    test('renders an XLSX package with workbook and formula cells', () {
      final result = OfficeRenderer.renderSpreadsheet({
        'sheets': [
          {
            'name': 'Revenue',
            'rows': [
              ['Month', 'Amount'],
              ['Jan', 10],
              ['Feb', 20],
              [
                'Total',
                {'formula': 'SUM(B2:B3)'},
              ],
            ],
          }
        ],
      });

      expect(result.extension, 'xlsx');
      expect(result.mime, contains('spreadsheetml.sheet'));
      final files = _decodeFiles(result.bytes);
      expect(
        files.keys,
        containsAll([
          '[Content_Types].xml',
          'xl/workbook.xml',
          'xl/worksheets/sheet1.xml',
          'xl/styles.xml',
        ]),
      );
      expect(files['xl/workbook.xml'], contains('Revenue'));
      expect(files['xl/worksheets/sheet1.xml'], contains('<f>SUM(B2:B3)</f>'));
    });

    test('renders a PPTX package with presentation parts', () {
      final result = OfficeRenderer.renderPresentation({
        'title': 'Quarterly Review',
        'slides': [
          {
            'layout': 'title',
            'title': 'Q1 <Review>',
            'subtitle': 'Highlights & risks',
          },
          {
            'layout': 'bullets',
            'title': 'Next steps',
            'bullets': ['Launch pilot', 'Review adoption'],
          },
        ],
      });

      expect(result.extension, 'pptx');
      expect(result.mime, contains('presentationml.presentation'));
      final files = _decodeFiles(result.bytes);
      expect(
        files.keys,
        containsAll([
          '[Content_Types].xml',
          'ppt/presentation.xml',
          'ppt/slides/slide1.xml',
          'ppt/slideMasters/slideMaster1.xml',
          'ppt/theme/theme1.xml',
        ]),
      );
      expect(files['ppt/slides/slide1.xml'], contains('Q1 &lt;Review&gt;'));
      expect(
          files['ppt/slides/slide1.xml'], contains('Highlights &amp; risks'));
    });
  });

  group('Office tools', () {
    late Directory tempDir;
    late WorkspaceInfo workspace;
    late SessionInfo session;
    late MessageInfo message;
    late List<PermissionRequest> permissions;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('office_tool_test_');
      final now = DateTime.now().millisecondsSinceEpoch;
      workspace = WorkspaceInfo(
        id: newId('ws'),
        name: 'office-tool-test',
        treeUri: tempDir.path,
        createdAt: now,
      );
      session = SessionInfo(
        id: newId('session'),
        projectId: newId('project'),
        workspaceId: workspace.id,
        title: 'Office test',
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
        text: 'create document',
      );
      permissions = [];
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('are available to the build agent', () {
      final ids = AgentRegistry.build.availableTools;
      expect(
          ids,
          containsAll([
            'create_document',
            'create_spreadsheet',
            'create_presentation'
          ]));
      final registry = ToolRegistry.builtins();
      expect(registry['create_document'], isNotNull);
      expect(registry['create_spreadsheet'], isNotNull);
      expect(registry['create_presentation'], isNotNull);
    });

    test('create_document writes a DOCX file and returns an attachment',
        () async {
      final tool = ToolRegistry.builtins()['create_document']!;

      final result = await tool.execute(
        {
          'filePath': 'outputs/report',
          'title': 'Report',
          'blocks': [
            {'type': 'paragraph', 'text': 'Generated on device.'},
          ],
        },
        _context(
          workspace: workspace,
          session: session,
          message: message,
          permissions: permissions,
        ),
      );

      final file = File('${tempDir.path}/outputs/report.docx');
      expect(await file.exists(), isTrue);
      expect(permissions, hasLength(1));
      expect(permissions.single.permission, 'write');
      expect(result.displayOutput, 'Created outputs/report.docx');
      expect(result.metadata['format'], 'docx');
      expect(result.attachments, hasLength(1));
      expect(result.attachments.single['mime'], contains('wordprocessingml'));

      final files = _decodeFiles(await file.readAsBytes());
      expect(files['word/document.xml'], contains('Generated on device.'));
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
      throw UnimplementedError('Subtasks are not used by Office tools.');
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

Map<String, String> _decodeFiles(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  return {
    for (final file in archive.files)
      if (file.isFile) file.name: utf8.decode(file.content as List<int>),
  };
}
