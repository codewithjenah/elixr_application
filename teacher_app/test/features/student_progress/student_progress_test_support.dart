import 'dart:async';

import 'package:elixr_core/elixr_core.dart';

class TestCursor extends TeacherProgressCursor {
  const TestCursor(this.value);
  final String value;

  @override
  bool operator ==(Object other) => other is TestCursor && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class FakeTeacherRelationshipRepository
    implements TeacherRelationshipRepository {
  final listeners = <StreamController<TeacherStudentLinkSnapshot>>[];

  @override
  Stream<TeacherStudentLinkSnapshot> watchLink({
    required String teacherId,
    required String traineeId,
  }) {
    final controller = StreamController<TeacherStudentLinkSnapshot>.broadcast();
    listeners.add(controller);
    return controller.stream;
  }

  void add(
    TeacherStudentLink? link, {
    bool verified = true,
    int listener = -1,
  }) => listeners[listener < 0 ? listeners.length - 1 : listener].add(
    TeacherStudentLinkSnapshot(link: link, isServerVerified: verified),
  );

  void addError(Object error, {int listener = -1}) =>
      listeners[listener < 0 ? listeners.length - 1 : listener].addError(error);

  @override
  Future<TeacherInvite> createOrRotateInvite({
    required String traineeId,
    required String traineeDisplayName,
  }) => throw UnimplementedError();
  @override
  Future<TeacherInvite?> getActiveInvite({required String traineeId}) =>
      throw UnimplementedError();
  @override
  Future<void> revokeInvite({required String traineeId}) =>
      throw UnimplementedError();
  @override
  Future<TeacherInvite> resolveCoachCode(String code) =>
      throw UnimplementedError();
  @override
  Future<TeacherStudentLink> requestLink({
    required String teacherId,
    required String teacherDisplayName,
    required String code,
  }) => throw UnimplementedError();
  @override
  Future<void> approveLink({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();
  @override
  Future<void> rejectLink({
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
  Future<void> cancelLink({
    required String linkId,
    required String teacherId,
  }) => throw UnimplementedError();
  @override
  Stream<List<TeacherStudentLink>> watchTraineeLinks({
    required String traineeId,
  }) => const Stream.empty();
  @override
  Stream<List<TeacherStudentLink>> watchTeacherLinks({
    required String teacherId,
  }) => const Stream.empty();
}

class ControllableTeacherProgressRepository
    implements TeacherProgressRepository {
  final summaries = <StreamController<PublicProfileSummary?>>[];
  final requests = <_Request>[];

  @override
  Stream<PublicProfileSummary?> watchSummary(String traineeId) {
    final controller = StreamController<PublicProfileSummary?>.broadcast();
    summaries.add(controller);
    return controller.stream;
  }

  @override
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId,
    int pageSize = TeacherProgressRepository.defaultPageSize,
    TeacherProgressCursor? startAfter,
  }) {
    final request = _Request(traineeId, startAfter);
    requests.add(request);
    return request.completer.future;
  }
}

class _Request {
  _Request(this.traineeId, this.cursor);
  final String traineeId;
  final TeacherProgressCursor? cursor;
  final completer = Completer<TeacherProgressPage>();
}

TeacherStudentLink approvedLink({bool access = true}) => TeacherStudentLink(
  id: 'teacher_trainee',
  teacherId: 'teacher',
  traineeId: 'trainee',
  teacherDisplayName: 'Teacher',
  traineeDisplayName: 'Trainee',
  status: TeacherStudentLinkStatus.approved,
  progressAccess: access
      ? TeacherProgressAccess.granted
      : TeacherProgressAccess.none,
  progressAccessVersion: access
      ? TeacherStudentLink.supportedProgressAccessVersion
      : null,
  progressAccessGrantedAt: access ? DateTime.utc(2026, 8, 14) : null,
);

PublicProfileSummary summary({int seconds = 60}) => PublicProfileSummary(
  totalDurationSeconds: seconds,
  completedMovementNames: seconds == 0 ? const [] : const ['Hand Stall'],
);

PublicProfileSession session(String id) => PublicProfileSession(
  sessionId: id,
  userId: 'trainee',
  movementName: 'Hand Stall',
  difficulty: 'Easy',
  legacyScore: 80,
  durationSeconds: 60,
  propType: TrainingProp.bottle,
  createdAt: '2026-08-14T00:00:00Z',
);
