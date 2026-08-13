import 'dart:async';

import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthRepository implements AuthRepositoryBase {
  FakeAuthRepository({User? initialUser}) : _currentUser = initialUser;

  User? _currentUser;
  PendingEmailChangeRecoveryResult recoveryResult =
      PendingEmailChangeRecoveryResult.pending();
  int recoveryCallCount = 0;
  int requestEmailChangeCallCount = 0;
  EmailChangeRequestResult requestEmailChangeResult =
      EmailChangeRequestResult.verificationSent;
  bool clearCurrentUserCalled = false;
  Future<PendingEmailChangeRecoveryResult> Function({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  })?
  recoveryHandler;

  @override
  Future<void> clearCurrentUser() async {
    clearCurrentUserCalled = true;
    _currentUser = null;
  }

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async {
    recoveryCallCount++;
    if (recoveryHandler != null) {
      return recoveryHandler!(
        originalUid: originalUid,
        pendingEmail: pendingEmail,
        recoveryPassword: recoveryPassword,
        originalEmail: originalEmail,
      );
    }
    return recoveryResult;
  }

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<User?> loadPersistedUser() async => _currentUser;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    String defaultRole = User.roleTrainee,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async {
    requestEmailChangeCallCount++;
    return requestEmailChangeResult;
  }

  @override
  Future<void> requestCurrentEmailVerification() async {}

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
}

User _testUser({String? id, String email = 'old@example.com'}) {
  return User(
    id: id ?? 'uid-1',
    firstName: 'Test',
    lastName: 'User',
    email: email,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService pending email recovery', () {
    late FakeAuthRepository repository;
    late AuthService authService;

    setUp(() async {
      repository = FakeAuthRepository(initialUser: _testUser());
      authService = AuthService(
        repository: repository,
        leaderboardRepository: null,
        pendingEmailPollInterval: const Duration(milliseconds: 50),
        pendingEmailTimeout: const Duration(milliseconds: 200),
      );
      authService.seedAuthenticatedUser(_testUser());
    });

    tearDown(() {
      authService.dispose();
    });

    Future<void> startPendingEmailChange() async {
      await authService.requestEmailChange(
        newEmail: 'new@example.com',
        currentPassword: 'secret-password',
      );
      await authService.waitForPendingEmailCheckIdle();
      expect(authService.hasPendingEmailChange, isTrue);
    }

    test('pending result does not clear AuthService.currentUser', () async {
      await startPendingEmailChange();
      final before = authService.currentUser;

      repository.recoveryResult = PendingEmailChangeRecoveryResult.pending();
      await authService.checkPendingEmailChange();

      expect(authService.currentUser, same(before));
      expect(authService.hasPendingEmailChange, isTrue);
    });

    test('transient failure does not clear AuthService.currentUser', () async {
      await startPendingEmailChange();
      final before = authService.currentUser;

      repository.recoveryResult =
          PendingEmailChangeRecoveryResult.transientFailure();
      await authService.checkPendingEmailChange();

      expect(authService.currentUser, same(before));
      expect(authService.hasPendingEmailChange, isTrue);
    });

    test('completed result updates email while preserving UID', () async {
      await startPendingEmailChange();

      repository.recoveryResult = PendingEmailChangeRecoveryResult.completed(
        _testUser(id: 'uid-1', email: 'new@example.com'),
      );
      await authService.checkPendingEmailChange();

      expect(authService.currentUser?.id, 'uid-1');
      expect(authService.currentUser?.email, 'new@example.com');
      expect(authService.hasPendingEmailChange, isFalse);
    });

    test('mismatched recovered UID is rejected', () async {
      await startPendingEmailChange();

      repository.recoveryResult = PendingEmailChangeRecoveryResult.completed(
        _testUser(id: 'other-uid', email: 'new@example.com'),
      );
      await authService.checkPendingEmailChange();

      expect(authService.currentUser?.id, 'uid-1');
      expect(authService.currentUser?.email, 'old@example.com');
      expect(authService.hasPendingEmailChange, isFalse);
      expect(authService.pendingEmailRecoveryError, isNotNull);
    });

    test(
      'successful recovery clears pending state and stops polling',
      () async {
        await startPendingEmailChange();

        repository.recoveryResult = PendingEmailChangeRecoveryResult.completed(
          _testUser(id: 'uid-1', email: 'new@example.com'),
        );
        await authService.checkPendingEmailChange();

        expect(authService.hasPendingEmailChange, isFalse);
        final callsAfterSuccess = repository.recoveryCallCount;

        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(repository.recoveryCallCount, callsAfterSuccess);
      },
    );

    test('timeout clears pending state and stops polling', () async {
      authService.dispose();
      authService = AuthService(
        repository: repository,
        leaderboardRepository: null,
        pendingEmailPollInterval: const Duration(milliseconds: 30),
        pendingEmailTimeout: const Duration(milliseconds: 80),
      );
      authService.seedAuthenticatedUser(_testUser());

      await authService.requestEmailChange(
        newEmail: 'new@example.com',
        currentPassword: 'secret-password',
      );
      await authService.waitForPendingEmailCheckIdle();

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(authService.hasPendingEmailChange, isFalse);
      expect(authService.pendingEmailRecoveryError, isNotNull);
    });

    test('logout clears pending recovery state', () async {
      await startPendingEmailChange();

      await authService.logout();

      expect(authService.hasPendingEmailChange, isFalse);
      expect(authService.currentUser, isNull);
      expect(repository.clearCurrentUserCalled, isTrue);
      expect(authService.pendingEmailRecoveryError, isNull);
    });

    test('repeated checks cannot overlap', () async {
      await startPendingEmailChange();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      repository.recoveryCallCount = 0;

      final completer = Completer<PendingEmailChangeRecoveryResult>();
      var inFlightChecks = 0;
      var maxConcurrentChecks = 0;

      repository.recoveryHandler =
          ({
            required String originalUid,
            required String pendingEmail,
            required String recoveryPassword,
            String? originalEmail,
          }) async {
            inFlightChecks++;
            maxConcurrentChecks = inFlightChecks > maxConcurrentChecks
                ? inFlightChecks
                : maxConcurrentChecks;
            final result = await completer.future;
            inFlightChecks--;
            return result;
          };

      final first = authService.checkPendingEmailChange();
      final second = authService.checkPendingEmailChange();
      final third = authService.checkPendingEmailChange();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(maxConcurrentChecks, 1);

      completer.complete(PendingEmailChangeRecoveryResult.pending());
      await Future.wait([first, second, third]);

      expect(repository.recoveryCallCount, 1);
    });
  });
}
