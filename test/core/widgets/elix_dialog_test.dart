import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_dialog.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uniformActionSize gives confirmation actions matching bounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixDialog(
          title: 'Confirm?',
          content: const Text('Confirmation copy'),
          uniformActionSize: const Size(128, 56),
          actions: [
            Button(onPressed: () {}, child: const Text('Cancel')),
            ElixPrimaryButton(
              label: 'Longer action',
              expanded: false,
              onPressed: () {},
            ),
          ],
        ),
      ),
    );

    final cancelRect = tester.getRect(find.byType(Button));
    final primaryRect = tester.getRect(find.byType(ElixPrimaryButton));

    expect(cancelRect.size, const Size(128, 56));
    expect(primaryRect.size, cancelRect.size);
  });
}
