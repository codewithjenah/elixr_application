import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  double contrastRatio(Color foreground, Color background) {
    final light = foreground.computeLuminance();
    final dark = background.computeLuminance();
    final lighter = light > dark ? light : dark;
    final darker = light > dark ? dark : light;
    return (lighter + 0.05) / (darker + 0.05);
  }

  test(
    'semantic modes preserve opaque high-contrast surfaces and distinct roles',
    () {
      final modes = [
        ElixSemanticColors.dark,
        ElixSemanticColors.light,
        ElixSemanticColors.highContrastDark,
        ElixSemanticColors.highContrastLight,
      ];

      expect(modes.map((mode) => mode.canvas).toSet(), hasLength(4));
      for (final mode in [
        ElixSemanticColors.highContrastDark,
        ElixSemanticColors.highContrastLight,
      ]) {
        expect(mode.canvas.a, 1);
        expect(mode.surfaceBase.a, 1);
        expect(mode.surfaceRaised.a, 1);
        expect(mode.surfaceTinted.a, 1);
        expect(mode.borderSubtle.a, 1);
        expect(mode.milestone, isNot(mode.warning));
      }
    },
  );

  test('normal text, brand states, and focus roles meet contrast floors', () {
    for (final mode in [
      ElixSemanticColors.dark,
      ElixSemanticColors.light,
      ElixSemanticColors.highContrastDark,
      ElixSemanticColors.highContrastLight,
    ]) {
      expect(
        contrastRatio(mode.textPrimary, mode.canvas),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(mode.textSecondary, mode.canvas),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(mode.onBrand, mode.brandPrimary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(mode.onBrand, mode.brandHover),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(mode.onBrand, mode.brandPressed),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(mode.focusRing, mode.surfaceRaised),
        greaterThanOrEqualTo(3),
      );
    }
  });

  testWidgets('resolves all four semantic colour modes', (tester) async {
    Future<ElixSemanticColors> resolve(FluentThemeData theme) async {
      late ElixSemanticColors colors;
      await tester.pumpWidget(
        FluentApp(
          key: UniqueKey(),
          theme: theme,
          home: Builder(
            builder: (context) {
              colors = context.elixColors;
              return const SizedBox();
            },
          ),
        ),
      );
      return colors;
    }

    expect(
      (await resolve(AppTheme.dark)).canvas,
      ElixSemanticColors.dark.canvas,
    );
    expect(
      (await resolve(AppTheme.light)).canvas,
      ElixSemanticColors.light.canvas,
    );
    expect(
      (await resolve(AppTheme.highContrastDark)).borderStrong,
      const Color(0xFFFFFFFF),
    );
    expect(
      (await resolve(AppTheme.highContrastLight)).borderStrong,
      const Color(0xFF000000),
    );
  });

  testWidgets('uses the specified typography metrics and compact branch', (
    tester,
  ) async {
    Future<(TextStyle, TextStyle)> stylesFor(double width) async {
      late TextStyle hero;
      late TextStyle metric;
      await tester.pumpWidget(
        FluentApp(
          home: MediaQuery(
            data: MediaQueryData(size: Size(width, 700)),
            child: Builder(
              builder: (context) {
                hero = ElixTypography.displayHero(context);
                metric = ElixTypography.metric(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return (hero, metric);
    }

    final desktop = await stylesFor(900);
    expect(desktop.$1.fontFamily, 'Manrope');
    expect(desktop.$1.fontFamilyFallback, [
      'Segoe UI Variable Text',
      'Segoe UI',
    ]);
    expect(desktop.$1.fontSize, 52);
    expect(desktop.$1.height, closeTo(53 / 52, 0.0001));
    expect(desktop.$1.fontWeight, FontWeight.w800);
    expect(desktop.$1.letterSpacing, -1.2);
    expect(desktop.$2.fontSize, 44);
    expect(desktop.$2.letterSpacing, -0.5);

    final compact = await stylesFor(899);
    expect(compact.$1.fontSize, 40);
    expect(compact.$1.height, closeTo(43 / 40, 0.0001));
    expect(compact.$1.letterSpacing, -0.7);
    expect(compact.$2.fontSize, 36);
    expect(ElixTypography.eyebrow().letterSpacing, 1.4);
  });
}
