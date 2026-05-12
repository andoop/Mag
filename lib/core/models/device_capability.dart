part of '../models.dart';

enum DeviceCapabilityCategory {
  files,
  media,
  clipboard,
  share,
  location,
  notifications,
  contacts,
  sensors,
}

enum DeviceCapabilityPermissionMode {
  none,
  once,
  always,
}

class DeviceCapabilityDefinition {
  const DeviceCapabilityDefinition({
    required this.id,
    required this.version,
    required this.category,
    required this.descriptionForAi,
    required this.inputSchema,
    required this.outputSchema,
    this.platforms = const ['android'],
    this.requiresUserGesture = true,
    this.permissionMode = DeviceCapabilityPermissionMode.once,
    this.webAliases = const [],
    this.directAiTool = false,
  });

  final String id;
  final int version;
  final DeviceCapabilityCategory category;
  final String descriptionForAi;
  final JsonMap inputSchema;
  final JsonMap outputSchema;
  final List<String> platforms;
  final bool requiresUserGesture;
  final DeviceCapabilityPermissionMode permissionMode;
  final List<String> webAliases;
  final bool directAiTool;

  JsonMap toJson() => {
        'id': id,
        'version': version,
        'category': category.name,
        'descriptionForAi': descriptionForAi,
        'inputSchema': inputSchema,
        'outputSchema': outputSchema,
        'platforms': platforms,
        'requiresUserGesture': requiresUserGesture,
        'permissionMode': permissionMode.name,
        'webAliases': webAliases,
        'directAiTool': directAiTool,
      };

  ToolDefinitionModel toToolModel() {
    return ToolDefinitionModel(
      id: 'device.${id.replaceAll('.', '_')}',
      description: descriptionForAi,
      parameters: inputSchema,
    );
  }
}
