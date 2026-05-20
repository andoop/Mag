import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

typedef AnalyticsProperties = Map<String, Object?>;
typedef AnalyticsInitializeCallback = FutureOr<void> Function();
typedef AnalyticsIdentifyCallback = FutureOr<void> Function(
  String userId,
  AnalyticsProperties traits,
);
typedef AnalyticsSetUserPropertiesCallback = FutureOr<void> Function(
  AnalyticsProperties properties,
);
typedef AnalyticsTrackEventCallback = FutureOr<void> Function(
  String eventName,
  AnalyticsProperties properties,
);
typedef AnalyticsTrackScreenCallback = FutureOr<void> Function(
  String screenName,
  AnalyticsProperties properties,
);
typedef AnalyticsResetCallback = FutureOr<void> Function();
typedef AnalyticsDisposeCallback = FutureOr<void> Function();

class AnalyticsEvent {
  const AnalyticsEvent(
    this.name, {
    this.properties = const {},
  });

  final String name;
  final AnalyticsProperties properties;
}

class AnalyticsScreen {
  const AnalyticsScreen(
    this.name, {
    this.properties = const {},
  });

  final String name;
  final AnalyticsProperties properties;
}

abstract class AnalyticsAdapter {
  const AnalyticsAdapter();

  String get name;

  Future<void> initialize();

  Future<void> identify(
    String userId, {
    AnalyticsProperties traits = const {},
  });

  Future<void> setUserProperties(AnalyticsProperties properties);

  Future<void> trackEvent(
    String eventName, {
    AnalyticsProperties properties = const {},
  });

  Future<void> trackScreen(
    String screenName, {
    AnalyticsProperties properties = const {},
  });

  Future<void> reset();

  Future<void> dispose();
}

class NoopAnalyticsAdapter extends AnalyticsAdapter {
  const NoopAnalyticsAdapter();

  @override
  String get name => 'noop';

  @override
  Future<void> dispose() async {}

  @override
  Future<void> identify(
    String userId, {
    AnalyticsProperties traits = const {},
  }) async {}

  @override
  Future<void> initialize() async {}

  @override
  Future<void> reset() async {}

  @override
  Future<void> setUserProperties(AnalyticsProperties properties) async {}

  @override
  Future<void> trackEvent(
    String eventName, {
    AnalyticsProperties properties = const {},
  }) async {}

  @override
  Future<void> trackScreen(
    String screenName, {
    AnalyticsProperties properties = const {},
  }) async {}
}

class DelegateAnalyticsAdapter extends AnalyticsAdapter {
  DelegateAnalyticsAdapter({
    required this.name,
    this.onInitialize,
    this.onIdentify,
    this.onSetUserProperties,
    this.onTrackEvent,
    this.onTrackScreen,
    this.onReset,
    this.onDispose,
  });

  @override
  final String name;
  final AnalyticsInitializeCallback? onInitialize;
  final AnalyticsIdentifyCallback? onIdentify;
  final AnalyticsSetUserPropertiesCallback? onSetUserProperties;
  final AnalyticsTrackEventCallback? onTrackEvent;
  final AnalyticsTrackScreenCallback? onTrackScreen;
  final AnalyticsResetCallback? onReset;
  final AnalyticsDisposeCallback? onDispose;

  @override
  Future<void> dispose() async {
    await Future.sync(() => onDispose?.call());
  }

  @override
  Future<void> identify(
    String userId, {
    AnalyticsProperties traits = const {},
  }) async {
    await Future.sync(() => onIdentify?.call(userId, traits));
  }

  @override
  Future<void> initialize() async {
    await Future.sync(() => onInitialize?.call());
  }

  @override
  Future<void> reset() async {
    await Future.sync(() => onReset?.call());
  }

  @override
  Future<void> setUserProperties(AnalyticsProperties properties) async {
    await Future.sync(() => onSetUserProperties?.call(properties));
  }

  @override
  Future<void> trackEvent(
    String eventName, {
    AnalyticsProperties properties = const {},
  }) async {
    await Future.sync(() => onTrackEvent?.call(eventName, properties));
  }

  @override
  Future<void> trackScreen(
    String screenName, {
    AnalyticsProperties properties = const {},
  }) async {
    await Future.sync(() => onTrackScreen?.call(screenName, properties));
  }
}

class FirebaseAnalyticsAdapter extends DelegateAnalyticsAdapter {
  FirebaseAnalyticsAdapter({
    AnalyticsInitializeCallback? onInitialize,
    AnalyticsIdentifyCallback? onIdentify,
    AnalyticsSetUserPropertiesCallback? onSetUserProperties,
    AnalyticsTrackEventCallback? onTrackEvent,
    AnalyticsTrackScreenCallback? onTrackScreen,
    AnalyticsResetCallback? onReset,
    AnalyticsDisposeCallback? onDispose,
  }) : super(
          name: 'firebase',
          onInitialize: onInitialize,
          onIdentify: onIdentify,
          onSetUserProperties: onSetUserProperties,
          onTrackEvent: onTrackEvent,
          onTrackScreen: onTrackScreen,
          onReset: onReset,
          onDispose: onDispose,
        );
}

