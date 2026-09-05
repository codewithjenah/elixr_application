import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _code = '7KPMXR4DQ2WT';

class _TeacherGoogleRepository extends Fake
    implements
        AuthRepositoryBase,
        GoogleAuthRepositoryBase,
        TeacherRegistrationRepositoryBase,
        TeacherGoogleAuthRepositoryBase,
        TeacherAuthorizationRepositoryBase {
  GoogleSignInResult teacherResult = const PendingGoogleSignIn(
    PendingGoogleProfile(
      uid: 'google-teacher',
      email: 'teacher@gmail.com',
      firstName: 'Google',
      lastName: 'Teacher',
      isNewUser: true,
      intent: GoogleOnboardingIntent.teacher,
      teacherAccessCode: _code,
    ),
  );
  int assertCodeCalls = 0;
  int teacherSignInCalls = 0;
  int teacherCompletionCalls = 0;
  int clearCurrentUserCalls = 0;
  String? assertedCode;
  String? completedCode;
  GoogleSignInResult? restoreResult;
  int ensureTeacherRoleClaimCalls = 0;

  @override
  Future<void> ensureTeacherRoleClaim() async {
    ensureTeacherRoleClaimCalls++;
  }

  @override
  Future<void> assertTeacherAccessCodeRedeemable(String code) async {
    assertCodeCalls++;
    assertedCode = code;
  }

  @override
  Future<GoogleSignInResult> signInWithGoogleTeacher({
    required String teacherAccessCode,
  }) async {
    teacherSignInCalls++;
    return teacherResult;
  }

  @override
  Future<User> completeGoogleTeacherProfile({
    required RegistrationLegalConsent legalConsent,
    required PendingGoogleProfile pendingProfile,
    required String firstName,
    String? middleName,
    required String lastName,
    required String teacherAccessCode,
  }) async {
    teacherCompletionCalls++;
    completedCode = teacherAccessCode;
    return User(
      id: pendingProfile.uid,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: pendingProfile.email,
      role: User.roleTeacher,
      teacherAccessCode: teacherAccessCode,
    );
  }

  @override
  Future<GoogleSignInResult> signInWithGoogle() async => teacherResult;

  @override
  Future<GoogleSignInResult?> restoreGoogleSignIn() async => restoreResult;

  @override
  Future<User> completeGoogleProfile({
    required RegistrationLegalConsent legalConsent,
    required PendingGoogleProfile pendingProfile,
    required String firstName,
    String? middleName,
    required String lastName,
  }) async {
    return User(
      id: pendingProfile.uid,
      firstName: firstName,
      middleName: middleName,
      lastName: lastName,
      email: pendingProfile.email,
    );
  }

  @override
  Future<void> cancelGoogleOnboarding(
    PendingGoogleProfile pendingProfile,
  ) async {}

  @override
  Future<Set<AuthProviderKind>> currentProviderKinds() async => const {
    AuthProviderKind.google,
  };

  @override
  Future<User?> loadPersistedUser() async => null;

  @override
  Future<void> clearCurrentUser() async {
    clearCurrentUserCalls++;
  }
}

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

void main() {
  late _TeacherGoogleRepository repository;
  late _RecordingPublicProfileRepository profiles;
  late AuthService auth;

  setUp(() {
    repository = _TeacherGoogleRepository();
    profiles = _RecordingPublicProfileRepository();
    auth = AuthService(
      repository: repository,
      publicProfileRepository: profiles,
      awaitInitialAuthState: () async {},
    );
  });

  tearDown(() => auth.dispose());

  test(
    'Teacher Google sign-in retains the normalized code for final validation',
    () async {
      await auth.signInWithGoogleTeacher(teacherAccessCode: '7kpm-xr4d-q2wt');

      expect(repository.assertCodeCalls, 0);
      expect(repository.teacherSignInCalls, 1);
      expect(repository.ensureTeacherRoleClaimCalls, 0);
      expect(auth.pendingGoogleProfile?.intent, GoogleOnboardingIntent.teacher);
      expect(auth.pendingGoogleProfile?.teacherAccessCode, _code);
    },
  );

  test('Teacher Google completion keeps the Teacher path separate', () async {
    await auth.signInWithGoogleTeacher(teacherAccessCode: _code);

    await auth.completeGoogleTeacherProfile(
      firstName: 'Ada',
      lastName: 'Lovelace',
      teacherAccessCode: '7kpm-xr4d-q2wt',
      legalConsent: RegistrationLegalConsent.current(),
    );

    expect(repository.teacherCompletionCalls, 1);
    expect(repository.completedCode, _code);
    expect(repository.ensureTeacherRoleClaimCalls, 1);
    expect(auth.currentUser?.isTeacher, isTrue);
    expect(auth.hasPendingGoogleProfile, isFalse);
    expect(profiles.seedCalls, 1);
    expect(profiles.seededUserIds, ['google-teacher']);
  });

  test('an existing Trainee is signed out and is never converted', () async {
    repository.teacherResult = const ExistingGoogleProfile(
      User(
        id: 'trainee-1',
        firstName: 'Existing',
        lastName: 'Trainee',
        email: 'trainee@gmail.com',
      ),
    );

    await expectLater(
      auth.signInWithGoogleTeacher(teacherAccessCode: _code),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Roles are immutable'),
        ),
      ),
    );

    expect(repository.clearCurrentUserCalls, 1);
    expect(auth.currentUser, isNull);
    expect(auth.hasPendingGoogleProfile, isFalse);
  });

  test(
    'restored incomplete Google onboarding is explicitly unspecified',
    () async {
      repository.restoreResult = const PendingGoogleSignIn(
        PendingGoogleProfile(
          uid: 'restored-google',
          email: 'restored@gmail.com',
          firstName: 'Restored',
          lastName: 'Google',
          isNewUser: false,
          intent: GoogleOnboardingIntent.teacher,
          teacherAccessCode: _code,
        ),
      );
      await auth.initialize();

      expect(
        auth.pendingGoogleProfile?.intent,
        GoogleOnboardingIntent.unspecified,
      );
      expect(auth.pendingGoogleProfile?.teacherAccessCode, isNull);
    },
  );
}
