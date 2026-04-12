part of 'tool_runtime.dart';

Future<ToolExecutionResult> _todoTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final raw = (args['todos'] as List?) ?? const [];
  final items = <TodoItem>[];
  var index = 0;
  for (final entry in raw.whereType<Map>()) {
    final m = Map<String, dynamic>.from(entry);
    final content = jsonStringCoerce(m['content'], '').trim();
    final status = jsonStringCoerce(m['status'], '').trim();
    if (content.isEmpty || status.isEmpty) {
      continue;
    }
    final idRaw = jsonStringCoerce(m['id'], '').trim();
    final priorityRaw = jsonStringCoerce(m['priority'], 'medium').trim();
    items.add(
      TodoItem(
        id: idRaw.isEmpty ? newId('todo') : idRaw,
        sessionId: ctx.session.id,
        content: content,
        status: status,
        priority: priorityRaw.isEmpty ? 'medium' : priorityRaw,
        position: index,
      ),
    );
    index++;
  }
  await ctx.saveTodos(items);
  final openCodeShape = items
      .map(
        (e) => <String, dynamic>{
          'content': e.content,
          'status': e.status,
          'priority': e.priority,
        },
      )
      .toList();
  await ctx.updateToolProgress(
    title: '${items.length} todo${items.length == 1 ? '' : 's'}',
    metadata: {'phase': 'processing', 'todos': openCodeShape},
  );
  final remaining = items.where((t) => t.status != 'completed').length;
  return ToolExecutionResult(
    title: '$remaining todos',
    output: const JsonEncoder.withIndent('  ').convert(openCodeShape),
    metadata: {
      'todos': openCodeShape,
    },
  );
}

Future<ToolExecutionResult> _questionTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final rawQuestions = (args['questions'] as List?) ?? const [];
  final parsed = rawQuestions
      .whereType<Map>()
      .map((item) => QuestionInfo.fromJson(Map<String, dynamic>.from(item)))
      .toList();
  if (parsed.isEmpty) {
    return ToolExecutionResult(
      title: 'Question',
      output:
          'Invalid arguments: questions must be a non-empty array of objects with question, header, and options.',
      metadata: const {},
    );
  }
  final request = QuestionRequest(
    id: newId('question'),
    sessionId: ctx.session.id,
    questions: parsed,
    messageId: ctx.message.id,
    callId: ctx.callId,
  );
  await ctx.updateToolProgress(
    title: parsed.length == 1
        ? 'Asking 1 question'
        : 'Asking ${parsed.length} questions',
    metadata: {
      'phase': 'awaiting_input',
      'questionCount': parsed.length,
    },
  );
  final answersRaw = await ctx.askQuestion(request);
  final n = parsed.length;
  final answers = <List<String>>[];
  for (var i = 0; i < n; i++) {
    if (i < answersRaw.length) {
      answers.add(List<String>.from(answersRaw[i]));
    } else {
      answers.add(<String>[]);
    }
  }

  String formatAnswer(List<String> answer) {
    if (answer.isEmpty) return 'Unanswered';
    return answer.join(', ');
  }

  final formatted = List.generate(
    n,
    (i) => '"${parsed[i].question}"="${formatAnswer(answers[i])}"',
  ).join(', ');
  final title = n == 1 ? 'Asked 1 question' : 'Asked $n questions';
  final output =
      'User has answered your questions: $formatted. You can now continue with the user\'s answers in mind.';

  return ToolExecutionResult(
    title: title,
    output: output,
    metadata: {'answers': answers},
  );
}

