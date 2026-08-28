import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_editorial_header.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildHeader({
    double width = 1000,
    ElixEditorialHeaderVariant variant = ElixEditorialHeaderVariant.standard,
  }) => FluentApp(
    theme: AppTheme.dark,
    home: MediaQuery(
      data: MediaQueryData(size: Size(width, 700)),
      child: ElixEditorialHeader(
        variant: variant,
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
    expect(find.byKey(ElixEyebrow.ruleKey), findsOneWidget);
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

  testWidgets('header variants use the Midnight Pour type scale', (
    tester,
  ) async {
    Future<TextStyle> headingStyle(ElixEditorialHeaderVariant variant) async {
      await tester.pumpWidget(buildHeader(variant: variant));
      final heading = tester.widget<Text>(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.textSpan?.toPlainText() == 'Midnight Pour',
        ),
      );
      return heading.textSpan!.style!;
    }

    expect((await headingStyle(ElixEditorialHeaderVariant.hero)).fontSize, 52);
    expect(
      (await headingStyle(ElixEditorialHeaderVariant.standard)).fontSize,
      36,
    );
    expect(
      (await headingStyle(ElixEditorialHeaderVariant.compact)).fontSize,
      24,
    );
    expect(
      (await headingStyle(ElixEditorialHeaderVariant.document)).fontSize,
      36,
    );

    await tester.pumpWidget(
      buildHeader(variant: ElixEditorialHeaderVariant.document),
    );
    final document = tester.widget<Text>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text && widget.textSpan?.toPlainText() == 'Midnight Pour',
      ),
    );
    expect(document.maxLines, 3);
  });
}
