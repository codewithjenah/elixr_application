import 'dart:async';

import 'package:elixr_application/core/auth/teacher_auth_messages.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/services/auth_email_callback_server.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingPublicProfileRepository extends PublicProfileRepository {
  int seedCalls = 0;
  final seededUserIds = <String>[];

  @override
  Future<void> seedNewAccountPublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    String? role,
  }) async {
    seedCalls++;
    seededUserIds.add(userId);
  }
}

class _TeacherFlowRepository
    implements AuthRepositoryBase, TeacherAuthorizationRepositoryBase {
  _TeacherFlowRepository({
    this.loginUser,
    this.loginThrows,
    this.persistedUser,
  });

  User? loginUser;
  User? refreshUser;
  Object? loginThrows;
  User? persistedUser;
  int registerCallCount = 0;
  String? lastDefaultRole;
  bool verificationRequested = false;
  bool emailVerified = false;
  bool staleTokenRefreshSucceeds = false;
  bool clearCalled = false;
  int isCurrentEmailVerifiedCalls = 0;
  int refreshAuthenticatedUserCalls = 0;
  Object? isCurrentEmailVerifiedThrows;
  Object? refreshAuthenticatedUserThrows;
  Object? ensureTeacherRoleClaimThrows;
  int ensureTeacherRoleClaimCalls = 0;

  @override
  Future<void> ensureTeacherRoleClaim() async {
    ensureTeacherRoleClaimCalls++;
    if (ensureTeacherRoleClaimThrows != null) {
      throw ensureTeacherRoleClaimThrows!;
    }
  }

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
  Future<bool> isCurrentEmailVerified() async {
    isCurrentEmailVerifiedCalls++;
    if (isCurrentEmailVerifiedThrows != null) {
      throw isCurrentEmailVerifiedThrows!;
    }
    if (staleTokenRefreshSucceeds) {
      emailVerified = true;
      return true;
    }
    return emailVerified;
  }

  @override
  Future<void> requestCurrentEmailVerification({String? continueUrl}) async {
    verificationRequested = true;
  }

  @override
  Future<User?> refreshAuthenticatedUser() async {
    refreshAuthenticatedUserCalls++;
    if (refreshAuthenticatedUserThrows != null) {
      throw refreshAuthenticatedUserThrows!;
    }
    return refreshUser ?? loginUser;
  }

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? continueUrl,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
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
      final profiles = _RecordingPublicProfileRepository();
      final auth = AuthService(
        repository: repository,
        publicProfileRepository: profiles,
        emailCallbackServer: MemoryAuthEmailCallbackServer(),
        awaitInitialAuthState: () async {},
      );
      await auth.initialize();

      await auth.registerTeacher(
        firstName: 'Jane',
        lastName: 'Doe',
        email: 'jane@school.edu',
        password: 'secret1',
        teacherAccessCode: '7KPM-XR4D-Q2WT',
        legalConsent: RegistrationLegalConsent.current(),
      );

      expect(repository.registerCallCount, 1);
      expect(repository.lastDefaultRole, User.roleTeacher);
      expect(repository.ensureTeacherRoleClaimCalls, 1);
      expect(repository.verificationRequested, isTrue);
      expect(auth.currentUser?.isTeacher, isTrue);
      expect(auth.needsEmailVerification, isTrue);
      expect(profiles.seedCalls, 1);
      expect(profiles.seededUserIds, ['teacher-new']);
    },
  );

  test(
    'register persists Trainee role and requests email verification',
    () async {
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
        legalConsent: RegistrationLegalConsent.current(),
      );

      expect(repository.registerCallCount, 1);
      expect(repository.lastDefaultRole, User.roleTrainee);
      expect(repository.ensureTeacherRoleClaimCalls, 0);
      expect(auth.currentUser?.isTrainee, isTrue);
      expect(repository.verificationRequested, isTrue);
      expect(auth.needsEmailVerification, isTrue);
    },
  );

  test('unverified trainee login sets needsEmailVerification true', () async {
    final repository = _TeacherFlowRepository(
      loginUser: User(
        id: 'tr1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        role: User.roleTrainee,
      ),
    );
    final auth = AuthService(
      repository: repository,
      awaitInitialAuthState: () async {},
    );
    await auth.initialize();

    await auth.login(email: 'ada@example.com', password: 'secret1');

    expect(auth.currentUser?.isTrainee, isTrue);
    expect(auth.needsEmailVerification, isTrue);
  });

  test('verified trainee login sets needsEmailVerification false', () async {
    final repository = _TeacherFlowRepository(
      loginUser: User(
        id: 'tr1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        role: User.roleTrainee,
      ),
    )..emailVerified = true;
    final auth = AuthService(
      repository: repository,
      awaitInitialAuthState: () async {},
    );
    await auth.initialize();

    await auth.login(email: 'ada@example.com', password: 'secret1');

    expect(auth.currentUser?.isTrainee, isTrue);
    expect(auth.needsEmailVerification, isFalse);
  });

  test('initialize gates persisted unverified trainee', () async {
    final repository = _TeacherFlowRepository(
      persistedUser: User(
        id: 'tr1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        role: User.roleTrainee,
      ),
    );
    final auth = AuthService(
      repository: repository,
      awaitInitialAuthState: () async {},
    );
    await auth.initialize();

    expect(auth.isAuthenticated, isTrue);
    expect(auth.currentUser?.isTrainee, isTrue);
    expect(auth.needsEmailVerification, isTrue);
    expect(auth.isLoading, isFalse);
    expect(auth.initializationState, AuthInitializationState.ready);
    expect(auth.initializationFailure, isNull);
  });

  test(
    'initialize resolves loading and exposes a safe dependency failure',
    () async {
      final loadingStates = <bool>[];
      final auth = AuthService(
        repository: _TeacherFlowRepository(),
        awaitInitialAuthState: () async {
          throw StateError('Bearer token and internal endpoint details');
        },
      );
      addTearDown(auth.dispose);
      auth.addListener(() => loadingStates.add(auth.isLoading));

      await auth.initialize();

      expect(loadingStates, <bool>[true, false]);
      expect(auth.isLoading, isFalse);
      expect(auth.initializationState, AuthInitializationState.failed);
      expect(auth.initializationFailure, isNotNull);
      expect(
        auth.initializationFailure!.message,
        "ELIXR couldn't finish preparing your session. Check your connection and try again.",
      );
      expect(auth.initializationFailure!.message, isNot(contains('Bearer')));
      expect(auth.currentUser, isNull);
    },
  );

  test(
    'initialize fails closed when restored Teacher claim finalization throws',
    () async {
      final repository =
          _TeacherFlowRepository(
              persistedUser: const User(
                id: 'legacy-teacher',
                firstName: 'Legacy',
                lastName: 'Teacher',
                email: 'legacy@school.edu',
                role: User.roleTeacher,
              ),
            )
            ..ensureTeacherRoleClaimThrows = const TeacherRoleClaimException(
              TeacherRoleClaimFailureKind.missingClaim,
              'internal claim response and token details',
            );
      final auth = AuthService(
        repository: repository,
        awaitInitialAuthState: () async {},
      );
      addTearDown(auth.dispose);

      await auth.initialize();

      expect(auth.isLoading, isFalse);
      expect(auth.initializationState, AuthInitializationState.failed);
      expect(
        auth.initializationFailure?.kind,
        AuthInitializationFailureKind.teacherAuthorization,
      );
      expect(auth.initializationFailure?.message, isNot(contains('internal')));
      expect(auth.currentUser, isNull);
      expect(auth.isAuthenticated, isFalse);
      expect(repository.ensureTeacherRoleClaimCalls, 1);
    },
  );

  test('initialize retry is serialized and clears the prior failure', () async {
    final firstAttemptGate = Completer<void>();
    var attempts = 0;
    var activeAttempts = 0;
    var maximumActiveAttempts = 0;
    final auth = AuthService(
      repository: _TeacherFlowRepository(),
      awaitInitialAuthState: () async {
        attempts++;
        activeAttempts++;
        if (activeAttempts > maximumActiveAttempts) {
          maximumActiveAttempts = activeAttempts;
        }
        try {
          if (attempts == 1) {
            await firstAttemptGate.future;
            throw StateError('transient startup failure');
          }
        } finally {
          activeAttempts--;
        }
      },
    );
    addTearDown(auth.dispose);

    final firstAttempt = auth.initialize();
    final duplicateFirstAttempt = auth.initialize();
    expect(identical(firstAttempt, duplicateFirstAttempt), isTrue);

    firstAttemptGate.complete();
    await firstAttempt;
    expect(auth.initializationState, AuthInitializationState.failed);

    final retry = auth.initialize();
    final duplicateRetry = auth.initialize();
    expect(identical(retry, duplicateRetry), isTrue);
    await retry;

    expect(attempts, 2);
    expect(maximumActiveAttempts, 1);
    expect(auth.isLoading, isFalse);
    expect(auth.initializationState, AuthInitializationState.ready);
    expect(auth.initializationFailure, isNull);
  });

  test('resend and check email verification work for trainees', () async {
    const trainee = User(
      id: 'tr1',
      firstName: 'Ada',
      lastName: 'Lovelace',
      email: 'ada@example.com',
      role: User.roleTrainee,
    );
    final repository = _TeacherFlowRepository(loginUser: trainee)
      ..emailVerified = true
      ..refreshUser = trainee;
    final auth = AuthService(
      repository: repository,
      emailCallbackServer: MemoryAuthEmailCallbackServer(),
      awaitInitialAuthState: () async {},
    );
    auth.seedAuthenticatedUser(trainee);

    expect(await auth.resendVerificationEmail(), isTrue);
    expect(repository.verificationRequested, isTrue);
    expect(await auth.checkEmailVerification(), isTrue);
    expect(auth.needsEmailVerification, isFalse);
    expect(auth.currentUser?.isTrainee, isTrue);
  });

  test(
    'verification watch detects a clicked email without a button press',
    () async {
      const trainee = User(
        id: 'tr1',
        firstName: 'Ada',
        lastName: 'Lovelace',
        email: 'ada@example.com',
        role: User.roleTrainee,
      );
      final repository = _TeacherFlowRepository(loginUser: trainee)
        ..emailVerified = false
        ..refreshUser = trainee;
      final auth = AuthService(
        repository: repository,
        emailCallbackServer: MemoryAuthEmailCallbackServer(),
        emailVerificationPollInterval: const Duration(milliseconds: 20),
        awaitInitialAuthState: () async {},
      );
      auth.seedAuthenticatedUser(trainee);

      await auth.beginEmailVerificationWatch();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(auth.needsEmailVerification, isTrue);

      repository.emailVerified = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(auth.needsEmailVerification, isFalse);
      auth.dispose();
    },
  );

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
    'valid login with a missing profile enters resumable completion',
    () async {
      final repository = _TeacherFlowRepository(
        loginThrows: const AuthFailure(
          AuthFailureKind.missingProfile,
          'Your sign-in is valid, but your ELIXR profile is incomplete.',
          pendingProfile: PendingGoogleProfile(
            uid: 'ghost-1',
            email: 'ghost@example.com',
            firstName: '',
            lastName: '',
            isNewUser: false,
            identityProvider: ProfileIdentityProvider.password,
          ),
        ),
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
            (error) => error.toString().contains('profile is incomplete'),
          ),
        ),
      );
      expect(auth.isAuthenticated, isFalse);
      expect(auth.hasPendingGoogleProfile, isTrue);
      expect(
        auth.pendingGoogleProfile?.identityProvider,
        ProfileIdentityProvider.password,
      );
    },
  );

  test('verified teacher login sets needsEmailVerification false', () async {
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
    expect(auth.needsEmailVerification, isFalse);
    expect(repository.ensureTeacherRoleClaimCalls, 1);
  });

  test('Teacher login fails closed when claim evidence is invalid', () async {
    final repository =
        _TeacherFlowRepository(
            loginUser: const User(
              id: 'legacy-teacher',
              firstName: 'Legacy',
              lastName: 'Teacher',
              email: 'legacy@school.edu',
              role: User.roleTeacher,
            ),
          )
          ..ensureTeacherRoleClaimThrows = const TeacherRoleClaimException(
            TeacherRoleClaimFailureKind.invalidEvidence,
            'Teacher authorization evidence is invalid.',
          );
    final auth = AuthService(
      repository: repository,
      awaitInitialAuthState: () async {},
    );
    await auth.initialize();

    await expectLater(
      auth.login(email: 'legacy@school.edu', password: 'secret1'),
      throwsA(
        isA<TeacherRoleClaimException>().having(
          (error) => error.kind,
          'kind',
          TeacherRoleClaimFailureKind.invalidEvidence,
        ),
      ),
    );

    expect(auth.currentUser, isNull);
    expect(repository.ensureTeacherRoleClaimCalls, 1);
  });

  group('ensureTeacherAuthorizationFresh', () {
    const teacher = User(
      id: 't1',
      firstName: 'T',
      lastName: 'E',
      email: 't@school.edu',
      role: User.roleTeacher,
    );

    AuthService buildAuth(_TeacherFlowRepository repository) {
      return AuthService(
        repository: repository,
        awaitInitialAuthState: () async {},
      );
    }

    test('returns true for a verified Teacher', () async {
      final repository = _TeacherFlowRepository(loginUser: teacher)
        ..emailVerified = true
        ..refreshUser = teacher;
      final auth = buildAuth(repository);
      auth.seedAuthenticatedUser(teacher);

      final allowed = await auth.ensureTeacherAuthorizationFresh();

      expect(allowed, isTrue);
      expect(repository.isCurrentEmailVerifiedCalls, 1);
      expect(repository.refreshAuthenticatedUserCalls, 1);
      expect(auth.needsEmailVerification, isFalse);
      expect(auth.currentUser?.isTeacher, isTrue);
    });

    test(
      'returns true when repository refresh succeeds for a stale token',
      () async {
        final repository = _TeacherFlowRepository(loginUser: teacher)
          ..emailVerified = false
          ..staleTokenRefreshSucceeds = true
          ..refreshUser = teacher;
        final auth = buildAuth(repository);
        auth.seedAuthenticatedUser(teacher);

        final allowed = await auth.ensureTeacherAuthorizationFresh();

        expect(allowed, isTrue);
        expect(repository.isCurrentEmailVerifiedCalls, 1);
        expect(repository.emailVerified, isTrue);
        expect(auth.needsEmailVerification, isFalse);
      },
    );

    test('returns false for an unverified Teacher', () async {
      final repository = _TeacherFlowRepository(loginUser: teacher)
        ..emailVerified = false;
      final auth = buildAuth(repository);
      auth.seedAuthenticatedUser(teacher);

      final allowed = await auth.ensureTeacherAuthorizationFresh();

      expect(allowed, isFalse);
      expect(repository.isCurrentEmailVerifiedCalls, 1);
      expect(repository.refreshAuthenticatedUserCalls, 0);
      expect(auth.needsEmailVerification, isTrue);
      expect(auth.isAuthenticated, isTrue);
    });

    test(
      'returns false for a Trainee without checking Teacher verification',
      () async {
        const trainee = User(
          id: 'tr1',
          firstName: 'Ada',
          lastName: 'Lovelace',
          email: 'ada@example.com',
          role: User.roleTrainee,
        );
        final repository = _TeacherFlowRepository(loginUser: trainee)
          ..emailVerified = true;
        final auth = buildAuth(repository);
        auth.seedAuthenticatedUser(trainee);

        final allowed = await auth.ensureTeacherAuthorizationFresh();

        expect(allowed, isFalse);
        expect(repository.isCurrentEmailVerifiedCalls, 0);
        expect(repository.refreshAuthenticatedUserCalls, 0);
      },
    );

    test('returns false when no authenticated user is present', () async {
      final repository = _TeacherFlowRepository();
      final auth = buildAuth(repository);

      final allowed = await auth.ensureTeacherAuthorizationFresh();

      expect(allowed, isFalse);
      expect(repository.isCurrentEmailVerifiedCalls, 0);
      expect(auth.isAuthenticated, isFalse);
    });

    test('fails closed when refreshed profile is no longer Teacher', () async {
      const trainee = User(
        id: 't1',
        firstName: 'T',
        lastName: 'E',
        email: 't@school.edu',
        role: User.roleTrainee,
      );
      final repository = _TeacherFlowRepository(loginUser: teacher)
        ..emailVerified = true
        ..refreshUser = trainee;
      final auth = buildAuth(repository);
      auth.seedAuthenticatedUser(teacher);

      final allowed = await auth.ensureTeacherAuthorizationFresh();

      expect(allowed, isFalse);
      expect(repository.refreshAuthenticatedUserCalls, 1);
      expect(auth.currentUser?.isTeacher, isNot(true));
    });

    test(
      'fails closed on repository refresh error without signing out',
      () async {
        final repository = _TeacherFlowRepository(loginUser: teacher)
          ..emailVerified = true
          ..refreshAuthenticatedUserThrows = Exception(
            'Network error. Check your connection and try again.',
          );
        final auth = buildAuth(repository);
        auth.seedAuthenticatedUser(teacher);

        final allowed = await auth.ensureTeacherAuthorizationFresh();

        expect(allowed, isFalse);
        expect(auth.isAuthenticated, isTrue);
        expect(auth.currentUser?.isTeacher, isTrue);
        expect(auth.teacherAuthErrorMessage, isNotNull);
        expect(auth.teacherAuthErrorMessage, isNot(contains('Firebase')));
        expect(auth.teacherAuthErrorMessage, isNot(contains('token')));
      },
    );

    test(
      'fails closed when email verification lookup throws without signing out',
      () async {
        final repository = _TeacherFlowRepository(loginUser: teacher)
          ..emailVerified = true
          ..isCurrentEmailVerifiedThrows = Exception(
            'Network error. Check your connection and try again.',
          );
        final auth = buildAuth(repository);
        auth.seedAuthenticatedUser(teacher);

        final allowed = await auth.ensureTeacherAuthorizationFresh();

        expect(allowed, isFalse);
        expect(repository.refreshAuthenticatedUserCalls, 0);
        expect(auth.isAuthenticated, isTrue);
        expect(auth.currentUser?.isTeacher, isTrue);
        expect(auth.teacherAuthErrorMessage, isNotNull);
      },
    );
  });
}
