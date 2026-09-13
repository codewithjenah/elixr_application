import 'package:elixr_application/core/constants/app_spacing.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_dialog.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required FluentThemeData theme,
    Size size = const Size(900, 700),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(
        theme: theme,
        home: ElixShadThemeBridge(
          child: ElixDialog(
            key: const ValueKey('footer-dialog'),
            title: 'Confirm?',
            content: const Text('Confirmation copy'),
            uniformActionSize: const Size(128, 56),
            actions: [
              Button(
                key: const ValueKey('footer-cancel'),
                onPressed: () {},
                child: const Text('Cancel'),
              ),
              ElixPrimaryButton(
                key: const ValueKey('footer-confirm'),
                label: 'Confirm',
                expanded: false,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  void expectFooterInsets(WidgetTester tester, Finder dialog) {
    final dialogRect = tester.getRect(dialog);
    final cancelRect = tester.getRect(
      find.byKey(const ValueKey('footer-cancel')),
    );
    final confirmRect = tester.getRect(
      find.byKey(const ValueKey('footer-confirm')),
    );
    expect(cancelRect.size, const Size(128, 56));
    expect(confirmRect.size, cancelRect.size);
    for (final action in [cancelRect, confirmRect]) {
      expect(dialogRect.contains(action.topLeft), isTrue);
      expect(dialogRect.contains(action.bottomRight), isTrue);
      expect(action.left - dialogRect.left, greaterThan(0));
      expect(dialogRect.right - action.right, greaterThan(0));
      expect(dialogRect.bottom - action.bottom, greaterThan(0));
    }
    if ((cancelRect.top - confirmRect.top).abs() < 1) {
      expect(confirmRect.left - cancelRect.right, AppSpacing.sm);
    }
  }

  testWidgets(
    'dialog footer gives normal confirmation actions bounded spacing',
    (tester) async {
      await pumpDialog(tester, theme: AppTheme.dark);
      expectFooterInsets(
        tester,
        find.byKey(const ValueKey('elix-shad-dialog')),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dialog footer remains usable in high contrast and narrow windows',
    (tester) async {
      await pumpDialog(
        tester,
        theme: AppTheme.highContrastDark,
        size: const Size(300, 560),
      );
      expectFooterInsets(tester, find.byKey(const ValueKey('footer-dialog')));
      expect(tester.takeException(), isNull);
    },
  );
}
