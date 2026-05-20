import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/core/app_analytics.dart';
import 'package:mobile_agent/core/analytics.dart';
import 'package:mobile_agent/core/analytics_bootstrap.dart';

enum _SampleStage { ready }

class _RecordingAdapter extends AnalyticsAdapter {
  _RecordingAdapter({this.throwOnTrack = false});

  final bool throwOnTrack;
  int initializeCount = 0;
  String? identifiedUserId;
  AnalyticsProperties identifiedTraits = const {};
  final List<Map<String, Object?>> trackedEvents = [];
  final List<Map<String, Object?>> trackedScreens = [];

  @override
  String get name => 'recording';

  @override
  Future<void> dispose() async {}

  @override
  Future<void> identify(
    String userId, {
    AnalyticsProperties traits = const {},
  }) async {
    identifiedUserId = userId;
    identifiedTraits = traits;
  }

  @override
  Future<void> initialize() async {
    initializeCount += 1;
  }

  @override
  Future<void> reset() async {}

  @override
  Future<void> setUserProperties(AnalyticsProperties properties) async {}

  @override
  Future<void> trackEvent(
    String eventName, {
    AnalyticsProperties properties = const {},
  }) async {
    if (throwOnTrack) {
      throw StateError('track failed');
    }
    trackedEvents.add({
      'name': eventName,
      'properties': properties,
    });
  }

  @override
  Future<void> trackScreen(
    String screenName, {
    AnalyticsProperties properties = const {},
  }) async {
    trackedScreens.add({
      'name': screenName,
      'properties': properties,
    });
  }
}

void main() {
  test('dispatches analytics calls and normalizes properties', () async {
    final adapter = _RecordingAdapter();
    final analytics = AnalyticsService(adapters: [adapter]);
    final when = DateTime.utc(2026, 5, 19, 9, 0, 0);

    await analytics.identify(
      'user-1',
      traits: {
        'platform': 'ios',
        'when': when,
      },
    );
    await analytics.trackEvent(
      'prompt_submitted',
      properties: {
        'duration': const Duration(seconds: 3),
        'stage': _SampleStage.ready,
        'nested': {'count': 2},
        'items': const [1, true, 'x'],
      },
    );
    await analytics.trackScreen(
      'workspace_home',
      properties: {'has_active_session': true},
    );

    expect(adapter.initializeCount, 1);
    expect(adapter.identifiedUserId, 'user-1');
    expect(adapter.identifiedTraits['when'], when.toIso8601String());
    expect(adapter.trackedEvents, hasLength(1));
    expect(adapter.trackedScreens, hasLength(1));

    final event = adapter.trackedEvents.single;
    final properties = event['properties']! as AnalyticsProperties;
    expect(event['name'], 'prompt_submitted');
    expect(properties['duration'], 3000);
    expect(properties['stage'], 'ready');
    expect(properties['nested'], '{"count":2}');
    expect(properties['items'], const [1, true, 'x']);
  });

  test('continues dispatching when one adapter fails', () async {
    final failing = _RecordingAdapter(throwOnTrack: true);
    final healthy = _RecordingAdapter();
    final analytics = AnalyticsService(adapters: [failing, healthy]);

    await analytics.trackEvent('workspace_opened');

    expect(failing.initializeCount, 1);
    expect(healthy.initializeCount, 1);
    expect(healthy.trackedEvents, hasLength(1));
    expect(healthy.trackedEvents.single['name'], 'workspace_opened');
  });

  test('app analytics builders keep event schema centralized', () {
    final event = AppAnalytics.promptSubmitted(
      agent: 'build',
      provider: 'openai',
      model: 'gpt-4.1',
      textLength: 12,
      hasParts: true,
      partCount: 2,
      variant: 'fast',
      format: 'jsonSchema',
    );
    final screen = AppAnalytics.workspaceHomeScreen(
      sessionCount: 3,
      hasActiveSession: true,
    );

    expect(event.name, AppAnalyticsEventName.promptSubmitted);
    expect(event.properties['agent'], 'build');
    expect(event.properties['part_count'], 2);
    expect(screen.name, AppAnalyticsScreenName.workspaceHome);
    expect(screen.properties['session_count'], 3);
  });

  test('analytics build config exposes user and event properties', () {
    const config = AnalyticsBuildConfig(
      provider: 'sensors',
      sensorsServerUrl: 'https://example.test/sa',
      customServerUrl: 'https://example.test/analytics',
      customApiKey: 'secret',
      customApiKeyHeader: 'authorization',
      channel: 'official',
      grayGroup: 'gray_a',
      isInternalUser: true,
    );

    expect(config.enabled, isTrue);
    expect(config.customServerUrl, 'https://example.test/analytics');
    expect(config.customApiKey, 'secret');
    expect(config.customApiKeyHeader, 'authorization');
    expect(config.userProperties['channel'], 'official');
    expect(config.userProperties['gray_group'], 'gray_a');
    expect(config.userProperties['is_internal_user'], isTrue);
    expect(config.eventProperties['channel'], 'official');
    expect(config.eventProperties['gray_group'], 'gray_a');
    expect(config.eventProperties['is_internal_user'], isTrue);
  });

  test('custom adapter posts normalized event payload to server', () async {
    final requests = <Map<String, Object?>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add({
        'path': request.uri.path,
        'apiKey': request.headers.value('x-api-key'),
        'payload': jsonDecode(body) as Map<String, dynamic>,
      });
      request.response.statusCode = 200;
      request.response.write('ok');
      await request.response.close();
    });

    final analytics = AnalyticsService.custom(
      endpoint:
          Uri.parse('http://${server.address.host}:${server.port}/events'),
      apiKey: 'demo-key',
    );

    await analytics.trackEvent(
      'workspace_opened',
      properties: {
        'count': 3,
        'nested': {'a': 1},
      },
    );
    await analytics.dispose();
    await server.close(force: true);

    expect(requests, hasLength(1));
    expect(requests.single['path'], '/events');
    expect(requests.single['apiKey'], 'demo-key');
    final payload = requests.single['payload']! as Map<String, dynamic>;
    expect(payload['type'], 'event');
    expect(payload['event'], 'workspace_opened');
    final properties = payload['properties']! as Map<String, dynamic>;
    expect(properties['count'], 3);
    expect(properties['nested'], '{"a":1}');
    expect(payload['source'], {
      'sdk': 'mobile_agent',
      'adapter': 'custom',
    });
  });
}