Future<ToolExecutionResult> _webFetchTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final url = Uri.parse(args['url'] as String? ?? '');
  await ctx.updateToolProgress(
    title: url.host.isEmpty ? 'WebFetch' : url.host,
    displayOutput: 'Fetching ${url.toString()}',
    metadata: {'phase': 'fetching', 'url': url.toString()},
  );
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'webfetch',
      patterns: [url.host],
      metadata: {'tool': 'webfetch', 'url': url.toString()},
      always: [url.host],
      messageId: ctx.message.id,
      callId: newId('call'),
    ),
  );
  final client = _toolHttpClientFactory();
  final request = await client.getUrl(url);
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  final contentType = response.headers.contentType?.mimeType ?? 'text/plain';
  client.close(force: true);
  return ToolExecutionResult(
    title: 'WebFetch',
    output: text,
    displayOutput:
        'Fetched ${url.toString()} · ${response.statusCode} · $contentType',
    metadata: {'statusCode': response.statusCode, 'contentType': contentType},
    attachments: [
      {
        'type': 'webpage',
        'url': url.toString(),
        'statusCode': response.statusCode,
        'mime': contentType,
        'title': _extractHtmlTitle(text) ?? url.host,
        'excerpt': _plainTextPreview(text, maxLength: 600),
      },
    ],
  );
}

const int _kDownloadMaxBytes = 25 * 1024 * 1024;

Future<ToolExecutionResult> _downloadTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final rawUrl = (args['url'] as String? ?? '').trim();
  final filePath = _strictFilePathArg(args, toolName: 'download');
  final overwrite = args['overwrite'] == true;
  final uri = Uri.tryParse(rawUrl);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.trim().isEmpty) {
    throw Exception(
      'The download tool only accepts public http/https URLs. '
      'Provide a full URL like `https://example.com/file.txt`.',
    );
  }

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
      'If you intentionally want to replace it, call `download` again with `overwrite: true`.',
    );
  }

  String? previousText;
  if (existing != null && !_looksBinaryEntry(existing)) {
    try {
      previousText = await ctx.bridge.readText(
        treeUri: ctx.workspace.treeUri,
        relativePath: filePath,
      );
    } catch (_) {}
  }

  await ctx.updateToolProgress(
    title: filePath,
    displayOutput: 'Downloading ${uri.toString()}',
    metadata: {
      'phase': 'fetching',
      'url': uri.toString(),
      'path': filePath,
      'filePath': filePath,
      'overwrite': overwrite,
    },
  );
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'download',
      patterns: [uri.host],
      metadata: {
        'tool': 'download',
        'url': uri.toString(),
        'path': filePath,
        'filePath': filePath,
        'overwrite': overwrite,
      },
      always: [uri.host],
      messageId: ctx.message.id,
      callId: ctx.callId ?? newId('call'),
    ),
  );

  final client = _toolHttpClientFactory();
  try {
    client.userAgent = 'mobile_agent';
    final request = await client.getUrl(uri);
    final response = await request.close();
    final statusCode = response.statusCode;
    if (statusCode < 200 || statusCode >= 300) {
      throw Exception(
        'Download failed with HTTP $statusCode for ${uri.toString()}.',
      );
    }
    final contentLength = response.contentLength;
    if (contentLength > _kDownloadMaxBytes) {
      throw Exception(
        'Download exceeds the ${_kDownloadMaxBytes ~/ (1024 * 1024)} MB limit.',
      );
    }
    final bytes = await _readResponseBytes(response, _kDownloadMaxBytes);
    final contentType =
        response.headers.contentType?.mimeType ?? _downloadMimeFromPath(filePath);
    await ctx.bridge.writeBytes(
      treeUri: ctx.workspace.treeUri,
      relativePath: filePath,
      bytes: bytes,
    );
    final updatedEntry = await ctx.bridge.stat(
      treeUri: ctx.workspace.treeUri,
      relativePath: filePath,
    );
    final isText = _looksTextDownload(
      contentType: contentType,
      filePath: filePath,
      bytes: bytes,
    );
    final attachments = <JsonMap>[];
    if (isText) {
      final text = utf8.decode(bytes, allowMalformed: true);
      if (previousText != null) {
        attachments.add(
          _buildDiffAttachment(
            kind: 'download_update',
            path: filePath,
            before: previousText,
            after: text,
          ),
        );
      }
      attachments.add(
        _buildDownloadedTextPreviewAttachment(
          filePath: filePath,
          content: text,
        ),
      );
    } else {
      attachments.add(
        {
          'type': 'file',
          'url': filePath,
          'filename': p.basename(filePath),
          'mime': contentType,
        },
      );
    }
    return ToolExecutionResult(
      title: filePath,
      output: 'Downloaded ${uri.toString()} to $filePath.',
      displayOutput: 'Downloaded ${uri.host} -> $filePath',
      metadata: {
        'url': uri.toString(),
        'path': filePath,
        'filepath': filePath,
        'contentType': contentType,
        'bytes': bytes.length,
        'statusCode': statusCode,
        'overwrite': overwrite,
        if (updatedEntry != null)
          'readLedger': _toolReadLedgerMetadata(
            path: filePath,
            lastModified: updatedEntry.lastModified,
            sourceTool: 'download',
          ),
      },
      attachments: attachments,
    );
  } finally {
    client.close(force: true);
  }
}

