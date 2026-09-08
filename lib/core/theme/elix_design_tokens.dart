import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';

/// Semantic colours for a single ELIXR appearance mode.
///
/// Feature code should resolve colours through [ElixThemeContext] instead of
/// selecting a dark/light constant itself. The legacy [AppColors] constants
/// remain available while existing screens are migrated in later phases.
@immutable
class ElixSemanticColors {
  const ElixSemanticColors({
    required this.canvas,
    required this.canvasDeep,
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceTinted,
    required this.surfaceInteractive,
    required this.surfaceSelected,
    required this.borderSubtle,
    required this.borderStrong,
    required this.borderInteractive,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.brandPrimary,
    required this.brandHover,
    required this.brandPressed,
    required this.brandSecondary,
    required this.onBrand,
    required this.focusRing,
    required this.milestone,
    required this.warning,
    required this.success,
    required this.error,
    required this.interactiveHover,
    required this.interactivePressed,
    required this.interactiveSelected,
    required this.disabledSurface,
    required this.disabledText,
    required this.disabledBorder,
    required this.glowPrimary,
    required this.glowSecondary,
    required this.shadow,
  });

  final Color canvas;
  final Color canvasDeep;
  final Color surfaceBase;
  final Color surfaceRaised;
  final Color surfaceTinted;
  final Color surfaceInteractive;
  final Color surfaceSelected;
  final Color borderSubtle;
  final Color borderStrong;
  final Color borderInteractive;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color brandPrimary;
  final Color brandHover;
  final Color brandPressed;
  final Color brandSecondary;
  final Color onBrand;
  final Color focusRing;

  /// Warm gold for earned ranks and milestones. Not a primary brand colour.
  final Color milestone;
  final Color warning;
  final Color success;
  final Color error;
  final Color interactiveHover;
  final Color interactivePressed;
  final Color interactiveSelected;
  final Color disabledSurface;
  final Color disabledText;
  final Color disabledBorder;
  final Color glowPrimary;
  final Color glowSecondary;
  final Color shadow;

  static const dark = ElixSemanticColors(
    canvas: AppColors.background,
    canvasDeep: AppColors.backgroundDeep,
    surfaceBase: AppColors.cardSurface,
    surfaceRaised: AppColors.cardSurface,
    surfaceTinted: AppColors.panelSurface,
    surfaceInteractive: AppColors.interactiveSurface,
    surfaceSelected: Color(0xFF32163F),
    borderSubtle: Color(0x663B2E5C),
    borderStrong: Color(0xFF8E65C5),
    borderInteractive: Color(0x99C052FF),
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
    brandPrimary: AppColors.primary,
    brandHover: AppColors.primarySoft,
    // Retains 4.5:1 contrast with the dark on-brand label when pressed.
    brandPressed: Color(0xFFEC2A9F),
    brandSecondary: AppColors.accent,
    onBrand: AppColors.background,
    focusRing: Color(0xFFFFFFFF),
    milestone: Color(0xFFF6C75A),
    warning: Color(0xFFF1A43C),
    success: AppColors.success,
    error: AppColors.error,
    interactiveHover: AppColors.interactiveSurface,
    interactivePressed: Color(0xFF2B2047),
    interactiveSelected: Color(0xFF32163F),
    disabledSurface: Color(0xFF211D2E),
    disabledText: Color(0xFF6F697C),
    disabledBorder: Color(0xFF393247),
    glowPrimary: Color(0x52FF2FA8),
    glowSecondary: Color(0x478C3DFF),
    shadow: Color(0xA6000000),
  );

  static const light = ElixSemanticColors(
    canvas: AppColors.backgroundLight,
    canvasDeep: Color(0xFFEAE7F0),
    surfaceBase: AppColors.backgroundLight,
    surfaceRaised: AppColors.cardSurfaceLight,
    surfaceTinted: AppColors.panelSurfaceLight,
    surfaceInteractive: Color(0xFFE8E1F3),
    surfaceSelected: Color(0xFFFFDDED),
    borderSubtle: AppColors.borderLight,
    borderStrong: Color(0xFF8A8A96),
    borderInteractive: Color(0xFF8C3DFF),
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryLight,
    textMuted: Color(0xFF777187),
    brandPrimary: AppColors.primary,
    brandHover: Color(0xFFFF79AD),
    brandPressed: Color(0xFFE83E7D),
    brandSecondary: AppColors.accent,
    onBrand: Color(0xFF1C1017),
    focusRing: Color(0xFF1C1C22),
    milestone: Color(0xFF8A6412),
    warning: Color(0xFFB75B00),
    success: Color(0xFF087A50),
    error: Color(0xFFC92F4A),
    interactiveHover: Color(0xFFE9E8EE),
    interactivePressed: Color(0xFFDCD9E5),
    interactiveSelected: Color(0xFFFFE0EC),
    disabledSurface: Color(0xFFE5E5EA),
    disabledText: Color(0xFF767680),
    disabledBorder: Color(0xFFB9B9C2),
    glowPrimary: Color(0x2EFF2FA8),
    glowSecondary: Color(0x248C3DFF),
    shadow: Color(0x24000000),
  );

