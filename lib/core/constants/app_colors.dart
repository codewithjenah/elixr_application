import 'dart:ui';

abstract final class AppColors {
  static const background = Color(0xFF080812);
  static const backgroundDeep = Color(0xFF0B0916);
  static const cardSurface = Color(0xFF141126);
  static const interactiveSurface = Color(0xFF231A3C);
  static const primary = Color(0xFFFF2FA8);
  static const primarySoft = Color(0xFFF43CB9);
  static const accent = Color(0xFF8C3DFF);
  static const accentSoft = Color(0xFF6A35D9);
  static const panelSurface = Color(0xFF1B1630);
  static const textPrimary = Color(0xFFF7F5FC);
  static const textSecondary = Color(0xFFAAA5B8);
  static const textMuted = Color(0xFF777187);
  static const success = Color(0xFF4FE3AF);
  static const error = Color(0xFFFF6B6B);
  static const warning = Color(0xFFF4B84A);
  static const border = Color(0xFF33284F);

  static const backgroundLight = Color(0xFFF3F3F6);
  static const cardSurfaceLight = Color(0xFFFFFFFF);
  static const panelSurfaceLight = Color(0xFFF0EDF6);
  static const textPrimaryLight = Color(0xFF1C1C22);
  static const textSecondaryLight = Color(0xFF5C5C66);
  static const borderLight = Color(0xFFE2E2E8);

  // High-contrast dark: pure white-on-black with a hard border.
  static const backgroundHighContrastDark = Color(0xFF000000);
  static const cardSurfaceHighContrastDark = Color(0xFF000000);
  static const textPrimaryHighContrastDark = Color(0xFFFFFFFF);
  static const textSecondaryHighContrastDark = Color(0xFFFFFFFF);
  static const borderHighContrastDark = Color(0xFFFFFFFF);

  // High-contrast light: pure black-on-white with a hard border.
  static const backgroundHighContrastLight = Color(0xFFFFFFFF);
  static const cardSurfaceHighContrastLight = Color(0xFFFFFFFF);
  static const textPrimaryHighContrastLight = Color(0xFF000000);
  static const textSecondaryHighContrastLight = Color(0xFF000000);
  static const borderHighContrastLight = Color(0xFF000000);
}
