import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_ids.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _PermissionDenied implements Exception {}

class _OtherFailure implements Exception {}

GroupAssignment _assignment() => const GroupAssignment(
  id: 'asgCustom',
  teacherId: 'teacher-1',
  groupId: 'group-1',
  movementId: 'tm1',
  revisionId: 'rev1',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Basic Bottle Balances',
  teacherDisplayName: 'Grace Hopper',
  groupName: 'BSHM 4A',
);

AssignmentAttempt _attempt({
  AssignmentAttemptStatus status = AssignmentAttemptStatus.inProgress,
  String traineeId = 'trainee-1',
  String assignmentId = 'asgCustom',
  String teacherId = 'teacher-1',
  String groupId = 'group-1',
  String movementId = 'tm1',
  String revisionId = 'rev1',
  MovementOrigin origin = MovementOrigin.teacherCreated,
  AssessmentMode assessmentMode = AssessmentMode.teacherReviewed,
  AssignmentAttemptKind attemptKind = AssignmentAttemptKind.teacherReviewDraft,
  bool awardsGlobalXp = false,
  String? sourceSessionId,
  DateTime? createdAt,
}) {
  return AssignmentAttempt(
    id: assignmentAttemptIdForTeacherCreatedDraft(
      assignmentId: assignmentId,
      traineeId: traineeId,
    ),
    traineeId: traineeId,
    teacherId: teacherId,
    groupId: groupId,
    assignmentId: assignmentId,
    movementId: movementId,
    revisionId: revisionId,
    origin: origin,
    assessmentMode: assessmentMode,
    attemptKind: attemptKind,
    status: status,
    awardsGlobalXp: awardsGlobalXp,
    sourceSessionId: sourceSessionId,
    createdAt: createdAt,
  );
}