Future<Uint8List> _readResponseBytes(
  HttpClientResponse response,
  int maxBytes,
) async {
  final builder = BytesBuilder(copy: false);
  var total = 0;
  await for (final chunk in response) {
    total += chunk.length;
    if (total > maxBytes) {
      throw Exception(
        'Download exceeds the ${maxBytes ~/ (1024 * 1024)} MB limit.',
      );
    }
    builder.add(chunk);
  }
  return builder.takeBytes();
}

bool _looksTextDownload({
  required String contentType,
  required String filePath,
  required Uint8List bytes,
}) {
  final mime = contentType.toLowerCase();
  if (mime.startsWith('text/')) return true;
  if (mime.contains('json') ||
      mime.contains('xml') ||
      mime.contains('yaml') ||
      mime.contains('javascript') ||
      mime.contains('html')) {
    return true;
  }
  final lower = filePath.toLowerCase();
  for (final ext in const [
    '.txt',
    '.md',
    '.markdown',
    '.json',
    '.yaml',
    '.yml',
    '.xml',
    '.html',
    '.htm',
    '.css',
    '.js',
    '.ts',
    '.tsx',
    '.jsx',
    '.dart',
    '.kt',
    '.java',
    '.properties',
    '.gradle',
    '.sh',
    '.py',
  ]) {
    if (lower.endsWith(ext)) return true;
  }
  final probe = bytes.length > 256 ? bytes.sublist(0, 256) : bytes;
  return !probe.any((b) => b == 0);
}

String _downloadMimeFromPath(String filePath) {
  final lower = filePath.toLowerCase();
  if (lower.endsWith('.txt')) return 'text/plain';
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) return 'text/markdown';
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.yaml') || lower.endsWith('.yml')) return 'application/yaml';
  if (lower.endsWith('.xml')) return 'application/xml';
  if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'application/octet-stream';
}

JsonMap _buildDownloadedTextPreviewAttachment({
  required String filePath,
  required String content,
}) {
  final lines = const LineSplitter().convert(content);
  final endLine = lines.isEmpty ? 1 : lines.length.clamp(1, 40);
  final preview = lines.take(endLine).join('\n');
  return {
    'type': 'text_preview',
    'path': filePath,
    'filename': p.basename(filePath),
    'mime': 'text/plain',
    'preview': preview,
    'startLine': 1,
    'endLine': endLine,
    'lineCount': lines.length,
  };
}

Future<ToolExecutionResult> _browserTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final requestedPath =
      _normalizeWorkspaceRelativePath(args['path'] as String? ?? '');
  if (requestedPath.isEmpty) {
    throw Exception('Missing workspace page path');
  }
  await ctx.updateToolProgress(
    title: requestedPath,
    metadata: {'phase': 'opening', 'path': requestedPath},
  );
  final resolvedPath = await _resolveBrowserPath(requestedPath, ctx);
  return ToolExecutionResult(
    title: 'Browser',
    output: 'Opened workspace page at $resolvedPath',
    displayOutput: 'Opened workspace page $resolvedPath',
    metadata: {
      'path': resolvedPath,
      'kind': 'workspace_page',
    },
    attachments: [
      {
        'type': 'browser_page',
        'path': resolvedPath,
        'filename': resolvedPath.split('/').last,
        'title': resolvedPath.split('/').last,
      },
    ],
  );
}

