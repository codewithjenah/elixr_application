import 'package:elixr_application/features/auth/teacher_register_screen.dart';
import 'package:elixr_application/services/auth_email_callback_server.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _TeacherRegisterRepository
    implements AuthRepositoryBase, TeacherRegistrationRepositoryBase {
  String? lastDefaultRole;
  String? lastTeacherAccessCode;
  String? prevalidatedAccessCode;
  String? accessCodeError;
  int accessCodeChecks = 0;
  bool verificationRequested = false;

  @override
  Future<void> assertTeacherAccessCodeRedeemable(String code) async {
    accessCodeChecks++;
    prevalidatedAccessCode = code;
    final error = accessCodeError;
    if (error != null) throw Exception(error);
  }

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
    String? teacherAccessCode,
  }) async {
    lastDefaultRole = defaultRole;
    lastTeacherAccessCode = teacherAccessCode;
    return User(
      id: 'teacher-new',
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: email,
      role: defaultRole,
    );
  }

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {
    verificationRequested = true;
  }

  @override
  Future<bool> isCurrentEmailVerified() async => false;

  @override
  Future<User?> loadPersistedUser() async => null;

  @override
  Future<void> clearCurrentUser() async {}

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

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

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({AuthService auth, _TeacherRegisterRepository repository})>
  pumpTeacherRegistration(WidgetTester tester) async {
    final repository = _TeacherRegisterRepository();
    final auth = AuthService(
      repository: repository,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
      awaitInitialAuthState: () async {},
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp(home: const TeacherRegisterScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    return (auth: auth, repository: repository);
  }

  testWidgets('starts with access code only, then shows registration methods', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = await pumpTeacherRegistration(tester);

    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('Teacher access code'), findsOneWidget);
    expect(find.text('Email address'), findsNothing);
    expect(find.text('Continue with Google'), findsNothing);

    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('teacher_register_access_code_field')),
        matching: find.byType(TextBox),
      ),
      '7kpm-xr4d-q2wt',
    );
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fixture.repository.accessCodeChecks, 1);
    expect(fixture.repository.prevalidatedAccessCode, '7KPMXR4DQ2WT');
    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Use email and password'), findsOneWidget);
    expect(find.text('Email address'), findsNothing);
  });

  testWidgets('does not expose registration methods for an invalid code', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final fixture = await pumpTeacherRegistration(tester);
    fixture.repository.accessCodeError =
        'That Teacher access code is invalid or has already been used.';

    await tester.enterText(find.byType(TextBox).first, '7KPM-XR4D-Q2WT');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    expect(
      find.text(
        'That Teacher access code is invalid or has already been used.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('teacher registration creates Teacher role with legal consent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final fixture = await pumpTeacherRegistration(tester);
    final repository = fixture.repository;
    final auth = fixture.auth;

    await tester.enterText(find.byType(TextBox).first, '7KPM-XR4D-Q2WT');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Use email and password'));
    await tester.pump();

    expect(find.text('Step 3 of 4'), findsOneWidget);
    expect(find.byKey(const Key('teacher_register_email_field')), findsNothing);
    await tester.enterText(find.byType(TextBox).at(0), 'Jane');
    await tester.enterText(find.byType(TextBox).at(2), 'Doe');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Step 4 of 4'), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_register_email_field')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextBox).at(0), 'jane@school.edu');
    await tester.enterText(find.byType(TextBox).at(1), 'secret12');
    await tester.enterText(find.byType(TextBox).at(2), 'secret12');
    await tester.tap(find.byKey(const Key('teacher_register_privacy_consent')));
    await tester.pump();
    await tester.tap(find.text('Create Teacher account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.lastDefaultRole, User.roleTeacher);
    expect(repository.lastTeacherAccessCode, '7KPMXR4DQ2WT');
    expect(repository.accessCodeChecks, 1);
    expect(repository.verificationRequested, isTrue);
    expect(auth.currentUser?.isTeacher, isTrue);
  });
}
