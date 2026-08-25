import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/features/teacher/teacher_settings_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Settings has Account, Legal, and Log out without Co-teachers', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);

    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherSettings,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherSettings,
          builder: (context, state) => const TeacherSettingsScreen(),
        ),
        GoRoute(
          path: AppRoutePaths.privacyPolicy,
          builder: (context, state) => const Text('privacy'),
        ),
        GoRoute(
          path: AppRoutePaths.termsOfService,
          builder: (context, state) => const Text('terms'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await tester.pump();

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Legal'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('Co-teachers'), findsNothing);
    expect(find.text('Invite a co-teacher'), findsNothing);
    expect(find.text('Invite a faculty member'), findsNothing);
  });
}
