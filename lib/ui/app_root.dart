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
        return WillPopScope(
          onWillPop: () async {
            final s = controller.state;
            if (s.workspace == null) {
              return true;
            }
            // 与 AppBar 左上角返回一致：直接回到项目首页，而非新建会话落地页。
            try {
              await controller.leaveProject();
            } catch (_) {
              // 保留在当前界面，避免误退出
            }
            return false;
          },
          child: workspace == null
              ? ProjectHomePage(controller: controller)
              : HomePage(controller: controller),
        );
      },
    );
  }
}
