import 'dart:io';

import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_application/services/trainee_profile_snapshot_store.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineRestoreRepository
    implements AuthRepositoryBase, PersistedProfileRestorationRepository {
  _OfflineRestoreRepository(this.restoration);

  PersistedProfileRestoration restoration;
  User? refreshUser;
  bool emailVerified = true;
  bool clearCalled = false;
  bool deleteCalled = false;

  @override
  Future<PersistedProfileRestoration> restorePersistedProfile() async =>
      restoration;

  @override
  Future<User?> loadPersistedUser() async => restoration.user;

  @override
  Future<void> clearCurrentUser() async => clearCalled = true;

  @override
  Future<User> login({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
    required String defaultRole,
    String? teacherAccessCode,
    required RegistrationLegalConsent legalConsent,
  }) => throw UnimplementedError();

  @override
  Future<void> sendPasswordResetEmail({
    String? continueUrl,
    required String email,
  }) async {}

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) => throw UnimplementedError();

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) => throw UnimplementedError();

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<bool> isCurrentEmailVerified() async => emailVerified;

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {}

  @override
  Future<User?> refreshAuthenticatedUser() async => refreshUser;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> deleteAccount({
    required String password,
    required String expectedUserId,
  }) async {
    deleteCalled = true;
  }

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();
}

