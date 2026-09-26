import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/services/auth_email_callback_server.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _TrackingCallbackServer extends MemoryAuthEmailCallbackServer {
  int stopCalls = 0;

  @override
  Future<void> stop() async {
    stopCalls++;
    await super.stop();
  }
}

class _TrackingPasswordResetRepository
    implements AuthRepositoryBase, EmailLinkAuthRepositoryBase {
  int sendPasswordResetEmailCallCount = 0;
  String? lastResetCode;
  String? lastNewPassword;

  @override
  Future<void> completeEmailVerificationLink(String code) async {}

  @override
  Future<void> completePasswordReset({
    required String code,
    required String newPassword,
  }) async {
    lastResetCode = code;
    lastNewPassword = newPassword;
  }

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TrackingPasswordResetRepository repository;
  late AuthService authService;
  late _TrackingCallbackServer callbackServer;

  setUp(() {
    repository = _TrackingPasswordResetRepository();
    callbackServer = _TrackingCallbackServer();
    authService = AuthService(
      repository: repository,
      leaderboardRepository: null,
      emailCallbackServer: callbackServer,
    );
  });

  tearDown(() {
    authService.dispose();
  });

  group('AuthService.sendPasswordResetEmail', () {
    test('delegates the email to the repository', () async {
      await authService.sendPasswordResetEmail(email: 'user@example.com');

      expect(repository.sendPasswordResetEmailCallCount, 1);
      expect(repository.lastEmail, 'user@example.com');
    });

    test('a bare reset redirect does not confirm the reset', () async {
      await authService.sendPasswordResetEmail(email: 'user@example.com');
      expect(authService.hasConfirmedPasswordResetLink, isFalse);

      authService.handleEmailActionCallback(
        Uri.parse('http://localhost:1/elixr-auth?elixr_action=reset'),
      );

      expect(authService.hasConfirmedPasswordResetLink, isFalse);
    });

    test('the local new-password form completes the reset', () async {
      await authService.sendPasswordResetEmail(email: 'user@example.com');

      final error = await callbackServer.passwordResetHandler!(
        'recovery-code',
        'NewPassw0rd',
      );

      expect(error, isNull);
      expect(repository.lastResetCode, 'recovery-code');
      expect(repository.lastNewPassword, 'NewPassw0rd');
      expect(authService.hasConfirmedPasswordResetLink, isTrue);
    });

    test('weak passwords are rejected before reaching the server', () async {
      final error = await callbackServer.passwordResetHandler!('c', 'short');

      expect(error, isNotNull);
      expect(repository.lastResetCode, isNull);
      expect(authService.hasConfirmedPasswordResetLink, isFalse);
    });

    test('propagates repository failures', () async {
      repository.errorToThrow = Exception('Too many attempts. Try again later');

      await expectLater(
        () => authService.sendPasswordResetEmail(email: 'user@example.com'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Too many attempts'),
          ),
        ),
      );
      expect(callbackServer.stopCalls, 1);
    });
  });
}
