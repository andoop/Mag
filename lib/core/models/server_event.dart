part of '../models.dart';

class ModelResponse {
  ModelResponse({
    required this.text,
    required this.toolCalls,
    required this.finishReason,
    required this.raw,
    this.usage = const ModelUsage(),
  });

  final String text;
  final List<ToolCall> toolCalls;
  final String finishReason;
  final JsonMap raw;
  final ModelUsage usage;
}

class ModelUsage {
  const ModelUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.reasoningTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalTokensFromApi,
  });

  final int inputTokens;
  final int outputTokens;
  final int reasoningTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;

  /// OpenAI-compatible `usage.total_tokens` when present.
  final int? totalTokensFromApi;

  int get promptTokens => inputTokens + cacheWriteTokens;
  int get completionTokens => outputTokens + cacheReadTokens;
  int get totalTokens => promptTokens + completionTokens;

  /// OpenCode `session/overflow.ts`: `total ?? input + output + cache.read + cache.write`.
  int get opencodeCompactionCount {
    final t = totalTokensFromApi;
    if (t != null && t > 0) return t;
    return inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens;
  }

  bool get isEmpty {
    if (totalTokensFromApi != null && totalTokensFromApi! > 0) return false;
    return inputTokens == 0 &&
        outputTokens == 0 &&
        reasoningTokens == 0 &&
        cacheReadTokens == 0 &&
        cacheWriteTokens == 0;
  }

  JsonMap toJson() => {
        'input': inputTokens,
        'output': outputTokens,
        'reasoning': reasoningTokens,
        'cache': {
          'read': cacheReadTokens,
          'write': cacheWriteTokens,
        },
        if (totalTokensFromApi != null) 'total': totalTokensFromApi,
      };

  factory ModelUsage.fromJson(JsonMap json) {
    final cache = Map<String, dynamic>.from(json['cache'] as Map? ?? const {});
    return ModelUsage(
      inputTokens: (json['input'] as num?)?.toInt() ?? 0,
      outputTokens: (json['output'] as num?)?.toInt() ?? 0,
      reasoningTokens: (json['reasoning'] as num?)?.toInt() ?? 0,
      cacheReadTokens: (cache['read'] as num?)?.toInt() ?? 0,
      cacheWriteTokens: (cache['write'] as num?)?.toInt() ?? 0,
      totalTokensFromApi: (json['total'] as num?)?.toInt(),
    );
  }
}

class ServerEvent {
  ServerEvent({
    required this.type,
    required this.properties,
    this.directory,
  });

  final String type;
  final JsonMap properties;
  final String? directory;

  JsonMap toJson() => {
        'type': type,
        'properties': properties,
        if (directory != null) 'directory': directory,
      };

  factory ServerEvent.fromJson(JsonMap json) => ServerEvent(
        type: json['type'] as String,
        properties: Map<String, dynamic>.from(
            json['properties'] as Map? ?? <String, dynamic>{}),
        directory: json['directory'] as String?,
      );

  String encode() => jsonEncode(toJson());
}
