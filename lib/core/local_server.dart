import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'database.dart';
import 'models.dart';
import 'session_engine.dart';
import 'workspace_bridge.dart';

const bool _kDebugServer = false;

void _debugLog(String tag, String message) {
  if (!_kDebugServer) return;
  // ignore: avoid_print
  print('[local-server][$tag] $message');
}

class LocalServer {
  LocalServer({
    required this.database,
    required this.engine,
    required this.events,
    required this.workspaceBridge,
  });

  final AppDatabase database;
  final SessionEngine engine;
  final LocalEventBus events;
  final WorkspaceBridge workspaceBridge;

  HttpServer? _server;

  Uri? get baseUri {
    final server = _server;
    if (server == null) return null;
    return Uri.parse('http://${server.address.address}:${server.port}');
  }

  Future<Uri> start() async {
    final existing = _server;
    if (existing != null) {
      return Uri.parse('http://${existing.address.address}:${existing.port}');
    }
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_listen());
    return baseUri!;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _listen() async {
    final server = _server;
    if (server == null) return;
    await for (final request in server) {
      unawaited(_handle(request));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      final path = request.uri.path;
      if (path == '/global/event') {
        await _handleSse(request, global: true);
        return;
      }
      if (path == '/event') {
        await _handleSse(request, global: false);
        return;
      }
      if (path == '/workspace' && request.method == 'GET') {
        final workspaces = await database.listWorkspaces();
        await _json(
            request.response, workspaces.map((item) => item.toJson()).toList());
        return;
      }
      if (path == '/workspace' && request.method == 'POST') {
        final body = await _readJson(request);
        final workspace = WorkspaceInfo.fromJson(body);
        await database.saveWorkspace(workspace);
        await engine.ensureProject(workspace);
        await _json(request.response, workspace.toJson());
        return;
      }
      if (path == '/agent' && request.method == 'GET') {
        await _json(request.response,
            engine.listAgents().map((item) => item.toJson()).toList());
        return;
      }
      if (path == '/session' && request.method == 'GET') {
        final workspaceId = request.uri.queryParameters['workspaceId'] ?? '';
        final sessions = await database.listSessions(workspaceId);
        await _json(
            request.response, sessions.map((item) => item.toJson()).toList());
        return;
      }
      if (path == '/session' && request.method == 'POST') {
        final body = await _readJson(request);
        final workspace = WorkspaceInfo.fromJson(
            Map<String, dynamic>.from(body['workspace'] as Map));
        final session = await engine.createSession(
          workspace: workspace,
          agent: body['agent'] as String? ?? 'build',
        );
        await _json(request.response, session.toJson());
        return;
      }
      if (path == '/permission' && request.method == 'GET') {
        final items = await database.listPermissionRequests();
        await _json(
            request.response, items.map((item) => item.toJson()).toList());
        return;
      }
      if (path == '/question' && request.method == 'GET') {
        final items = await database.listQuestionRequests();
        await _json(
            request.response, items.map((item) => item.toJson()).toList());
        return;
      }
      if (path == '/settings/model' && request.method == 'GET') {
        final config = ModelConfig.fromJson(
          await database.getSetting('model_config') ??
              ModelConfig.defaults().toJson(),
        );
        await _json(request.response, config.toJson());
        return;
      }
      if (path == '/settings/model' && request.method == 'POST') {
        final body = await _readJson(request);
        await database.putSetting('model_config', body);
        await _json(request.response, body);
        return;
      }
      final segments = request.uri.pathSegments;
      if (segments.length >= 3 &&
          segments.first == 'workspace-file' &&
          request.method == 'GET') {
        final workspaceId = segments[1];
        final relativePath = segments.sublist(2).join('/');
        final workspace = (await database.listWorkspaces())
            .cast<WorkspaceInfo?>()
            .firstWhere((item) => item?.id == workspaceId, orElse: () => null);
        if (workspace == null) {
          request.response.statusCode = 404;
          await _json(request.response, {'error': 'Workspace not found'});
          return;
        }
        try {
          final bytes = await workspaceBridge.readBytes(
            treeUri: workspace.treeUri,
            relativePath: relativePath,
          );
          request.response.headers.contentType =
              _contentTypeForPath(relativePath);
          request.response.add(bytes);
          await request.response.close();
        } catch (_) {
          request.response.statusCode = 404;
          await _json(request.response, {'error': 'Workspace file not found'});
        }
        return;
      }
      if (segments.length >= 2 &&
          segments.first == 'session' &&
          request.method == 'GET') {
        final sessionId = segments[1];
        if (segments.length == 3 && segments[2] == 'message') {
          final snapshot = await engine.snapshot(sessionId);
          await _json(
            request.response,
            snapshot.messages.map((message) {
              final parts = snapshot.parts
                  .where((item) => item.messageId == message.id)
                  .toList();
              return {
                'info': message.toJson(),
                'parts': parts.map((item) => item.toJson()).toList(),
              };
            }).toList(),
          );
          return;
        }
      }
      if (segments.length >= 3 &&
          segments.first == 'session' &&
          request.method == 'POST') {
        final sessionId = segments[1];
        final session = await database.getSession(sessionId);
        if (session == null) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final workspace = (await database.listWorkspaces())
            .firstWhere((item) => item.id == session.workspaceId);
        final body = await _readJson(request);
        if (segments[2] == 'prompt') {
          final format = body['format'] == null
              ? null
              : MessageFormat.fromJson(
                  Map<String, dynamic>.from(body['format'] as Map));
          final message = await engine.prompt(
            workspace: workspace,
            session: session,
            text: body['text'] as String? ?? '',
            agent: body['agent'] as String?,
            format: format,
          );
          await _json(request.response, message.toJson());
          return;
        }
        if (segments[2] == 'message') {
          final message = MessageInfo(
            id: newId('message'),
            sessionId: session.id,
            role: SessionRole.user,
            agent: body['agent'] as String? ?? session.agent,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            text: body['text'] as String? ?? '',
            format: body['format'] == null
                ? null
                : MessageFormat.fromJson(
                    Map<String, dynamic>.from(body['format'] as Map)),
          );
          await database.saveMessage(message);
          events.emit(ServerEvent(
            type: 'message.updated',
            properties: message.toJson(),
            directory: workspace.treeUri,
          ));
          await _json(request.response, message.toJson());
          return;
        }
        if (segments[2] == 'prompt_async') {
          final format = body['format'] == null
              ? null
              : MessageFormat.fromJson(
                  Map<String, dynamic>.from(body['format'] as Map));
          _debugLog('prompt_async', 'session=${session.id}');
          unawaited(
            engine
                .promptAsync(
              workspace: workspace,
              session: session,
              text: body['text'] as String? ?? '',
              agent: body['agent'] as String?,
              format: format,
            )
                .catchError((error) async {
              events.emit(ServerEvent(
                type: 'session.error',
                properties: {
                  'sessionID': session.id,
                  'message': error.toString(),
                },
                directory: workspace.treeUri,
              ));
            }),
          );
          request.response.statusCode = 204;
          await request.response.close();
          return;
        }
        if (segments[2] == 'compact') {
          final updated = await engine.compactSession(
            workspace: workspace,
            session: session,
          );
          await _json(request.response, updated.toJson());
          return;
        }
      }
      if (segments.length == 3 &&
          segments.first == 'session' &&
          segments[2] == 'cancel' &&
          request.method == 'POST') {
        final sessionId = segments[1];
        final session = await database.getSession(sessionId);
        if (session == null) {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        final workspace = (await database.listWorkspaces())
            .firstWhere((item) => item.id == session.workspaceId);
        await engine.cancel(sessionId, directory: workspace.treeUri);
        await _json(request.response, {'ok': true});
        return;
      }
      if (segments.length == 3 &&
          segments.first == 'permission' &&
          request.method == 'POST') {
        final body = await _readJson(request);
        final reply = PermissionReply.values
            .firstWhere((item) => item.name == body['reply']);
        await engine.permissionCenter.reply(segments[1], reply);
        await _json(request.response, {'ok': true});
        return;
      }
      if (segments.length == 3 &&
          segments.first == 'question' &&
          request.method == 'POST') {
        final body = await _readJson(request);
        final answers = ((body['answers'] as List?) ?? const [])
            .map((item) => List<String>.from(item as List))
            .toList();
        await engine.questionCenter.reply(segments[1], answers);
        await _json(request.response, {'ok': true});
        return;
      }
      request.response.statusCode = 404;
      await _json(request.response, {'error': 'Not found'});
    } catch (error) {
      request.response.statusCode = 500;
      await _json(request.response, {'error': error.toString()});
    }
  }

  Future<void> _handleSse(HttpRequest request, {required bool global}) async {
    request.response.bufferOutput = false;
    request.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    request.response.headers
        .set(HttpHeaders.cacheControlHeader, 'no-cache, no-transform');
    request.response.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
    request.response.headers.set('X-Accel-Buffering', 'no');
    request.response.headers.set('X-Content-Type-Options', 'nosniff');
    final directory = request.uri.queryParameters['directory'];
    var closed = false;
    var writeQueue = Future<void>.value();

    Future<void> writeEvent(ServerEvent event) {
      if (closed) return Future.value();
      writeQueue = writeQueue.then((_) async {
        if (closed) return;
        request.response.write('data: ${jsonEncode(event.toJson())}\n\n');
        await request.response.flush();
      }).catchError((_) {});
      return writeQueue;
    }

    final heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(writeEvent(
          ServerEvent(type: 'server.heartbeat', properties: const {})));
    });
    final subscription = events.stream.listen((event) {
      if (!global && directory != null && event.directory != directory) {
        return;
      }
      unawaited(writeEvent(event));
    });
    await writeEvent(
        ServerEvent(type: 'server.connected', properties: const {}));
    try {
      await request.response.done.catchError((_) {});
    } finally {
      closed = true;
      heartbeat.cancel();
      await subscription.cancel();
      await writeQueue.catchError((_) {});
    }
  }

  Future<JsonMap> _readJson(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.isEmpty) return <String, dynamic>{};
    return Map<String, dynamic>.from(jsonDecode(body) as Map);
  }

  Future<void> _json(HttpResponse response, Object body) async {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}

ContentType _contentTypeForPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.html') || lower.endsWith('.htm')) {
    return ContentType.html;
  }
  if (lower.endsWith('.css')) {
    return ContentType('text', 'css', charset: 'utf-8');
  }
  if (lower.endsWith('.js') || lower.endsWith('.mjs')) {
    return ContentType('application', 'javascript', charset: 'utf-8');
  }
  if (lower.endsWith('.json')) {
    return ContentType.json;
  }
  if (lower.endsWith('.svg')) {
    return ContentType('image', 'svg+xml');
  }
  if (lower.endsWith('.png')) {
    return ContentType('image', 'png');
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return ContentType('image', 'jpeg');
  }
  if (lower.endsWith('.gif')) {
    return ContentType('image', 'gif');
  }
  if (lower.endsWith('.webp')) {
    return ContentType('image', 'webp');
  }
  if (lower.endsWith('.wasm')) {
    return ContentType('application', 'wasm');
  }
  return ContentType('text', 'plain', charset: 'utf-8');
}
