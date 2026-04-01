import 'package:flutter/material.dart';

import '../store/app_controller.dart';
import 'home_page.dart';
import 'project_home_page.dart';

/// 对齐 OpenCode：`/` 为项目首页，进入工作区后再显示会话壳（含新建会话落地页与时间线）。
class AppRoot extends StatelessWidget {
  const AppRoot({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final workspace = controller.state.workspace;
        if (workspace == null) {
          return ProjectHomePage(controller: controller);
        }
        return HomePage(controller: controller);
      },
    );
  }
}
