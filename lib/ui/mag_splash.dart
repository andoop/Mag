import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';

import 'i18n.dart';
import 'oc_theme.dart';

/// 首帧之后、本地服务与配置加载完成前的过渡界面，与原生启动页配色一致。
class MagSplashPage extends StatelessWidget {
  const MagSplashPage({super.key, this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final brightness = PlatformDispatcher.instance.platformBrightness;
    final oc = brightness == Brightness.dark ? OcColors.dark : OcColors.light;
    return Scaffold(
      backgroundColor: oc.pageBackground,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/branding/app_icon.png',
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Mag',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                    color: oc.text.withOpacity(0.88),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l(context, '正在启动…', 'Starting…'),
                  style: TextStyle(
                    fontSize: 13,
                    color: oc.muted,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade700,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: oc.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
