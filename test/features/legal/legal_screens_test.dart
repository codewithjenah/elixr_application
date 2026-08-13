import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/legal/privacy_policy_screen.dart';
import 'package:elixr_application/features/legal/terms_of_service_screen.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> pumpLegal(
  WidgetTester tester, {
  required String location,
  required Widget screen,
}) async {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(path: location, builder: (context, state) => screen),
      GoRoute(
        path: '/register',
        builder: (context, state) =>
            const ScaffoldPage(content: Center(child: Text('Register'))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    FluentApp.router(
      theme: AppTheme.dark,
      routeInformationParser: router.routeInformationParser,
      routerDelegate: router.routerDelegate,
      routeInformationProvider: router.routeInformationProvider,
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
}

Finder containing(String text) {
  return find.textContaining(text, skipOffstage: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows privacy policy retains Trainee webcam disclosures', (
    tester,
  ) async {
    await pumpLegal(
      tester,
      location: '/privacy-policy',
      screen: const PrivacyPolicyScreen(),
    );

    expect(containing('pose/hand landmark detection'), findsOneWidget);
    expect(containing('raw camera video is never uploaded'), findsOneWidget);
    expect(containing('claimed achievements'), findsOneWidget);
    expect(containing('Settings > Privacy'), findsOneWidget);
    expect(containing('leaderboard identity'), findsOneWidget);
    expect(containing('Settings > Security'), findsWidgets);
    expect(containing('not yet active'), findsNothing);
  });

  testWidgets('Windows terms retain leaderboard disclosure', (tester) async {
    await pumpLegal(
      tester,
      location: '/terms-of-service',
      screen: const TermsOfServiceScreen(),
    );

    expect(containing('Leaderboard scores'), findsOneWidget);
    expect(containing('not yet active'), findsNothing);
  });
}