  // Contrast modes deliberately use opaque black/white surfaces and borders.
  // Status colours remain separate semantic roles, not surface treatments.
  static const highContrastDark = ElixSemanticColors(
    canvas: Color(0xFF000000),
    canvasDeep: Color(0xFF000000),
    surfaceBase: Color(0xFF000000),
    surfaceRaised: Color(0xFF000000),
    surfaceTinted: Color(0xFF000000),
    surfaceInteractive: Color(0xFF000000),
    surfaceSelected: Color(0xFF000000),
    borderSubtle: Color(0xFFFFFFFF),
    borderStrong: Color(0xFFFFFFFF),
    borderInteractive: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFFFFFFF),
    textMuted: Color(0xFFFFFFFF),
    brandPrimary: Color(0xFFFFFFFF),
    brandHover: Color(0xFFFFFFFF),
    brandPressed: Color(0xFFFFFFFF),
    brandSecondary: Color(0xFFFFFFFF),
    onBrand: Color(0xFF000000),
    focusRing: Color(0xFFFFFFFF),
    milestone: Color(0xFFFFFF00),
    warning: Color(0xFF00FFFF),
    success: Color(0xFF00FF00),
    error: Color(0xFFFF6B6B),
    interactiveHover: Color(0xFF000000),
    interactivePressed: Color(0xFF000000),
    interactiveSelected: Color(0xFF000000),
    disabledSurface: Color(0xFF000000),
    disabledText: Color(0xFFFFFFFF),
    disabledBorder: Color(0xFFFFFFFF),
    glowPrimary: Color(0x00000000),
    glowSecondary: Color(0x00000000),
    shadow: Color(0x00000000),
  );

  static const highContrastLight = ElixSemanticColors(
    canvas: Color(0xFFFFFFFF),
    canvasDeep: Color(0xFFFFFFFF),
    surfaceBase: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceTinted: Color(0xFFFFFFFF),
    surfaceInteractive: Color(0xFFFFFFFF),
    surfaceSelected: Color(0xFFFFFFFF),
    borderSubtle: Color(0xFF000000),
    borderStrong: Color(0xFF000000),
    borderInteractive: Color(0xFF000000),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF000000),
    textMuted: Color(0xFF000000),
    brandPrimary: Color(0xFF000000),
    brandHover: Color(0xFF000000),
    brandPressed: Color(0xFF000000),
    brandSecondary: Color(0xFF000000),
    onBrand: Color(0xFFFFFFFF),
    focusRing: Color(0xFF000000),
    milestone: Color(0xFF7A5200),
    warning: Color(0xFF7A3000),
    success: Color(0xFF006B24),
    error: Color(0xFFB00020),
    interactiveHover: Color(0xFFFFFFFF),
    interactivePressed: Color(0xFFFFFFFF),
    interactiveSelected: Color(0xFFFFFFFF),
    disabledSurface: Color(0xFFFFFFFF),
    disabledText: Color(0xFF000000),
    disabledBorder: Color(0xFF000000),
    glowPrimary: Color(0x00000000),
    glowSecondary: Color(0x00000000),
    shadow: Color(0x00000000),
  );
}

/// Shared timing values. Route transitions keep their existing timing until a
/// later migration explicitly opts into [route].
abstract final class ElixMotion {
  static const micro = Duration(milliseconds: 120);
  static const standard = Duration(milliseconds: 180);
  static const route = Duration(milliseconds: 280);
  static const intro = Duration(milliseconds: 360);
  static const ambient = Duration(milliseconds: 6000);

  static const microCurve = Curves.easeOutCubic;
  static const standardCurve = Curves.easeInOutCubic;
  static const routeCurve = Curves.easeOut;
  static const introCurve = Curves.easeOutCubic;
  static const ambientCurve = Curves.easeInOutSine;

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}

/// Visible keyboard focus treatment. High contrast uses a thicker ring so
/// focus is never colour-only.
abstract final class ElixFocus {
  static const ringWidth = 2.0;
  static const ringWidthHighContrast = 4.0;
}

/// Role-level tuning for the shared ELIXR visual system.
///
/// Both workspaces resolve the same semantic colours and components. Teacher
/// pages only reduce atmospheric light and flatten routine dense surfaces so
/// operational information stays easy to scan.
@immutable
class ElixWorkspaceVisuals {
  const ElixWorkspaceVisuals({
    this.ambientGlowScale = 1,
    this.persistentGlowScale = 1,
    this.flattenDenseSurfaces = false,
  });

