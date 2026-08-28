import 'dart:ui' show Tristate;

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:elixr_application/core/widgets/elix_card.dart';
import 'package:elixr_application/core/widgets/elix_panel_card.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
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
      data: MediaQueryData(disableAnimations: reducedMotion),
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

  testWidgets('primary button resolves accessible brand interaction states', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(ElixPrimaryButton(label: 'Save', onPressed: () {})),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    final background = button.style!.backgroundColor!;
    final foreground = button.style!.foregroundColor!;

    expect(
      background.resolve({WidgetState.hovered}),
      ElixSemanticColors.dark.brandHover,
    );
    expect(
      background.resolve({WidgetState.pressed}),
      ElixSemanticColors.dark.brandPressed,
    );
    expect(foreground.resolve({}), ElixSemanticColors.dark.onBrand);
  });

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
}
