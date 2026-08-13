import 'package:elixr_teacher/app.dart';
import 'package:elixr_teacher/core/router/teacher_router.dart';
import 'package:elixr_teacher/core/router/teacher_routes.dart';
import 'package:elixr_teacher/core/theme/teacher_theme.dart';
import 'package:elixr_teacher/features/auth/login_screen.dart';
import 'package:elixr_teacher/features/auth/teacher_auth_controller.dart';
import 'package:elixr_teacher/features/auth/verify_email_screen.dart';
import 'package:elixr_teacher/features/roster/roster_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_auth_repository.dart';

Finder labeledField(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Future<void> setPhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Future<void> pumpRoutedApp(
  WidgetTester tester, {
  required TeacherAuthController controller,
}) async {
  final router = createTeacherRouter(controller);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<TeacherAuthController>.value(
      value: controller,
      child: MaterialApp.router(
        theme: buildTeacherTheme(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthRepository repository;
  late TeacherAuthController controller;

  setUp(() {
    repository = FakeAuthRepository();
    controller = TeacherAuthController(repository: repository);
  });

  tearDown(() {
    controller.dispose();
  });

  testWidgets('signed-out state routes to Login', (tester) async {
    await setPhoneSurface(tester);
    await controller.initialize();
    await pumpRoutedApp(tester, controller: controller);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RosterScreen), findsNothing);
  });

  testWidgets('protected roster does not stay reachable while signed out', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    await controller.initialize();
    final router = createTeacherRouter(controller);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<TeacherAuthController>.value(
        value: controller,
        child: MaterialApp.router(
          theme: buildTeacherTheme(),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    router.go(TeacherRoutes.roster);
    await tester.pump();
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RosterScreen), findsNothing);
  });

  testWidgets('unverified Teacher goes to Verify Email', (tester) async {
    repository.persistedUser = fakeTeacher();
    repository.emailVerified = false;
    await controller.initialize();
    await setPhoneSurface(tester);
    await pumpRoutedApp(tester, controller: controller);

    expect(find.byType(VerifyEmailScreen), findsOneWidget);
    expect(find.textContaining('teacher@example.com'), findsOneWidget);
    expect(find.byType(RosterScreen), findsNothing);
  });

  testWidgets('verified Teacher goes to Roster', (tester) async {
    repository.persistedUser = fakeTeacher();
    repository.emailVerified = true;
    await controller.initialize();
    await setPhoneSurface(tester);
    await pumpRoutedApp(tester, controller: controller);

    expect(find.byType(RosterScreen), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.textContaining('teacher@example.com'), findsOneWidget);
    expect(find.text('No students linked yet'), findsOneWidget);
  });

  testWidgets('missing profile cannot enter Teacher shell', (tester) async {
    repository.authSessionWithoutProfile = true;
    await controller.initialize();
    await setPhoneSurface(tester);
    await pumpRoutedApp(tester, controller: controller);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RosterScreen), findsNothing);
    expect(find.text(TeacherAuthMessages.notATeacher), findsNothing);
  });

  testWidgets('logout returns to Login', (tester) async {
    repository.persistedUser = fakeTeacher();
    repository.emailVerified = true;
    await controller.initialize();
    await setPhoneSurface(tester);
    await pumpRoutedApp(tester, controller: controller);

    await tester.tap(find.byKey(const Key('roster_logout')));
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RosterScreen), findsNothing);
  });

  testWidgets('logged-in Trainee cannot enter Teacher shell', (tester) async {
    await controller.initialize();
    repository.loginResult = fakeTrainee();
    await setPhoneSurface(tester);
    await pumpRoutedApp(tester, controller: controller);

    await tester.enterText(labeledField('Email'), 'trainee@example.com');
    await tester.enterText(labeledField('Password'), 'secret1');
    await tester.tap(find.byKey(const Key('login_sign_in')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RosterScreen), findsNothing);
    expect(find.text(TeacherAuthMessages.notATeacher), findsOneWidget);
  });

  testWidgets('logged-in Admin cannot enter Teacher shell', (tester) async {
    await controller.initialize();
    repository.loginResult = fakeAdmin();
    await setPhoneSurface(tester);
    await pumpRoutedApp(tester, controller: controller);

    await tester.enterText(labeledField('Email'), 'admin@example.com');
    await tester.enterText(labeledField('Password'), 'secret1');
    await tester.tap(find.byKey(const Key('login_sign_in')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RosterScreen), findsNothing);
    expect(find.text(TeacherAuthMessages.notATeacher), findsOneWidget);
  });

  testWidgets('ElixrTeacherApp shows login after signed-out initialize', (
    tester,
  ) async {
    await controller.initialize();
    await setPhoneSurface(tester);
    await tester.pumpWidget(ElixrTeacherApp(authController: controller));
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
