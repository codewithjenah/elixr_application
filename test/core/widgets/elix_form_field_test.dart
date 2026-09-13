import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_form_field.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

void main() {
  Widget host(Widget child, {required FluentThemeData theme}) => FluentApp(
    theme: theme,
    home: ElixShadThemeBridge(
      child: Center(child: SizedBox(width: 360, child: child)),
    ),
  );

  testWidgets('text fields expose their label, helper, and required cue', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ElixTextField(
          label: 'Display name',
          placeholder: 'Add a name',
          helperText: 'Shown to your class.',
          required: true,
        ),
        theme: AppTheme.light,
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == 'Display name *',
      ),
      findsOneWidget,
    );
    expect(find.text('Shown to your class.'), findsOneWidget);
    expect(find.byType(shad.ShadInput), findsOneWidget);
  });

  testWidgets('validation replaces helper text and announces the error', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ElixTextArea(
          label: 'Instructions',
          helperText: 'Use short steps.',
          errorText: 'Instructions are required.',
        ),
        theme: AppTheme.dark,
      ),
    );

    expect(find.text('Instructions are required.'), findsOneWidget);
    expect(find.text('Use short steps.'), findsNothing);
    expect(find.byType(shad.ShadTextarea), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('separator resolves from the active ELIXR theme', (tester) async {
    await tester.pumpWidget(host(const ElixSeparator(), theme: AppTheme.dark));

    expect(find.byType(shad.ShadSeparator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('button variants map to the installed Shadcn variants', (
    tester,
  ) async {
    for (final variant in ElixButtonVariant.values) {
      await tester.pumpWidget(
        host(
          ElixPrimaryButton(
            label: variant.name,
            onPressed: () {},
            expanded: false,
            variant: variant,
          ),
          theme: AppTheme.dark,
        ),
      );

      expect(find.byType(shad.ShadButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('text fields accept autofocus and maxLength', (tester) async {
    await tester.pumpWidget(
      host(
        const ElixTextField(label: 'Join code', autofocus: true, maxLength: 8),
        theme: AppTheme.dark,
      ),
    );

    final input = tester.widget<shad.ShadInput>(find.byType(shad.ShadInput));
    expect(input.autofocus, isTrue);
    expect(input.maxLength, 8);
    expect(tester.takeException(), isNull);
  });
}
