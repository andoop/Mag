import 'dart:developer' as developer;

import 'package:sensors_analytics_flutter_plugin/sensors_analytics_flutter_plugin.dart';

import 'analytics.dart';
import '../platform/analytics_config_bridge.dart';

const String _kAnalyticsProvider = String.fromEnvironment(
  'MAG_ANALYTICS_PROVIDER',
  defaultValue: 'none',
);
const String _kSensorsServerUrl = String.fromEnvironment(
  'MAG_SENSORS_SERVER_URL',
  defaultValue: '',
);
const String _kSensorsEnableLog = String.fromEnvironment(
  'MAG_SENSORS_ENABLE_LOG',
  defaultValue: '',
);
const String _kSensorsFlushIntervalMs = String.fromEnvironment(
  'MAG_SENSORS_FLUSH_INTERVAL_MS',
  defaultValue: '',
);
const String _kSensorsFlushBulkSize = String.fromEnvironment(
  'MAG_SENSORS_FLUSH_BULK_SIZE',
  defaultValue: '',
);
const String _kCustomServerUrl = String.fromEnvironment(
  'MAG_CUSTOM_ANALYTICS_SERVER_URL',
  defaultValue: '',
);
const String _kCustomApiKey = String.fromEnvironment(
  'MAG_CUSTOM_ANALYTICS_API_KEY',
  defaultValue: '',
);
const String _kCustomApiKeyHeader = String.fromEnvironment(
  'MAG_CUSTOM_ANALYTICS_API_KEY_HEADER',
  defaultValue: '',
);
const String _kAnalyticsChannel = String.fromEnvironment(
  'MAG_ANALYTICS_CHANNEL',
  defaultValue: '',
);
const String _kAnalyticsGrayGroup = String.fromEnvironment(
  'MAG_ANALYTICS_GRAY_GROUP',
  defaultValue: '',
);
const String _kAnalyticsIsInternalUser = String.fromEnvironment(
  'MAG_ANALYTICS_IS_INTERNAL_USER',
  defaultValue: '',
);

class AnalyticsBuildConfig {
  const AnalyticsBuildConfig({
    this.provider = 'none',
    this.sensorsServerUrl = '',
    this.sensorsEnableLog = false,
    this.sensorsFlushIntervalMs = 15000,
    this.sensorsFlushBulkSize = 100,
    this.customServerUrl = '',
    this.customApiKey = '',
    this.customApiKeyHeader = 'x-api-key',
    this.channel = '',
    this.grayGroup = '',
    this.isInternalUser = false,
  });

  final String provider;
  final String sensorsServerUrl;
  final bool sensorsEnableLog;
  final int sensorsFlushIntervalMs;
  final int sensorsFlushBulkSize;
  final String customServerUrl;
  final String customApiKey;
  final String customApiKeyHeader;
  final String channel;
  final String grayGroup;
  final bool isInternalUser;

  bool get enabled {
    switch (provider.trim().toLowerCase()) {
      case 'sensors':
        return sensorsServerUrl.trim().isNotEmpty;
      case 'custom':
        return customServerUrl.trim().isNotEmpty;
      case '':
      case 'none':
        return false;
      default:
        return true;
    }
  }

  AnalyticsProperties get userProperties => {
        if (channel.isNotEmpty) 'channel': channel,
        if (grayGroup.isNotEmpty) 'gray_group': grayGroup,
        'is_internal_user': isInternalUser,
      };

  AnalyticsProperties get eventProperties => {
        if (channel.isNotEmpty) 'channel': channel,
        if (grayGroup.isNotEmpty) 'gray_group': grayGroup,
        'is_internal_user': isInternalUser,
      };
}

class AnalyticsBootstrapResult {
  const AnalyticsBootstrapResult({
    required this.analytics,
    required this.config,
  });

  final AnalyticsService analytics;
  final AnalyticsBuildConfig config;
}

Future<AnalyticsBootstrapResult> createAnalyticsBootstrap() async {
  final native = await AnalyticsConfigBridge.load();
  final config = AnalyticsBuildConfig(
    provider: _firstNonEmpty(_kAnalyticsProvider, native.provider, 'none')
        .toLowerCase(),
    sensorsServerUrl:
        _firstNonEmpty(_kSensorsServerUrl, native.sensorsServerUrl, ''),
    sensorsEnableLog:
        _resolveBool(_kSensorsEnableLog, native.sensorsEnableLog, false),
    sensorsFlushIntervalMs: _resolveInt(
      _kSensorsFlushIntervalMs,
      native.sensorsFlushIntervalMs,
      15000,
    ),
    sensorsFlushBulkSize: _resolveInt(
      _kSensorsFlushBulkSize,
      native.sensorsFlushBulkSize,
      100,
    ),
    customServerUrl:
        _firstNonEmpty(_kCustomServerUrl, native.customServerUrl, ''),
    customApiKey: _firstNonEmpty(_kCustomApiKey, native.customApiKey, ''),
    customApiKeyHeader: _firstNonEmpty(
      _kCustomApiKeyHeader,
      native.customApiKeyHeader,
      'x-api-key',
    ),
    channel: _firstNonEmpty(_kAnalyticsChannel, native.channel, ''),
    grayGroup: _firstNonEmpty(_kAnalyticsGrayGroup, native.grayGroup, ''),
    isInternalUser: _resolveBool(
      _kAnalyticsIsInternalUser,
      native.isInternalUser,
      false,
    ),
  );
  return AnalyticsBootstrapResult(
    analytics: _createAnalyticsService(config),
    config: config,
  );
}

