import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../store/app_controller.dart';
import '../ui/app_root.dart';
import '../ui/i18n.dart';
import '../ui/mag_splash.dart';
import '../ui/oc_theme.dart';

class MobileAgentApp extends StatefulWidget {
  const MobileAgentApp({super.key});

  @override
  State<MobileAgentApp> createState() => _MobileAgentAppState();
}

class _MobileAgentAppState extends State<MobileAgentApp> {
  late final AppController _controller;
  late final Future<void> _bootstrap;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _bootstrap = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.disposeController();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
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
          themeMode: _controller.themeMode,
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
      },
    );
  }
}
