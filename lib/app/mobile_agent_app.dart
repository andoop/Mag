import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/analytics.dart';
import '../core/analytics_bootstrap.dart';
import '../store/app_controller.dart';
import '../ui/app_root.dart';
import '../ui/i18n.dart';
import '../ui/mag_splash.dart';
import '../ui/oc_theme.dart';

class MobileAgentApp extends StatefulWidget {
  const MobileAgentApp({
    super.key,
    this.analytics,
    this.analyticsConfig,
  });

  final AnalyticsService? analytics;
  final AnalyticsBuildConfig? analyticsConfig;

  @override
  State<MobileAgentApp> createState() => _MobileAgentAppState();
}

class _MobileAgentAppState extends State<MobileAgentApp> {
  late final AppController _controller;
  late final Future<void> _bootstrap;
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    _controller = AppController(
      analytics: widget.analytics,
      analyticsConfig: widget.analyticsConfig,
    );
    _themeMode = _controller.themeMode;
    _controller.addListener(_handleControllerChanged);
    _bootstrap = _controller.initialize();
  }

  void _handleControllerChanged() {
    final nextThemeMode = _controller.themeMode;
    if (nextThemeMode == _themeMode) return;
    setState(() => _themeMode = nextThemeMode);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.disposeController();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => l(context, 'Mag', 'Mag'),
      themeAnimationDuration: Duration.zero,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
      ],
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: _themeMode,
      home: FutureBuilder<void>(
        future: _bootstrap,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const MagSplashPage();
          }
          if (snapshot.hasError) {
            return MagSplashPage(error: snapshot.error);
          }
          return AppRoot(controller: _controller);
        },
      ),
    );
  }
}