class SensorsAnalyticsAdapter extends DelegateAnalyticsAdapter {
  SensorsAnalyticsAdapter({
    AnalyticsInitializeCallback? onInitialize,
    AnalyticsIdentifyCallback? onIdentify,
    AnalyticsSetUserPropertiesCallback? onSetUserProperties,
    AnalyticsTrackEventCallback? onTrackEvent,
    AnalyticsTrackScreenCallback? onTrackScreen,
    AnalyticsResetCallback? onReset,
    AnalyticsDisposeCallback? onDispose,
  }) : super(
          name: 'sensors',
          onInitialize: onInitialize,
          onIdentify: onIdentify,
          onSetUserProperties: onSetUserProperties,
          onTrackEvent: onTrackEvent,
          onTrackScreen: onTrackScreen,
          onReset: onReset,
          onDispose: onDispose,
        );
}

class CustomServerAnalyticsAdapter extends AnalyticsAdapter {
  CustomServerAnalyticsAdapter({
    required Uri endpoint,
    this.apiKey = '',
    this.apiKeyHeader = 'x-api-key',
    this.connectTimeout = const Duration(seconds: 10),
  })  : _endpoint = endpoint,
        _client = HttpClient();

  final Uri _endpoint;
  final HttpClient _client;
  final String apiKey;
  final String apiKeyHeader;
  final Duration connectTimeout;

  @override
  String get name => 'custom';

  @override
  Future<void> initialize() async {}

  @override
  Future<void> identify(
    String userId, {
    AnalyticsProperties traits = const {},
  }) {
    return _post(
      type: 'identify',
      body: {
        'userId': userId,
        'traits': traits,
      },
    );
  }

  @override
  Future<void> setUserProperties(AnalyticsProperties properties) {
    return _post(
      type: 'user_properties',
      body: {
        'properties': properties,
      },
    );
  }

  @override
  Future<void> trackEvent(
    String eventName, {
    AnalyticsProperties properties = const {},
  }) {
    return _post(
      type: 'event',
      body: {
        'event': eventName,
        'properties': properties,
      },
    );
  }

  @override
  Future<void> trackScreen(
    String screenName, {
    AnalyticsProperties properties = const {},
  }) {
    return _post(
      type: 'screen',
      body: {
        'screen': screenName,
        'properties': properties,
      },
    );
  }

  @override
  Future<void> reset() {
    return _post(type: 'reset', body: const {});
  }

  @override
  Future<void> dispose() async {
    _client.close(force: false);
  }

  Future<void> _post({
    required String type,
    required Map<String, Object?> body,
  }) async {
    final request = await _client.postUrl(_endpoint).timeout(connectTimeout);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (apiKey.trim().isNotEmpty) {
      request.headers.set(apiKeyHeader, apiKey.trim());
    }
    request.write(jsonEncode({
      'type': type,
      'sentAt': DateTime.now().toUtc().toIso8601String(),
      'source': {
        'sdk': 'mobile_agent',
        'adapter': name,
      },
      ...body,
    }));
    final response = await request.close().timeout(connectTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final responseBody = await response.transform(utf8.decoder).join();
      throw HttpException(
        'Custom analytics server responded with ${response.statusCode}: $responseBody',
        uri: _endpoint,
      );
    }
    await response.drain<void>();
  }
}

class AnalyticsService {
  AnalyticsService({
    List<AnalyticsAdapter> adapters = const [NoopAnalyticsAdapter()],
  }) : _adapters = List<AnalyticsAdapter>.unmodifiable(
          adapters.isEmpty ? const [NoopAnalyticsAdapter()] : adapters,
        );

  factory AnalyticsService.firebase({
    AnalyticsInitializeCallback? onInitialize,
    AnalyticsIdentifyCallback? onIdentify,
    AnalyticsSetUserPropertiesCallback? onSetUserProperties,
    AnalyticsTrackEventCallback? onTrackEvent,
    AnalyticsTrackScreenCallback? onTrackScreen,
    AnalyticsResetCallback? onReset,
    AnalyticsDisposeCallback? onDispose,
  }) {
    return AnalyticsService(
      adapters: [
        FirebaseAnalyticsAdapter(
          onInitialize: onInitialize,
          onIdentify: onIdentify,
          onSetUserProperties: onSetUserProperties,
          onTrackEvent: onTrackEvent,
          onTrackScreen: onTrackScreen,
          onReset: onReset,
          onDispose: onDispose,
        ),
      ],
    );
  }

