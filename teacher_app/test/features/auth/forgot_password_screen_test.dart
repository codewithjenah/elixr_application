import 'package:elixr_teacher/core/theme/teacher_theme.dart';
import 'package:elixr_teacher/features/auth/forgot_password_screen.dart';
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
      initialLocation: '/forgot-password',
      routes: [
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const Scaffold(body: Text('Login')),
        ),
      ],
    );
  });

  tearDown(() {
    controller.dispose();
    router.dispose();
  });

  Future<void> pumpForgot(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
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

  testWidgets('does not disclose whether an account exists', (tester) async {
    await pumpForgot(tester);

    await tester.enterText(labeledField('Email'), 'anyone@example.com');
    await tester.tap(find.byKey(const Key('forgot_password_submit')));
    await tester.pump();
    await tester.pump();

    expect(repository.sendPasswordResetEmailCallCount, 1);
    expect(find.text(TeacherAuthMessages.resetEmailSent), findsOneWidget);
    expect(find.textContaining('not found'), findsNothing);
    expect(find.textContaining('does not exist'), findsNothing);
    expect(find.textContaining('no account'), findsNothing);
  });

  testWidgets('shows a failure without a success claim', (tester) async {
    repository.passwordResetError = Exception(
      'Network error. Check your connection and try again.',
    );
    await pumpForgot(tester);

    await tester.enterText(labeledField('Email'), 'anyone@example.com');
    await tester.tap(find.byKey(const Key('forgot_password_submit')));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Network error. Check your connection and try again.'),
      findsOneWidget,
    );
    expect(find.text(TeacherAuthMessages.resetEmailSent), findsNothing);
  });
}
