import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../store/app_controller.dart';
import '../ui/home_page.dart';
import '../ui/i18n.dart';

class MobileAgentApp extends StatefulWidget {
  const MobileAgentApp({super.key});

  @override
  State<MobileAgentApp> createState() => _MobileAgentAppState();
}

class _MobileAgentAppState extends State<MobileAgentApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.disposeController();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => l(context, '移动代理', 'Mobile Agent'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh'),
        Locale('en'),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF111827),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5F4),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Color(0xFFF5F5F4),
          surfaceTintColor: Colors.transparent,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFFFAFAF9),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardTheme(
          elevation: 0,
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: Color(0x14000000)),
          ),
        ),
      ),
      home: HomePage(controller: _controller),
    );
  }
}
