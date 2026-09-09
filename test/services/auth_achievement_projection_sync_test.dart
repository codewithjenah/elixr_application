import 'dart:async';

import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
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
  Completer<void>? clearGate;
  Completer<User>? loginGate;

  @override
  Future<void> clearCurrentUser() async {
    persistedUser = null;
    await clearGate?.future;
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
    return await loginGate?.future ?? loginUser ?? _user();
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {}

  @override
  Future<User?> loadPersistedUser() async => persistedUser;

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
    return registerUser ?? _user(first: firstName, last: lastName);
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
  Future<User?> refreshAuthenticatedUser() async => persistedUser;

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
  int seedCalls = 0;
  final syncUserIds = <String>[];
  final syncDisplayNames = <String>[];
  final syncPictureUrls = <String?>[];
  final callOrder = <String>[];
  Completer<void>? gate;
  Object? syncError;
  Object? seedError;
  bool? identityAfterGate;

  @override
  Future<void> seedNewAccountPublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    String? role,
  }) async {
    seedCalls++;
    callOrder.add('seed');
    if (seedError != null) throw seedError!;
  }

  @override
  Future<void> syncClaimedAchievementProjections({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    bool Function()? isCurrentIdentity,
  }) async {
    syncCalls++;
    callOrder.add('sync');
    syncUserIds.add(userId);
    syncDisplayNames.add(displayName);
    syncPictureUrls.add(profilePictureUrl);
    if (gate != null) await gate!.future;
    identityAfterGate = isCurrentIdentity?.call();
    if (syncError != null) throw syncError!;
  }
}

class _RecordingLeaderboardRepository extends LeaderboardRepository {
  int touchCalls = 0;
  final touchedUserIds = <String>[];
  Object? touchError;

  @override
  Future<bool> touchLastActive({
    required String userId,
    DateTime? nowUtc,
  }) async {
    touchCalls++;
    touchedUserIds.add(userId);
    if (touchError != null) throw touchError!;
    return true;
  }
}

