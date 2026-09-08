import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_policy.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _assessment = TeacherActivityAssessmentConfig(
  readiness: TeacherActivityReadinessSpec(
    hands: ActivityHandRequirement.twoHands,
    body: ActivityBodyRequirement.upperBody,
  ),
  rubric: TeacherActivityRubric(
    template: TeacherActivityRubricTemplate.beginnerFundamentals,
    maximumScore: 30,
    criteria: [
      TeacherActivityRubricCriterion(
        id: 'setup',
        label: 'Setup',
        description: 'Start prepared.',
        maximumPoints: 10,
      ),
      TeacherActivityRubricCriterion(
        id: 'control',
        label: 'Control',
        description: 'Keep the bottle controlled.',
        maximumPoints: 10,
      ),
      TeacherActivityRubricCriterion(
        id: 'finish',
        label: 'Finish',
        description: 'Finish safely.',
        maximumPoints: 10,
      ),
    ],
  ),
  recordingDurationSeconds: 45,
);

const _assignment = GroupAssignment(
  id: 'activity-1',
  teacherId: 'teacher-1',
  groupId: 'g1',
  movementId: 'tm1',
  revisionId: 'rev1',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Bottle Control Activity',
  teacherDisplayName: 'Grace Hopper',
  groupName: 'BSHM 4A',
  allowedProp: TrainingProp.bottle,
  maxScore: 30,
  activityAssessment: _assessment,
  attemptPolicy: AssignmentAttemptPolicy.finite(2),
);

Matcher _serverCode(String code) {
  return isA<ClassroomException>().having(
    (error) => error.serverCode,
    'serverCode',
    code,
  );
}

