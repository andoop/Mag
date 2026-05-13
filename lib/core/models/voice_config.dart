part of '../models.dart';

const String kVoiceRealtimeConfigKey = 'voice_realtime_config';

enum VoiceRealtimeProvider {
  qwen,
  doubao,
}

String voiceRealtimeProviderId(VoiceRealtimeProvider provider) {
  switch (provider) {
    case VoiceRealtimeProvider.qwen:
      return 'qwen';
    case VoiceRealtimeProvider.doubao:
      return 'doubao';
  }
}

VoiceRealtimeProvider voiceRealtimeProviderFromId(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'doubao':
      return VoiceRealtimeProvider.doubao;
    case 'qwen':
    default:
      return VoiceRealtimeProvider.qwen;
  }
}

class QwenVoiceConfig {
  const QwenVoiceConfig({
    this.apiKey = '',
    this.endpoint = 'wss://dashscope.aliyuncs.com/api-ws/v1/realtime',
    this.model = 'qwen3-asr-flash-realtime',
  });

  final String apiKey;
  final String endpoint;
  final String model;

  bool get isConfigured => apiKey.trim().isNotEmpty;

  QwenVoiceConfig copyWith({
    String? apiKey,
    String? endpoint,
    String? model,
  }) {
    return QwenVoiceConfig(
      apiKey: apiKey ?? this.apiKey,
      endpoint: endpoint ?? this.endpoint,
      model: model ?? this.model,
    );
  }

  JsonMap toJson() => {
        'apiKey': apiKey,
        'endpoint': endpoint,
        'model': model,
      };

  factory QwenVoiceConfig.fromJson(JsonMap json) {
    return QwenVoiceConfig(
      apiKey: json['apiKey'] as String? ?? '',
      endpoint: json['endpoint'] as String? ??
          'wss://dashscope.aliyuncs.com/api-ws/v1/realtime',
      model: json['model'] as String? ?? 'qwen3-asr-flash-realtime',
    );
  }
}

class DoubaoVoiceConfig {
  const DoubaoVoiceConfig({
    this.apiKey = '',
    this.appKey = '',
    this.accessKey = '',
    this.resourceId = 'volc.bigasr.sauc.duration',
    this.endpoint = 'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel',
    this.model = '',
  });

  final String apiKey;
  final String appKey;
  final String accessKey;
  final String resourceId;
  final String endpoint;
  final String model;

  bool get usesNewApiKey => apiKey.trim().isNotEmpty;
  bool get isConfigured =>
      usesNewApiKey ||
      (appKey.trim().isNotEmpty && accessKey.trim().isNotEmpty);

  DoubaoVoiceConfig copyWith({
    String? apiKey,
    String? appKey,
    String? accessKey,
    String? resourceId,
    String? endpoint,
    String? model,
  }) {
    return DoubaoVoiceConfig(
      apiKey: apiKey ?? this.apiKey,
      appKey: appKey ?? this.appKey,
      accessKey: accessKey ?? this.accessKey,
      resourceId: resourceId ?? this.resourceId,
      endpoint: endpoint ?? this.endpoint,
      model: model ?? this.model,
    );
  }

  JsonMap toJson() => {
        'apiKey': apiKey,
        'appKey': appKey,
        'accessKey': accessKey,
        'resourceId': resourceId,
        'endpoint': endpoint,
        'model': model,
      };

  factory DoubaoVoiceConfig.fromJson(JsonMap json) {
    return DoubaoVoiceConfig(
      apiKey: json['apiKey'] as String? ?? '',
      appKey: json['appKey'] as String? ?? '',
      accessKey: json['accessKey'] as String? ?? '',
      resourceId: json['resourceId'] as String? ?? 'volc.bigasr.sauc.duration',
      endpoint: json['endpoint'] as String? ??
          'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel',
      model: json['model'] as String? ?? '',
    );
  }
}

class VoiceRealtimeConfig {
  const VoiceRealtimeConfig({
    this.enabled = false,
    this.provider = VoiceRealtimeProvider.qwen,
    this.language = 'zh',
    this.sampleRate = 16000,
    this.serverVad = true,
    this.qwen = const QwenVoiceConfig(),
    this.doubao = const DoubaoVoiceConfig(),
  });

  final bool enabled;
  final VoiceRealtimeProvider provider;
  final String language;
  final int sampleRate;
  final bool serverVad;
  final QwenVoiceConfig qwen;
  final DoubaoVoiceConfig doubao;

  factory VoiceRealtimeConfig.defaults() => const VoiceRealtimeConfig();

  bool get selectedProviderConfigured {
    switch (provider) {
      case VoiceRealtimeProvider.qwen:
        return qwen.isConfigured;
      case VoiceRealtimeProvider.doubao:
        return doubao.isConfigured;
    }
  }

  String get providerId => voiceRealtimeProviderId(provider);

  VoiceRealtimeConfig copyWith({
    bool? enabled,
    VoiceRealtimeProvider? provider,
    String? language,
    int? sampleRate,
    bool? serverVad,
    QwenVoiceConfig? qwen,
    DoubaoVoiceConfig? doubao,
  }) {
    return VoiceRealtimeConfig(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      language: language ?? this.language,
      sampleRate: sampleRate ?? this.sampleRate,
      serverVad: serverVad ?? this.serverVad,
      qwen: qwen ?? this.qwen,
      doubao: doubao ?? this.doubao,
    );
  }

  JsonMap toJson() => {
        'enabled': enabled,
        'provider': providerId,
        'language': language,
        'sampleRate': sampleRate,
        'serverVad': serverVad,
        'qwen': qwen.toJson(),
        'doubao': doubao.toJson(),
      };

  factory VoiceRealtimeConfig.fromJson(JsonMap json) {
    return VoiceRealtimeConfig(
      enabled: json['enabled'] as bool? ?? false,
      provider: voiceRealtimeProviderFromId(json['provider'] as String?),
      language: json['language'] as String? ?? 'zh',
      sampleRate: (json['sampleRate'] as num?)?.toInt() ?? 16000,
      serverVad: json['serverVad'] as bool? ?? true,
      qwen: QwenVoiceConfig.fromJson(
        Map<String, dynamic>.from(json['qwen'] as Map? ?? const {}),
      ),
      doubao: DoubaoVoiceConfig.fromJson(
        Map<String, dynamic>.from(json['doubao'] as Map? ?? const {}),
      ),
    );
  }
}
