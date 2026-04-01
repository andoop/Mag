part of '../home_page.dart';

typedef PromptReferenceAction = Future<void> Function(String);

const Color _kPageBackground = Color(0xFFF5F5F4);
const Color _kPanelBackground = Colors.white;

/// 底部菜单、会话列表等 Sheet（浅色，与 [_kPageBackground] 协调）
const Color kOcBgDeep = Color(0xFFF4F4F5);
const Color kOcSurface = Color(0xFFFFFFFF);
const Color kOcElevated = Color(0xFFE4E4E7);
const Color kOcSelectedFill = Color(0xFFEFF6FF);
const Color kOcBorder = Color(0xFFE4E4E7);
const Color kOcText = Color(0xFF18181B);
const Color kOcMuted = Color(0xFF71717A);
const Color kOcAccent = Color(0xFF2563EB);
const Color kOcAccentMuted = Color(0xFF0891B2);
const Color kOcGreen = Color(0xFF16A34A);
const Color kOcOrange = Color(0xFFEA580C);
const Color _kMutedPanel = Color(0xFFFAFAF9);
const Color _kBorderColor = Color(0x14000000);
const Color _kSoftBorderColor = Color(0x0F000000);
const Color _kAgentBubble = Colors.white;
const Color _kUserBubble = Color(0xFFF0FDF4);

/// 小标签样式：浅底细边框（用于 Free / Latest）。
class OcModelTag extends StatelessWidget {
  const OcModelTag({
    super.key,
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: kOcBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          height: 1.15,
          color: kOcMuted,
          letterSpacing: 0.02,
        ),
      ),
    );
  }
}

BoxDecoration _panelDecoration({
  Color background = _kPanelBackground,
  double radius = 18,
  bool elevated = true,
}) {
  return BoxDecoration(
    color: background,
    borderRadius: BorderRadius.circular(radius),
    border: const Border.fromBorderSide(BorderSide(color: _kBorderColor)),
    boxShadow: elevated
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 1),
            ),
          ]
        : null,
  );
}

ButtonStyle _compactActionButtonStyle(BuildContext context) {
  return OutlinedButton.styleFrom(
    fixedSize: const Size.fromHeight(30),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
    side: const BorderSide(color: _kBorderColor),
    shape: const StadiumBorder(),
    foregroundColor: Colors.black87,
    backgroundColor: Colors.white.withOpacity(0.78),
  );
}

ButtonStyle _compactFilledActionButtonStyle(BuildContext context) {
  return FilledButton.styleFrom(
    fixedSize: const Size.fromHeight(30),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
    textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 11.5,
        ),
    shape: const StadiumBorder(),
  );
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14),
          const SizedBox(width: 5),
        ],
        Text(label),
      ],
    );
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: _compactFilledActionButtonStyle(context),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: _compactActionButtonStyle(context),
      child: child,
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: const EdgeInsets.all(6),
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
      iconSize: 17,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: Colors.white.withOpacity(0.78),
        side: const BorderSide(color: _kBorderColor),
      ),
      icon: Icon(icon),
    );
  }
}

String _toolStatusLabel(BuildContext context, String status) {
  switch (status) {
    case 'running':
      return l(context, '运行中', 'Running');
    case 'pending':
      return l(context, '等待中', 'Pending');
    case 'completed':
      return l(context, '已完成', 'Completed');
    case 'error':
      return l(context, '错误', 'Error');
    default:
      return status;
  }
}

double _contextUsageRatio(SessionInfo? session, String model) {
  if (session == null) return 0;
  final window = inferContextWindow(model);
  if (window <= 0) return 0;
  return (session.totalTokens / window).clamp(0, 1);
}

String _contextUsageLabel(SessionInfo? session, String model) {
  if (session == null) return '--';
  final window = inferContextWindow(model);
  return '${formatTokenCount(session.totalTokens)} / ${formatTokenCount(window)}';
}
