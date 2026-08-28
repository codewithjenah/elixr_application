import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import 'elix_design_tokens.dart';

/// Theme extension so [ElixThemeContext] can detect high-contrast mode.
@immutable
class ElixContrastTheme extends ThemeExtension<ElixContrastTheme> {
  const ElixContrastTheme({required this.highContrast});

  final bool highContrast;

  @override
  ElixContrastTheme copyWith({bool? highContrast}) {
    return ElixContrastTheme(highContrast: highContrast ?? this.highContrast);
  }

  @override
  ElixContrastTheme lerp(ThemeExtension<ElixContrastTheme>? other, double t) {
    if (other is! ElixContrastTheme) return this;
    return t < 0.5 ? this : other;
  }
}

extension ElixThemeContext on BuildContext {
  bool get isDarkTheme => FluentTheme.of(this).brightness == Brightness.dark;

  bool get isHighContrast =>
      FluentTheme.of(this).extension<ElixContrastTheme>()?.highContrast ??
      false;

  ElixSemanticColors get elixColors {
    if (isHighContrast) {
      return isDarkTheme
          ? ElixSemanticColors.highContrastDark
          : ElixSemanticColors.highContrastLight;
    }
    return isDarkTheme ? ElixSemanticColors.dark : ElixSemanticColors.light;
  }

  Color get elixBackground => elixColors.canvas;

  Color get elixCardSurface => elixColors.surfaceRaised;

  Color get elixPanelSurface => elixColors.surfaceTinted;

  Color get elixTextPrimary => elixColors.textPrimary;

  Color get elixTextSecondary => elixColors.textSecondary;

  Color get elixBorder => elixColors.borderSubtle;
}

abstract final class AppTheme {
  static FluentThemeData get dark {
    return _buildTheme(
      brightness: Brightness.dark,
      background: AppColors.background,
      cardSurface: AppColors.cardSurface,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
      colors: ElixSemanticColors.dark,
      highContrast: false,
    );
  }

  static FluentThemeData get light {
    return _buildTheme(
      brightness: Brightness.light,
      background: AppColors.backgroundLight,
      cardSurface: AppColors.cardSurfaceLight,
      textPrimary: AppColors.textPrimaryLight,
      textSecondary: AppColors.textSecondaryLight,
      colors: ElixSemanticColors.light,
      highContrast: false,
    );
  }

  static FluentThemeData get highContrastDark {
    return _buildTheme(
      brightness: Brightness.dark,
      background: AppColors.backgroundHighContrastDark,
      cardSurface: AppColors.cardSurfaceHighContrastDark,
      textPrimary: AppColors.textPrimaryHighContrastDark,
      textSecondary: AppColors.textSecondaryHighContrastDark,
      colors: ElixSemanticColors.highContrastDark,
      highContrast: true,
    );
  }

  static FluentThemeData get highContrastLight {
    return _buildTheme(
      brightness: Brightness.light,
      background: AppColors.backgroundHighContrastLight,
      cardSurface: AppColors.cardSurfaceHighContrastLight,
      textPrimary: AppColors.textPrimaryHighContrastLight,
      textSecondary: AppColors.textSecondaryHighContrastLight,
      colors: ElixSemanticColors.highContrastLight,
      highContrast: true,
    );
  }

