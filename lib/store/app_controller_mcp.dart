// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
part of 'app_controller.dart';

extension AppControllerMcp on AppController {
  Future<void> reloadMcp() async {
    final servers = await _client!.listMcpServers();
    final statuses = await _client!.listMcpStatuses();
    final tools = await _client!.listMcpTools();
    final resources = await _client!.listMcpResources();
    final prompts = await _client!.listMcpPrompts();
    state = state.copyWith(
      mcpServers: servers,
      mcpStatuses: statuses,
      mcpTools: tools,
      mcpResources: resources,
      mcpPrompts: prompts,
    );
    notifyListeners();
  }

  Future<void> saveMcpServer(McpServerConfig server) async {
    final servers = await _client!.saveMcpServer(server);
    final statuses = await _client!.listMcpStatuses();
    final tools = await _client!.listMcpTools();
    final resources = await _client!.listMcpResources();
    final prompts = await _client!.listMcpPrompts();
    state = state.copyWith(
      mcpServers: servers,
      mcpStatuses: statuses,
      mcpTools: tools,
      mcpResources: resources,
      mcpPrompts: prompts,
    );
    notifyListeners();
  }

  Future<void> deleteMcpServer(String serverId) async {
    final servers = await _client!.deleteMcpServer(serverId);
    final statuses = Map<String, McpServerStatus>.from(state.mcpStatuses)
      ..remove(serverId);
    state = state.copyWith(
      mcpServers: servers,
      mcpStatuses: statuses,
      mcpTools: state.mcpTools.where((item) => item.serverId != serverId).toList(),
      mcpResources:
          state.mcpResources.where((item) => item.serverId != serverId).toList(),
      mcpPrompts: state.mcpPrompts.where((item) => item.serverId != serverId).toList(),
    );
    notifyListeners();
  }

  Future<void> refreshMcpServer(String serverId) async {
    final status = await _client!.refreshMcpServer(serverId);
    final lists = await Future.wait([
      _client!.listMcpTools(),
      _client!.listMcpResources(),
      _client!.listMcpPrompts(),
    ]);
    state = state.copyWith(
      mcpStatuses: {
        ...state.mcpStatuses,
        serverId: status,
      },
      mcpTools: lists[0] as List<McpToolDefinition>,
      mcpResources: lists[1] as List<McpResourceDefinition>,
      mcpPrompts: lists[2] as List<McpPromptDefinition>,
    );
    notifyListeners();
  }

  Future<void> disconnectMcpServer(String serverId) async {
    await _client!.disconnectMcpServer(serverId);
    final next = Map<String, McpServerStatus>.from(state.mcpStatuses);
    next[serverId] = (next[serverId] ?? McpServerStatus(serverId: serverId)).copyWith(
      connected: false,
      connecting: false,
      error: null,
    );
    state = state.copyWith(mcpStatuses: next);
    notifyListeners();
  }

  Future<McpOAuthAuthorization> authorizeMcpOAuth(String serverId) {
    return _client!.authorizeMcpOAuth(serverId);
  }

  Future<void> callbackMcpOAuth({
    required String serverId,
    required String code,
  }) async {
    await _client!.callbackMcpOAuth(serverId: serverId, code: code);
    await reloadMcp();
  }

  Future<McpToolCallResult> callMcpTool({
    required String serverId,
    required String toolName,
    JsonMap arguments = const {},
  }) {
    return _client!.callMcpTool(
      serverId: serverId,
      toolName: toolName,
      arguments: arguments,
    );
  }

  Future<List<McpResourceContent>> readMcpResource({
    required String serverId,
    required String uri,
  }) {
    return _client!.readMcpResource(serverId: serverId, uri: uri);
  }

  Future<List<McpPromptMessage>> getMcpPrompt({
    required String serverId,
    required String promptName,
    Map<String, String> arguments = const {},
  }) {
    return _client!.getMcpPrompt(
      serverId: serverId,
      promptName: promptName,
      arguments: arguments,
    );
  }
}
