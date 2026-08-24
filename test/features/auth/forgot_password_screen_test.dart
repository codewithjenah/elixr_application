import 'package:elixr_application/core/auth/teacher_auth_messages.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/auth_scaffold.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/features/auth/forgot_password_screen.dart';
import 'package:elixr_application/features/auth/login_screen.dart';
import 'package:elixr_application/services/auth_email_callback_server.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _TrackingPasswordResetRepository implements AuthRepositoryBase {
  int sendPasswordResetEmailCallCount = 0;
  String? lastEmail;
  Object? errorToThrow;

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {
    sendPasswordResetEmailCallCount++;
    lastEmail = email;
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<void> clearCurrentUser() async {}

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();

  @override
  Future<bool> isCurrentEmailVerified() async => false;

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<User?> loadPersistedUser() async => null;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    String defaultRole = User.roleTrainee,
    String? teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {}

  @override
  Future<User?> refreshAuthenticatedUser() async => null;

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}
  @override
  Future<void> deleteAccount({
    required String password,
    required String expectedUserId,
  }) async {}
}

Future<void> _setSurface(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Finder _authField(String placeholder) {
  return find.byWidgetPredicate(
    (widget) => widget is TextBox && widget.placeholder == placeholder,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TrackingPasswordResetRepository repository;
  late AuthService authService;
  late GoRouter router;

  setUp(() {
    repository = _TrackingPasswordResetRepository();
    authService = AuthService(
      repository: repository,
      leaderboardRepository: null,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
    );
    router = GoRouter(
      initialLocation: '/forgot-password',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordScreen(),
        ),
      ],
    );
  });

  tearDown(() {
    authService.dispose();
    router.dispose();
  });

  Widget wrap() {
    return ChangeNotifierProvider<AuthService>.value(
      value: authService,
      child: FluentApp.router(
        theme: AppTheme.dark,
        routeInformationParser: router.routeInformationParser,
        routerDelegate: router.routerDelegate,
        routeInformationProvider: router.routeInformationProvider,
      ),
    );
  }

  Future<void> pumpForgotPasswordScreen(WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pump(const Duration(milliseconds: 700));
  }

  group('ForgotPasswordScreen', () {
    testWidgets('requires an email before calling AuthService', (tester) async {
      await _setSurface(tester);
      await pumpForgotPasswordScreen(tester);

      await tester.tap(find.byType(ElixPrimaryButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(repository.sendPasswordResetEmailCallCount, 0);
      expect(find.text('Email address is required.'), findsOneWidget);
    });

    testWidgets(
      'shows a generic success message after submitting a valid email',
      (tester) async {
        await _setSurface(tester);
        await pumpForgotPasswordScreen(tester);

        await tester.enterText(
          _authField('Email address'),
          '  trainee@example.com ',
        );
        await tester.tap(find.byType(ElixPrimaryButton));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(repository.sendPasswordResetEmailCallCount, 1);
        expect(repository.lastEmail, 'trainee@example.com');
        expect(find.text('Check your email'), findsOneWidget);
        expect(find.textContaining('trainee@example.com'), findsOneWidget);
        expect(find.byType(ElixPrimaryButton), findsNothing);
      },
    );

    testWidgets('auto-detects when the reset email link is completed', (
      tester,
    ) async {
      await _setSurface(tester);
      await pumpForgotPasswordScreen(tester);

      await tester.enterText(
        _authField('Email address'),
        'trainee@example.com',
      );
      await tester.tap(find.byType(ElixPrimaryButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      authService.handleEmailActionCallback(
        Uri.parse('http://localhost:1/elixr-auth?mode=reset'),
      );
      await tester.pump();

      expect(
        find.text(TeacherAuthMessages.passwordResetCompleted),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    });

    testWidgets('shows AuthErrorBanner when the reset request fails', (
      tester,
    ) async {
      repository.errorToThrow = Exception(
        'Network error. Check your connection and try again.',
      );
      await _setSurface(tester);
      await pumpForgotPasswordScreen(tester);

      await tester.enterText(
        _authField('Email address'),
        'trainee@example.com',
      );
      await tester.tap(find.byType(ElixPrimaryButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(repository.sendPasswordResetEmailCallCount, 1);
      expect(find.byType(AuthErrorBanner), findsOneWidget);
      expect(
        find.text('Network error. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(find.text('Check your email for a reset link'), findsNothing);
    });

    testWidgets('returns to login from the footer link', (tester) async {
      await _setSurface(tester);
      await pumpForgotPasswordScreen(tester);

      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is AuthFooterLink && widget.action == 'Sign in',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('LoginScreen forgot password link', () {
    testWidgets('navigates to the forgot-password screen', (tester) async {
      router = GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(
            path: '/login',
            builder: (context, state) => const LoginScreen(),
          ),
          GoRoute(
            path: '/forgot-password',
            builder: (context, state) => const ForgotPasswordScreen(),
          ),
        ],
      );

      await _setSurface(tester);
      await tester.pumpWidget(wrap());
      await tester.pump(const Duration(milliseconds: 700));

      final forgotPasswordLink = find.byWidgetPredicate(
        (widget) =>
            widget is AuthFooterLink && widget.action == 'Forgot password?',
      );
      expect(forgotPasswordLink, findsOneWidget);
      await tester.tap(forgotPasswordLink);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    });
  });
}