void main() {
  tearDown(PublicProfileRepository.clearAchievementSyncInFlightForTest);
  tearDown(LeaderboardRepository.clearLastActiveTouchForTest);

  test('initialization triggers best-effort projection sync', () async {
    final profiles = _RecordingPublicProfileRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(persisted: _user()),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => 'u1',
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
      currentFirebaseAuthUid: () => 'u1',
    );

    await auth.login(email: 'ada@example.com', password: 'secret');
    await Future<void>.delayed(Duration.zero);

    expect(profiles.syncCalls, 1);
    expect(profiles.syncUserIds.single, 'u1');
    expect(auth.currentUser?.id, 'u1');
  });

  test('registration seeds public profile before projection sync', () async {
    final profiles = _RecordingPublicProfileRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(
        registerUser: _user(id: 'u2', first: 'Grace', last: 'Hopper'),
      ),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => 'u2',
    );

    await auth.register(
      firstName: 'Grace',
      lastName: 'Hopper',
      email: 'grace@example.com',
      password: 'secret',
      legalConsent: RegistrationLegalConsent.current(),
    );
    await Future<void>.delayed(Duration.zero);

    expect(profiles.seedCalls, 1);
    expect(profiles.syncCalls, 1);
    expect(profiles.callOrder, ['seed', 'sync']);
    expect(profiles.syncUserIds.single, 'u2');
    expect(profiles.syncDisplayNames.single, 'Grace Hopper');
  });

  test('registration seed failure does not fail authentication', () async {
    final profiles = _RecordingPublicProfileRepository()
      ..seedError = Exception('firestore unavailable');
    final auth = AuthService(
      repository: _FakeAuthRepository(
        registerUser: _user(id: 'u2', first: 'Grace', last: 'Hopper'),
      ),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => 'u2',
    );

    await auth.register(
      firstName: 'Grace',
      lastName: 'Hopper',
      email: 'grace@example.com',
      password: 'secret',
      legalConsent: RegistrationLegalConsent.current(),
    );
    await Future<void>.delayed(Duration.zero);

    expect(auth.isAuthenticated, isTrue);
    expect(auth.currentUser?.id, 'u2');
    expect(profiles.seedCalls, 1);
    expect(profiles.syncCalls, 1);
    expect(profiles.callOrder, ['seed', 'sync']);
  });

  test('registration triggers best-effort projection sync', () async {
    final profiles = _RecordingPublicProfileRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(
        registerUser: _user(id: 'u2', first: 'Grace', last: 'Hopper'),
      ),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => 'u2',
    );

    await auth.register(
      firstName: 'Grace',
      lastName: 'Hopper',
      email: 'grace@example.com',
      password: 'secret',
      legalConsent: RegistrationLegalConsent.current(),
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
      currentFirebaseAuthUid: () => 'u1',
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

  test('initialization touches last-active for a restored user', () async {
    final leaderboard = _RecordingLeaderboardRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(persisted: _user()),
      leaderboardRepository: leaderboard,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => 'u1',
    );

    await auth.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(leaderboard.touchCalls, 1);
    expect(leaderboard.touchedUserIds, ['u1']);
    expect(auth.isAuthenticated, isTrue);
  });

  test('login touches last-active for the authenticated user', () async {
    final leaderboard = _RecordingLeaderboardRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(loginUser: _user()),
      leaderboardRepository: leaderboard,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => 'u1',
    );

    await auth.login(email: 'ada@example.com', password: 'secret');
    await Future<void>.delayed(Duration.zero);

    expect(leaderboard.touchCalls, 1);
    expect(leaderboard.touchedUserIds.single, 'u1');
  });

  test('presence touch failure does not fail authentication', () async {
    final leaderboard = _RecordingLeaderboardRepository()
      ..touchError = Exception('firestore unavailable');
    final auth = AuthService(
      repository: _FakeAuthRepository(loginUser: _user()),
      leaderboardRepository: leaderboard,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => 'u1',
    );

    await auth.login(email: 'ada@example.com', password: 'secret');
    await Future<void>.delayed(Duration.zero);

    expect(auth.isAuthenticated, isTrue);
    expect(auth.currentUser?.id, 'u1');
    expect(leaderboard.touchCalls, 1);
  });

  test('missing user id does not start a presence touch', () async {
    final leaderboard = _RecordingLeaderboardRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(persisted: _user(id: null)),
      leaderboardRepository: leaderboard,
      awaitInitialAuthState: () async {},
    );

    await auth.initialize();
    await Future<void>.delayed(Duration.zero);

    expect(leaderboard.touchCalls, 0);
  });

  test('presence touch is abandoned when Firebase switches accounts', () async {
    var firebaseUid = 'trainee-a';
    final leaderboard = _RecordingLeaderboardRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(),
      leaderboardRepository: leaderboard,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => firebaseUid,
    );
    auth.seedAuthenticatedUser(_user(id: 'trainee-a'));

    auth.touchLeaderboardPresence();
    firebaseUid = 'teacher-b';
    auth.handleFirebaseAuthIdentityChanged(firebaseUid);
    await Future<void>.delayed(Duration.zero);

    expect(auth.currentUser, isNull);
    expect(leaderboard.touchCalls, 0);
  });

  test('presence touch is abandoned when Firebase becomes null', () async {
    String? firebaseUid = 'teacher-a';
    final leaderboard = _RecordingLeaderboardRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(),
      leaderboardRepository: leaderboard,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => firebaseUid,
    );
    auth.seedAuthenticatedUser(_user(id: 'teacher-a'));

    auth.touchLeaderboardPresence();
    firebaseUid = null;
    auth.handleFirebaseAuthIdentityChanged(null);
    await Future<void>.delayed(Duration.zero);

    expect(auth.currentUser, isNull);
    expect(leaderboard.touchCalls, 0);
  });

  test('presence touch is abandoned when AuthService is disposed', () async {
    final leaderboard = _RecordingLeaderboardRepository();
    final auth = AuthService(
      repository: _FakeAuthRepository(),
      leaderboardRepository: leaderboard,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => 'u1',
    );
    auth.seedAuthenticatedUser(_user());

    auth.touchLeaderboardPresence();
    auth.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(leaderboard.touchCalls, 0);
  });

  test('in-flight projection observes account invalidation', () async {
    String? firebaseUid = 'account-a';
    final gate = Completer<void>();
    final profiles = _RecordingPublicProfileRepository()..gate = gate;
    final auth = AuthService(
      repository: _FakeAuthRepository(loginUser: _user(id: 'account-a')),
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
      currentFirebaseAuthUid: () => firebaseUid,
    );
    await auth.login(email: 'a@example.com', password: 'secret');
    await Future<void>.delayed(Duration.zero);
    firebaseUid = 'account-b';
    auth.handleFirebaseAuthIdentityChanged(firebaseUid);
    gate.complete();
    await pumpEventQueue();

    expect(profiles.identityAfterGate, isFalse);
  });

  test('Firebase auth stream invalidates the published account', () async {
    String? firebaseUid = 'account-a';
    var listenCount = 0;
    final authStates = StreamController<String?>.broadcast(
      onListen: () => listenCount++,
    );
    addTearDown(authStates.close);
    final auth = AuthService(
      repository: _FakeAuthRepository(persisted: _user(id: 'account-a')),
      firebaseAuthUidChanges: authStates.stream,
      currentFirebaseAuthUid: () => firebaseUid,
    );
    addTearDown(auth.dispose);

    final initialization = auth.initialize();
    authStates.add(firebaseUid);
    await initialization;
    expect(auth.currentUser?.id, 'account-a');
    expect(listenCount, 1);

    firebaseUid = null;
    authStates.add(null);
    await pumpEventQueue();
    expect(auth.currentUser, isNull);
    expect(listenCount, 1);
  });

  test('logout publishes null before Firebase sign-out completes', () async {
    final clearGate = Completer<void>();
    final repository = _FakeAuthRepository()..clearGate = clearGate;
    final auth = AuthService(
      repository: repository,
      awaitInitialAuthState: () async {},
    );
    auth.seedAuthenticatedUser(_user(id: 'account-a'));
    var notifications = 0;
    auth.addListener(() => notifications++);

    final logout = auth.logout();
    await Future<void>.delayed(Duration.zero);

    expect(auth.currentUser, isNull);
    expect(notifications, greaterThan(0));
    expect(clearGate.isCompleted, isFalse);
    clearGate.complete();
    await logout;
  });

  test(
    'second-account login invalidates the first account before auth work',
    () async {
      final loginGate = Completer<User>();
      final repository = _FakeAuthRepository()..loginGate = loginGate;
      final auth = AuthService(
        repository: repository,
        awaitInitialAuthState: () async {},
      );
      auth.seedAuthenticatedUser(_user(id: 'account-a'));

      final login = auth.login(email: 'b@example.com', password: 'secret');
      await Future<void>.delayed(Duration.zero);
      expect(auth.currentUser, isNull);

      loginGate.complete(_user(id: 'account-b'));
      await login;
      expect(auth.currentUser?.id, 'account-b');
    },
  );
}
