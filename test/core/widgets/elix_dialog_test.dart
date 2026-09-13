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

  testWidgets('confirm returns true only after the confirm action', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: Builder(
            builder: (context) => ElixPrimaryButton(
              label: 'Open confirm',
              onPressed: () async {
                result = await ElixDialog.confirm(
                  context,
                  title: 'Archive this classroom?',
                  message: 'Students keep their submitted work.',
                  confirmLabel: 'Archive',
                  confirmKey: const ValueKey('confirm-archive'),
                  cancelKey: const ValueKey('cancel-archive'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Archive this classroom?'), findsOneWidget);
    expect(
      tester
          .widget<ElixPrimaryButton>(
            find.byKey(const ValueKey('confirm-archive')),
          )
          .variant,
      ElixButtonVariant.primary,
    );

    await tester.tap(find.byKey(const ValueKey('cancel-archive')));
    await tester.pumpAndSettle();
    expect(result, isFalse);

    await tester.tap(find.text('Open confirm'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-archive')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('destructive confirm uses the destructive action treatment', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: Builder(
            builder: (context) => ElixPrimaryButton(
              label: 'Open destructive',
              onPressed: () => ElixDialog.confirm(
                context,
                title: 'Delete movement?',
                message: 'This cannot be undone.',
                confirmLabel: 'Delete',
                destructive: true,
                confirmKey: const ValueKey('confirm-delete'),
                cancelKey: const ValueKey('cancel-delete'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open destructive'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ElixPrimaryButton>(
            find.byKey(const ValueKey('confirm-delete')),
          )
          .variant,
      ElixButtonVariant.destructive,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirm footer stays inside a narrow window', (tester) async {
    tester.view.physicalSize = const Size(300, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: Builder(
            builder: (context) => ElixPrimaryButton(
              label: 'Open confirm',
              onPressed: () => ElixDialog.confirm(
                context,
                title: 'Leave class?',
                message: 'You can join again later with a new code.',
                confirmKey: const ValueKey('confirm-leave'),
                cancelKey: const ValueKey('cancel-leave'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open confirm'));
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('elix-shad-dialog'));
    final cancelRect = tester.getRect(
      find.byKey(const ValueKey('cancel-leave')),
    );
    final confirmRect = tester.getRect(
      find.byKey(const ValueKey('confirm-leave')),
    );
    final dialogRect = tester.getRect(dialog);
    expect(dialogRect.contains(cancelRect.topLeft), isTrue);
    expect(dialogRect.contains(cancelRect.bottomRight), isTrue);
    expect(dialogRect.contains(confirmRect.topLeft), isTrue);
    expect(dialogRect.contains(confirmRect.bottomRight), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading action shows a progress ring', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: Center(
            child: ElixPrimaryButton(
              key: const ValueKey('busy-delete'),
              label: 'Deleting...',
              expanded: false,
              isLoading: true,
              variant: ElixButtonVariant.destructive,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );

    final button = tester.widget<ElixPrimaryButton>(
      find.byKey(const ValueKey('busy-delete')),
    );
    expect(button.isLoading, isTrue);
    expect(find.byType(ProgressRing), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single footer action stays bounded inside ShadDialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: Builder(
            builder: (context) => ElixPrimaryButton(
              label: 'Open lightbox',
              onPressed: () => ElixDialog.show<void>(
                context,
                title: 'Confirmed movement image',
                maxWidth: 760,
                content: const SizedBox(
                  width: 400,
                  height: 160,
                  child: ColoredBox(color: Color(0xFF000000)),
                ),
                actions: [
                  ElixPrimaryButton(
                    key: const ValueKey('lightbox-close'),
                    label: 'Close',
                    expanded: false,
                    variant: ElixButtonVariant.secondary,
                    onPressed: () =>
                        Navigator.of(context, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open lightbox'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lightbox-close')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('lightbox-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lightbox-close')), findsNothing);
  });

  testWidgets('confirm stays open when the barrier is tapped', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: Builder(
            builder: (context) => ElixPrimaryButton(
              label: 'Open confirm',
              onPressed: () => ElixDialog.confirm(
                context,
                title: 'Delete movement?',
                message: 'This cannot be undone.',
                confirmLabel: 'Delete',
                destructive: true,
                confirmKey: const ValueKey('confirm-keep'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open confirm'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Delete movement?'), findsOneWidget);
    expect(find.byKey(const ValueKey('confirm-keep')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
