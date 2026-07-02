import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';

extension ElixThemeContext on BuildContext {
  bool get isDarkTheme => FluentTheme.of(this).brightness == Brightness.dark;

  Color get elixBackground =>
      isDarkTheme ? AppColors.background : AppColors.backgroundLight;

  Color get elixCardSurface =>
      isDarkTheme ? AppColors.cardSurface : AppColors.cardSurfaceLight;

  Color get elixTextPrimary =>
      isDarkTheme ? AppColors.textPrimary : AppColors.textPrimaryLight;

  Color get elixTextSecondary =>
      isDarkTheme ? AppColors.textSecondary : AppColors.textSecondaryLight;

  Color get elixBorder => isDarkTheme ? AppColors.border : AppColors.borderLight;
}

abstract final class AppTheme {
  static FluentThemeData get dark {
    return _buildTheme(
      brightness: Brightness.dark,
      background: AppColors.background,
      cardSurface: AppColors.cardSurface,
      textPrimary: AppColors.textPrimary,
      textSecondary: AppColors.textSecondary,
    );
  }

  static FluentThemeData get light {
    return _buildTheme(
      brightness: Brightness.light,
      background: AppColors.backgroundLight,
      cardSurface: AppColors.cardSurfaceLight,
      textPrimary: AppColors.textPrimaryLight,
      textSecondary: AppColors.textSecondaryLight,
    );
  }

  static FluentThemeData _buildTheme({
    required Brightness brightness,
    required Color background,
    required Color cardSurface,
    required Color textPrimary,
    required Color textSecondary,
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
        body: TextStyle(
          color: textPrimary,
          fontSize: 16,
        ),
        bodyLarge: TextStyle(
          color: textSecondary,
          fontSize: 14,
        ),
        bodyStrong: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        caption: TextStyle(
          color: textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }

  static BoxDecoration cardDecoration(BuildContext context, {Color? color}) {
    final isDark = context.isDarkTheme;
    return BoxDecoration(
      color: color ?? context.elixCardSurface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: context.elixBorder.withValues(alpha: isDark ? 0.6 : 1),
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF000000).withValues(alpha: isDark ? 0.25 : 0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static TextStyle get headingLarge => const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
      );

  static TextStyle get headingMedium => const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
      );

  static TextStyle get body => const TextStyle(
        fontSize: 16,
      );

  static TextStyle get bodySecondary => const TextStyle(
        fontSize: 14,
      );

  static TextStyle get caption => const TextStyle(
        fontSize: 12,
      );
}
