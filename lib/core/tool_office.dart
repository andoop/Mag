part of 'tool_runtime.dart';

const String _kCreateDocumentDescription = '''
Create a DOCX file fully on device from structured content.

Use this when the user asks for a Word document, report, memo, proposal, or
other text-heavy Office file. Provide structured blocks only; do not provide
base64, raw XML, or binary content.

Supported block types:
- heading: { "type": "heading", "level": 1|2, "text": "..." }
- paragraph: { "type": "paragraph", "text": "..." }
- list: { "type": "list", "items": ["..."] }
- table: { "type": "table", "rows": [["Header", "Value"], ["A", "B"]] }
''';

const String _kCreateSpreadsheetDescription = '''
Create an XLSX file fully on device from structured sheets and rows.

Use this when the user asks for an Excel workbook, table, plan, tracker, or
spreadsheet. Provide structured sheets/rows only; do not provide base64, raw XML,
or binary content. The first row is styled as a header row.
''';

const String _kCreatePresentationDescription = '''
Create a PPTX file fully on device from structured slides.

Use this when the user asks for a PowerPoint deck, slides, pitch deck, or
presentation. Use simple fixed-layout slides. Provide structured slide content
only; do not provide base64, raw XML, or binary content.
''';

JsonMap officeDocumentToolParametersSchema() => {
      'type': 'object',
      'properties': {
        'filePath': {
          'type': 'string',
          'description':
              'REQUIRED. Workspace-relative destination path. Use .docx.',
        },
        'title': {
          'type': 'string',
          'description': 'Document title.',
        },
        'blocks': {
          'type': 'array',
          'description': 'Ordered document blocks.',
          'items': {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'enum': ['heading', 'paragraph', 'list', 'table'],
              },
              'level': {'type': 'integer'},
              'text': {'type': 'string'},
              'items': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'rows': {
                'type': 'array',
                'items': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
              },
            },
            'additionalProperties': false,
          },
        },
        'overwrite': {
          'type': 'boolean',
          'description': 'Optional. Set true to replace an existing file.',
        },
      },
      'required': ['filePath', 'title', 'blocks'],
      'additionalProperties': false,
    };

JsonMap officeSpreadsheetToolParametersSchema() => {
      'type': 'object',
      'properties': {
        'filePath': {
          'type': 'string',
          'description':
              'REQUIRED. Workspace-relative destination path. Use .xlsx.',
        },
        'sheets': {
          'type': 'array',
          'description': 'Workbook sheets. At least one sheet is required.',
          'items': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string'},
              'rows': {
                'type': 'array',
                'items': {
                  'type': 'array',
                  'items': {},
                },
              },
            },
            'required': ['name', 'rows'],
            'additionalProperties': false,
          },
        },
        'overwrite': {
          'type': 'boolean',
          'description': 'Optional. Set true to replace an existing file.',
        },
      },
      'required': ['filePath', 'sheets'],
      'additionalProperties': false,
    };

JsonMap officePresentationToolParametersSchema() => {
      'type': 'object',
      'properties': {
        'filePath': {
          'type': 'string',
          'description':
              'REQUIRED. Workspace-relative destination path. Use .pptx.',
        },
        'title': {
          'type': 'string',
          'description': 'Presentation title.',
        },
        'slides': {
          'type': 'array',
          'description': 'Fixed-layout slides. At least one slide is required.',
          'items': {
            'type': 'object',
            'properties': {
              'layout': {
                'type': 'string',
                'enum': ['title', 'bullets', 'table'],
              },
              'title': {'type': 'string'},
              'subtitle': {'type': 'string'},
              'bullets': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'table': {
                'type': 'array',
                'items': {
                  'type': 'array',
                  'items': {'type': 'string'},
                },
              },
            },
            'additionalProperties': false,
          },
        },
        'overwrite': {
          'type': 'boolean',
          'description': 'Optional. Set true to replace an existing file.',
        },
      },
      'required': ['filePath', 'title', 'slides'],
      'additionalProperties': false,
    };

