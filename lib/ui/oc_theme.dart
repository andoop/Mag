import 'package:flutter/material.dart';

@immutable
class OcColors extends ThemeExtension<OcColors> {
  const OcColors({
    required this.pageBackground,
    required this.panelBackground,
    required this.bgDeep,
    required this.surface,
    required this.elevated,
    required this.selectedFill,
    required this.border,
    required this.text,
    required this.muted,
    required this.accent,
    required this.accentMuted,
    required this.green,
    required this.orange,
    required this.mutedPanel,
    required this.borderColor,
    required this.softBorderColor,
    required this.agentBubble,
    required this.userBubble,
    required this.foreground,
    required this.foregroundMuted,
    required this.foregroundHint,
    required this.foregroundFaint,
    required this.composerOptionBg,
    required this.optionDefaultBg,
    required this.permissionPreviewBg,
    required this.sendButtonBg,
    required this.sendButtonFg,
    required this.tagBlueGrey,
    required this.tagGreen,
    required this.tagBlue,
    required this.tagOrange,
    required this.shadow,
    required this.progressBg,
  });

  final Color pageBackground;
  final Color panelBackground;
  final Color bgDeep;
  final Color surface;
  final Color elevated;
  final Color selectedFill;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
  final Color accentMuted;
  final Color green;
  final Color orange;
  final Color mutedPanel;
  final Color borderColor;
  final Color softBorderColor;
  final Color agentBubble;
  final Color userBubble;
  final Color foreground;
  final Color foregroundMuted;
  final Color foregroundHint;
  final Color foregroundFaint;
  final Color composerOptionBg;
  final Color optionDefaultBg;
  final Color permissionPreviewBg;
  final Color sendButtonBg;
  final Color sendButtonFg;
  final Color tagBlueGrey;
  final Color tagGreen;
  final Color tagBlue;
  final Color tagOrange;
  final Color shadow;
  final Color progressBg;

  static OcColors of(BuildContext context) =>
      Theme.of(context).extension<OcColors>()!;

  static const light = OcColors(
    pageBackground: Color(0xFFF5F5F4),
    panelBackground: Color(0xFFFFFFFF),
    bgDeep: Color(0xFFF4F4F5),
    surface: Color(0xFFFFFFFF),
    elevated: Color(0xFFE4E4E7),
    selectedFill: Color(0xFFEFF6FF),
    border: Color(0xFFE4E4E7),
    text: Color(0xFF18181B),
    muted: Color(0xFF71717A),
    accent: Color(0xFF2563EB),
    accentMuted: Color(0xFF0891B2),
    green: Color(0xFF16A34A),
    orange: Color(0xFFEA580C),
    mutedPanel: Color(0xFFFAFAF9),
    borderColor: Color(0x14000000),
    softBorderColor: Color(0x0F000000),
    agentBubble: Color(0xFFFFFFFF),
    userBubble: Color(0xFFF0FDF4),
    foreground: Color(0xDD000000),
    foregroundMuted: Color(0x8A000000),
    foregroundHint: Color(0x73000000),
    foregroundFaint: Color(0x61000000),
    composerOptionBg: Color(0xFFF8FAFC),
    optionDefaultBg: Color(0xFFF9FAFB),
    permissionPreviewBg: Color(0xFFF5F3FF),
    sendButtonBg: Color(0xFF111827),
    sendButtonFg: Color(0xFFFFFFFF),
    tagBlueGrey: Color(0xFFCFD8DC),
    tagGreen: Color(0xFFC8E6C9),
    tagBlue: Color(0xFFBBDEFB),
    tagOrange: Color(0xFFFFE0B2),
    shadow: Color(0x05000000),
    progressBg: Color(0x0F000000),
  );

  static const dark = OcColors(
    pageBackground: Color(0xFF111113),
    panelBackground: Color(0xFF1C1C1E),
    bgDeep: Color(0xFF18181B),
    surface: Color(0xFF1C1C1E),
    elevated: Color(0xFF27272A),
    selectedFill: Color(0xFF172554),
    border: Color(0xFF27272A),
    text: Color(0xFFE4E4E7),
    muted: Color(0xFFA1A1AA),
    accent: Color(0xFF3B82F6),
    accentMuted: Color(0xFF22D3EE),
    green: Color(0xFF22C55E),
    orange: Color(0xFFF97316),
    mutedPanel: Color(0xFF18181B),
    borderColor: Color(0x20FFFFFF),
    softBorderColor: Color(0x14FFFFFF),
    agentBubble: Color(0xFF1C1C1E),
    userBubble: Color(0xFF052E16),
    foreground: Color(0xDEFFFFFF),
    foregroundMuted: Color(0x8AFFFFFF),
    foregroundHint: Color(0x73FFFFFF),
    foregroundFaint: Color(0x61FFFFFF),
    composerOptionBg: Color(0xFF1E1E22),
    optionDefaultBg: Color(0xFF1E1E22),
    permissionPreviewBg: Color(0xFF1E1B2E),
    sendButtonBg: Color(0xFF3B82F6),
    sendButtonFg: Color(0xFFFFFFFF),
    tagBlueGrey: Color(0xFF2D3748),
    tagGreen: Color(0xFF1A3A2A),
    tagBlue: Color(0xFF1E2D4D),
    tagOrange: Color(0xFF3D2B1A),
    shadow: Color(0x20000000),
    progressBg: Color(0x20FFFFFF),
  );

