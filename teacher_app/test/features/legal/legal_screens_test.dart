import 'package:elixr_teacher/core/theme/teacher_theme.dart';
import 'package:elixr_teacher/features/legal/legal_screens.dart';
import 'package:flutter/material.dart';
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
        builder: (context, state) => const Scaffold(body: Text('Register')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp.router(theme: buildTeacherTheme(), routerConfig: router),
  );
  await tester.pump();
}

Finder containing(String text) {
  return find.textContaining(text, skipOffstage: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Teacher privacy policy omits Trainee-only webcam copy', (
    tester,
  ) async {
    await pumpLegal(
      tester,
      location: '/privacy-policy',
      screen: const PrivacyPolicyScreen(),
    );

    expect(containing('Firebase Authentication'), findsOneWidget);
    expect(containing('Teacher-account'), findsOneWidget);
    expect(containing('Teacher↔Trainee relationship records'), findsOneWidget);
    expect(containing('approve each request'), findsOneWidget);
    expect(containing('saved-image access'), findsOneWidget);
    expect(containing('sanitized, read-only progress summary'), findsOneWidget);
    expect(containing('pose/hand landmark'), findsNothing);
    expect(containing('Settings > Privacy'), findsNothing);
    expect(containing('claimed achievements'), findsNothing);
    expect(containing('raw camera video is never uploaded'), findsNothing);
  });

  testWidgets('Teacher terms do not claim an active leaderboard', (
    tester,
  ) async {
    await pumpLegal(
      tester,
      location: '/terms-of-service',
      screen: const TermsOfServiceScreen(),
    );

    expect(containing('Teacher approves'), findsOneWidget);
    expect(containing('read-only when separately authorized'), findsOneWidget);
    expect(containing('Leaderboard scores'), findsNothing);
    expect(containing('educational and training purposes'), findsOneWidget);
  });
}
