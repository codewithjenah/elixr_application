import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/email_link_ack_store.dart';
import 'package:elixr_application/services/auth_email_callback_server.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/join_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeniedEmailLinkAckStore implements EmailLinkAckStore {
  @override
  Future<void> createPending({
    required String token,
    required String uid,
  }) async {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    );
  }

  @override
  Future<bool> isClicked(String token) async => false;

  @override
  Future<void> delete(String token) async {}
}

class _TrackingDeleteAccountRepository implements AuthRepositoryBase {
  int deleteAccountCallCount = 0;
  int clearCurrentUserCallCount = 0;
  String? lastPassword;
  Object? errorToThrow;
  bool emailVerified = true;

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
  Future<bool> isCurrentEmailVerified() async => emailVerified;

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
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {}

  @override
  Future<void> requestDeleteAccountEmailVerification({
    String confirmationCode = '',
    String? continueUrl,
  }) async {}

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
    email: 'ada@example.com',
  );

  const deleteCode = '123456';

  AuthService buildService(_TrackingDeleteAccountRepository repo) {
    return AuthService(
      repository: repo,
      generateDeleteVerificationCode: () => deleteCode,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
    );
  }

  Future<void> confirmDeleteEmail(AuthService service) async {
    await service.requestDeleteAccountEmailVerification();
    expect(service.confirmDeleteVerificationCode(deleteCode), isTrue);
  }

  test(
    'deleteAccount clears local auth and exposes one-shot message',
    () async {
      final repo = _TrackingDeleteAccountRepository();
      final service = buildService(repo);
      service.seedAuthenticatedUser(sampleUser);
      await confirmDeleteEmail(service);

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
      final service = buildService(repo);
      service.seedAuthenticatedUser(sampleUser);
      await confirmDeleteEmail(service);

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

  test(
    'deleteAccount refuses unverified email without starting purge',
    () async {
      final repo = _TrackingDeleteAccountRepository()..emailVerified = false;
      final service = buildService(repo);
      service.seedAuthenticatedUser(sampleUser);
      await confirmDeleteEmail(service);

      await expectLater(
        () => service.deleteAccount(password: 'secret'),
        throwsA(
          predicate(
            (error) => error.toString().contains(
              accountDeletionRequiresVerifiedEmailMessage,
            ),
          ),
        ),
      );

      expect(repo.deleteAccountCallCount, 0);
      expect(repo.clearCurrentUserCallCount, 0);
      expect(service.isAuthenticated, isTrue);
      expect(service.currentUser?.id, 'uid-1');
      expect(service.takeAccountDeletedMessage(), isNull);
    },
  );

  test('deleteAccount refuses without the email confirmation code', () async {
    final repo = _TrackingDeleteAccountRepository();
    final service = buildService(repo);
    service.seedAuthenticatedUser(sampleUser);

    await expectLater(
      () => service.deleteAccount(password: 'secret'),
      throwsA(
        predicate(
          (error) => error.toString().contains(
            accountDeletionRequiresEmailConfirmationMessage,
          ),
        ),
      ),
    );

    expect(repo.deleteAccountCallCount, 0);
    expect(service.isAuthenticated, isTrue);
  });

  test('wrong delete confirmation code does not unlock delete', () async {
    final repo = _TrackingDeleteAccountRepository();
    final service = buildService(repo);
    service.seedAuthenticatedUser(sampleUser);
    await service.requestDeleteAccountEmailVerification();

    expect(service.confirmDeleteVerificationCode('000000'), isFalse);
    await expectLater(
      () => service.deleteAccount(password: 'secret'),
      throwsA(
        predicate(
          (error) => error.toString().contains(
            accountDeletionRequiresEmailConfirmationMessage,
          ),
        ),
      ),
    );
    expect(repo.deleteAccountCallCount, 0);
  });

  test(
    'email callback after clicking the delete link unlocks delete',
    () async {
      final repo = _TrackingDeleteAccountRepository();
      final service = buildService(repo);
      service.seedAuthenticatedUser(sampleUser);
      await service.requestDeleteAccountEmailVerification();

      service.handleEmailActionCallback(
        Uri.parse(
          'http://localhost:1/elixr-auth?mode=delete&token=$deleteCode',
        ),
      );
      await service.deleteAccount(password: 'secret');
      expect(repo.deleteAccountCallCount, 1);
    },
  );

  test('Firebase verifyEmail redirect still unlocks pending delete', () async {
    final repo = _TrackingDeleteAccountRepository();
    final service = buildService(repo);
    service.seedAuthenticatedUser(sampleUser);
    await service.requestDeleteAccountEmailVerification();

    service.handleEmailActionCallback(
      Uri.parse(
        'http://localhost:1/elixr-auth?mode=verifyEmail&oobCode=abc'
        '&token=$deleteCode',
      ),
    );
    await service.deleteAccount(password: 'secret');
    expect(repo.deleteAccountCallCount, 1);
  });

  test(
    'Firebase redirect without a token still unlocks pending delete',
    () async {
      final repo = _TrackingDeleteAccountRepository();
      final service = buildService(repo);
      service.seedAuthenticatedUser(sampleUser);
      await service.requestDeleteAccountEmailVerification();

      service.handleEmailActionCallback(
        Uri.parse('http://localhost:1/elixr-auth?mode=verifyEmail&oobCode=abc'),
      );
      await service.deleteAccount(password: 'secret');
      expect(repo.deleteAccountCallCount, 1);
    },
  );

  test('elixr://auth from the protocol handler unlocks delete', () async {
    final repo = _TrackingDeleteAccountRepository();
    final joinLinks = JoinLinkService();
    addTearDown(joinLinks.dispose);
    final service = AuthService(
      repository: repo,
      generateDeleteVerificationCode: () => deleteCode,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
      joinLinkService: joinLinks,
    );
    addTearDown(service.dispose);
    service.seedAuthenticatedUser(sampleUser);
    await service.requestDeleteAccountEmailVerification();

    expect(
      joinLinks.acceptUri(
        Uri.parse('elixr://auth?elixr_action=delete&token=$deleteCode'),
      ),
      isTrue,
    );
    await service.deleteAccount(password: 'secret');
    expect(repo.deleteAccountCallCount, 1);
  });

  test('email-link ack from another device unlocks delete', () async {
    final repo = _TrackingDeleteAccountRepository();
    final acks = MemoryEmailLinkAckStore();
    final service = AuthService(
      repository: repo,
      generateDeleteVerificationCode: () => deleteCode,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
      emailLinkAckStore: acks,
      emailLinkAckPollInterval: const Duration(milliseconds: 20),
    );
    addTearDown(service.dispose);
    service.seedAuthenticatedUser(sampleUser);
    await service.requestDeleteAccountEmailVerification();

    acks.markClicked(deleteCode);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await service.deleteAccount(password: 'secret');
    expect(repo.deleteAccountCallCount, 1);
  });

  test(
    'delete email still sends when ack store is permission-denied',
    () async {
      final repo = _TrackingDeleteAccountRepository();
      final service = AuthService(
        repository: repo,
        generateDeleteVerificationCode: () => deleteCode,
        emailCallbackServer: MemoryAuthEmailCallbackServer(),
        emailLinkAckStore: _DeniedEmailLinkAckStore(),
      );
      addTearDown(service.dispose);
      service.seedAuthenticatedUser(sampleUser);

      await service.requestDeleteAccountEmailVerification();
      expect(service.confirmDeleteVerificationCode(deleteCode), isTrue);
    },
  );

  test('extracts a nested Firebase continueUrl token', () {
    expect(
      extractDeleteConfirmationCode(
        'https://elixr-app-2026.firebaseapp.com/__/auth/action'
        '?mode=verifyEmail&oobCode=abc'
        '&continueUrl=${Uri.encodeComponent('http://localhost:1/elixr-auth?mode=delete&token=$deleteCode')}',
      ),
      deleteCode,
    );
  });

  // Storage-list failure → Auth.delete skipped is covered at repository level in
  // test/data/repositories/auth_account_deletion_storage_test.dart.
}