  @override
  OcColors copyWith({
    Color? pageBackground,
    Color? panelBackground,
    Color? bgDeep,
    Color? surface,
    Color? elevated,
    Color? selectedFill,
    Color? border,
    Color? text,
    Color? muted,
    Color? accent,
    Color? accentMuted,
    Color? green,
    Color? orange,
    Color? mutedPanel,
    Color? borderColor,
    Color? softBorderColor,
    Color? agentBubble,
    Color? userBubble,
    Color? foreground,
    Color? foregroundMuted,
    Color? foregroundHint,
    Color? foregroundFaint,
    Color? composerOptionBg,
    Color? optionDefaultBg,
    Color? permissionPreviewBg,
    Color? sendButtonBg,
    Color? sendButtonFg,
    Color? tagBlueGrey,
    Color? tagGreen,
    Color? tagBlue,
    Color? tagOrange,
    Color? shadow,
    Color? progressBg,
  }) {
    return OcColors(
      pageBackground: pageBackground ?? this.pageBackground,
      panelBackground: panelBackground ?? this.panelBackground,
      bgDeep: bgDeep ?? this.bgDeep,
      surface: surface ?? this.surface,
      elevated: elevated ?? this.elevated,
      selectedFill: selectedFill ?? this.selectedFill,
      border: border ?? this.border,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      green: green ?? this.green,
      orange: orange ?? this.orange,
      mutedPanel: mutedPanel ?? this.mutedPanel,
      borderColor: borderColor ?? this.borderColor,
      softBorderColor: softBorderColor ?? this.softBorderColor,
      agentBubble: agentBubble ?? this.agentBubble,
      userBubble: userBubble ?? this.userBubble,
      foreground: foreground ?? this.foreground,
      foregroundMuted: foregroundMuted ?? this.foregroundMuted,
      foregroundHint: foregroundHint ?? this.foregroundHint,
      foregroundFaint: foregroundFaint ?? this.foregroundFaint,
      composerOptionBg: composerOptionBg ?? this.composerOptionBg,
      optionDefaultBg: optionDefaultBg ?? this.optionDefaultBg,
      permissionPreviewBg: permissionPreviewBg ?? this.permissionPreviewBg,
      sendButtonBg: sendButtonBg ?? this.sendButtonBg,
      sendButtonFg: sendButtonFg ?? this.sendButtonFg,
      tagBlueGrey: tagBlueGrey ?? this.tagBlueGrey,
      tagGreen: tagGreen ?? this.tagGreen,
      tagBlue: tagBlue ?? this.tagBlue,
      tagOrange: tagOrange ?? this.tagOrange,
      shadow: shadow ?? this.shadow,
      progressBg: progressBg ?? this.progressBg,
    );
  }

  @override
  OcColors lerp(OcColors? other, double t) {
    if (other is! OcColors) return this;
    return OcColors(
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
      panelBackground: Color.lerp(panelBackground, other.panelBackground, t)!,
      bgDeep: Color.lerp(bgDeep, other.bgDeep, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      elevated: Color.lerp(elevated, other.elevated, t)!,
      selectedFill: Color.lerp(selectedFill, other.selectedFill, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      green: Color.lerp(green, other.green, t)!,
      orange: Color.lerp(orange, other.orange, t)!,
      mutedPanel: Color.lerp(mutedPanel, other.mutedPanel, t)!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      softBorderColor:
          Color.lerp(softBorderColor, other.softBorderColor, t)!,
      agentBubble: Color.lerp(agentBubble, other.agentBubble, t)!,
      userBubble: Color.lerp(userBubble, other.userBubble, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      foregroundMuted:
          Color.lerp(foregroundMuted, other.foregroundMuted, t)!,
      foregroundHint: Color.lerp(foregroundHint, other.foregroundHint, t)!,
      foregroundFaint:
          Color.lerp(foregroundFaint, other.foregroundFaint, t)!,
      composerOptionBg:
          Color.lerp(composerOptionBg, other.composerOptionBg, t)!,
      optionDefaultBg:
          Color.lerp(optionDefaultBg, other.optionDefaultBg, t)!,
      permissionPreviewBg:
          Color.lerp(permissionPreviewBg, other.permissionPreviewBg, t)!,
      sendButtonBg: Color.lerp(sendButtonBg, other.sendButtonBg, t)!,
      sendButtonFg: Color.lerp(sendButtonFg, other.sendButtonFg, t)!,
      tagBlueGrey: Color.lerp(tagBlueGrey, other.tagBlueGrey, t)!,
      tagGreen: Color.lerp(tagGreen, other.tagGreen, t)!,
      tagBlue: Color.lerp(tagBlue, other.tagBlue, t)!,
      tagOrange: Color.lerp(tagOrange, other.tagOrange, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      progressBg: Color.lerp(progressBg, other.progressBg, t)!,
    );
  }
}

extension OcThemeX on BuildContext {
  OcColors get oc => OcColors.of(this);
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}

ThemeData buildLightTheme() {
  const oc = OcColors.light;
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF111827),
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: oc.pageBackground,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: oc.pageBackground,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: oc.mutedPanel,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.transparent,
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: oc.panelBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: oc.borderColor),
      ),
    ),
    dividerTheme: DividerThemeData(color: oc.border),
    extensions: const [OcColors.light],
  );
}

ThemeData buildDarkTheme() {
  const oc = OcColors.dark;
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF111827),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: oc.pageBackground,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: oc.pageBackground,
      surfaceTintColor: Colors.transparent,
      foregroundColor: oc.text,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: oc.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.transparent,
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: oc.panelBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: oc.borderColor),
      ),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: oc.surface),
    dialogTheme: DialogTheme(
      backgroundColor: oc.surface,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(color: oc.border),
    popupMenuTheme: PopupMenuThemeData(
      color: oc.surface,
      surfaceTintColor: Colors.transparent,
    ),
    extensions: const [OcColors.dark],
  );
}
