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

class _FirebaseWriteFailure implements Exception {}

class _FallbackReadFailure implements Exception {}

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

AssignmentAttempt _canonical({
  AssignmentAttemptStatus status = AssignmentAttemptStatus.inProgress,
  String teacherId = 'teacher-1',
}) {
  final canonical = canonicalTeacherReviewSubmissionAttempt(
    traineeId: 'trainee-1',
    assignment: _assignment(),
  );
  return AssignmentAttempt(
    id: canonical.id,
    traineeId: canonical.traineeId,
    teacherId: teacherId,
    groupId: canonical.groupId,
    assignmentId: canonical.assignmentId,
    movementId: canonical.movementId,
    revisionId: canonical.revisionId,
    origin: canonical.origin,
    assessmentMode: canonical.assessmentMode,
    attemptKind: canonical.attemptKind,
    status: status,
  );
}

Future<AssignmentAttempt> _startCanonical({
  required Future<void> Function(AssignmentAttempt) create,
  required Future<AssignmentAttempt?> Function(String) readExisting,
  required Future<AssignmentAttempt> Function(AssignmentAttempt) promote,
}) {
  return getOrCreateCanonicalTeacherReviewSubmissionWorkflow(
    traineeId: 'trainee-1',
    assignment: _assignment(),
    create: create,
    readExisting: readExisting,
    promoteLegacyDraft: promote,
    shouldReadAfterCreateFailure: (error) => error is _FirebaseWriteFailure,
    isFallbackReadFailure: (error) => error is _FallbackReadFailure,
  );
}

void main() {
  test('canonical first create succeeds before any read', () async {
    var read = false;

    final result = await _startCanonical(
      create: (canonical) async {
        expect(canonical.status, AssignmentAttemptStatus.inProgress);
      },
      readExisting: (_) async {
        read = true;
        return null;
      },
      promote: (_) async => fail('must not promote a new canonical attempt'),
    );

    expect(read, isFalse);
    expect(result.id, 'review_sub_asgCustom_trainee-1');
    expect(result.status, AssignmentAttemptStatus.inProgress);
  });

  test(
    'canonical create race reads and reuses existing in_progress attempt',
    () async {
      var read = false;
      final existing = _canonical();

      final result = await _startCanonical(
        create: (_) async => throw _FirebaseWriteFailure(),
        readExisting: (_) async {
          read = true;
          return existing;
        },
        promote: (_) async => fail('must not promote in_progress attempt'),
      );

      expect(read, isTrue);
      expect(result, same(existing));
    },
  );

  test('canonical legacy draft is promoted after fallback read', () async {
    final result = await _startCanonical(
      create: (_) async => throw _FirebaseWriteFailure(),
      readExisting: (_) async =>
          _canonical(status: AssignmentAttemptStatus.draft),
      promote: (existing) async {
        expect(existing.status, AssignmentAttemptStatus.draft);
        return existing.copyWith(status: AssignmentAttemptStatus.inProgress);
      },
    );

    expect(result.status, AssignmentAttemptStatus.inProgress);
  });

  for (final status in [
    AssignmentAttemptStatus.submitted,
    AssignmentAttemptStatus.unsubmitting,
    AssignmentAttemptStatus.checked,
  ]) {
    test('canonical $status remains blocked from restart', () {
      expect(
        () => _startCanonical(
          create: (_) async => throw _FirebaseWriteFailure(),
          readExisting: (_) async => _canonical(status: status),
          promote: (_) async => fail('must not promote $status attempt'),
        ),
        throwsA(
          isA<ClassroomException>().having(
            (error) => error.code,
            'code',
            ClassroomError.invalidState,
          ),
        ),
      );
    });
  }

  test(
    'canonical malformed or identity-mismatched fallback is rejected',
    () async {
      await expectLater(
        _startCanonical(
          create: (_) async => throw _FirebaseWriteFailure(),
          readExisting: (_) async =>
              throw const ClassroomException(ClassroomError.malformed),
          promote: (_) async => fail('must not promote malformed attempt'),
        ),
        throwsA(
          isA<ClassroomException>().having(
            (error) => error.code,
            'code',
            ClassroomError.malformed,
          ),
        ),
      );
      await expectLater(
        _startCanonical(
          create: (_) async => throw _FirebaseWriteFailure(),
          readExisting: (_) async => _canonical(teacherId: 'other-teacher'),
          promote: (_) async => fail('must not promote identity mismatch'),
        ),
        throwsA(
          isA<ClassroomException>().having(
            (error) => error.code,
            'code',
            ClassroomError.identityMismatch,
          ),
        ),
      );
    },
  );

  test('create failure with failed fallback read preserves original error', () {
    expect(
      () => _startCanonical(
        create: (_) async => throw _FirebaseWriteFailure(),
        readExisting: (_) async => throw _FallbackReadFailure(),
        promote: (_) async => fail('must not promote'),
      ),
      throwsA(isA<_FirebaseWriteFailure>()),
    );
  });

  test('canonical attempt with abandoned state is blocked from restart', () {
    expect(
      () => _startCanonical(
        create: (_) async => throw _FirebaseWriteFailure(),
        readExisting: (_) async =>
            _canonical().copyWith(abandonedAt: DateTime.utc(2026, 8, 30)),
        promote: (_) async => fail('must not restart abandoned attempt'),
      ),
      throwsA(
        isA<ClassroomException>().having(
          (error) => error.code,
          'code',
          ClassroomError.invalidState,
        ),
      ),
    );
  });

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
