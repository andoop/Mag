import 'package:flutter/material.dart';

import 'core/analytics_bootstrap.dart';
import 'app/mobile_agent_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final analyticsBootstrap = await createAnalyticsBootstrap();
  runApp(MobileAgentApp(
    analytics: analyticsBootstrap.analytics,
    analyticsConfig: analyticsBootstrap.config,
  ));
}