Future<AnalyticsService> createAnalyticsService() async {
  final bootstrap = await createAnalyticsBootstrap();
  return bootstrap.analytics;
}

AnalyticsService _createAnalyticsService(AnalyticsBuildConfig config) {
  switch (config.provider.trim().toLowerCase()) {
    case 'sensors':
      return _createSensorsAnalyticsService(config);
    case 'custom':
      return _createCustomAnalyticsService(config);
    case '':
    case 'none':
      return AnalyticsService();
    default:
      developer.log(
        'Unknown analytics provider: ${config.provider}. Falling back to noop.',
        name: 'mobile_agent.analytics',
      );
      return AnalyticsService();
  }
}

AnalyticsService _createSensorsAnalyticsService(AnalyticsBuildConfig config) {
  final serverUrl = config.sensorsServerUrl.trim();
  if (serverUrl.isEmpty) {
    developer.log(
      'Sensors analytics provider selected without server url. Falling back to noop.',
      name: 'mobile_agent.analytics',
    );
    return AnalyticsService();
  }

  return AnalyticsService.sensors(
    onInitialize: () async {
      await SensorsAnalyticsFlutterPlugin.init(
        serverUrl: serverUrl,
        enableLog: config.sensorsEnableLog,
        flushInterval: config.sensorsFlushIntervalMs,
        flushBulkSize: config.sensorsFlushBulkSize,
        autoTrackTypes: const <SAAutoTrackType>{},
      );
    },
    onIdentify: (userId, traits) async {
      SensorsAnalyticsFlutterPlugin.identify(userId);
      if (traits.isNotEmpty) {
        SensorsAnalyticsFlutterPlugin.profileSet(
          _dynamicProperties(traits),
        );
      }
    },
    onSetUserProperties: (properties) async {
      if (properties.isEmpty) return;
      SensorsAnalyticsFlutterPlugin.profileSet(
        _dynamicProperties(properties),
      );
    },
    onTrackEvent: (eventName, properties) async {
      SensorsAnalyticsFlutterPlugin.track(
        eventName,
        _dynamicProperties(properties),
      );
    },
    onTrackScreen: (screenName, properties) async {
      SensorsAnalyticsFlutterPlugin.trackViewScreen(
        screenName,
        _dynamicProperties(properties),
      );
    },
    onReset: () async {
      SensorsAnalyticsFlutterPlugin.logout();
    },
    onDispose: () async {
      SensorsAnalyticsFlutterPlugin.flush();
    },
  );
}

AnalyticsService _createCustomAnalyticsService(AnalyticsBuildConfig config) {
  final serverUrl = config.customServerUrl.trim();
  if (serverUrl.isEmpty) {
    developer.log(
      'Custom analytics provider selected without server url. Falling back to noop.',
      name: 'mobile_agent.analytics',
    );
    return AnalyticsService();
  }
  final endpoint = Uri.tryParse(serverUrl);
  if (endpoint == null || !endpoint.hasScheme || endpoint.host.trim().isEmpty) {
    developer.log(
      'Invalid custom analytics server url: $serverUrl. Falling back to noop.',
      name: 'mobile_agent.analytics',
    );
    return AnalyticsService();
  }
  return AnalyticsService.custom(
    endpoint: endpoint,
    apiKey: config.customApiKey,
    apiKeyHeader: config.customApiKeyHeader,
  );
}

Map<String, dynamic> _dynamicProperties(AnalyticsProperties properties) {
  if (properties.isEmpty) return <String, dynamic>{};
  return Map<String, dynamic>.from(properties);
}

String _firstNonEmpty(String first, String second, String fallback) {
  final a = first.trim();
  if (a.isNotEmpty) return a;
  final b = second.trim();
  if (b.isNotEmpty) return b;
  return fallback;
}

bool _resolveBool(String raw, bool? nativeValue, bool fallback) {
  final value = raw.trim().toLowerCase();
  if (value.isNotEmpty) {
    return value == 'true' || value == '1' || value == 'yes';
  }
  return nativeValue ?? fallback;
}

int _resolveInt(String raw, int? nativeValue, int fallback) {
  final value = raw.trim();
  if (value.isNotEmpty) {
    return int.tryParse(value) ?? nativeValue ?? fallback;
  }
  return nativeValue ?? fallback;
}
