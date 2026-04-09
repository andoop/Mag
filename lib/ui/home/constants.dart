part of '../home_page.dart';

typedef PromptReferenceAction = Future<void> Function(String);

class OcModelTag extends StatelessWidget {
  const OcModelTag({
    super.key,
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: oc.bgDeep,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: oc.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          height: 1.15,
          color: oc.muted,
          letterSpacing: 0.02,
        ),
      ),
    );
  }
}

BoxDecoration _panelDecoration(
  BuildContext context, {
  Color? background,
  double radius = 18,
  bool elevated = true,
}) {
  final oc = context.oc;
  return BoxDecoration(
    color: background ?? oc.panelBackground,
    borderRadius: BorderRadius.circular(radius),
    border: Border.fromBorderSide(BorderSide(color: oc.borderColor)),
    boxShadow: elevated
        ? [
            BoxShadow(
              color: oc.shadow,
              blurRadius: 10,
              offset: const Offset(0, 1),
            ),
          ]
        : null,
  );
}

ButtonStyle _compactActionButtonStyle(BuildContext context) {
  final oc = context.oc;
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
    side: BorderSide(color: oc.borderColor),
    shape: const StadiumBorder(),
    foregroundColor: oc.foreground,
    backgroundColor: oc.panelBackground.withOpacity(0.78),
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
    this.small = false,
    this.quiet = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool small;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final buttonSize = small ? 26.0 : 32.0;
    final padding = small ? 4.0 : 6.0;
    final iconSize = small ? 14.0 : 17.0;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      constraints: BoxConstraints(minWidth: buttonSize, minHeight: buttonSize),
      padding: EdgeInsets.all(padding),
      visualDensity: VisualDensity.compact,
      splashRadius: small ? 15 : 18,
      iconSize: iconSize,
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: quiet
            ? oc.panelBackground.withOpacity(0.34)
            : oc.panelBackground.withOpacity(0.78),
        side: BorderSide(
          color: quiet ? oc.borderColor.withOpacity(0.55) : oc.borderColor,
        ),
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
