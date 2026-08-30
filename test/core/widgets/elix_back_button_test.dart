import 'dart:ui' show Tristate;

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_back_button.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('back control exposes its destination and invokes its callback', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: Center(
          child: ElixBackButton(
            label: 'Groups',
            tooltip: 'Back to groups',
            semanticLabel: 'Back to groups',
            onPressed: () => calls++,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Back to groups'), findsOneWidget);
    expect(find.text('Groups'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ElixBackButton)).height,
      greaterThanOrEqualTo(36),
    );

    await tester.tap(find.byType(ElixBackButton));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('disabled back control remains visible but cannot activate', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.highContrastDark,
        home: const Center(
          child: ElixBackButton(
            tooltip: 'Back',
            semanticLabel: 'Back',
            onPressed: null,
          ),
        ),
      ),
    );

    final semantics = tester.getSemantics(find.bySemanticsLabel('Back'));
    expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
    expect(find.byIcon(FluentIcons.chrome_back), findsOneWidget);
  });
}
