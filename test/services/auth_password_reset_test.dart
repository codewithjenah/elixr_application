import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _TrackingPasswordResetRepository implements AuthRepositoryBase {
  int sendPasswordResetEmailCallCount = 0;
  String? lastEmail;
  Object? errorToThrow;

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TrackingPasswordResetRepository repository;
  late AuthService authService;

  setUp(() {
    repository = _TrackingPasswordResetRepository();
    authService = AuthService(
      repository: repository,
      leaderboardRepository: null,
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
    });
  });
}
