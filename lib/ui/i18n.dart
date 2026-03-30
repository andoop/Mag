import 'package:flutter/material.dart';

bool isZhLocale(BuildContext context) {
  final locale = Localizations.maybeLocaleOf(context);
  return locale?.languageCode.toLowerCase().startsWith('zh') ?? true;
}

String l(BuildContext context, String zh, String en) {
  return isZhLocale(context) ? zh : en;
}

String modelCountText(BuildContext context, int count) {
  return isZhLocale(context) ? '$count 个模型' : '$count models';
}

String todoStatusText(BuildContext context, String status) {
  switch (status) {
    case 'pending':
      return l(context, '待处理', 'Pending');
    case 'in_progress':
      return l(context, '进行中', 'In Progress');
    case 'completed':
      return l(context, '已完成', 'Completed');
    case 'cancelled':
      return l(context, '已取消', 'Cancelled');
    default:
      return status;
  }
}
