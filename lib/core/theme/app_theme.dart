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
      acrylicBackgroundColor: colors.surfaceRaised,
      micaBackgroundColor: cardSurface,
      menuColor: colors.surfaceRaised,
      cardColor: colors.surfaceRaised,
      selectionColor: colors.brandPrimary.withValues(alpha: 0.34),
      shadowColor: colors.shadow,
      resources: _resourcesFor(brightness, colors),
      buttonTheme: _buttonTheme(colors, highContrast),
      dialogTheme: _dialogTheme(colors, highContrast),
      tooltipTheme: _tooltipTheme(colors, highContrast),
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

  static ResourceDictionary _resourcesFor(
    Brightness brightness,
    ElixSemanticColors colors,
  ) {
    if (brightness == Brightness.light) {
      return ResourceDictionary.light(
        textFillColorPrimary: colors.textPrimary,
        textFillColorSecondary: colors.textSecondary,
        textFillColorTertiary: colors.textMuted,
        textFillColorDisabled: colors.disabledText,
        controlFillColorDefault: colors.surfaceRaised,
        controlFillColorSecondary: colors.surfaceInteractive,
        controlFillColorTertiary: colors.surfaceBase,
        controlFillColorDisabled: colors.disabledSurface,
        controlFillColorInputActive: colors.surfaceRaised,
        controlSolidFillColorDefault: colors.surfaceRaised,
        controlStrokeColorDefault: colors.borderSubtle,
        controlStrokeColorSecondary: colors.borderInteractive,
        cardStrokeColorDefault: colors.borderSubtle,
        cardStrokeColorDefaultSolid: colors.borderSubtle,
        surfaceStrokeColorDefault: colors.borderStrong,
        surfaceStrokeColorFlyout: colors.borderSubtle,
        dividerStrokeColorDefault: colors.borderSubtle,
        focusStrokeColorOuter: colors.focusRing,
        focusStrokeColorInner: colors.canvas,
        cardBackgroundFillColorDefault: colors.surfaceRaised,
        cardBackgroundFillColorSecondary: colors.surfaceTinted,
        layerOnAcrylicFillColorDefault: colors.surfaceRaised,
        layerOnMicaBaseAltFillColorDefault: colors.surfaceTinted,
        solidBackgroundFillColorBase: colors.canvas,
        solidBackgroundFillColorSecondary: colors.canvasDeep,
        solidBackgroundFillColorTertiary: colors.surfaceBase,
        solidBackgroundFillColorQuarternary: colors.surfaceRaised,
        systemFillColorSuccess: colors.success,
        systemFillColorCaution: colors.warning,
        systemFillColorCritical: colors.error,
      );
    }

    return ResourceDictionary.dark(
      textFillColorPrimary: colors.textPrimary,
      textFillColorSecondary: colors.textSecondary,
      textFillColorTertiary: colors.textMuted,
      textFillColorDisabled: colors.disabledText,
      textOnAccentFillColorPrimary: colors.onBrand,
      textOnAccentFillColorSecondary: colors.onBrand.withValues(alpha: 0.82),
      textOnAccentFillColorDisabled: colors.disabledText,
      controlFillColorDefault: colors.surfaceRaised.withValues(alpha: 0.92),
      controlFillColorSecondary: colors.surfaceInteractive,
      controlFillColorTertiary: colors.surfaceBase,
      controlFillColorDisabled: colors.disabledSurface,
      controlFillColorInputActive: colors.surfaceRaised,
      controlStrongFillColorDefault: colors.textSecondary,
      controlStrongFillColorDisabled: colors.disabledText,
      controlSolidFillColorDefault: colors.surfaceRaised,
      subtleFillColorSecondary: colors.interactiveHover.withValues(alpha: 0.72),
      subtleFillColorTertiary: colors.interactivePressed.withValues(
        alpha: 0.76,
      ),
      accentFillColorDisabled: colors.disabledSurface,
      controlStrokeColorDefault: colors.borderSubtle,
      controlStrokeColorSecondary: colors.borderInteractive,
      cardStrokeColorDefault: colors.borderSubtle,
      cardStrokeColorDefaultSolid: colors.borderSubtle,
      controlStrongStrokeColorDefault: colors.borderStrong,
      controlStrongStrokeColorDisabled: colors.disabledBorder,
      surfaceStrokeColorDefault: colors.borderStrong,
      surfaceStrokeColorFlyout: colors.borderSubtle,
      dividerStrokeColorDefault: colors.borderSubtle,
      focusStrokeColorOuter: colors.focusRing,
      focusStrokeColorInner: colors.canvas,
      cardBackgroundFillColorDefault: colors.surfaceRaised,
      cardBackgroundFillColorSecondary: colors.surfaceTinted,
      smokeFillColorDefault: colors.shadow.withValues(alpha: 0.72),
      layerFillColorDefault: colors.surfaceRaised,
      layerFillColorAlt: colors.surfaceBase,
      layerOnAcrylicFillColorDefault: colors.surfaceRaised,
      layerOnMicaBaseAltFillColorDefault: colors.surfaceTinted,
      layerOnMicaBaseAltFillColorSecondary: colors.surfaceInteractive,
      layerOnMicaBaseAltFillColorTertiary: colors.surfaceRaised,
      solidBackgroundFillColorBase: colors.canvas,
      solidBackgroundFillColorSecondary: colors.canvasDeep,
      solidBackgroundFillColorTertiary: colors.surfaceBase,
      solidBackgroundFillColorQuarternary: colors.surfaceRaised,
      solidBackgroundFillColorBaseAlt: colors.canvasDeep,
      systemFillColorSuccess: colors.success,
      systemFillColorCaution: colors.warning,
      systemFillColorCritical: colors.error,
      systemFillColorSuccessBackground: colors.success.withValues(alpha: 0.14),
      systemFillColorCautionBackground: colors.warning.withValues(alpha: 0.14),
      systemFillColorCriticalBackground: colors.error.withValues(alpha: 0.14),
    );
  }

  static ButtonThemeData _buttonTheme(
    ElixSemanticColors colors,
    bool highContrast,
  ) {
    ShapeBorder shapeFor(Set<WidgetState> states) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: states.contains(WidgetState.focused)
            ? colors.focusRing
            : states.contains(WidgetState.disabled)
            ? colors.disabledBorder
            : colors.borderSubtle,
        width: states.contains(WidgetState.focused)
            ? (highContrast ? 4 : 2)
            : (highContrast ? 2 : 1),
      ),
    );

    return ButtonThemeData(
      defaultButtonStyle: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.disabledSurface;
          }
          if (states.contains(WidgetState.pressed)) {
            return colors.interactivePressed;
          }
          if (states.contains(WidgetState.hovered)) {
            return colors.interactiveHover;
          }
          return colors.surfaceRaised;
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.disabledText
              : colors.textPrimary,
        ),
        shape: WidgetStateProperty.resolveWith(shapeFor),
      ),
      filledButtonStyle: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.disabledSurface;
          }
          if (states.contains(WidgetState.pressed)) return colors.brandPressed;
          if (states.contains(WidgetState.hovered)) return colors.brandHover;
          return colors.brandPrimary;
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.disabledText
              : colors.onBrand,
        ),
        shape: WidgetStateProperty.resolveWith(shapeFor),
      ),
      iconButtonStyle: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return colors.interactivePressed;
          }
          if (states.contains(WidgetState.hovered)) {
            return colors.interactiveHover;
          }
          return Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? colors.disabledText
              : colors.textSecondary,
        ),
        shape: WidgetStateProperty.resolveWith(shapeFor),
      ),
    );
  }

  static ContentDialogThemeData _dialogTheme(
    ElixSemanticColors colors,
    bool highContrast,
  ) => ContentDialogThemeData(
    decoration: BoxDecoration(
      color: colors.surfaceRaised,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: highContrast ? colors.borderStrong : colors.borderInteractive,
        width: highContrast ? 2 : 1,
      ),
      boxShadow: highContrast
          ? const []
          : [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 32,
                offset: Offset(0, 16),
              ),
            ],
    ),
    barrierColor: colors.shadow.withValues(alpha: 0.78),
    padding: const EdgeInsets.all(20),
    titlePadding: const EdgeInsets.only(bottom: AppSpacing.sm),
    actionsSpacing: AppSpacing.sm,
    actionsPadding: const EdgeInsets.all(20),
    actionsDecoration: BoxDecoration(
      color: colors.surfaceTinted,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      border: Border(top: BorderSide(color: colors.borderSubtle)),
    ),
  );

  static TooltipThemeData _tooltipTheme(
    ElixSemanticColors colors,
    bool highContrast,
  ) => TooltipThemeData(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    waitDuration: const Duration(milliseconds: 650),
    decoration: BoxDecoration(
      color: colors.surfaceInteractive,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: highContrast ? colors.borderStrong : colors.borderSubtle,
        width: highContrast ? 2 : 1,
      ),
      boxShadow: highContrast
          ? const []
          : [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
    ),
    textStyle: supporting(color: colors.textPrimary).copyWith(fontSize: 12),
  );

  static BoxDecoration cardDecoration(BuildContext context, {Color? color}) {
    final isDark = context.isDarkTheme;
    final highContrast = context.isHighContrast;
    final flattenDenseSurfaces =
        context.elixWorkspaceVisuals.flattenDenseSurfaces;
    return BoxDecoration(
      color: color ?? context.elixCardSurface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: context.elixBorder.withValues(
          alpha: highContrast ? 1 : (isDark ? 0.6 : 1),
        ),
        width: highContrast ? 2 : 1,
      ),
      boxShadow: highContrast || flattenDenseSurfaces
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
  static const brandFontFamily = ElixTypography.wordmarkFamily;

  static const brandFontFallbacks = ElixTypography.wordmarkFallbacks;

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
    final ambientScale = context.elixWorkspaceVisuals.ambientGlowScale;
    if (context.isHighContrast) {
      return BoxDecoration(color: context.elixBackground);
    }
    return BoxDecoration(
      color: context.elixBackground,
      gradient: RadialGradient(
        center: const Alignment(-0.78, -0.86),
        radius: 1.45,
        colors: [
          AppColors.primary.withValues(
            alpha: (isDark ? 0.105 : 0.04) * ambientScale,
          ),
          AppColors.accent.withValues(
            alpha: (isDark ? 0.045 : 0.025) * ambientScale,
          ),
          context.elixBackground,
          context.elixColors.canvasDeep,
        ],
        stops: const [0.0, 0.22, 0.62, 1.0],
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