Future<ToolExecutionResult> _createDocumentTool(
  JsonMap args,
  ToolRuntimeContext ctx,
) async {
  return _createOfficeFile(
    args: args,
    ctx: ctx,
    toolName: 'create_document',
    requiredExtension: 'docx',
    render: OfficeRenderer.renderDocument,
  );
}

Future<ToolExecutionResult> _createSpreadsheetTool(
  JsonMap args,
  ToolRuntimeContext ctx,
) async {
  return _createOfficeFile(
    args: args,
    ctx: ctx,
    toolName: 'create_spreadsheet',
    requiredExtension: 'xlsx',
    render: OfficeRenderer.renderSpreadsheet,
  );
}

Future<ToolExecutionResult> _createPresentationTool(
  JsonMap args,
  ToolRuntimeContext ctx,
) async {
  return _createOfficeFile(
    args: args,
    ctx: ctx,
    toolName: 'create_presentation',
    requiredExtension: 'pptx',
    render: OfficeRenderer.renderPresentation,
  );
}

Future<ToolExecutionResult> _createOfficeFile({
  required JsonMap args,
  required ToolRuntimeContext ctx,
  required String toolName,
  required String requiredExtension,
  required OfficeRenderResult Function(JsonMap args) render,
}) async {
  final overwrite = args['overwrite'] == true;
  final filePath = _officeOutputPath(
    _strictFilePathArg(args, toolName: toolName),
    requiredExtension,
  );
  final existing = await ctx.bridge.getEntry(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  if (existing != null && existing.isDirectory) {
    throw Exception('Destination path is a directory: $filePath');
  }
  if (existing != null && !overwrite) {
    throw Exception(
      'Destination already exists: $filePath\n'
      'If you intentionally want to replace it, call `$toolName` again with '
      '`overwrite: true`.',
    );
  }

  await ctx.updateToolProgress(
    title: filePath,
    displayOutput: 'Rendering $filePath on device',
    metadata: {
      'phase': 'rendering',
      'path': filePath,
      'filePath': filePath,
      'format': requiredExtension,
      'overwrite': overwrite,
    },
  );

  final result = render(args);
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'write',
      patterns: [filePath],
      metadata: {
        'tool': toolName,
        'path': filePath,
        'filePath': filePath,
        'format': requiredExtension,
        'bytes': result.bytes.length,
        'overwrite': overwrite,
      },
      always: [filePath],
      messageId: ctx.message.id,
      callId: ctx.callId ?? newId('call'),
    ),
  );

  await ctx.bridge.writeBytes(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
    bytes: result.bytes,
  );
  final entry = await ctx.bridge.stat(
    treeUri: ctx.workspace.treeUri,
    relativePath: filePath,
  );
  return ToolExecutionResult(
    title: filePath,
    output: 'Created $filePath on device.',
    displayOutput: 'Created $filePath',
    metadata: {
      'path': filePath,
      'filePath': filePath,
      'format': requiredExtension,
      'mime': result.mime,
      'bytes': result.bytes.length,
      'itemCount': result.itemCount,
      'overwrite': overwrite,
      if (entry != null)
        'readLedger': _toolReadLedgerMetadata(
          path: filePath,
          lastModified: entry.lastModified,
          sourceTool: toolName,
        ),
    },
    attachments: [
      {
        'type': 'file',
        'url': filePath,
        'path': filePath,
        'filename': p.basename(filePath),
        'mime': result.mime,
        'bytes': result.bytes.length,
        'format': requiredExtension,
      },
    ],
  );
}

String _officeOutputPath(String filePath, String requiredExtension) {
  final extension = p.extension(filePath).toLowerCase();
  if (extension.isEmpty) {
    return '$filePath.$requiredExtension';
  }
  if (extension != '.$requiredExtension') {
    throw Exception(
      'Office output path must end with .$requiredExtension: $filePath',
    );
  }
  return filePath;
}
