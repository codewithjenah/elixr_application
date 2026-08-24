import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_application/features/auth/login_screen.dart';
import 'package:elixr_application/features/auth/complete_google_profile_screen.dart';
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

class _GoogleLoginRepository extends _LoginRepository
    implements GoogleAuthRepositoryBase {
  int googleCalls = 0;
  int completionCalls = 0;
  int cancellationCalls = 0;
  int googleDeletionCalls = 0;
  GoogleSignInResult? resultOverride;

  @override
  Future<GoogleSignInResult> signInWithGoogle() async {
    googleCalls++;
    return resultOverride ??
        const PendingGoogleSignIn(
          PendingGoogleProfile(
            uid: 'google-1',
            email: 'google@example.com',
            firstName: 'Google',
            lastName: 'User',
            isNewUser: true,
          ),
        );
  }

  @override
  Future<void> cancelGoogleOnboarding(
    PendingGoogleProfile pendingProfile,
  ) async {
    cancellationCalls++;
  }

  @override
  Future<User> completeGoogleProfile({
    required PendingGoogleProfile pendingProfile,
    required String firstName,
    String? middleName,
    required String lastName,
  }) async {
    completionCalls++;
    return User(
      id: pendingProfile.uid,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: pendingProfile.email,
    );
  }

  @override
  Future<Set<AuthProviderKind>> currentProviderKinds() async => const {
    AuthProviderKind.google,
  };

  @override
  Future<void> deleteAccountWithReauthentication({
    required AccountReauthentication reauthentication,
    required String expectedUserId,
  }) async {
    googleDeletionCalls++;
  }

  @override
  Future<GoogleSignInResult?> restoreGoogleSignIn() async => null;
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

  testWidgets(
    'Google button starts provider sign-in and enters pending state',
    (tester) async {
      final googleRepository = _GoogleLoginRepository();
      auth.dispose();
      repository = googleRepository;
      auth = AuthService(
        repository: repository,
        emailCallbackServer: MemoryAuthEmailCallbackServer(),
      );
      await pumpLogin(tester);

      await tester.tap(find.byKey(const Key('login_google_button')));
      await tester.pump(const Duration(milliseconds: 150));

      expect(googleRepository.googleCalls, 1);
      expect(auth.hasPendingGoogleProfile, isTrue);
      expect(auth.currentUser, isNull);
    },
  );

  testWidgets('pending Google user completes a consented Trainee profile', (
    tester,
  ) async {
    final googleRepository = _GoogleLoginRepository();
    auth.dispose();
    repository = googleRepository;
    auth = AuthService(
      repository: repository,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
    );
    await auth.signInWithGoogle();
    await tester.binding.setSurfaceSize(const Size(760, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: const FluentApp(home: CompleteGoogleProfileScreen()),
      ),
    );

    expect(find.text('google@example.com'), findsOneWidget);
    final consent = find.byKey(const Key('google_profile_legal_consent'));
    await tester.ensureVisible(consent);
    await tester.tap(consent);
    final submit = find.widgetWithText(
      ElixPrimaryButton,
      'Create Trainee Profile',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump(const Duration(milliseconds: 150));

    expect(googleRepository.completionCalls, 1);
    expect(auth.hasPendingGoogleProfile, isFalse);
    expect(auth.currentUser?.isTrainee, isTrue);
  });

  test('cancelling Google onboarding clears pending auth state', () async {
    final googleRepository = _GoogleLoginRepository();
    auth.dispose();
    repository = googleRepository;
    auth = AuthService(
      repository: repository,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
    );

    await auth.signInWithGoogle();
    await auth.cancelGoogleOnboarding();

    expect(googleRepository.cancellationCalls, 1);
    expect(auth.hasPendingGoogleProfile, isFalse);
    expect(auth.currentUser, isNull);
  });

  test('Google-only deletion uses Google reauthentication', () async {
    final googleRepository = _GoogleLoginRepository()
      ..resultOverride = const ExistingGoogleProfile(
        User(
          id: 'google-1',
          firstName: 'Google',
          lastName: 'User',
          email: 'google@example.com',
        ),
      );
    auth.dispose();
    repository = googleRepository;
    auth = AuthService(
      repository: repository,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
    );

    await auth.signInWithGoogle();
    await auth.deleteAccount(
      reauthentication: const AccountReauthentication.google(),
      confirmationPhrase: 'delete google@example.com',
    );

    expect(googleRepository.googleDeletionCalls, 1);
    expect(auth.currentUser, isNull);
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
