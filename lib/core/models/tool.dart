part of '../models.dart';

class ToolCall {
  ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final JsonMap arguments;

  JsonMap toJson() => {
        'id': id,
        'name': name,
        'arguments': arguments,
      };

  factory ToolCall.fromJson(JsonMap json) => ToolCall(
        id: json['id'] as String,
        name: json['name'] as String,
        arguments: Map<String, dynamic>.from(
            json['arguments'] as Map? ?? <String, dynamic>{}),
      );
}

class ToolDefinitionModel {
  ToolDefinitionModel({
    required this.id,
    required this.description,
    required this.parameters,
  });

  final String id;
  final String description;
  final JsonMap parameters;

  JsonMap toJson() => {
        'id': id,
        'description': description,
        'parameters': parameters,
      };
}

class ToolExecutionResult {
  ToolExecutionResult({
    required this.title,
    required this.output,
    this.displayOutput,
    JsonMap? metadata,
    List<JsonMap>? attachments,
  })  : metadata = metadata ?? <String, dynamic>{},
        attachments = attachments ?? const [];

  final String title;
  final String output;
  final String? displayOutput;
  final JsonMap metadata;
  final List<JsonMap> attachments;

  JsonMap toJson() => {
        'title': title,
        'output': output,
        'displayOutput': displayOutput,
        'metadata': metadata,
        'attachments': attachments,
      };
}
