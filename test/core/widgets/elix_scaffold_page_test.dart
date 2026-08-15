import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_scaffold_page.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildPage(FluentThemeData theme) {
    return FluentApp(
      theme: theme,
      home: const ElixScaffoldPage(content: Text('Ambient content')),
    );
  }

  testWidgets('keeps Fluent scaffold transparent over the ambient background', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage(AppTheme.dark));

    final scaffoldContext = tester.element(find.byType(ScaffoldPage));
    expect(
      FluentTheme.of(scaffoldContext).scaffoldBackgroundColor,
      Colors.transparent,
    );
    expect(find.text('Ambient content'), findsOneWidget);
  });

  testWidgets('uses a solid high-contrast background', (tester) async {
    await tester.pumpWidget(buildPage(AppTheme.highContrastDark));

    final decoration = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((decoration) => decoration.color != null);
    expect(decoration.gradient, isNull);
  });
}
