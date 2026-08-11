import 'dart:ui';

abstract final class AppColors {
  static const background = Color(0xFF0D0D0F);
  static const cardSurface = Color(0xFF1A1A1F);
  static const primary = Color(0xFFFF4D8D);
  static const primarySoft = Color(0xFFFF7EB3);
  static const accent = Color(0xFF8B5CF6);
  static const accentSoft = Color(0xFFA78BFA);
  static const panelSurface = Color(0xFF16121F);
  static const textPrimary = Color(0xFFF5F5F5);
  static const textSecondary = Color(0xFFA0A0A8);
  static const success = Color(0xFF6EE7B7);
  static const error = Color(0xFFFF6B6B);
  static const warning = Color(0xFFFFB347);
  static const border = Color(0xFF2A2A32);

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
