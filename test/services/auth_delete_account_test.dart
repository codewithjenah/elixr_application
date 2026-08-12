import 'package:elixr_application/data/models/user.dart';
import 'package:elixr_application/data/repositories/auth_repository.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _TrackingDeleteAccountRepository implements AuthRepositoryBase {
  int deleteAccountCallCount = 0;
  int clearCurrentUserCallCount = 0;
  String? lastPassword;
  Object? errorToThrow;

  @override
  Future<void> deleteAccount({required String password}) async {
    deleteAccountCallCount++;
    lastPassword = password;
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  Future<void> clearCurrentUser() async {
    clearCurrentUserCallCount++;
  }

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
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<void> requestCurrentEmailVerification() async {}

  @override
  Future<User?> refreshAuthenticatedUser() async => null;

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

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
    email: 'ada@example.com',
  );

  test(
    'deleteAccount clears local auth and exposes one-shot message',
    () async {
      final repo = _TrackingDeleteAccountRepository();
      final service = AuthService(repository: repo);
      service.seedAuthenticatedUser(sampleUser);

      await service.deleteAccount(password: 'secret');

      expect(repo.deleteAccountCallCount, 1);
      expect(repo.lastPassword, 'secret');
      expect(repo.clearCurrentUserCallCount, 1);
      expect(service.isAuthenticated, isFalse);
      expect(service.currentUser, isNull);
      expect(
        service.takeAccountDeletedMessage(),
        'Your account and associated data have been permanently deleted.',
      );
      expect(service.takeAccountDeletedMessage(), isNull);
    },
  );

  test(
    'deleteAccount failure leaves auth state and does not set message',
    () async {
      final repo = _TrackingDeleteAccountRepository()
        ..errorToThrow = Exception('purge failed');
      final service = AuthService(repository: repo);
      service.seedAuthenticatedUser(sampleUser);

      await expectLater(
        () => service.deleteAccount(password: 'secret'),
        throwsA(isA<Exception>()),
      );

      expect(service.isAuthenticated, isTrue);
      expect(service.currentUser?.id, 'uid-1');
      expect(repo.clearCurrentUserCallCount, 0);
      expect(service.takeAccountDeletedMessage(), isNull);
    },
  );

  // Storage-list failure → Auth.delete skipped is covered at repository level in
  // test/data/repositories/auth_account_deletion_storage_test.dart.
}
