import 'package:elixr_core/models/user.dart';
import 'package:elixr_teacher/core/theme/teacher_theme.dart';
import 'package:elixr_teacher/features/auth/register_screen.dart';
import 'package:elixr_teacher/features/auth/teacher_auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_auth_repository.dart';

Finder labeledField(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );
}

Future<void> setPhoneSurface(WidgetTester tester) async {
  const size = Size(412, 1400);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthRepository repository;
  late TeacherAuthController controller;
  late GoRouter router;

  setUp(() async {
    repository = FakeAuthRepository();
    controller = TeacherAuthController(repository: repository);
    await controller.initialize();
    router = GoRouter(
      initialLocation: '/register',
      routes: [
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(body: Text('Login')),
        ),
        GoRoute(
          path: '/privacy-policy',
          builder: (context, state) =>
              const Scaffold(body: Text('Privacy Policy')),
        ),
        GoRoute(
          path: '/terms-of-service',
          builder: (context, state) =>
              const Scaffold(body: Text('Terms of Service')),
        ),
      ],
    );
  });

  tearDown(() {
    controller.dispose();
    router.dispose();
  });

  Future<void> pumpRegister(WidgetTester tester) async {
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

  Future<void> fillValidForm(
    WidgetTester tester, {
    String password = 'secret1',
    String confirmPassword = 'secret1',
  }) async {
    await tester.enterText(labeledField('First name'), 'Ada');
    await tester.enterText(labeledField('Last name'), 'Lovelace');
    await tester.enterText(labeledField('Email'), 'ada@example.com');
    await tester.enterText(labeledField('Password'), password);
    await tester.enterText(labeledField('Confirm password'), confirmPassword);
  }

  Future<void> acceptLegal(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final consent = find.byKey(const Key('register_privacy_consent'));
    await tester.ensureVisible(consent);
    await tester.pump();
    tester.widget<CheckboxListTile>(consent).onChanged?.call(true);
    await tester.pump();
  }

  testWidgets('Create Account stays disabled until legal consent is checked', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    await pumpRegister(tester);
    await fillValidForm(tester);
    await tester.pump();

    final createAccount = find.byKey(const Key('register_create_account'));
    await tester.ensureVisible(createAccount);
    final button = tester.widget<FilledButton>(createAccount);
    expect(button.onPressed, isNull);

    await tester.tap(createAccount);
    await tester.pump();
    expect(repository.registerCallCount, 0);

    await acceptLegal(tester);

    final enabled = tester.widget<FilledButton>(createAccount);
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('password mismatch does not invoke registration', (tester) async {
    await setPhoneSurface(tester);
    await pumpRegister(tester);
    await fillValidForm(tester, confirmPassword: 'secret2');
    await acceptLegal(tester);

    final createAccount = find.byKey(const Key('register_create_account'));
    await tester.ensureVisible(createAccount);
    await tester.tap(createAccount);
    await tester.pump();
    await tester.pump();

    expect(repository.registerCallCount, 0);
    expect(find.text(TeacherAuthMessages.passwordMismatch), findsOneWidget);
  });

  testWidgets('successful Teacher registration passes User.roleTeacher', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    await pumpRegister(tester);
    await fillValidForm(tester);
    await acceptLegal(tester);

    await tester.ensureVisible(
      find.byKey(const Key('register_create_account')),
    );
    await tester.tap(find.byKey(const Key('register_create_account')));
    await tester.pump();
    await tester.pump();

    expect(repository.registerCallCount, 1);
    expect(repository.lastDefaultRole, User.roleTeacher);
    expect(controller.status, TeacherAuthStatus.unverifiedTeacher);
  });
}
