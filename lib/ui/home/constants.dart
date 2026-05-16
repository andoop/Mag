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
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool small;
  final bool quiet;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    final buttonSize = small ? 26.0 : 32.0;
    final padding = small ? 4.0 : 6.0;
    final iconSize = small ? 14.0 : 16.0;
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
        fixedSize: Size(buttonSize, buttonSize),
        minimumSize: Size(buttonSize, buttonSize),
        maximumSize: Size(buttonSize, buttonSize),
        backgroundColor: quiet
            ? oc.panelBackground.withOpacity(0.34)
            : oc.panelBackground.withOpacity(0.78),
        side: BorderSide(
          color: quiet ? oc.borderColor.withOpacity(0.55) : oc.borderColor,
        ),
      ),
      icon: Icon(icon, color: iconColor),
    );
  }
}

class _SmoothExpansion extends StatefulWidget {
  const _SmoothExpansion({
    required this.open,
    required this.child,
  });

  static const duration = Duration(milliseconds: 240);
  static const curve = Curves.easeInOutCubic;

  final bool open;
  final Widget child;

  @override
  State<_SmoothExpansion> createState() => _SmoothExpansionState();
}

class _SmoothExpansionState extends State<_SmoothExpansion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _renderChild = false;
  Timer? _removeTimer;

  @override
  void initState() {
    super.initState();
    _renderChild = widget.open;
    _controller = AnimationController(
      vsync: this,
      duration: _SmoothExpansion.duration,
      value: widget.open ? 1 : 0,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: _SmoothExpansion.curve,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(covariant _SmoothExpansion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open) {
      _removeTimer?.cancel();
      _removeTimer = null;
      if (!_renderChild) setState(() => _renderChild = true);
      _controller.forward();
      return;
    }
    if (oldWidget.open && !widget.open) {
      _removeTimer?.cancel();
      _controller.reverse();
      _removeTimer = Timer(_SmoothExpansion.duration, () {
        if (!mounted || widget.open) return;
        setState(() => _renderChild = false);
      });
    }
  }

  @override
  void dispose() {
    _removeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_renderChild && !widget.open) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final t = _animation.value.clamp(0.0, 1.0);
        return ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            heightFactor: t,
            child: IgnorePointer(
              ignoring: !widget.open,
              child: Opacity(opacity: t, child: child),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _FloatingPillAction extends StatelessWidget {
  const _FloatingPillAction({
    required this.visible,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool visible;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !visible,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedScale(
            scale: visible ? 1 : 0.92,
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Tooltip(
                  message: label,
                  child: Material(
                    color: oc.bgDeep.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(999),
                    child: InkWell(
                      onTap: onPressed,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 16, color: oc.foregroundMuted),
                            const SizedBox(width: 2),
                            Text(
                              label,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: oc.foregroundMuted,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickCollapseButton extends StatelessWidget {
  const _QuickCollapseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final oc = context.oc;
    return Positioned(
      left: 6,
      right: 6,
      bottom: 6,
      child: Material(
        color: oc.panelBackground.withOpacity(context.isDarkMode ? 0.9 : 0.96),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  size: 16,
                  color: oc.foregroundMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  l(context, '收起', 'Collapse'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: oc.foregroundMuted,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
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

double _contextUsageRatio(
  SessionInfo? session,
  String model, {
  ProviderModelLimit? limit,
}) {
  if (session == null) return 0;
  final window = contextWindowForModel(model, limit: limit);
  if (window <= 0) return 0;
  return (session.totalTokens / window).clamp(0, 1);
}

String _contextUsageLabel(
  SessionInfo? session,
  String model, {
  ProviderModelLimit? limit,
}) {
  if (session == null) return '--';
  final window = contextWindowForModel(model, limit: limit);
  return '${formatTokenCount(session.totalTokens)} / ${formatTokenCount(window)}';
}
