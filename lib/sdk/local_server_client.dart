import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/models.dart';

class SessionMessageBundle {
  SessionMessageBundle({
    required this.message,
    required this.parts,
  });

  final MessageInfo message;
  final List<MessagePart> parts;
}

class LocalServerClient {
  LocalServerClient(this.baseUri);

  final Uri baseUri;
  final HttpClient _client = HttpClient();

  Future<List<WorkspaceInfo>> listWorkspaces() async {
    final data = await _get('/workspace');
    return (data as List)
        .map((item) => WorkspaceInfo.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<List<AgentDefinition>> listAgents() async {
    final data = await _get('/agent');
    return (data as List)
        .map((item) => AgentDefinition.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<WorkspaceInfo> saveWorkspace(WorkspaceInfo workspace) async {
    final data = await _post('/workspace', workspace.toJson());
    return WorkspaceInfo.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<SessionInfo>> listSessions(String workspaceId) async {
    final data = await _get('/session?workspaceId=$workspaceId');
    return (data as List)
        .map((item) => SessionInfo.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<SessionInfo> createSession(WorkspaceInfo workspace, {String agent = 'build'}) async {
    final data = await _post('/session', {
      'workspace': workspace.toJson(),
      'agent': agent,
    });
    return SessionInfo.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<SessionMessageBundle>> listSessionMessages(String sessionId) async {
    final data = await _get('/session/$sessionId/message');
    return (data as List).map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return SessionMessageBundle(
        message: MessageInfo.fromJson(Map<String, dynamic>.from(map['info'] as Map)),
        parts: (map['parts'] as List)
            .map((part) => MessagePart.fromJson(Map<String, dynamic>.from(part as Map)))
            .toList(),
      );
    }).toList();
  }

  Future<void> sendPromptAsync(
    String sessionId,
    String text, {
    String? agent,
    MessageFormat? format,
  }) async {
    await _post('/session/$sessionId/prompt_async', {
      'text': text,
      'agent': agent,
      'format': format?.toJson(),
    });
  }

  Future<MessageInfo> createMessage(
    String sessionId,
    String text, {
    String? agent,
    MessageFormat? format,
  }) async {
    final data = await _post('/session/$sessionId/message', {
      'text': text,
      'agent': agent,
      'format': format?.toJson(),
    });
    return MessageInfo.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<ModelConfig> loadModelConfig() async {
    final data = await _get('/settings/model');
    return ModelConfig.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> saveModelConfig(ModelConfig config) async {
    await _post('/settings/model', config.toJson());
  }

  Future<List<PermissionRequest>> listPermissions() async {
    final data = await _get('/permission');
    return (data as List)
        .map((item) => PermissionRequest.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> replyPermission(String requestId, PermissionReply reply) async {
    await _post('/permission/$requestId/reply', {'reply': reply.name});
  }

  Future<List<QuestionRequest>> listQuestions() async {
    final data = await _get('/question');
    return (data as List)
        .map((item) => QuestionRequest.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> replyQuestion(String requestId, List<List<String>> answers) async {
    await _post('/question/$requestId/reply', {'answers': answers});
  }

  Future<void> cancelSession(String sessionId) async {
    await _post('/session/$sessionId/cancel', const {});
  }

  Future<SessionInfo> compactSession(String sessionId) async {
    final data = await _post('/session/$sessionId/compact', const {});
    return SessionInfo.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Stream<ServerEvent> globalEvents({String? directory}) async* {
    final uri = baseUri.replace(
      path: '/global/event',
      queryParameters: {
        if (directory != null) 'directory': directory,
      },
    );
    final request = await _client.getUrl(uri);
    final response = await request.close();
    await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final payload = jsonDecode(line.substring(6)) as Map<String, dynamic>;
      yield ServerEvent.fromJson(payload);
    }
  }

  Future<dynamic> _get(String path) async {
    final request = await _client.getUrl(baseUri.resolve(path));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body);
  }

  Future<dynamic> _post(String path, JsonMap body) async {
    final request = await _client.postUrl(baseUri.resolve(path));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close();
    if (response.statusCode == 204) return null;
    final text = await response.transform(utf8.decoder).join();
    if (text.isEmpty) return null;
    return jsonDecode(text);
  }
}
