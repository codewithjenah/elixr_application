import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_application/features/auth/login_screen.dart';
import 'package:elixr_application/services/auth_email_callback_server.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _LoginRepository implements AuthRepositoryBase {
  int loginCalls = 0;
  Object? loginError;

  @override
  Future<User> login({required String email, required String password}) async {
    loginCalls++;
    if (loginError != null) throw loginError!;
    return User(
      id: 'trainee-1',
      firstName: 'Test',
      lastName: 'Trainee',
      email: email,
    );
  }

  @override
  Future<bool> isCurrentEmailVerified() async => true;
  @override
  Future<User?> refreshAuthenticatedUser() async => null;
  @override
  Future<User?> loadPersistedUser() async => null;
  @override
  Future<void> clearCurrentUser() async {}
  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {}
  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {}
  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
  }) async => EmailChangeRequestResult.unchanged;
  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();
  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
    String? teacherAccessCode,
  }) => throw UnimplementedError();
  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) => throw UnimplementedError();
  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) => throw UnimplementedError();
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _LoginRepository repository;
  late AuthService auth;

  setUp(() {
    repository = _LoginRepository();
    auth = AuthService(
      repository: repository,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
    );
  });

  tearDown(() => auth.dispose());

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(660, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp(theme: AppTheme.dark, home: const LoginScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
  }

  Finder field(String placeholder) => find.byWidgetPredicate(
    (widget) => widget is TextBox && widget.placeholder == placeholder,
  );

  testWidgets('validates locally and has no compact auth scroller', (
    tester,
  ) async {
    await pumpLogin(tester);
    await tester.enterText(field('Email address'), 'not-an-email');
    await tester.tap(find.widgetWithText(ElixPrimaryButton, 'Sign In'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(repository.loginCalls, 0);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not reject an existing six-character password locally', (
    tester,
  ) async {
    await pumpLogin(tester);
    await tester.enterText(field('Email address'), 'user@example.com');
    await tester.enterText(field('Password'), 'old123');
    await tester.tap(find.widgetWithText(ElixPrimaryButton, 'Sign In'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(repository.loginCalls, 1);
  });

  testWidgets('uses a generic credential failure message', (tester) async {
    repository.loginError = Exception('User not found');
    await pumpLogin(tester);
    await tester.enterText(field('Email address'), 'user@example.com');
    await tester.enterText(field('Password'), 'old123');
    await tester.tap(find.widgetWithText(ElixPrimaryButton, 'Sign In'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Email or password is incorrect.'), findsOneWidget);
    expect(find.textContaining('User not found'), findsNothing);
  });
}
