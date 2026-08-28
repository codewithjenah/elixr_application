import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_editorial_header.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildHeader({double width = 1000}) => FluentApp(
    theme: AppTheme.dark,
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 700)),
      child: ElixEditorialHeader(
        eyebrow: 'PRACTICE',
        heading: 'Midnight ',
        accentHeading: 'Pour',
        subtitle: 'Build confident flair movement.',
        actions: [
          Button(onPressed: () {}, child: const Text('Start')),
          Button(onPressed: () {}, child: const Text('Details')),
        ],
      ),
    ),
  );

  testWidgets('exposes one semantic header with all editorial content', (
    tester,
  ) async {
    await tester.pumpWidget(buildHeader());

    expect(find.text('PRACTICE'), findsOneWidget);
    expect(find.text('Midnight Pour', findRichText: true), findsOneWidget);
    expect(find.text('Build confident flair movement.'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Midnight Pour'))
          .flagsCollection
          .isHeader,
      isTrue,
    );
    final heading = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.textSpan?.toPlainText() == 'Midnight Pour',
      ),
    );
    expect(heading.maxLines, 2);
  });

  testWidgets('stacks controls in compact space without dropping actions', (
    tester,
  ) async {
    await tester.pumpWidget(buildHeader(width: 500));

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.byType(Column), findsWidgets);
  });
}
