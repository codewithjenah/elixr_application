import 'dart:ui' show Tristate;

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:elixr_application/core/widgets/elix_card.dart';
import 'package:elixr_application/core/widgets/elix_panel_card.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_application/core/widgets/elix_sidebar_chrome.dart';
import 'package:elixr_application/core/widgets/elix_stat_card.dart';
import 'package:elixr_application/core/widgets/elix_summary_stat_card.dart';
import 'package:elixr_application/core/widgets/elix_tone_label.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(
    Widget child, {
    bool reducedMotion = false,
    FluentThemeData? theme,
  }) => FluentApp(
    theme: theme ?? AppTheme.dark,
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(1100, 700),
        disableAnimations: reducedMotion,
      ),
      child: Center(child: child),
    ),
  );

  testWidgets('interactive card activates from Enter and Space', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      host(
        ElixCard(
          onTap: () => activations++,
          semanticLabel: 'Practice card',
          child: const Text('Card'),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);

    expect(activations, 2);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Practice card'))
          .flagsCollection
          .isButton,
      isTrue,
    );
  });

  testWidgets('disabled interactive surfaces do not activate or accept focus', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      host(
        ElixHoverSurface(
          enabled: false,
          onTap: () => activations++,
          child: const Text('Disabled'),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.text('Disabled'));

    expect(activations, 0);
    expect(
      tester.getSemantics(find.text('Disabled')).flagsCollection.isEnabled !=
          Tristate.none,
      isTrue,
    );
  });

  testWidgets('reduced motion makes shared decorative animations immediate', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ElixPrimaryButton(label: 'Save', onPressed: () {}),
        reducedMotion: true,
      ),
    );

    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('elix-primary-button-surface')),
    );
    expect(surface.duration, Duration.zero);
    final innerTheme = tester
        .widgetList<FluentTheme>(find.byType(FluentTheme))
        .where(
          (theme) =>
              theme.data.fasterAnimationDuration == Duration.zero &&
              theme.data.fastAnimationDuration == Duration.zero,
        );
    expect(innerTheme, isNotEmpty);
  });

  testWidgets('primary button renders an accessible gradient surface', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(ElixPrimaryButton(label: 'Save', onPressed: () {})),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final foreground = button.style!.foregroundColor!;
    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('elix-primary-button-surface')),
    );
    final decoration = surface.decoration! as BoxDecoration;

    expect(decoration.gradient, isA<LinearGradient>());
    expect((decoration.gradient! as LinearGradient).colors, [
      ElixSemanticColors.dark.brandPrimary,
      ElixSemanticColors.dark.brandSecondary,
    ]);
    expect(decoration.borderRadius, BorderRadius.circular(12));
    expect(foreground.resolve({}), ElixSemanticColors.dark.onBrand);
  });

  testWidgets('primary button exposes its pressed surface from the keyboard', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(ElixPrimaryButton(label: 'Save', onPressed: () {})),
    );

    LinearGradient gradient() {
      final surface = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey('elix-primary-button-surface')),
      );
      return (surface.decoration! as BoxDecoration).gradient! as LinearGradient;
    }

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(gradient().colors.first, ElixSemanticColors.dark.brandPressed);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 150));
    expect(gradient().colors.first, ElixSemanticColors.dark.brandPrimary);
  });

  testWidgets('sidebar destination activates from keyboard and shows focus', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 260,
          child: ElixSidebarNavTile(
            label: 'Dashboard',
            icon: FluentIcons.home,
            isActive: false,
            isCollapsed: false,
            onTap: () => activations++,
          ),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(activations, 1);
    final decoration =
        tester
                .widget<AnimatedContainer>(
                  find.byKey(
                    const ValueKey('elix-sidebar-nav-surface-Dashboard'),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect((decoration.border! as Border).top.width, 2);
    expect(
      (decoration.border! as Border).top.color,
      ElixSemanticColors.dark.focusRing,
    );
  });

  testWidgets('high-contrast active sidebar fill stays opaque', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 260,
          child: ElixSidebarNavTile(
            label: 'Dashboard',
            icon: FluentIcons.home,
            isActive: true,
            isCollapsed: false,
            onTap: () {},
          ),
        ),
        theme: AppTheme.highContrastDark,
      ),
    );

    final decoration =
        tester
                .widget<AnimatedContainer>(
                  find.byKey(
                    const ValueKey('elix-sidebar-nav-surface-Dashboard'),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect(
      decoration.color,
      ElixSemanticColors.highContrastDark.surfaceSelected,
    );
    expect(decoration.color?.a, 1);
  });

  testWidgets('reduced motion skips sidebar hover flourish duration', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 260,
          child: ElixSidebarNavTile(
            label: 'Dashboard',
            icon: FluentIcons.home,
            isActive: false,
            isCollapsed: false,
            onTap: () {},
          ),
        ),
        reducedMotion: true,
      ),
    );

    final surface = tester.widget<AnimatedContainer>(
      find.byKey(const ValueKey('elix-sidebar-nav-surface-Dashboard')),
    );
    expect(surface.duration, Duration.zero);
  });

  testWidgets('sidebar destination activates from a pointer tap', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 260,
          child: ElixSidebarNavTile(
            label: 'Dashboard',
            icon: FluentIcons.home,
            isActive: false,
            isCollapsed: false,
            onTap: () => activations++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Dashboard'));
    expect(activations, 1);
  });

  testWidgets(
    'sidebar collapse control activates from keyboard and shows focus',
    (tester) async {
      var activations = 0;
      await tester.pumpWidget(
        host(
          ElixSidebarCollapseButton(
            isCollapsed: false,
            onTap: () => activations++,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(activations, 1);
      final decoration =
          tester
                  .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                  .decoration!
              as BoxDecoration;
      expect((decoration.border! as Border).top.width, ElixFocus.ringWidth);
      expect(
        (decoration.border! as Border).top.color,
        ElixSemanticColors.dark.focusRing,
      );
    },
  );

  testWidgets('loading button keeps its accessible action name and state', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ElixPrimaryButton(
          label: 'Save changes',
          onPressed: null,
          isLoading: true,
        ),
      ),
    );

    final semantics = tester.getSemantics(
      find.bySemanticsLabel('Save changes'),
    );
    expect(semantics.label, 'Save changes');
    expect(semantics.value, 'Loading');
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
  });

  testWidgets('high-contrast card focus changes the visible border', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ElixCard(onTap: () {}, child: const Text('Card')),
        theme: AppTheme.highContrastDark,
      ),
    );

    Border border() =>
        (tester
                        .widget<AnimatedContainer>(
                          find.byType(AnimatedContainer),
                        )
                        .decoration
                    as BoxDecoration)
                .border!
            as Border;

    expect(border().top.width, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(border().top.width, 4);
  });

  testWidgets('high-contrast hover surface focus changes the visible border', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ElixHoverSurface(onTap: () {}, child: const Text('Surface')),
        theme: AppTheme.highContrastLight,
      ),
    );

    Border border() =>
        (tester
                        .widget<AnimatedContainer>(
                          find.byType(AnimatedContainer),
                        )
                        .decoration
                    as BoxDecoration)
                .border!
            as Border;

    expect(border().top.width, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(border().top.width, 4);
  });

  testWidgets('neutral cards stay out of the tab order', (tester) async {
    await tester.pumpWidget(host(const ElixCard(child: Text('Overview'))));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    expect(find.byType(ElixCard), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Overview')).flagsCollection.isButton,
      isNot(isTrue),
    );
  });

  testWidgets('disabled interactive cards do not activate or take focus', (
    tester,
  ) async {
    var activations = 0;
    await tester.pumpWidget(
      host(
        ElixCard(
          enabled: false,
          onTap: () => activations++,
          semanticLabel: 'Locked card',
          child: const Text('Locked'),
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.tap(find.text('Locked'));

    expect(activations, 0);
  });

  testWidgets('selected cards use a leading bar, not colour alone', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ElixCard(
          selected: true,
          onTap: () {},
          semanticLabel: 'Selected session',
          child: const Text('Selected'),
        ),
      ),
    );

    expect(find.byKey(ElixCard.selectedMarkKey), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Selected session'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    final decoration =
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration
            as BoxDecoration;
    expect((decoration.border! as Border).top.width, 2);
  });

  testWidgets('highlighted cards use a restrained glow', (tester) async {
    await tester.pumpWidget(
      host(
        const ElixCard(
          variant: ElixCardVariant.highlighted,
          child: Text('Recommended'),
        ),
      ),
    );
    final decoration =
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: find.byType(ElixCard),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.boxShadow, isNotEmpty);
    expect(decoration.gradient, isNull);
  });

  testWidgets('high-contrast highlighted cards drop glow and stay opaque', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ElixCard(
          variant: ElixCardVariant.highlighted,
          child: Text('Recommended'),
        ),
        theme: AppTheme.highContrastDark,
      ),
    );
    final decoration =
        tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: find.byType(ElixCard),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(decoration.boxShadow, isEmpty);
    expect(decoration.gradient, isNull);
    expect(decoration.color?.a, 1);
  });

  testWidgets('metric cards use the large metric type scale', (tester) async {
    await tester.pumpWidget(
      host(
        const ElixStatCard(
          label: 'Sessions',
          value: '12',
          icon: FluentIcons.history,
        ),
      ),
    );

    final value = tester.widget<Text>(find.text('12'));
    expect(value.style?.fontSize, 44);
    expect(value.style?.fontWeight, FontWeight.w800);
  });

  testWidgets('summary stat cards use compact type and accent wash', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ElixSummaryStatCard(
          label: 'Planned Days',
          value: '4',
          detail: 'Training days this month',
          icon: FluentIcons.calendar,
          accent: Color(0xFF7C5CFF),
        ),
      ),
    );

    final value = tester.widget<Text>(find.text('4'));
    expect(value.style?.fontSize, 20);
    expect(value.style?.fontWeight, FontWeight.w800);
    expect(find.text('Training days this month'), findsOneWidget);

    final chrome = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final decoration = chrome.decoration! as BoxDecoration;
    expect(decoration.gradient, isNotNull);
    expect(decoration.borderRadius, BorderRadius.circular(14));
  });

  testWidgets('warning labels include an icon as well as colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ElixToneLabel(tone: ElixTone.warning, label: 'Camera missing'),
      ),
    );

    expect(find.text('Camera missing'), findsOneWidget);
    expect(find.byIcon(ElixToneCues.icon(ElixTone.warning)), findsOneWidget);
  });

  testWidgets('reduced motion makes card hover transitions immediate', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ElixCard(onTap: () {}, child: const Text('Card')),
        reducedMotion: true,
      ),
    );

    expect(
      tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).duration,
      Duration.zero,
    );
  });
}