void main() {
  late InMemoryClassroomAssignmentRepository classroom;

  setUp(() {
    classroom = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 9, 8, 12),
    )..assignments[_assignment.id] = _assignment;
  });

  tearDown(() => classroom.dispose());

  Future<AssignmentAttempt> reserve(String requestId) {
    return classroom.reserveTeacherActivityAttempt(
      traineeId: 'trainee-1',
      assignment: _assignment,
      requestId: requestId,
    );
  }

  Future<AssignmentAttempt> recover(String requestId) {
    return reserveTeacherActivityAttemptWithRecovery(
      assignments: classroom,
      traineeId: 'trainee-1',
      assignment: _assignment,
      requestId: requestId,
    );
  }

  int consumedCount() => classroom.teacherActivityConsumedCount(
    assignmentId: _assignment.id,
    traineeId: 'trainee-1',
  );

  String? activeId() => classroom.teacherActivityActiveAttemptId(
    assignmentId: _assignment.id,
    traineeId: 'trainee-1',
  );

  test('opening with no active reservation succeeds', () async {
    final reserved = await reserve('activity-open-1');
    expect(reserved.status, AssignmentAttemptStatus.inProgress);
    expect(consumedCount(), 0);
    expect(activeId(), reserved.id);
  });

  test('same request id reuses the active reservation', () async {
    final first = await reserve('activity-open-1');
    final second = await reserve('activity-open-1');
    expect(second.id, first.id);
    expect(consumedCount(), 0);
  });

  test('a new request id conflicts with an active reservation', () async {
    await reserve('activity-open-1');
    await expectLater(
      reserve('activity-open-2'),
      throwsA(_serverCode('attempt_in_progress')),
    );
    expect(consumedCount(), 0);
  });

  test(
    'stale unconsumed reservation recovers without incrementing consumed_count',
    () async {
      final stale = await reserve('activity-open-1');
      final recovered = await recover('activity-open-2');
      expect(recovered.id, isNot(stale.id));
      expect(consumedCount(), 0);
      expect(activeId(), recovered.id);
      expect(
        classroom.attempts[stale.id]?.isAbandonedTeacherReviewDraft,
        isTrue,
      );
      expect(
        classroom.attempts.values
            .where(
              (attempt) =>
                  attempt.assignmentId == _assignment.id &&
                  attempt.status == AssignmentAttemptStatus.inProgress,
            )
            .map((attempt) => attempt.id),
        [recovered.id],
      );
    },
  );

  test(
    'consumed interrupted attempt remains counted after abandonment',
    () async {
      final reserved = await reserve('activity-open-1');
      await classroom.consumeTeacherActivityAttempt(
        traineeId: 'trainee-1',
        attempt: reserved,
      );
      expect(consumedCount(), 1);
      await classroom.abandonTeacherActivityAttempt(
        traineeId: 'trainee-1',
        attempt: reserved,
      );
      expect(consumedCount(), 1);
      expect(activeId(), isNull);
      expect(classroom.attempts[reserved.id]?.recordingStartedAt, isNotNull);
    },
  );

  test(
    'another attempt is allowed only while the finite policy has remaining attempts',
    () async {
      final first = await reserve('activity-open-1');
      await classroom.consumeTeacherActivityAttempt(
        traineeId: 'trainee-1',
        attempt: first,
      );
      final second = await recover('activity-open-2');
      expect(consumedCount(), 1);
      expect(second.id, isNot(first.id));
      await classroom.consumeTeacherActivityAttempt(
        traineeId: 'trainee-1',
        attempt: second,
      );
      await classroom.abandonTeacherActivityAttempt(
        traineeId: 'trainee-1',
        attempt: second,
      );
      await expectLater(
        recover('activity-open-3'),
        throwsA(_serverCode('attempts_exhausted')),
      );
      expect(consumedCount(), 2);
    },
  );

  test('finite attempts exhausted remains blocked', () async {
    for (var index = 0; index < 2; index++) {
      final reserved = await recover('activity-open-$index');
      await classroom.consumeTeacherActivityAttempt(
        traineeId: 'trainee-1',
        attempt: reserved,
      );
      await classroom.abandonTeacherActivityAttempt(
        traineeId: 'trainee-1',
        attempt: reserved,
      );
    }
    await expectLater(
      reserve('activity-open-final'),
      throwsA(_serverCode('attempts_exhausted')),
    );
  });

  test('graded activity remains blocked', () async {
    final graded = _assignment.copyWith(gradingLocked: true);
    classroom.assignments[_assignment.id] = graded;
    await expectLater(
      classroom.reserveTeacherActivityAttempt(
        traineeId: 'trainee-1',
        assignment: graded,
        requestId: 'activity-open-1',
      ),
      throwsA(_serverCode('graded')),
    );
  });

  test('overdue activity remains blocked', () async {
    classroom.assignments[_assignment.id] = _assignment.copyWith(
      dueAt: DateTime.utc(2026, 9, 1),
    );
    await expectLater(
      classroom.reserveTeacherActivityAttempt(
        traineeId: 'trainee-1',
        assignment: classroom.assignments[_assignment.id]!,
        requestId: 'activity-open-1',
      ),
      throwsA(_serverCode('deadline_passed')),
    );
  });

  test('forbidden trainee remains blocked', () async {
    const forbidden = GroupAssignment(
      id: 'activity-1',
      teacherId: 'teacher-1',
      groupId: 'g1',
      movementId: 'tm1',
      revisionId: 'rev1',
      origin: MovementOrigin.teacherCreated,
      assessmentMode: AssessmentMode.teacherReviewed,
      status: GroupAssignmentStatus.active,
      displayTitle: 'Bottle Control Activity',
      teacherDisplayName: 'Grace Hopper',
      groupName: 'BSHM 4A',
      allowedProp: TrainingProp.bottle,
      maxScore: 30,
      attemptPolicy: AssignmentAttemptPolicy.finite(2),
    );
    classroom.assignments[forbidden.id] = forbidden;
    await expectLater(
      reserveTeacherActivityAttemptWithRecovery(
        assignments: classroom,
        traineeId: 'trainee-1',
        assignment: forbidden,
        requestId: 'activity-open-1',
      ),
      throwsA(_serverCode('forbidden')),
    );
    expect(consumedCount(), 0);
    expect(activeId(), isNull);
  });

  test(
    'reservation Retry recovers instead of looping on attempt_in_progress',
    () async {
      await reserve('activity-open-1');
      final recovered = await recover('activity-open-retry-1');
      final retried = await recover('activity-open-retry-2');
      expect(retried.id, isNot(recovered.id));
      expect(consumedCount(), 0);
      expect(activeId(), retried.id);
    },
  );

  test('normal quit/release leaves the Activity reopenable', () async {
    final reserved = await reserve('activity-open-1');
    await classroom.abandonTeacherActivityAttempt(
      traineeId: 'trainee-1',
      attempt: reserved,
    );
    final reopened = await reserve('activity-open-2');
    expect(reopened.id, isNot(reserved.id));
    expect(consumedCount(), 0);
  });

  test(
    'recovery uses the conflict active_attempt_id when the attempts watch is stale',
    () async {
      final hidden = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 9, 8, 12),
      )..assignments[_assignment.id] = _assignment;
      addTearDown(hidden.dispose);
      final stale = await hidden.reserveTeacherActivityAttempt(
        traineeId: 'trainee-1',
        assignment: _assignment,
        requestId: 'activity-open-1',
      );
      final recovering = _HiddenWatchClassroom(hidden);
      final recovered = await reserveTeacherActivityAttemptWithRecovery(
        assignments: recovering,
        traineeId: 'trainee-1',
        assignment: _assignment,
        requestId: 'activity-open-2',
      );
      expect(recovered.id, isNot(stale.id));
      expect(
        hidden.teacherActivityConsumedCount(
          assignmentId: _assignment.id,
          traineeId: 'trainee-1',
        ),
        0,
      );
    },
  );

  test(
    'recovery prefers the conflict lock when the watch returns a different in_progress row',
    () async {
      final hidden = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 9, 8, 12),
      )..assignments[_assignment.id] = _assignment;
      addTearDown(hidden.dispose);
      final lock = await hidden.reserveTeacherActivityAttempt(
        traineeId: 'trainee-1',
        assignment: _assignment,
        requestId: 'activity-open-1',
      );
      final decoy = teacherReviewSubmissionDraftAttempt(
        traineeId: 'trainee-1',
        assignment: _assignment,
        attemptId: 'activity_${_assignment.id}_trainee-1_decoy',
        createdAt: DateTime.utc(2026, 9, 8, 11),
      ).copyWith(status: AssignmentAttemptStatus.inProgress);
      final recovering = _HiddenWatchClassroom(hidden, watchAttempts: [decoy]);
      final recovered = await reserveTeacherActivityAttemptWithRecovery(
        assignments: recovering,
        traineeId: 'trainee-1',
        assignment: _assignment,
        requestId: 'activity-open-2',
      );
      expect(recovered.id, isNot(lock.id));
      expect(recovered.id, isNot(decoy.id));
      expect(
        hidden.teacherActivityActiveAttemptId(
          assignmentId: _assignment.id,
          traineeId: 'trainee-1',
        ),
        recovered.id,
      );
      expect(
        hidden.teacherActivityConsumedCount(
          assignmentId: _assignment.id,
          traineeId: 'trainee-1',
        ),
        0,
      );
    },
  );
}

class _HiddenWatchClassroom extends InMemoryClassroomAssignmentRepository {
  _HiddenWatchClassroom(this._inner, {this.watchAttempts = const []});

  final InMemoryClassroomAssignmentRepository _inner;
  final List<AssignmentAttempt> watchAttempts;

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  }) {
    return Stream<List<AssignmentAttempt>>.value(watchAttempts);
  }

  @override
  Future<AssignmentAttempt?> getAttempt({required String attemptId}) {
    return _inner.getAttempt(attemptId: attemptId);
  }

  @override
  Future<AssignmentAttempt> reserveTeacherActivityAttempt({
    required String traineeId,
    required GroupAssignment assignment,
    required String requestId,
  }) {
    return _inner.reserveTeacherActivityAttempt(
      traineeId: traineeId,
      assignment: assignment,
      requestId: requestId,
    );
  }

  @override
  Future<void> abandonTeacherActivityAttempt({
    required String traineeId,
    required AssignmentAttempt attempt,
  }) {
    return _inner.abandonTeacherActivityAttempt(
      traineeId: traineeId,
      attempt: attempt,
    );
  }
}
