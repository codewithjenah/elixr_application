import 'package:flutter/material.dart';

/// ELIXR pink identity on a dark Material 3 surface, for the Android Teacher app.
abstract final class TeacherColors {
  static const primary = Color(0xFFFF4D8D);
  static const primarySoft = Color(0xFFFF7EB3);
  static const background = Color(0xFF0D0D0F);
  static const surface = Color(0xFF1A1A1F);
  static const surfaceHigh = Color(0xFF221C28);
  static const textPrimary = Color(0xFFF5F5F5);
  static const textSecondary = Color(0xFFA0A0A8);
  static const error = Color(0xFFFF6B6B);
  static const success = Color(0xFF6EE7B7);
  static const border = Color(0xFF2A2A32);
}

ThemeData buildTeacherTheme() {
  const colorScheme = ColorScheme.dark(
    primary: TeacherColors.primary,
    onPrimary: Color(0xFF1A0510),
    secondary: TeacherColors.primarySoft,
    onSecondary: Color(0xFF1A0510),
    surface: TeacherColors.surface,
    onSurface: TeacherColors.textPrimary,
    error: TeacherColors.error,
    onError: Color(0xFF1A0505),
    outline: TeacherColors.border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: TeacherColors.background,
    canvasColor: TeacherColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: TeacherColors.background,
      foregroundColor: TeacherColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: TeacherColors.surface,
      labelStyle: const TextStyle(color: TeacherColors.textSecondary),
      floatingLabelStyle: const TextStyle(color: TeacherColors.primarySoft),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TeacherColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TeacherColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: TeacherColors.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // A global button style must remain usable in unbounded horizontal
        // layouts such as a Row. Full-width buttons opt in through their
        // bounded parent instead.
        minimumSize: const Size(64, 48),
        backgroundColor: TeacherColors.primary,
        foregroundColor: const Color(0xFF1A0510),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: TeacherColors.primarySoft,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TeacherColors.primary;
        }
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(const Color(0xFF1A0510)),
      side: const BorderSide(color: TeacherColors.textSecondary, width: 1.5),
    ),
  );
}