  const ElixWorkspaceVisuals.teacher()
    : ambientGlowScale = 0.72,
      persistentGlowScale = 0.72,
      flattenDenseSurfaces = true;

  final double ambientGlowScale;
  final double persistentGlowScale;
  final bool flattenDenseSurfaces;
}

class ElixWorkspaceVisualScope extends InheritedWidget {
  const ElixWorkspaceVisualScope({
    super.key,
    required this.visuals,
    required super.child,
  });

  const ElixWorkspaceVisualScope.teacher({super.key, required super.child})
    : visuals = const ElixWorkspaceVisuals.teacher();

  final ElixWorkspaceVisuals visuals;

  static ElixWorkspaceVisuals of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ElixWorkspaceVisualScope>()
          ?.visuals ??
      const ElixWorkspaceVisuals();

  @override
  bool updateShouldNotify(ElixWorkspaceVisualScope oldWidget) =>
      visuals != oldWidget.visuals;
}

extension ElixWorkspaceVisualContext on BuildContext {
  ElixWorkspaceVisuals get elixWorkspaceVisuals =>
      ElixWorkspaceVisualScope.of(this);
}

/// Status roles that must always ship with a non-colour cue (icon, mark, or
/// border change). [milestone] is warm gold for earned ranks only.
enum ElixTone { selected, warning, success, error, milestone }

abstract final class ElixToneCues {
  static IconData icon(ElixTone tone) => switch (tone) {
    ElixTone.selected => FluentIcons.check_mark,
    ElixTone.warning => FluentIcons.warning,
    ElixTone.success => FluentIcons.completed_solid,
    ElixTone.error => FluentIcons.error_badge,
    ElixTone.milestone => FluentIcons.trophy2,
  };

  static Color color(ElixSemanticColors palette, ElixTone tone) =>
      switch (tone) {
        ElixTone.selected => palette.brandPrimary,
        ElixTone.warning => palette.warning,
        ElixTone.success => palette.success,
        ElixTone.error => palette.error,
        ElixTone.milestone => palette.milestone,
      };
}

/// ELIXR's semantic type scale. It is intentionally separate from Fluent's
/// typography slots so later screen migration can be incremental.
abstract final class ElixTypography {
  static const fontFamily = 'Manrope';
  static const wordmarkFamily = 'Bahnschrift';
  static const fontFallbacks = ['Segoe UI Variable Text', 'Segoe UI'];
  static const wordmarkFallbacks = ['Segoe UI Variable Display', 'Segoe UI'];
  static const compactBreakpoint = 900.0;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactBreakpoint;

  static TextStyle displayHero(BuildContext context, {Color? color}) => _style(
    fontSize: isCompact(context) ? 40 : 52,
    lineHeight: isCompact(context) ? 43 : 53,
    fontWeight: FontWeight.w800,
    letterSpacing: isCompact(context) ? -0.7 : -1.2,
    color: color,
  );

  static TextStyle pageTitle(BuildContext context, {Color? color}) => _style(
    fontSize: isCompact(context) ? 30 : 36,
    lineHeight: isCompact(context) ? 34 : 40,
    fontWeight: FontWeight.w800,
    letterSpacing: isCompact(context) ? -0.3 : -0.6,
    color: color,
  );

  static TextStyle sectionTitle(BuildContext context, {Color? color}) => _style(
    fontSize: isCompact(context) ? 22 : 24,
    lineHeight: isCompact(context) ? 27 : 29,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: color,
  );

  static TextStyle cardTitle({Color? color}) => _style(
    fontSize: 18,
    lineHeight: 23,
    fontWeight: FontWeight.w700,
    color: color,
  );

  static TextStyle body({Color? color}) => _style(
    fontSize: 16,
    lineHeight: 24,
    fontWeight: FontWeight.w400,
    color: color,
  );

  static TextStyle supporting({Color? color}) => _style(
    fontSize: 14,
    lineHeight: 20,
    fontWeight: FontWeight.w400,
    color: color,
  );

  static TextStyle eyebrow({Color? color}) => _style(
    fontSize: 12,
    lineHeight: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.4,
    color: color,
  );

  static TextStyle metric(BuildContext context, {Color? color}) => _style(
    fontSize: isCompact(context) ? 36 : 44,
    lineHeight: isCompact(context) ? 38 : 44,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.5,
    color: color,
  );

  static TextStyle label({Color? color}) => _style(
    fontSize: 13,
    lineHeight: 17,
    fontWeight: FontWeight.w600,
    color: color,
  );

  static TextStyle _style({
    required double fontSize,
    required double lineHeight,
    required FontWeight fontWeight,
    double? letterSpacing,
    Color? color,
  }) => TextStyle(
    fontFamily: fontFamily,
    fontFamilyFallback: fontFallbacks,
    fontSize: fontSize,
    height: lineHeight / fontSize,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    color: color,
  );
}
