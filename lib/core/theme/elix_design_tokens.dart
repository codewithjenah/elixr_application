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
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceTinted,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
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
  });

  final Color canvas;
  final Color surfaceBase;
  final Color surfaceRaised;
  final Color surfaceTinted;
  final Color borderSubtle;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color brandPrimary;
  final Color brandHover;
  final Color brandPressed;
  final Color brandSecondary;
  final Color onBrand;
  final Color focusRing;
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

  static const dark = ElixSemanticColors(
    canvas: AppColors.background,
    surfaceBase: AppColors.background,
    surfaceRaised: AppColors.cardSurface,
    surfaceTinted: AppColors.panelSurface,
    borderSubtle: AppColors.border,
    borderStrong: Color(0xFF686874),
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    brandPrimary: AppColors.primary,
    brandHover: Color(0xFFFF79AD),
    brandPressed: Color(0xFFE83E7D),
    brandSecondary: AppColors.accent,
    onBrand: Color(0xFF1C1017),
    focusRing: Color(0xFFFFFFFF),
    milestone: Color(0xFFA78BFA),
    warning: AppColors.warning,
    success: AppColors.success,
    error: AppColors.error,
    interactiveHover: Color(0xFF23232A),
    interactivePressed: Color(0xFF30303A),
    interactiveSelected: Color(0xFF301A29),
    disabledSurface: Color(0xFF27272D),
    disabledText: Color(0xFF7A7A84),
    disabledBorder: Color(0xFF41414A),
  );

  static const light = ElixSemanticColors(
    canvas: AppColors.backgroundLight,
    surfaceBase: AppColors.backgroundLight,
    surfaceRaised: AppColors.cardSurfaceLight,
    surfaceTinted: AppColors.panelSurfaceLight,
    borderSubtle: AppColors.borderLight,
    borderStrong: Color(0xFF8A8A96),
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryLight,
    brandPrimary: AppColors.primary,
    brandHover: Color(0xFFFF79AD),
    brandPressed: Color(0xFFE83E7D),
    brandSecondary: AppColors.accent,
    onBrand: Color(0xFF1C1017),
    focusRing: Color(0xFF1C1C22),
    milestone: Color(0xFF6D46D9),
    warning: Color(0xFFB75B00),
    success: Color(0xFF087A50),
    error: Color(0xFFC92F4A),
    interactiveHover: Color(0xFFE9E8EE),
    interactivePressed: Color(0xFFDCD9E5),
    interactiveSelected: Color(0xFFFFE0EC),
    disabledSurface: Color(0xFFE5E5EA),
    disabledText: Color(0xFF767680),
    disabledBorder: Color(0xFFB9B9C2),
  );

  // Contrast modes deliberately use opaque black/white surfaces and borders.
  // Status colours remain separate semantic roles, not surface treatments.
  static const highContrastDark = ElixSemanticColors(
    canvas: Color(0xFF000000),
    surfaceBase: Color(0xFF000000),
    surfaceRaised: Color(0xFF000000),
    surfaceTinted: Color(0xFF000000),
    borderSubtle: Color(0xFFFFFFFF),
    borderStrong: Color(0xFFFFFFFF),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFFFFFFF),
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
  );

  static const highContrastLight = ElixSemanticColors(
    canvas: Color(0xFFFFFFFF),
    surfaceBase: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceTinted: Color(0xFFFFFFFF),
    borderSubtle: Color(0xFF000000),
    borderStrong: Color(0xFF000000),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF000000),
    brandPrimary: Color(0xFF000000),
    brandHover: Color(0xFF000000),
    brandPressed: Color(0xFF000000),
    brandSecondary: Color(0xFF000000),
    onBrand: Color(0xFFFFFFFF),
    focusRing: Color(0xFF000000),
    milestone: Color(0xFF0000CC),
    warning: Color(0xFF7A3000),
    success: Color(0xFF006B24),
    error: Color(0xFFB00020),
    interactiveHover: Color(0xFFFFFFFF),
    interactivePressed: Color(0xFFFFFFFF),
    interactiveSelected: Color(0xFFFFFFFF),
    disabledSurface: Color(0xFFFFFFFF),
    disabledText: Color(0xFF000000),
    disabledBorder: Color(0xFF000000),
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

/// ELIXR's semantic type scale. It is intentionally separate from Fluent's
/// typography slots so later screen migration can be incremental.
abstract final class ElixTypography {
  static const fontFamily = 'Manrope';
  static const fontFallbacks = ['Segoe UI Variable Text', 'Segoe UI'];
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
