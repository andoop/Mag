import 'dart:io';

import 'package:flutter/services.dart';

class NativeAnalyticsConfig {
  const NativeAnalyticsConfig({
    this.provider = '',
    this.sensorsServerUrl = '',
    this.sensorsEnableLog = false,
    this.sensorsFlushIntervalMs,
    this.sensorsFlushBulkSize,
    this.customServerUrl = '',
    this.customApiKey = '',
    this.customApiKeyHeader = '',
    this.channel = '',
    this.grayGroup = '',
    this.isInternalUser = false,
  });

  factory NativeAnalyticsConfig.fromJson(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const NativeAnalyticsConfig();
    return NativeAnalyticsConfig(
      provider: raw['provider'] as String? ?? '',
      sensorsServerUrl: raw['sensorsServerUrl'] as String? ?? '',
      sensorsEnableLog: raw['sensorsEnableLog'] as bool? ?? false,
      sensorsFlushIntervalMs: (raw['sensorsFlushIntervalMs'] as num?)?.toInt(),
      sensorsFlushBulkSize: (raw['sensorsFlushBulkSize'] as num?)?.toInt(),
      customServerUrl: raw['customServerUrl'] as String? ?? '',
      customApiKey: raw['customApiKey'] as String? ?? '',
      customApiKeyHeader: raw['customApiKeyHeader'] as String? ?? '',
      channel: raw['channel'] as String? ?? '',
      grayGroup: raw['grayGroup'] as String? ?? '',
      isInternalUser: raw['isInternalUser'] as bool? ?? false,
    );
  }

  final String provider;
  final String sensorsServerUrl;
  final bool sensorsEnableLog;
  final int? sensorsFlushIntervalMs;
  final int? sensorsFlushBulkSize;
  final String customServerUrl;
  final String customApiKey;
  final String customApiKeyHeader;
  final String channel;
  final String grayGroup;
  final bool isInternalUser;
}

class AnalyticsConfigBridge {
  AnalyticsConfigBridge._();

  static const MethodChannel _channel =
      MethodChannel('mobile_agent/analytics_config');

  static Future<NativeAnalyticsConfig> load() async {
    if (!Platform.isAndroid) {
      return const NativeAnalyticsConfig();
    }
    final raw = await _channel.invokeMapMethod<dynamic, dynamic>('getConfig');
    return NativeAnalyticsConfig.fromJson(raw);
  }
}