void main() {
  const trainee = User(
    id: 'trainee-A',
    firstName: 'Ada',
    lastName: 'Lovelace',
    email: 'ada@example.test',
    role: User.roleTrainee,
  );

  Future<(TraineeProfileSnapshotStore, Directory)> createStore() async {
    final directory = await Directory.systemTemp.createTemp('elixr_auth_');
    addTearDown(() => directory.delete(recursive: true));
    return (TraineeProfileSnapshotStore(directory: directory), directory);
  }

  Future<void> saveTrainee(TraineeProfileSnapshotStore store, User user) =>
      store.save(
        TraineeProfileSnapshot.fromAuthoritativeUser(
          user,
          emailVerified: true,
        )!,
      );

  AuthService service({
    required _OfflineRestoreRepository repository,
    required TraineeProfileSnapshotStore store,
    required String? Function() firebaseUid,
  }) => AuthService(
    repository: repository,
    traineeProfileSnapshotStore: store,
    currentFirebaseAuthUid: firebaseUid,
    awaitInitialAuthState: () async {},
  );

  test(
    'authoritative persisted profile refreshes the Trainee snapshot',
    () async {
      final (store, _) = await createStore();
      final auth = service(
        repository: _OfflineRestoreRepository(
          const PersistedProfileRestoration.authoritative(trainee),
        ),
        store: store,
        firebaseUid: () => 'trainee-A',
      );
      addTearDown(auth.dispose);

      await auth.initialize();

      expect(auth.currentUser, trainee);
      expect(auth.isOfflineRestoredTrainee, isFalse);
      expect(auth.isAuthenticatedSessionReady, isTrue);
      expect((await store.load('trainee-A'))?.user.email, trainee.email);
    },
  );

  test(
    'matching persisted Firebase UID restores cached Trainee offline',
    () async {
      final (store, _) = await createStore();
      await saveTrainee(store, trainee);
      final auth = service(
        repository: _OfflineRestoreRepository(
          const PersistedProfileRestoration.unavailable(),
        ),
        store: store,
        firebaseUid: () => 'trainee-A',
      );
      addTearDown(auth.dispose);

      await auth.initialize();

      expect(auth.currentUser?.id, 'trainee-A');
      expect(auth.isOfflineRestoredTrainee, isTrue);
      expect(auth.isAuthenticatedSessionReady, isTrue);
    },
  );

  test('no Firebase identity does not authenticate from a cache', () async {
    final (store, _) = await createStore();
    await saveTrainee(store, trainee);
    final auth = service(
      repository: _OfflineRestoreRepository(
        const PersistedProfileRestoration.unavailable(),
      ),
      store: store,
      firebaseUid: () => null,
    );
    addTearDown(auth.dispose);

    await auth.initialize();

    expect(auth.currentUser, isNull);
    expect(auth.isAuthenticatedSessionReady, isFalse);
  });

  test(
    'a snapshot for another UID cannot restore the active identity',
    () async {
      final (store, _) = await createStore();
      await saveTrainee(
        store,
        trainee.copyWith(id: 'trainee-B', email: 'b@example.test'),
      );
      final auth = service(
        repository: _OfflineRestoreRepository(
          const PersistedProfileRestoration.unavailable(),
        ),
        store: store,
        firebaseUid: () => 'trainee-A',
      );
      addTearDown(auth.dispose);

      await auth.initialize();

      expect(auth.currentUser, isNull);
    },
  );

  test('Teacher cache data cannot restore through the Trainee path', () async {
    final (store, directory) = await createStore();
    await File(
      '${directory.path}${Platform.pathSeparator}profiles.json',
    ).writeAsString(
      '{"schema_version":1,"accounts":{"teacher-A":'
      '{"uid":"teacher-A","role":"Teacher","first_name":"T",'
      '"last_name":"E","email":"t@example.test","email_verified":true}}}',
    );
    final auth = service(
      repository: _OfflineRestoreRepository(
        const PersistedProfileRestoration.unavailable(),
      ),
      store: store,
      firebaseUid: () => 'teacher-A',
    );
    addTearDown(auth.dispose);

    await auth.initialize();

    expect(auth.currentUser, isNull);
  });

  test('invalid authoritative profile never falls back to a cache', () async {
    final (store, _) = await createStore();
    await saveTrainee(store, trainee);
    final auth = service(
      repository: _OfflineRestoreRepository(
        const PersistedProfileRestoration.invalidProfile(),
      ),
      store: store,
      firebaseUid: () => 'trainee-A',
    );
    addTearDown(auth.dispose);

    await auth.initialize();

    expect(auth.currentUser, isNull);
  });

  test(
    'explicit logout removes the snapshot and cannot resurrect it',
    () async {
      final (store, _) = await createStore();
      await saveTrainee(store, trainee);
      final repository = _OfflineRestoreRepository(
        const PersistedProfileRestoration.unavailable(),
      );
      final auth = service(
        repository: repository,
        store: store,
        firebaseUid: () => 'trainee-A',
      );
      addTearDown(auth.dispose);
      await auth.initialize();

      await auth.logout();

      expect(repository.clearCalled, isTrue);
      expect(auth.currentUser, isNull);
      expect(await store.load('trainee-A'), isNull);
    },
  );

  test('account deletion purges the corresponding Trainee snapshot', () async {
    final (store, _) = await createStore();
    await saveTrainee(store, trainee);
    final repository = _OfflineRestoreRepository(
      const PersistedProfileRestoration.authoritative(trainee),
    );
    final auth = service(
      repository: repository,
      store: store,
      firebaseUid: () => 'trainee-A',
    );
    addTearDown(auth.dispose);
    await auth.initialize();

    await auth.deleteAccount(
      password: 'current-password',
      confirmationPhrase: 'delete ada@example.test',
    );

    expect(repository.deleteCalled, isTrue);
    expect(await store.load('trainee-A'), isNull);
  });

  test(
    'foreground refresh replaces offline data and clears offline state',
    () async {
      final (store, _) = await createStore();
      await saveTrainee(store, trainee);
      final refreshed = trainee.copyWith(firstName: 'Grace');
      final repository = _OfflineRestoreRepository(
        const PersistedProfileRestoration.unavailable(),
      )..refreshUser = refreshed;
      final auth = service(
        repository: repository,
        store: store,
        firebaseUid: () => 'trainee-A',
      );
      addTearDown(auth.dispose);
      await auth.initialize();

      await auth.refreshAuthoritativeProfileOnForeground();

      expect(auth.currentUser?.firstName, 'Grace');
      expect(auth.isOfflineRestoredTrainee, isFalse);
      expect((await store.load('trainee-A'))?.user.firstName, 'Grace');
    },
  );
}