  static FluentThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color cardSurface,
    required Color textPrimary,
    required Color textSecondary,
    required ElixSemanticColors colors,
    required bool highContrast,
  }) {
    return FluentThemeData(
      brightness: brightness,
      accentColor: AccentColor.swatch({
        'normal': colors.brandPrimary,
        'dark': colors.brandPrimary,
        'light': colors.brandSecondary,
      }),
      scaffoldBackgroundColor: background,
      micaBackgroundColor: cardSurface,
      extensions: [ElixContrastTheme(highContrast: highContrast)],
      typography: Typography.raw(
        title: TextStyle(
          fontFamily: ElixTypography.fontFamily,
          fontFamilyFallback: ElixTypography.fontFallbacks,
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        subtitle: TextStyle(
          fontFamily: ElixTypography.fontFamily,
          fontFamilyFallback: ElixTypography.fontFallbacks,
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        body: TextStyle(
          fontFamily: ElixTypography.fontFamily,
          fontFamilyFallback: ElixTypography.fontFallbacks,
          color: textPrimary,
          fontSize: 16,
        ),
        bodyLarge: TextStyle(
          fontFamily: ElixTypography.fontFamily,
          fontFamilyFallback: ElixTypography.fontFallbacks,
          color: textSecondary,
          fontSize: 14,
        ),
        bodyStrong: TextStyle(
          fontFamily: ElixTypography.fontFamily,
          fontFamilyFallback: ElixTypography.fontFallbacks,
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        caption: TextStyle(
          fontFamily: ElixTypography.fontFamily,
          fontFamilyFallback: ElixTypography.fontFallbacks,
          color: textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  static BoxDecoration cardDecoration(BuildContext context, {Color? color}) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    return BoxDecoration(
      color: color ?? context.elixCardSurface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: context.elixBorder.withValues(
          alpha: highContrast ? 1 : (isDark ? 0.6 : 1),
        ),
        width: highContrast ? 2 : 1,
      ),
      boxShadow: highContrast
          ? const []
          : [
              BoxShadow(
                color: const Color(
                  0xFF000000,
                ).withValues(alpha: isDark ? 0.25 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
    );
  }

  static BoxDecoration panelDecoration(
    BuildContext context, {
    Color? color,
    Color? glow,
    bool highlighted = false,
  }) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final surface =
        color ??
        (highContrast
            ? context.elixCardSurface
            : (isDark ? AppColors.panelSurface : context.elixCardSurface));
    final borderColor = highlighted
        ? AppColors.primary.withValues(alpha: highContrast ? 1 : 0.55)
        : (highContrast
              ? context.elixBorder
              : (isDark
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : context.elixBorder));
    final glowColor = glow ?? AppColors.primary;
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor, width: highContrast ? 2 : 1),
      boxShadow: highContrast
          ? const []
          : [
              BoxShadow(
                color: const Color(
                  0xFF000000,
                ).withValues(alpha: isDark ? 0.28 : 0.08),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
              if (highlighted)
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.22),
                  blurRadius: 24,
                  spreadRadius: -4,
                ),
            ],
    );
  }

  /// Geometric Windows display face for ELIXR wordmarks.
  static const brandFontFamily = 'Bahnschrift';

  static const brandFontFallbacks = ['Segoe UI Variable Display', 'Segoe UI'];

  static TextStyle brandTitle({double fontSize = 28, Color? color}) =>
      TextStyle(
        fontFamily: brandFontFamily,
        fontFamilyFallback: brandFontFallbacks,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
        color: color ?? AppColors.primary,
        fontVariations: const [
          FontVariation('wght', 700),
          FontVariation('wdth', 85),
        ],
      );

  static TextStyle get headingLarge => const TextStyle(
    fontFamily: ElixTypography.fontFamily,
    fontFamilyFallback: ElixTypography.fontFallbacks,
    fontSize: 28,
    fontWeight: FontWeight.bold,
  );

  static TextStyle get headingMedium => const TextStyle(
    fontFamily: ElixTypography.fontFamily,
    fontFamilyFallback: ElixTypography.fontFallbacks,
    fontSize: 20,
    fontWeight: FontWeight.w600,
  );

  static TextStyle get body => const TextStyle(
    fontFamily: ElixTypography.fontFamily,
    fontFamilyFallback: ElixTypography.fontFallbacks,
    fontSize: 16,
  );

  static TextStyle get bodySecondary => const TextStyle(
    fontFamily: ElixTypography.fontFamily,
    fontFamilyFallback: ElixTypography.fontFallbacks,
    fontSize: 14,
  );

  static TextStyle get caption => const TextStyle(
    fontFamily: ElixTypography.fontFamily,
    fontFamilyFallback: ElixTypography.fontFallbacks,
    fontSize: 12,
  );

  static TextStyle displayHero(BuildContext context, {Color? color}) =>
      ElixTypography.displayHero(context, color: color);

  static TextStyle pageTitle(BuildContext context, {Color? color}) =>
      ElixTypography.pageTitle(context, color: color);

  static TextStyle sectionTitle(BuildContext context, {Color? color}) =>
      ElixTypography.sectionTitle(context, color: color);

  static TextStyle cardTitle({Color? color}) =>
      ElixTypography.cardTitle(color: color);

  static TextStyle supporting({Color? color}) =>
      ElixTypography.supporting(color: color);

  static TextStyle eyebrow({Color? color}) =>
      ElixTypography.eyebrow(color: color);

  static TextStyle metric(BuildContext context, {Color? color}) =>
      ElixTypography.metric(context, color: color);

  static TextStyle label({Color? color}) => ElixTypography.label(color: color);

  /// Subtle ambient wash used behind every primary ELIXR page.
  static BoxDecoration ambientPageBackground(BuildContext context) {
    final isDark = context.isDarkTheme;
    if (context.isHighContrast) {
      return BoxDecoration(color: context.elixBackground);
    }
    return BoxDecoration(
      color: context.elixBackground,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.primary.withValues(alpha: isDark ? 0.06 : 0.04),
          context.elixBackground,
          AppColors.accent.withValues(alpha: isDark ? 0.05 : 0.03),
        ],
        stops: const [0.0, 0.45, 1.0],
      ),
    );
  }

  /// Backward-compatible name for the former practice-only page background.
  @Deprecated('Use ambientPageBackground instead.')
  static BoxDecoration practicePageBackground(BuildContext context) =>
      ambientPageBackground(context);

  /// Premium session panel shell for guided practice.
  static BoxDecoration practicePanelDecoration(
    BuildContext context, {
    Color? accent,
  }) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final tint = accent ?? AppColors.accent;
    final panelSurface = isDark
        ? AppColors.panelSurface
        : context.elixCardSurface;
    final tintedPanelSurface = Color.alphaBlend(
      tint.withValues(alpha: isDark ? 0.055 : 0.035),
      panelSurface,
    );
    return BoxDecoration(
      color: highContrast ? context.elixCardSurface : null,
      gradient: highContrast
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [panelSurface, tintedPanelSurface, const Color(0xFF15121D)]
                  : [panelSurface, tintedPanelSurface, panelSurface],
              stops: const [0, 0.48, 1],
            ),
      borderRadius: BorderRadius.circular(AppSpacing.practiceSurfaceRadius),
      border: Border.all(
        color: highContrast
            ? context.elixBorder
            : tint.withValues(alpha: isDark ? 0.22 : 0.18),
        width: highContrast ? 2 : 1,
      ),
      boxShadow: highContrast
          ? const []
          : [
              BoxShadow(
                color: const Color(
                  0xFF000000,
                ).withValues(alpha: isDark ? 0.32 : 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
    );
  }

  /// Compact metric tile inside the session panel.
  static BoxDecoration practiceMetricTileDecoration(BuildContext context) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    return BoxDecoration(
      color: highContrast
          ? context.elixCardSurface
          : (isDark
                ? const Color(0xFF1E1A28).withValues(alpha: 0.72)
                : context.elixBorder.withValues(alpha: 0.12)),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: context.elixBorder.withValues(
          alpha: highContrast ? 1 : (isDark ? 0.45 : 0.35),
        ),
        width: highContrast ? 2 : 1,
      ),
    );
  }

  /// Grouped status / setup surfaces inside the session panel.
  static BoxDecoration practiceSectionSurface(
    BuildContext context, {
    Color? accent,
  }) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final tint = accent ?? AppColors.accent;
    return BoxDecoration(
      color: highContrast
          ? context.elixCardSurface
          : (isDark
                ? const Color(0xFF12101A).withValues(alpha: 0.65)
                : context.elixBorder.withValues(alpha: 0.08)),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: highContrast
            ? context.elixBorder
            : tint.withValues(alpha: isDark ? 0.2 : 0.14),
        width: highContrast ? 2 : 1,
      ),
    );
  }
}
