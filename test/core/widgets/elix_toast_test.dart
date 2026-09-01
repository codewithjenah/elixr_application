import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpToastHost(
    WidgetTester tester, {
    Size? size,
    String message = 'Unarchived BSIT-3A.',
  }) async {
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (context) => Button(
            onPressed: () => ElixToast.showSuccess(context, message: message),
            child: const Text('Show toast'),
          ),
        ),
      ),
    );
  }

  testWidgets('renders once and can be dismissed manually', (tester) async {
    await pumpToastHost(tester);

    await tester.tap(find.text('Show toast'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('elix_toast')), findsOneWidget);
    expect(find.text('Unarchived BSIT-3A.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('elix_toast_close')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('elix_toast')), findsNothing);
  });

  testWidgets('auto-dismisses and keeps long text within a narrow window', (
    tester,
  ) async {
    await pumpToastHost(
      tester,
      size: const Size(260, 480),
      message:
          'The classroom was successfully updated with a longer confirmation message.',
    );

    await tester.tap(find.text('Show toast'));
    await tester.pumpAndSettle();

    final toast = tester.getRect(find.byKey(const Key('elix_toast')));
    expect(toast.width, lessThanOrEqualTo(228));

    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('elix_toast')), findsNothing);
  });
}