void main() {
  test('create-first succeeds without reading a missing attempt', () async {
    var created = false;
    var read = false;
    final assignment = _assignment();

    final result = await startTeacherCreatedAttemptWorkflow(
      traineeId: 'trainee-1',
      assignment: assignment,
      create: (draft) async {
        created = true;
        expect(draft.awardsGlobalXp, isFalse);
        expect(draft.sourceSessionId, isNull);
        expect(
          draft.toCreateMap(createdAt: 'ts').containsKey('source_session_id'),
          isFalse,
        );
        expect(draft.toCreateMap(createdAt: 'ts').containsKey('xp'), isFalse);
      },
      readExisting: (_) async {
        read = true;
        return null;
      },
      promoteDraftToInProgress: (_) async =>
          fail('must not promote after create'),
      isPermissionDenied: (error) => error is _PermissionDenied,
    );

    expect(created, isTrue);
    expect(read, isFalse);
    expect(
      result.id,
      assignmentAttemptIdForTeacherCreatedDraft(
        assignmentId: assignment.id,
        traineeId: 'trainee-1',
      ),
    );
    expect(result.attemptKind, AssignmentAttemptKind.teacherReviewDraft);
    expect(result.origin, MovementOrigin.teacherCreated);
    expect(result.assessmentMode, AssessmentMode.teacherReviewed);
    expect(result.awardsGlobalXp, isFalse);
    expect(result.sourceSessionId, isNull);
  });

  test(
    'permission-denied create falls back to owned in_progress attempt',
    () async {
      final createdAt = DateTime.utc(2026, 8, 19);
      final existing = _attempt(createdAt: createdAt);
      var promoted = false;

      final result = await startTeacherCreatedAttemptWorkflow(
        traineeId: 'trainee-1',
        assignment: _assignment(),
        create: (_) async => throw _PermissionDenied(),
        readExisting: (_) async => existing,
        promoteDraftToInProgress: (attempt) async {
          promoted = true;
          return attempt;
        },
        isPermissionDenied: (error) => error is _PermissionDenied,
      );

      expect(promoted, isFalse);
      expect(result.id, existing.id);
      expect(result.status, AssignmentAttemptStatus.inProgress);
      expect(result.createdAt, createdAt);
      expect(result.awardsGlobalXp, isFalse);
      expect(result.sourceSessionId, isNull);
    },
  );

  test(
    'owned draft is promoted to in_progress while preserving created_at',
    () async {
      final createdAt = DateTime.utc(2026, 8, 18);
      final existing = _attempt(
        status: AssignmentAttemptStatus.draft,
        createdAt: createdAt,
      );

      final result = await startTeacherCreatedAttemptWorkflow(
        traineeId: 'trainee-1',
        assignment: _assignment(),
        create: (_) async => throw _PermissionDenied(),
        readExisting: (_) async => existing,
        promoteDraftToInProgress: (attempt) async {
          expect(attempt.createdAt, createdAt);
          expect(attempt.status, AssignmentAttemptStatus.draft);
          return AssignmentAttempt(
            id: attempt.id,
            traineeId: attempt.traineeId,
            teacherId: attempt.teacherId,
            groupId: attempt.groupId,
            assignmentId: attempt.assignmentId,
            movementId: attempt.movementId,
            revisionId: attempt.revisionId,
            origin: attempt.origin,
            assessmentMode: attempt.assessmentMode,
            attemptKind: attempt.attemptKind,
            status: AssignmentAttemptStatus.inProgress,
            createdAt: attempt.createdAt,
          );
        },
        isPermissionDenied: (error) => error is _PermissionDenied,
      );

      expect(result.status, AssignmentAttemptStatus.inProgress);
      expect(result.createdAt, createdAt);
      expect(result.traineeId, 'trainee-1');
      expect(result.assignmentId, 'asgCustom');
    },
  );

  test('mismatched existing attempt fails closed', () async {
    final existing = _attempt(teacherId: 'other-teacher');

    expect(
      () => startTeacherCreatedAttemptWorkflow(
        traineeId: 'trainee-1',
        assignment: _assignment(),
        create: (_) async => throw _PermissionDenied(),
        readExisting: (_) async => existing,
        promoteDraftToInProgress: (_) async =>
            fail('must not promote mismatch'),
        isPermissionDenied: (error) => error is _PermissionDenied,
      ),
      throwsA(
        isA<ClassroomException>().having(
          (error) => error.code,
          'code',
          ClassroomError.identityMismatch,
        ),
      ),
    );
  });

  test('malformed existing attempt fails closed', () async {
    expect(
      () => startTeacherCreatedAttemptWorkflow(
        traineeId: 'trainee-1',
        assignment: _assignment(),
        create: (_) async => throw _PermissionDenied(),
        readExisting: (_) async =>
            throw const ClassroomException(ClassroomError.malformed),
        promoteDraftToInProgress: (_) async =>
            fail('must not promote malformed'),
        isPermissionDenied: (error) => error is _PermissionDenied,
      ),
      throwsA(
        isA<ClassroomException>().having(
          (error) => error.code,
          'code',
          ClassroomError.malformed,
        ),
      ),
    );
  });

  test('missing fallback read fails closed', () async {
    expect(
      () => startTeacherCreatedAttemptWorkflow(
        traineeId: 'trainee-1',
        assignment: _assignment(),
        create: (_) async => throw _PermissionDenied(),
        readExisting: (_) async => null,
        promoteDraftToInProgress: (_) async => fail('must not promote missing'),
        isPermissionDenied: (error) => error is _PermissionDenied,
      ),
      throwsA(
        isA<ClassroomException>().having(
          (error) => error.code,
          'code',
          ClassroomError.notFound,
        ),
      ),
    );
  });

  test('non-permission create errors are not swallowed', () async {
    expect(
      () => startTeacherCreatedAttemptWorkflow(
        traineeId: 'trainee-1',
        assignment: _assignment(),
        create: (_) async => throw _OtherFailure(),
        readExisting: (_) async => fail('must not read after other failure'),
        promoteDraftToInProgress: (_) async => fail('must not promote'),
        isPermissionDenied: (error) => error is _PermissionDenied,
      ),
      throwsA(isA<_OtherFailure>()),
    );
  });

  test('attempt with source session or XP is not reusable', () {
    expect(
      isReusableTeacherCreatedStartAttempt(
        attempt: _attempt(sourceSessionId: 'sessA'),
        traineeId: 'trainee-1',
        assignment: _assignment(),
      ),
      isFalse,
    );
    expect(
      isReusableTeacherCreatedStartAttempt(
        attempt: _attempt(awardsGlobalXp: true),
        traineeId: 'trainee-1',
        assignment: _assignment(),
      ),
      isFalse,
    );
  });
}
