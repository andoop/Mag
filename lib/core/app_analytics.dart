import 'dart:io';

import 'analytics.dart';

class AppAnalyticsEventName {
  static const String appInitialized = 'app_initialized';
  static const String firstInstall = 'first_install';
  static const String workspaceOpened = 'workspace_opened';
  static const String workspaceLeft = 'workspace_left';
  static const String projectCreated = 'project_created';
  static const String projectRenamed = 'project_renamed';
  static const String projectDeleted = 'project_deleted';
  static const String sessionCreated = 'session_created';
  static const String promptSubmitted = 'prompt_submitted';
  static const String providerConnected = 'provider_connected';
  static const String providerDisconnected = 'provider_disconnected';
  static const String modelSelected = 'model_selected';
  static const String shortcutPreviewOpened = 'shortcut_preview_opened';
}

class AppAnalyticsScreenName {
  static const String projectHome = 'project_home';
  static const String workspaceHome = 'workspace_home';
}

class AppAnalytics {
  const AppAnalytics._();

  static AnalyticsEvent appInitialized({
    required String themeMode,
    required int agentCount,
    required int providerConnectionCount,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.appInitialized,
      properties: {
        'platform': Platform.operatingSystem,
        'theme_mode': themeMode,
        'agent_count': agentCount,
        'provider_connection_count': providerConnectionCount,
      },
    );
  }

  static AnalyticsEvent firstInstall() {
    return const AnalyticsEvent(AppAnalyticsEventName.firstInstall);
  }

  static AnalyticsEvent workspaceOpened({
    required int sessionCount,
    required bool hasActiveSession,
    required bool openedFromSavedSession,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.workspaceOpened,
      properties: {
        'session_count': sessionCount,
        'has_active_session': hasActiveSession,
        'opened_from_saved_session': openedFromSavedSession,
      },
    );
  }

  static AnalyticsEvent workspaceLeft({
    required bool hadWorkspace,
    required int sessionCount,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.workspaceLeft,
      properties: {
        'had_workspace': hadWorkspace,
        'session_count': sessionCount,
      },
    );
  }

  static AnalyticsEvent projectCreated({
    required int nameLength,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.projectCreated,
      properties: {
        'name_length': nameLength,
      },
    );
  }

  static AnalyticsEvent projectRenamed({
    required int oldNameLength,
    required int newNameLength,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.projectRenamed,
      properties: {
        'old_name_length': oldNameLength,
        'new_name_length': newNameLength,
      },
    );
  }

  static AnalyticsEvent projectDeleted({
    required bool wasActiveWorkspace,
    required int sessionCount,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.projectDeleted,
      properties: {
        'was_active_workspace': wasActiveWorkspace,
        'session_count': sessionCount,
      },
    );
  }

  static AnalyticsEvent sessionCreated({
    required String agent,
    required int previousSessionCount,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.sessionCreated,
      properties: {
        'agent': agent,
        'previous_session_count': previousSessionCount,
      },
    );
  }

  static AnalyticsEvent promptSubmitted({
    required String agent,
    required String provider,
    required String model,
    required int textLength,
    required bool hasParts,
    required int partCount,
    String variant = '',
    String format = '',
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.promptSubmitted,
      properties: {
        'agent': agent,
        'variant': variant,
        'provider': provider,
        'model': model,
        'text_length': textLength,
        'has_parts': hasParts,
        'part_count': partCount,
        'format': format,
      },
    );
  }

  static AnalyticsEvent providerConnected({
    required String provider,
    required int modelCount,
    required bool selected,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.providerConnected,
      properties: {
        'provider': provider,
        'model_count': modelCount,
        'selected': selected,
      },
    );
  }

  static AnalyticsEvent providerDisconnected({
    required String provider,
    required int remainingProviderCount,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.providerDisconnected,
      properties: {
        'provider': provider,
        'remaining_provider_count': remainingProviderCount,
      },
    );
  }

  static AnalyticsEvent modelSelected({
    required String provider,
    required String model,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.modelSelected,
      properties: {
        'provider': provider,
        'model': model,
      },
    );
  }

  static AnalyticsEvent shortcutPreviewOpened({
    required int pathDepth,
  }) {
    return AnalyticsEvent(
      AppAnalyticsEventName.shortcutPreviewOpened,
      properties: {
        'path_depth': pathDepth,
      },
    );
  }

  static const AnalyticsScreen projectHomeScreen = AnalyticsScreen(
    AppAnalyticsScreenName.projectHome,
  );

  static AnalyticsScreen workspaceHomeScreen({
    required int sessionCount,
    required bool hasActiveSession,
  }) {
    return AnalyticsScreen(
      AppAnalyticsScreenName.workspaceHome,
      properties: {
        'session_count': sessionCount,
        'has_active_session': hasActiveSession,
      },
    );
  }
}
