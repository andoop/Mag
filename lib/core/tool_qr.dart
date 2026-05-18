part of 'tool_runtime.dart';

const String _kCreateQrCodeDescription = '''
Create a QR code SVG file in the workspace.

For detailed examples, parameter guidance, and HTML bridge usage, load the
`qr-code-generation` skill first.
''';

JsonMap qrCodeToolParametersSchema() => {
      'type': 'object',
      'properties': {
        'filePath': {
          'type': 'string',
          'description': 'Workspace-relative .svg path.',
        },
        'text': {
          'type': 'string',
          'description': 'QR payload.',
        },
        'size': {
          'type': 'integer',
          'description': 'Pixels, 96-2048.',
        },
        'margin': {
          'type': 'integer',
          'description': 'Quiet-zone modules, 0-16.',
        },
        'foregroundColor': {
          'type': 'string',
          'description': '#RGB or #RRGGBB.',
        },
        'backgroundColor': {
          'type': 'string',
          'description': '#RGB, #RRGGBB, or transparent.',
        },
        'errorCorrectionLevel': {
          'type': 'string',
          'enum': ['L', 'M', 'Q', 'H'],
          'description': 'L, M, Q, or H.',
        },
        'overwrite': {
          'type': 'boolean',
          'description': 'Replace existing file.',
        },
      },
      'required': ['filePath', 'text'],
      'additionalProperties': false,
    };

Future<ToolExecutionResult> _createQrCodeTool(
  JsonMap args,
  ToolRuntimeContext ctx,
) async {
  const toolName = 'create_qr_code';
  const requiredExtension = 'svg';
  final overwrite = args['overwrite'] == true;
  final filePath = _qrCodeOutputPath(
    _strictFilePathArg(args, toolName: toolName),
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

  final artifact = QrCodeGenerator.generate(
    QrCodeOptions.fromJson(args),
  );
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
        'mime': artifact.mimeType,
        'bytes': artifact.bytes.length,
        'moduleCount': artifact.moduleCount,
        'textBytes': artifact.textBytes,
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
    bytes: artifact.bytes,
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
      'mime': artifact.mimeType,
      'bytes': artifact.bytes.length,
      'moduleCount': artifact.moduleCount,
      'textBytes': artifact.textBytes,
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
        'mime': artifact.mimeType,
        'bytes': artifact.bytes.length,
        'format': requiredExtension,
      },
    ],
  );
}

String _qrCodeOutputPath(String filePath) {
  final extension = p.extension(filePath).toLowerCase();
  if (extension.isEmpty) {
    return '$filePath.svg';
  }
  if (extension != '.svg') {
    throw Exception('QR code output path must end with .svg: $filePath');
  }
  return filePath;
}
