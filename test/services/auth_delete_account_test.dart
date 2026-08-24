import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _TrackingDeleteAccountRepository implements AuthRepositoryBase {
  int deleteAccountCallCount = 0;
  int clearCurrentUserCallCount = 0;
  int emailVerificationCheckCount = 0;
  String? lastPassword;
  String? lastExpectedUserId;
  Object? errorToThrow;
  bool emailVerified = true;

  @override
  Future<void> deleteAccount({
    required String password,
    required String expectedUserId,
  }) async {
    deleteAccountCallCount++;
    lastPassword = password;
    lastExpectedUserId = expectedUserId;
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<void> clearCurrentUser() async {
    clearCurrentUserCallCount++;
  }

  @override
  Future<bool> isCurrentEmailVerified() async {
    emailVerificationCheckCount++;
    return emailVerified;
  }

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();

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
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {}

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

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
}

void main() {
  const sampleUser = User(
    id: 'uid-1',
    firstName: 'Ada',
    lastName: 'Lovelace',
    email: 'Ada@Example.com',
  );

  AuthService buildService(_TrackingDeleteAccountRepository repo) {
    return AuthService(repository: repo);
  }

  test('confirmation phrase is account-scoped and canonical', () {
    expect(
      accountDeletionConfirmationPhraseFor(' Ada@Example.com '),
      'delete ada@example.com',
    );
  });

  test(
    'deleteAccount reauthenticates the expected user and clears auth',
    () async {
      final repo = _TrackingDeleteAccountRepository();
      final service = buildService(repo);
      addTearDown(service.dispose);
      service.seedAuthenticatedUser(sampleUser);

      await service.deleteAccount(
        password: 'secret',
        confirmationPhrase: 'delete ada@example.com',
      );

      expect(repo.deleteAccountCallCount, 1);
      expect(repo.lastPassword, 'secret');
      expect(repo.lastExpectedUserId, 'uid-1');
      expect(repo.clearCurrentUserCallCount, 1);
      expect(repo.emailVerificationCheckCount, 0);
      expect(service.isAuthenticated, isFalse);
      expect(service.currentUser, isNull);
      expect(
        service.takeAccountDeletedMessage(),
        'Your account and associated data have been permanently deleted.',
      );
      expect(service.takeAccountDeletedMessage(), isNull);
    },
  );

  test('wrong typed phrase never starts account deletion', () async {
    final repo = _TrackingDeleteAccountRepository();
    final service = buildService(repo);
    addTearDown(service.dispose);
    service.seedAuthenticatedUser(sampleUser);

    await expectLater(
      () => service.deleteAccount(
        password: 'secret',
        confirmationPhrase: 'delete someone@example.com',
      ),
      throwsA(
        predicate(
          (error) => error.toString().contains(
            accountDeletionRequiresTypedConfirmationMessage,
          ),
        ),
      ),
    );

    expect(repo.deleteAccountCallCount, 0);
    expect(repo.clearCurrentUserCallCount, 0);
    expect(service.isAuthenticated, isTrue);
  });

  test('unverified email does not block password-authorized erasure', () async {
    final repo = _TrackingDeleteAccountRepository()..emailVerified = false;
    final service = buildService(repo);
    addTearDown(service.dispose);
    service.seedAuthenticatedUser(sampleUser);

    await service.deleteAccount(
      password: 'secret',
      confirmationPhrase: 'delete ada@example.com',
    );

    expect(repo.deleteAccountCallCount, 1);
    expect(repo.emailVerificationCheckCount, 0);
  });

  test('delete failure preserves local authentication state', () async {
    final repo = _TrackingDeleteAccountRepository()
      ..errorToThrow = Exception('purge failed');
    final service = buildService(repo);
    addTearDown(service.dispose);
    service.seedAuthenticatedUser(sampleUser);

    await expectLater(
      () => service.deleteAccount(
        password: 'secret',
        confirmationPhrase: 'delete ada@example.com',
      ),
      throwsA(isA<Exception>()),
    );

    expect(service.isAuthenticated, isTrue);
    expect(service.currentUser?.id, 'uid-1');
    expect(repo.clearCurrentUserCallCount, 0);
    expect(service.takeAccountDeletedMessage(), isNull);
  });

  test('missing persisted user id never reaches repository deletion', () async {
    final repo = _TrackingDeleteAccountRepository();
    final service = buildService(repo);
    addTearDown(service.dispose);
    service.seedAuthenticatedUser(
      const User(
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
      ),
    );

    await expectLater(
      () => service.deleteAccount(
        password: 'secret',
        confirmationPhrase: 'delete ada@example.com',
      ),
      throwsA(isA<Exception>()),
    );

    expect(repo.deleteAccountCallCount, 0);
  });
}
