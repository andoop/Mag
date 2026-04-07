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
      .map((item) =>
          QuestionInfo.fromJson(Map<String, dynamic>.from(item)))
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
  final client = HttpClient();
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

Future<ToolExecutionResult> _browserTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final requestedPath = _normalizeWorkspaceRelativePath(args['path'] as String? ?? '');
  if (requestedPath.isEmpty) {
    throw Exception('Missing workspace page path');
  }
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

Future<ToolExecutionResult> _filerefTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final raw = (args['refs'] as List?) ?? const [];
  final out = <JsonMap>[];
  final warnings = <String>[];
  for (final e in raw.whereType<Map>()) {
    final m = Map<String, dynamic>.from(e);
    String path;
    try {
      path = _normalizeWorkspaceRelativePath(jsonStringCoerce(m['path'], ''));
    } catch (e) {
      warnings.add('Invalid path ${m['path']}: $e');
      continue;
    }
    var kind = jsonStringCoerce(m['kind'], 'modified').trim().toLowerCase();
    if (path.isEmpty) {
      warnings.add('Skipped empty path');
      continue;
    }
    if (kind != 'created' && kind != 'modified') {
      kind = 'modified';
    }
    final entry = await ctx.bridge.stat(
      treeUri: ctx.workspace.treeUri,
      relativePath: path,
    );
    if (entry == null) {
      warnings.add('Not found in workspace: $path');
    }
    out.add({
      'path': path,
      'kind': kind,
      'exists': entry != null,
    });
  }
  if (out.isEmpty) {
    return ToolExecutionResult(
      title: 'fileref',
      output:
          'No valid refs. Provide refs: [{path, kind}] with workspace-relative paths (. and ./ allowed; .. cannot escape root).',
      metadata: {'refs': <JsonMap>[]},
    );
  }
  final pretty = const JsonEncoder.withIndent('  ').convert(out);
  final warnBlock =
      warnings.isEmpty ? '' : '\n\nWarnings:\n${warnings.join('\n')}';
  return ToolExecutionResult(
    title: '${out.length} file ref${out.length == 1 ? '' : 's'}',
    output:
        'Registered file references for the conversation UI.$warnBlock\n\n$pretty',
    metadata: {'refs': out},
  );
}

Future<ToolExecutionResult> _skillTool(
    JsonMap args, ToolRuntimeContext ctx) async {
  final name = (args['name'] as String? ?? '').trim();
  final skills = <String, String>{
    'android_workspace':
        'Use workspace tools before answering. Prefer read, glob, grep, edit, and apply_patch inside the selected Android workspace.',
    'mobile_agent':
        'This mobile agent mirrors Mag semantics. Keep actions observable through parts, permissions, and events.',
  };
  final content = skills[name];
  if (content == null) {
    throw Exception('Unknown skill: $name');
  }
  return ToolExecutionResult(
    title: 'Skill',
    output: '<skill_content>\n$content\n</skill_content>',
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
  );
}

