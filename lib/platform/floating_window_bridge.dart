import 'dart:io';

import 'package:flutter/services.dart';

import '../core/models.dart';

class FloatingWindowConfig {
  const FloatingWindowConfig({
    required this.serverUri,
    required this.session,
    required this.workspace,
    required this.darkMode,
  });

  final Uri serverUri;
  final SessionInfo session;
  final WorkspaceInfo workspace;
  final bool darkMode;

  Map<String, Object?> toJson() => {
        'serverUri': serverUri.toString(),
        'sessionId': session.id,
        'sessionTitle': session.title,
        'workspaceId': workspace.id,
        'workspaceName': workspace.name,
        'workspaceDirectory': workspace.treeUri,
        'darkMode': darkMode,
      };
}

class FloatingWindowBridge {
  FloatingWindowBridge._();

  static const MethodChannel _channel =
      MethodChannel('mobile_agent/floating_window');

  /// True on Android (system overlay) and iOS 15+ (PiP).
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;

  /// Whether the user has granted the necessary permission.
  /// Android requires SYSTEM_ALERT_WINDOW; iOS PiP is always available.
  static Future<bool> hasPermission() async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('hasPermission') ?? false;
  }

  /// Opens the system permission settings screen (Android only).
  static Future<void> openPermissionSettings() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('openPermissionSettings');
  }

  /// Shows the floating window / PiP overlay.
  /// Returns `true` if the window was opened successfully.
  static Future<bool> show(FloatingWindowConfig config) async {
    if (!isSupported) return false;
    return await _channel.invokeMethod<bool>('show', config.toJson()) ?? false;
  }

  /// Hides the floating window / PiP overlay.
  static Future<void> hide() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('hide');
  }

  /// Moves the host app to the background so the floating window is visible.
  static Future<void> moveToBackground() async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('moveToBackground');
  }

  /// Requests notification permission (Android 13+).
  /// Safe to call at any time; no-ops on older versions or when already granted.
  static Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('requestNotificationPermission');
  }

  /// Shows a persistent notification telling the user the app is running in
  /// the background. Pass already-localized [title] and [body] strings.
  static Future<void> showBackgroundNotification({
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('showBackgroundNotification', {
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  /// Cancels the background notification shown by [showBackgroundNotification].
  static Future<void> hideBackgroundNotification() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('hideBackgroundNotification');
    } catch (_) {}
  }
}