Future<ToolExecutionResult> _skillTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final name = (args['name'] as String? ?? '').trim();
  if (name.isEmpty) {
    throw Exception('Skill name is required.');
  }
  final registry = SkillRegistry.instance;
  final skills = await registry.available(
    ctx.workspace,
    agentDefinition: ctx.agentDefinition,
  );
  final skill = await registry.get(
    ctx.workspace,
    name,
    agentDefinition: ctx.agentDefinition,
  );
  if (skill == null) {
    final available = skills.map((item) => item.name).join(', ');
    throw Exception(
      available.isEmpty
          ? 'Unknown skill: $name. No skills are currently available.'
          : 'Unknown skill: $name. Available skills: $available',
    );
  }
  await ctx.askPermission(
    PermissionRequest(
      id: newId('perm'),
      sessionId: ctx.session.id,
      permission: 'skill',
      patterns: [skill.name],
      metadata: {
        'tool': 'skill',
        'name': skill.name,
        'location': skill.location,
      },
      always: [skill.name],
      messageId: ctx.message.id,
      callId: ctx.callId ?? newId('call'),
    ),
  );
  final files = await registry.sampleFiles(ctx.workspace, skill);
  final buffer = StringBuffer()
    ..writeln('<skill_content name="${skill.name}">')
    ..writeln('# Skill: ${skill.name}')
    ..writeln()
    ..writeln(skill.content)
    ..writeln()
    ..writeln('Base directory for this skill: ${skill.directory}')
    ..writeln(
        'Relative paths in this skill (e.g., scripts/, reference/) are relative to this base directory.')
    ..writeln('Note: file list is sampled.')
    ..writeln()
    ..writeln('<skill_files>');
  for (final file in files) {
    buffer.writeln('<file>$file</file>');
  }
  buffer
    ..writeln('</skill_files>')
    ..writeln('</skill_content>');
  return ToolExecutionResult(
    title: 'Loaded skill: ${skill.name}',
    output: buffer.toString().trim(),
    metadata: {
      'name': skill.name,
      'dir': skill.directoryPath,
      'location': skill.location,
      'files': files,
    },
    displayOutput: 'Loaded skill ${skill.name}',
  );
}

Future<ToolExecutionResult> _invalidTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final tool = args['tool'] as String? ?? 'unknown';
  final error = args['error'] as String? ?? 'invalid input';
  return ToolExecutionResult(
    title: 'Invalid',
    output: 'The $tool tool call was invalid: $error',
  );
}

Future<ToolExecutionResult> _planExitTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final answers = await ctx.askQuestion(
    QuestionRequest(
      id: newId('question'),
      sessionId: ctx.session.id,
      questions: [
        QuestionInfo(
          question: 'Leave plan mode and switch to build mode?',
          header: 'Plan Exit',
          options: [
            QuestionOption(
                label: 'Switch', description: 'Switch to build mode'),
            QuestionOption(label: 'Stay', description: 'Keep planning'),
          ],
        ),
      ],
      messageId: ctx.message.id,
      callId: ctx.callId,
    ),
  );
  final accepted = answers.isNotEmpty && answers.first.contains('Switch');
  if (!accepted) {
    throw Exception('User stayed in plan mode');
  }
  return ToolExecutionResult(
    title: 'Plan Exit',
    output: 'Switching to build mode.',
    metadata: {'switchAgent': 'build'},
  );
}

Future<ToolExecutionResult> _taskTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  return ctx.runSubtask(
    session: ctx.session,
    description: args['description'] as String? ?? '',
    prompt: args['prompt'] as String? ?? '',
    subagentType: args['subagent_type'] as String? ?? 'general',
    taskId: args['task_id'] as String?,
  );
}
