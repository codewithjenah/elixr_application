import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';

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

  Color get elixBackground {
    if (isHighContrast) {
      return isDarkTheme
          ? AppColors.backgroundHighContrastDark
          : AppColors.backgroundHighContrastLight;
    }
    return isDarkTheme ? AppColors.background : AppColors.backgroundLight;
  }

  Color get elixCardSurface {
    if (isHighContrast) {
      return isDarkTheme
          ? AppColors.cardSurfaceHighContrastDark
          : AppColors.cardSurfaceHighContrastLight;
    }
    return isDarkTheme ? AppColors.cardSurface : AppColors.cardSurfaceLight;
  }

  Color get elixPanelSurface {
    if (isHighContrast) {
      return isDarkTheme
          ? AppColors.cardSurfaceHighContrastDark
          : AppColors.cardSurfaceHighContrastLight;
    }
    return isDarkTheme ? AppColors.panelSurface : AppColors.panelSurfaceLight;
  }

  Color get elixTextPrimary {
    if (isHighContrast) {
      return isDarkTheme
          ? AppColors.textPrimaryHighContrastDark
          : AppColors.textPrimaryHighContrastLight;
    }
    return isDarkTheme ? AppColors.textPrimary : AppColors.textPrimaryLight;
  }

  Color get elixTextSecondary {
    if (isHighContrast) {
      return isDarkTheme
          ? AppColors.textSecondaryHighContrastDark
          : AppColors.textSecondaryHighContrastLight;
    }
    return isDarkTheme ? AppColors.textSecondary : AppColors.textSecondaryLight;
  }

  Color get elixBorder {
    if (isHighContrast) {
      return isDarkTheme
          ? AppColors.borderHighContrastDark
          : AppColors.borderHighContrastLight;
    }
    return isDarkTheme ? AppColors.border : AppColors.borderLight;
  }
}

abstract final class AppTheme {
  static FluentThemeData get dark {
    return _buildTheme(
      brightness: Brightness.dark,
      background: AppColors.background,
      cardSurface: AppColors.cardSurface,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
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
      highContrast: true,
    );
  }

  static FluentThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color cardSurface,
    required Color textPrimary,
    required Color textSecondary,
    required bool highContrast,
  }) {
    return FluentThemeData(
      brightness: brightness,
      accentColor: AccentColor.swatch({
        'normal': AppColors.primary,
        'dark': AppColors.primary,
        'light': AppColors.primarySoft,
      }),
      scaffoldBackgroundColor: background,
      micaBackgroundColor: cardSurface,
      extensions: [ElixContrastTheme(highContrast: highContrast)],
      typography: Typography.raw(
        title: TextStyle(
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        subtitle: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        body: TextStyle(color: textPrimary, fontSize: 16),
        bodyLarge: TextStyle(color: textSecondary, fontSize: 14),
        bodyStrong: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        caption: TextStyle(color: textSecondary, fontSize: 12),
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

  static TextStyle brandTitle({double fontSize = 28, Color? color}) =>
      TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        color: color ?? AppColors.primary,
      );

  static TextStyle get headingLarge =>
      const TextStyle(fontSize: 28, fontWeight: FontWeight.bold);

  static TextStyle get headingMedium =>
      const TextStyle(fontSize: 20, fontWeight: FontWeight.w600);

  static TextStyle get body => const TextStyle(fontSize: 16);

  static TextStyle get bodySecondary => const TextStyle(fontSize: 14);

  static TextStyle get caption => const TextStyle(fontSize: 12);

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
    return BoxDecoration(
      color: highContrast
          ? context.elixCardSurface
          : (isDark ? AppColors.panelSurface : context.elixCardSurface),
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
