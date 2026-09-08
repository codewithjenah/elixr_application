import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/auth/auth_text_field.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('password checklist reports met and unmet requirements', (
    tester,
  ) async {
    final password = ValueNotifier('ab');
    addTearDown(password.dispose);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: ValueListenableBuilder<String>(
            valueListenable: password,
            builder: (context, value, _) =>
                AuthPasswordChecklist(password: value),
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.byType(AuthPasswordChecklist)).label,
      contains('8 or more characters not met'),
    );

    password.value = 'secret12';
    await tester.pump();

    expect(
      tester.getSemantics(find.byType(AuthPasswordChecklist)).label,
      contains('8 or more characters met'),
    );
    expect(find.text('8+ characters'), findsOneWidget);
    expect(find.text('Letter'), findsOneWidget);
    expect(find.text('Number'), findsOneWidget);
  });

  testWidgets('auth field keeps a stable supporting-text slot', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: AuthTextField(
            controller: controller,
            label: 'Email address',
            placeholder: 'Email address',
            icon: FluentIcons.mail_solid,
          ),
        ),
      ),
    );

    final before = tester.getSize(find.byType(AuthTextField));

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: AuthTextField(
            controller: controller,
            label: 'Email address',
            placeholder: 'Email address',
            icon: FluentIcons.mail_solid,
            status: AuthFieldStatus.error,
            validationText: 'Enter a valid email address.',
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AuthTextField)).height, before.height);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });
}