  factory AnalyticsService.sensors({
    AnalyticsInitializeCallback? onInitialize,
    AnalyticsIdentifyCallback? onIdentify,
    AnalyticsSetUserPropertiesCallback? onSetUserProperties,
    AnalyticsTrackEventCallback? onTrackEvent,
    AnalyticsTrackScreenCallback? onTrackScreen,
    AnalyticsResetCallback? onReset,
    AnalyticsDisposeCallback? onDispose,
  }) {
    return AnalyticsService(
      adapters: [
        SensorsAnalyticsAdapter(
          onInitialize: onInitialize,
          onIdentify: onIdentify,
          onSetUserProperties: onSetUserProperties,
          onTrackEvent: onTrackEvent,
          onTrackScreen: onTrackScreen,
          onReset: onReset,
          onDispose: onDispose,
        ),
      ],
    );
  }

  factory AnalyticsService.custom({
    required Uri endpoint,
    String apiKey = '',
    String apiKeyHeader = 'x-api-key',
    Duration connectTimeout = const Duration(seconds: 10),
  }) {
    return AnalyticsService(
      adapters: [
        CustomServerAnalyticsAdapter(
          endpoint: endpoint,
          apiKey: apiKey,
          apiKeyHeader: apiKeyHeader,
          connectTimeout: connectTimeout,
        ),
      ],
    );
  }

  final List<AnalyticsAdapter> _adapters;
  bool _initialized = false;

  List<AnalyticsAdapter> get adapters => _adapters;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await Future.wait([
      for (final adapter in _adapters)
        _guard('initialize', adapter, () => adapter.initialize()),
    ]);
  }

  Future<void> identify(
    String userId, {
    AnalyticsProperties traits = const {},
  }) async {
    final normalizedTraits = _normalizeProperties(traits);
    await _dispatch(
      'identify',
      (adapter) => adapter.identify(userId, traits: normalizedTraits),
    );
  }

  Future<void> setUserProperties(AnalyticsProperties properties) async {
    final normalized = _normalizeProperties(properties);
    await _dispatch(
      'setUserProperties',
      (adapter) => adapter.setUserProperties(normalized),
    );
  }

  Future<void> trackEvent(
    String eventName, {
    AnalyticsProperties properties = const {},
  }) async {
    final normalized = _normalizeProperties(properties);
    await _dispatch(
      'trackEvent:$eventName',
      (adapter) => adapter.trackEvent(eventName, properties: normalized),
    );
  }

  Future<void> track(AnalyticsEvent event) {
    return trackEvent(event.name, properties: event.properties);
  }

  Future<void> trackScreen(
    String screenName, {
    AnalyticsProperties properties = const {},
  }) async {
    final normalized = _normalizeProperties(properties);
    await _dispatch(
      'trackScreen:$screenName',
      (adapter) => adapter.trackScreen(screenName, properties: normalized),
    );
  }

  Future<void> screen(AnalyticsScreen screen) {
    return trackScreen(screen.name, properties: screen.properties);
  }

  Future<void> reset() async {
    await _dispatch('reset', (adapter) => adapter.reset());
  }

  Future<void> dispose() async {
    await Future.wait([
      for (final adapter in _adapters)
        _guard('dispose', adapter, () => adapter.dispose()),
    ]);
  }

  Future<void> _dispatch(
    String operation,
    Future<void> Function(AnalyticsAdapter adapter) action,
  ) async {
    await initialize();
    await Future.wait([
      for (final adapter in _adapters)
        _guard(operation, adapter, () => action(adapter)),
    ]);
  }

  Future<void> _guard(
    String operation,
    AnalyticsAdapter adapter,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      developer.log(
        'Analytics operation failed: $operation',
        name: 'mobile_agent.analytics',
        error: error,
        stackTrace: stackTrace,
        time: DateTime.now(),
        zone: Zone.current,
        sequenceNumber: adapter.name.hashCode,
      );
    }
  }

  AnalyticsProperties _normalizeProperties(AnalyticsProperties properties) {
    if (properties.isEmpty) return const {};
    final normalized = <String, Object?>{};
    properties.forEach((key, value) {
      final trimmedKey = key.trim();
      if (trimmedKey.isEmpty) return;
      normalized[trimmedKey] = _normalizeValue(value);
    });
    return normalized;
  }

  Object? _normalizeValue(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toIso8601String();
    if (value is Duration) return value.inMilliseconds;
    if (value is Enum) return value.name;
    if (value is Iterable) {
      return value.map(_normalizeValue).toList(growable: false);
    }
    if (value is Map) {
      return jsonEncode(value.map(
        (key, nestedValue) =>
            MapEntry(key.toString(), _normalizeValue(nestedValue)),
      ));
    }
    return value.toString();
  }
}
