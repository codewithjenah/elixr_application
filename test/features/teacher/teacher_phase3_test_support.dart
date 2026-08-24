import 'dart:async';

import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';

class Phase3TestAuthRepository implements AuthRepositoryBase {
  @override
  Future<User?> loadPersistedUser() async => null;

  @override
  Future<void> clearCurrentUser() async {}

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
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
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    String? continueUrl,
  }) async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<bool> isCurrentEmailVerified() async => true;

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

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();
}

AuthService phase3TeacherAuth() {
  return AuthService(
    repository: Phase3TestAuthRepository(),
    awaitInitialAuthState: () async {},
  )..seedAuthenticatedUser(
    User(
      id: 'teacher',
      firstName: 'Grace',
      lastName: 'Hopper',
      email: 'teacher@example.com',
      role: User.roleTeacher,
    ),
  );
}

class FakeTeacherLinksRepository implements TeacherRelationshipRepository {
  final _controllers = <StreamController<List<TeacherStudentLink>>>[];

  @override
  Stream<List<TeacherStudentLink>> watchTeacherLinks({
    required String teacherId,
  }) {
    final controller = StreamController<List<TeacherStudentLink>>.broadcast();
    _controllers.add(controller);
    return controller.stream;
  }

  void emit(List<TeacherStudentLink> links, {int listener = -1}) {
    final index = listener < 0 ? _controllers.length - 1 : listener;
    _controllers[index].add(links);
  }

  void emitError(Object error, {int listener = -1}) {
    final index = listener < 0 ? _controllers.length - 1 : listener;
    _controllers[index].addError(error);
  }

  @override
  Future<TeacherRosterInvite> createOrRotateRosterInvite({
    required String teacherId,
    required String teacherDisplayName,
  }) => throw UnimplementedError();

  @override
  Future<TeacherRosterInvite?> getActiveRosterInvite({
    required String teacherId,
  }) => throw UnimplementedError();

  @override
  Future<void> revokeRosterInvite({required String teacherId}) =>
      throw UnimplementedError();

  @override
  Future<TeacherRosterInvite> resolveRosterCode(String code) =>
      throw UnimplementedError();

  @override
  Stream<List<TeacherStudentLink>> watchTraineeLinks({
    required String traineeId,
  }) => const Stream.empty();

  @override
  Stream<TeacherStudentLinkSnapshot> watchLink({
    required String teacherId,
    required String traineeId,
  }) => const Stream.empty();

  @override
  Future<TeacherStudentLink> requestTeacherJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  }) => throw UnimplementedError();

  @override
  Future<void> approveJoin({
    required String linkId,
    required String teacherId,
  }) => throw UnimplementedError();

  @override
  Future<void> rejectJoin({
    required String linkId,
    required String teacherId,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelJoin({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<void> revokeLink({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<void> grantProgressAccess({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<void> removeProgressAccess({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<void> grantEvidenceAccess({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<void> removeEvidenceAccess({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<void> revokeAllEvidenceAccess({required String traineeId}) =>
      throw UnimplementedError();
}

class FakePublicProfileRepository extends PublicProfileRepository {
  final _controllers = <String, StreamController<PublicProfile?>>{};

  @override
  Stream<PublicProfile?> watchProfileRoot(String userId) {
    final controller = _controllers.putIfAbsent(
      userId,
      () => StreamController<PublicProfile?>.broadcast(),
    );
    return controller.stream;
  }

  void emitProfile(String userId, PublicProfile? profile) {
    _controllers[userId]?.add(profile);
  }
}

TeacherStudentLink approvedProgressLink({
  String teacherId = 'teacher',
  String traineeId = 'trainee',
}) {
  final now = DateTime.utc(2026, 8, 19);
  return TeacherStudentLink(
    id: '${teacherId}_$traineeId',
    teacherId: teacherId,
    traineeId: traineeId,
    teacherDisplayName: 'Teacher',
    traineeDisplayName: 'Trainee',
    status: TeacherStudentLinkStatus.approved,
    progressAccess: TeacherProgressAccess.granted,
    progressAccessVersion: TeacherStudentLink.supportedProgressAccessVersion,
    progressAccessGrantedAt: now,
    createdAt: now,
    updatedAt: now,
  );
}

GroupMembership membership({
  required String groupId,
  required String teacherId,
  required String traineeId,
  GroupMembershipStatus status = GroupMembershipStatus.approved,
  String traineeName = 'Ada Lovelace',
}) {
  final now = DateTime.utc(2026, 8, 19);
  return GroupMembership(
    id: GroupMembership.documentId(groupId: groupId, traineeId: traineeId),
    groupId: groupId,
    teacherId: teacherId,
    traineeId: traineeId,
    traineeDisplayName: traineeName,
    teacherDisplayName: 'Grace Hopper',
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

ElixrGroup activeGroup({
  String id = 'group-1',
  String teacherId = 'teacher',
  String name = 'BSHM 4A',
}) {
  final now = DateTime.utc(2026, 8, 19);
  return ElixrGroup(
    id: id,
    teacherId: teacherId,
    name: name,
    status: ElixrGroupStatus.active,
    createdAt: now,
    updatedAt: now,
  );
}

PublicProfileSummary sampleSummary() => const PublicProfileSummary(
  totalDurationSeconds: 120,
  completedMovementNames: ['Hand Stall'],
);

PublicProfileSession sampleSession({String id = 'session-1'}) =>
    PublicProfileSession(
      sessionId: id,
      userId: 'trainee',
      movementName: 'Hand Stall',
      difficulty: 'Easy',
      durationSeconds: 60,
      propType: TrainingProp.bottle,
      rubric: const RubricAssessment(
        technique: 2,
        stability: 2,
        completion: 2,
        propPositioning: 2,
      ),
      assessmentVersion: 2,
    );

class TrackingTeacherProgressRepository implements TeacherProgressRepository {
  final InMemoryTeacherProgressRepository inner =
      InMemoryTeacherProgressRepository();
  final List<String> summaryWatches = [];
  final List<String> sessionFetches = [];

  @override
  Stream<PublicProfileSummary?> watchSummary(String traineeId) {
    summaryWatches.add(traineeId);
    return inner.watchSummary(traineeId);
  }

  @override
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId,
    int pageSize = TeacherProgressRepository.defaultPageSize,
    TeacherProgressCursor? startAfter,
  }) {
    sessionFetches.add(traineeId);
    return inner.fetchSessionsPage(
      traineeId: traineeId,
      pageSize: pageSize,
      startAfter: startAfter,
    );
  }
}
