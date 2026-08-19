import 'package:elixr_application/core/auth/teacher_auth_messages.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _TeacherFlowRepository implements AuthRepositoryBase {
  _TeacherFlowRepository({
    this.loginUser,
    this.loginThrows,
    this.persistedUser,
  });

  User? loginUser;
  Object? loginThrows;
  User? persistedUser;
  int registerCallCount = 0;
  String? lastDefaultRole;
  bool verificationRequested = false;
  bool emailVerified = false;
  bool clearCalled = false;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
  }) async {
    registerCallCount++;
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
  Future<User> login({required String email, required String password}) async {
    if (loginThrows != null) throw loginThrows!;
    if (loginUser != null) return loginUser!;
    throw const MissingUserProfileException();
  }

  @override
  Future<User?> loadPersistedUser() async => persistedUser;

  @override
  Future<void> clearCurrentUser() async {
    clearCalled = true;
  }

  @override
  Future<bool> isCurrentEmailVerified() async => emailVerified;

  @override
  Future<void> requestCurrentEmailVerification() async {
    verificationRequested = true;
  }

  @override
  Future<User?> refreshAuthenticatedUser() async => loginUser;

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

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

  test(
    'registerTeacher persists Teacher role and requests verification',
    () async {
      final repository = _TeacherFlowRepository();
      repository.emailVerified = false;
      final auth = AuthService(
        repository: repository,
        awaitInitialAuthState: () async {},
      );
      await auth.initialize();

      await auth.registerTeacher(
        firstName: 'Jane',
        lastName: 'Doe',
        email: 'jane@school.edu',
        password: 'secret1',
      );

      expect(repository.registerCallCount, 1);
      expect(repository.lastDefaultRole, User.roleTeacher);
      expect(repository.verificationRequested, isTrue);
      expect(auth.currentUser?.isTeacher, isTrue);
      expect(auth.needsTeacherEmailVerification, isTrue);
    },
  );

  test('register persists Trainee role without Teacher verification', () async {
    final repository = _TeacherFlowRepository();
    final auth = AuthService(
      repository: repository,
      awaitInitialAuthState: () async {},
    );
    await auth.initialize();

    await auth.register(
      firstName: 'Ada',
      lastName: 'Lovelace',
      email: 'ada@example.com',
      password: 'secret1',
    );

    expect(repository.registerCallCount, 1);
    expect(repository.lastDefaultRole, User.roleTrainee);
    expect(auth.currentUser?.isTrainee, isTrue);
    expect(auth.needsTeacherEmailVerification, isFalse);
    expect(repository.verificationRequested, isFalse);
  });

  test('login rejects Admin role without granting product access', () async {
    final repository = _TeacherFlowRepository(
      loginUser: User(
        id: 'admin-1',
        firstName: 'Ad',
        lastName: 'Min',
        email: 'admin@example.com',
        role: User.roleAdmin,
      ),
    );
    final auth = AuthService(
      repository: repository,
      awaitInitialAuthState: () async {},
    );
    await auth.initialize();

    await expectLater(
      auth.login(email: 'admin@example.com', password: 'secret1'),
      throwsA(
        predicate(
          (error) =>
              error.toString().contains(TeacherAuthMessages.unsupportedRole),
        ),
      ),
    );
    expect(auth.isAuthenticated, isFalse);
    expect(auth.currentUser, isNull);
    expect(repository.clearCalled, isTrue);
  });

  test('login rejects unknown role without granting product access', () async {
    final repository = _TeacherFlowRepository(
      loginUser: User(
        id: 'unknown-1',
        firstName: 'Un',
        lastName: 'Known',
        email: 'unknown@example.com',
        role: 'Moderator',
      ),
    );
    final auth = AuthService(
      repository: repository,
      awaitInitialAuthState: () async {},
    );
    await auth.initialize();

    await expectLater(
      auth.login(email: 'unknown@example.com', password: 'secret1'),
      throwsA(
        predicate(
          (error) =>
              error.toString().contains(TeacherAuthMessages.unsupportedRole),
        ),
      ),
    );
    expect(auth.isAuthenticated, isFalse);
    expect(auth.currentUser, isNull);
    expect(repository.clearCalled, isTrue);
  });

  test(
    'initialize signs out persisted unsupported role without product access',
    () async {
      final repository = _TeacherFlowRepository(
        persistedUser: User(
          id: 'admin-1',
          firstName: 'Ad',
          lastName: 'Min',
          email: 'admin@example.com',
          role: User.roleAdmin,
        ),
      );
      final auth = AuthService(
        repository: repository,
        awaitInitialAuthState: () async {},
      );
      await auth.initialize();

      expect(auth.isAuthenticated, isFalse);
      expect(auth.currentUser, isNull);
      expect(repository.clearCalled, isTrue);
    },
  );

  test(
    'login with missing profile fails closed without synthesizing Trainee',
    () async {
      final repository = _TeacherFlowRepository(
        loginThrows: const MissingUserProfileException(),
      );
      final auth = AuthService(
        repository: repository,
        awaitInitialAuthState: () async {},
      );
      await auth.initialize();

      await expectLater(
        auth.login(email: 'ghost@example.com', password: 'secret1'),
        throwsA(
          predicate(
            (error) =>
                error.toString().contains(TeacherAuthMessages.missingProfile),
          ),
        ),
      );
      expect(auth.isAuthenticated, isFalse);
    },
  );

  test(
    'verified teacher login sets needsTeacherEmailVerification false',
    () async {
      final repository = _TeacherFlowRepository(
        loginUser: User(
          id: 't1',
          firstName: 'T',
          lastName: 'E',
          email: 't@school.edu',
          role: User.roleTeacher,
        ),
      )..emailVerified = true;
      final auth = AuthService(
        repository: repository,
        awaitInitialAuthState: () async {},
      );
      await auth.initialize();

      await auth.login(email: 't@school.edu', password: 'secret1');

      expect(auth.currentUser?.isTeacher, isTrue);
      expect(auth.needsTeacherEmailVerification, isFalse);
    },
  );
}
