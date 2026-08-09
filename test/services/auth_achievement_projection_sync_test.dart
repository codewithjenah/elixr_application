import 'dart:async';

import 'package:elixr_application/data/models/user.dart';
import 'package:elixr_application/data/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

User _user({
  String? id = 'u1',
  String first = 'Ada',
  String last = 'Lovelace',
}) {
  return User(
    id: id,
    firstName: first,
    lastName: last,
    email: 'ada@example.com',
    profilePictureUrl: 'https://example.com/ada.png',
  );
}

class _FakeAuthRepository implements AuthRepositoryBase {
  _FakeAuthRepository({User? persisted, this.loginUser, this.registerUser})
    : persistedUser = persisted;

  User? persistedUser;
  User? loginUser;
  User? registerUser;

  @override
  Future<void> clearCurrentUser() async {
    persistedUser = null;
  }

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<User> login({required String email, required String password}) async {
    return loginUser ?? _user();
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<User?> loadPersistedUser() async => persistedUser;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    return registerUser ?? _user(first: firstName, last: lastName);
  }

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<void> requestCurrentEmailVerification() async {}

  @override
  Future<User?> refreshAuthenticatedUser() async => persistedUser;

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
  }) async => _user(id: userId, first: firstName, last: lastName);

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async => _user(id: userId);
}

class _RecordingPublicProfileRepository extends PublicProfileRepository {
  int syncCalls = 0;
  final syncUserIds = <String>[];
  final syncDisplayNames = <String>[];
  final syncPictureUrls = <String?>[];
  Completer<void>? gate;
  Object? syncError;

  @override
  Future<void> syncClaimedAchievementProjections({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    syncCalls++;
    syncUserIds.add(userId);
    syncDisplayNames.add(displayName);
    syncPictureUrls.add(profilePictureUrl);
    if (gate != null) await gate!.future;
    if (syncError != null) throw syncError!;
  }
}

void main() {
  tearDown(PublicProfileRepository.clearAchievementSyncInFlightForTest);

  test('initialization triggers best-effort projection sync', () async {
    final profiles = _RecordingPublicProfileRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(persisted: _user()),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
    );

    await auth.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(profiles.syncCalls, 1);
    expect(profiles.syncUserIds, ['u1']);
    expect(profiles.syncDisplayNames, ['Ada Lovelace']);
    expect(profiles.syncPictureUrls, ['https://example.com/ada.png']);
    expect(auth.isAuthenticated, isTrue);
  });

  test('login triggers best-effort projection sync', () async {
    final profiles = _RecordingPublicProfileRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(loginUser: _user()),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
    );

    await auth.login(email: 'ada@example.com', password: 'secret');
    await Future<void>.delayed(Duration.zero);

    expect(profiles.syncCalls, 1);
    expect(profiles.syncUserIds.single, 'u1');
    expect(auth.currentUser?.id, 'u1');
  });

  test('registration triggers best-effort projection sync', () async {
    final profiles = _RecordingPublicProfileRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(
        registerUser: _user(id: 'u2', first: 'Grace', last: 'Hopper'),
      ),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
    );

    await auth.register(
      firstName: 'Grace',
      lastName: 'Hopper',
      email: 'grace@example.com',
      password: 'secret',
    );
    await Future<void>.delayed(Duration.zero);

    expect(profiles.syncCalls, 1);
    expect(profiles.syncUserIds.single, 'u2');
    expect(profiles.syncDisplayNames.single, 'Grace Hopper');
  });

  test('projection failure does not fail authentication', () async {
    final profiles = _RecordingPublicProfileRepository()
      ..syncError = Exception('firestore unavailable');
    final auth = AuthService(
      repository: _FakeAuthRepository(loginUser: _user()),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
    );

    await auth.login(email: 'ada@example.com', password: 'secret');
    await Future<void>.delayed(Duration.zero);

    expect(auth.isAuthenticated, isTrue);
    expect(auth.currentUser?.id, 'u1');
    expect(profiles.syncCalls, 1);
  });

  test('missing user id does not start synchronization', () async {
    final profiles = _RecordingPublicProfileRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(persisted: _user(id: null)),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
    );

    await auth.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(auth.currentUser, isNotNull);
    expect(profiles.syncCalls, 0);
  });

  test('empty user id does not start synchronization', () async {
    final profiles = _RecordingPublicProfileRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(persisted: _user(id: '  ')),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
    );

    await auth.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(profiles.syncCalls, 0);
  });
}
