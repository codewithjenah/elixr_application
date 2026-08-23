import 'package:elixr_application/features/auth/teacher_register_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _TeacherRegisterRepository implements AuthRepositoryBase {
  String? lastDefaultRole;
  bool verificationRequested = false;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
  }) async {
    lastDefaultRole = defaultRole;
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
  Future<void> requestCurrentEmailVerification() async {
    verificationRequested = true;
  }

  @override
  Future<void> requestDeleteAccountEmailVerification() async {}

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
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
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
  Future<void> deleteAccount({required String password}) async {}

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

  testWidgets('teacher registration creates Teacher role with legal consent', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = _TeacherRegisterRepository();
    final auth = AuthService(
      repository: repository,
      awaitInitialAuthState: () async {},
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: auth,
        child: FluentApp(home: const TeacherRegisterScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    await tester.enterText(find.byType(TextBox).at(0), 'Jane');
    await tester.enterText(find.byType(TextBox).at(2), 'Doe');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    await tester.enterText(find.byType(TextBox).at(0), 'jane@school.edu');
    await tester.enterText(find.byType(TextBox).at(1), 'secret1');
    await tester.enterText(find.byType(TextBox).at(2), 'secret1');
    await tester.tap(find.byKey(const Key('teacher_register_privacy_consent')));
    await tester.pump();
    await tester.tap(find.text('Create Teacher account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repository.lastDefaultRole, User.roleTeacher);
    expect(repository.verificationRequested, isTrue);
    expect(auth.currentUser?.isTeacher, isTrue);
  });
}
