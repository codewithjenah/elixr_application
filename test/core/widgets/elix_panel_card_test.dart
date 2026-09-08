import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/theme/elix_design_tokens.dart';
import 'package:elixr_application/core/widgets/elix_panel_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('accent bar supports LayoutBuilder content', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        home: SizedBox(
          width: 480,
          child: ElixPanelCard(
            accent: AppColors.primary,
            showAccentBar: true,
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  SizedBox(height: constraints.maxWidth > 0 ? 80 : 0),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('teacher routine panels are flat while hero panels keep depth', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: const ElixWorkspaceVisualScope.teacher(
          child: Column(
            children: [
              ElixPanelCard(child: Text('Routine')),
              ElixPanelCard(
                variant: ElixPanelVariant.hero,
                child: Text('Highlight'),
              ),
            ],
          ),
        ),
      ),
    );

    final panels = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) => container.decoration is BoxDecoration);
    final routine = panels.firstWhere(
      (container) =>
          (container.decoration! as BoxDecoration).borderRadius ==
          BorderRadius.circular(18),
    );
    final hero = panels.lastWhere(
      (container) =>
          (container.decoration! as BoxDecoration).borderRadius ==
          BorderRadius.circular(18),
    );

    expect((routine.decoration! as BoxDecoration).boxShadow, isEmpty);
    expect((hero.decoration! as BoxDecoration).boxShadow, isNotEmpty);
  });

  testWidgets('high contrast panels use an opaque strong border', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.highContrastDark,
        home: const ElixPanelCard(
          accent: AppColors.primary,
          showAccentBar: true,
          child: Text('High contrast'),
        ),
      ),
    );

    final panel = tester
        .widgetList<Container>(find.byType(Container))
        .firstWhere((container) => container.decoration is BoxDecoration);
    final border = (panel.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, ElixSemanticColors.highContrastDark.borderStrong);
    expect(border.top.color.a, 1);
  });
}
