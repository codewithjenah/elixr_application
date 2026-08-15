import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/onboarding/onboarding_overlay.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _OnboardingNavigatorHarness extends StatefulWidget {
  const _OnboardingNavigatorHarness({super.key});

  @override
  State<_OnboardingNavigatorHarness> createState() =>
      _OnboardingNavigatorHarnessState();
}

class _OnboardingNavigatorHarnessState
    extends State<_OnboardingNavigatorHarness> {
  final innerNavigatorKey = GlobalKey<NavigatorState>();
  bool authenticated = true;

  void logout() => setState(() => authenticated = false);

  @override
  Widget build(BuildContext context) {
    if (!authenticated) return const Center(child: Text('Login'));
    return Navigator(
      key: innerNavigatorKey,
      onGenerateRoute: (_) => FluentPageRoute<void>(
        builder: (context) => Center(
          child: Button(
            onPressed: () => OnboardingOverlay.show(context),
            child: const Text('Show tutorial'),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('tutorial closes with the authenticated navigator on logout', (
    tester,
  ) async {
    final key = GlobalKey<_OnboardingNavigatorHarnessState>();
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: _OnboardingNavigatorHarness(key: key),
      ),
    );

    await tester.tap(find.text('Show tutorial'));
    await tester.pumpAndSettle();
    expect(find.text('Prepare your space'), findsOneWidget);

    key.currentState!.logout();
    await tester.pumpAndSettle();

    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Prepare your space'), findsNothing);
  });
}
