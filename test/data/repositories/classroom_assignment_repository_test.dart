import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_ids.dart';
import 'package:elixr_application/data/models/assignment_submission_limits.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:flutter_test/flutter_test.dart';

ElixrGroup _group({
  String id = 'g1',
  String teacherId = 'teacher-1',
  ElixrGroupStatus status = ElixrGroupStatus.active,
}) => ElixrGroup(id: id, teacherId: teacherId, name: 'BSHM 4A', status: status);

void main() {
  late InMemoryClassroomAssignmentRepository assignments;
  late InMemoryTeacherMovementRepository movements;

  setUp(() {
    var n = 0;
    assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 8, 20),
      generateId: () => 'asg${++n}',
    );
    movements = InMemoryTeacherMovementRepository(
      now: () => DateTime.utc(2026, 8, 20),
      generateId: () => 'tm${++n}',
    );
  });

  tearDown(() {
    assignments.dispose();
    movements.dispose();
  });

  test('official assignment uses canonical identity mapping', () async {
    final assignment = await assignments.createOfficialAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: _group(),
      officialMovementName: 'Hand Stall',
      dueAt: DateTime.utc(2026, 8, 21, 12),
    );
    final identity = officialElixrIdentityForName('Hand Stall')!;
    expect(assignment.origin, MovementOrigin.officialElixr);
    expect(assignment.officialMovementName, 'Hand Stall');
    expect(assignment.movementId, identity.movementId);
    expect(assignment.revisionId, identity.revisionId);
    expect(assignment.groupName, 'BSHM 4A');
    expect(assignment.dueAt, DateTime.utc(2026, 8, 21, 12));
  });

  test(
    'targeted assignments require approved targets and filter trainee reads',
    () async {
      final groups = InMemoryGroupRepository();
      groups.seedMembership(
        const GroupMembership(
          id: 'g1_trainee-a',
          groupId: 'g1',
          teacherId: 'teacher-1',
          traineeId: 'trainee-a',
          traineeDisplayName: 'Trainee A',
          teacherDisplayName: 'Grace Hopper',
          status: GroupMembershipStatus.approved,
        ),
      );
      assignments.dispose();
      assignments = InMemoryClassroomAssignmentRepository(
        groupRepository: groups,
        now: () => DateTime.utc(2026, 8, 20),
        generateId: () => 'targeted',
      );

      final assignment = await assignments.createOfficialAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(),
        officialMovementName: 'Hand Stall',
        audience: AssignmentAudience.individualStudent(['trainee-a']),
      );

      expect(
        assignment.audience.type,
        AssignmentAudienceType.individualStudent,
      );
      expect(
        await assignments.fetchAssignmentsForTrainee(traineeId: 'trainee-a'),
        [assignment],
      );
      expect(
        await assignments.fetchAssignmentsForTrainee(traineeId: 'trainee-b'),
        isEmpty,
      );
      await expectLater(
        assignments.createOfficialAssignment(
          teacherId: 'teacher-1',
          teacherDisplayName: 'Grace Hopper',
          group: _group(),
          officialMovementName: 'Hand Stall',
          audience: AssignmentAudience.individualStudent(['trainee-b']),
        ),
        throwsA(isA<ClassroomException>()),
      );
      groups.dispose();
    },
  );

  test('targeted in-memory creation rejects a missing membership source', () {
    expect(
      () => assignments.createOfficialAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(),
        officialMovementName: 'Hand Stall',
        audience: AssignmentAudience.individualStudent(['trainee-a']),
      ),
      throwsA(isA<ClassroomException>()),
    );
  });

  test('Teacher cannot assign to another Teacher group', () async {
    expect(
      () => assignments.createOfficialAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(teacherId: 'teacher-2'),
        officialMovementName: 'Hand Stall',
      ),
      throwsA(
        isA<ClassroomException>().having(
          (error) => error.code,
          'code',
          ClassroomError.forbidden,
        ),
      ),
    );
  });

  test('Teacher cannot assign to an archived group', () async {
    expect(
      () => assignments.createOfficialAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(status: ElixrGroupStatus.archived),
        officialMovementName: 'Hand Stall',
      ),
      throwsA(
        isA<ClassroomException>().having(
          (error) => error.code,
          'code',
          ClassroomError.inactive,
        ),
      ),
    );
  });

  test('unofficial names fail closed', () async {
    expect(
      () => assignments.createOfficialAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(),
        officialMovementName: 'Arm Stall',
      ),
      throwsA(
        isA<ClassroomException>().having(
          (error) => error.code,
          'code',
          ClassroomError.unofficial,
        ),
      ),
    );
  });

  test('Teacher-created assignment pins the current revision', () async {
    final movement = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'First.',
      requiredProp: TrainingProp.bottle,
    );
    final firstRevision = (await movements.getRevision(
      movementId: movement.id,
      revisionId: movement.currentRevisionId,
    ))!;
    final assignment = await assignments.createTeacherCreatedAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: _group(),
      movement: movement,
      revision: firstRevision,
    );
    expect(assignment.origin, MovementOrigin.teacherCreated);
    expect(assignment.revisionId, firstRevision.id);
    expect(assignment.officialMovementName, isNull);

    final edited = await movements.editMovement(
      teacherId: 'teacher-1',
      movementId: movement.id,
      title: 'Tin Balance',
      instructions: 'Second.',
      requiredProp: TrainingProp.bottle,
    );
    expect(assignment.revisionId, isNot(edited.currentRevisionId));
    expect(assignment.revisionId, firstRevision.id);
  });

  test('archived Teacher movement cannot be newly assigned', () async {
    final movement = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'First.',
      requiredProp: TrainingProp.bottle,
    );
    await movements.archiveMovement(
      teacherId: 'teacher-1',
      movementId: movement.id,
    );
    final archived = (await movements.getMovement(movementId: movement.id))!;
    final revision = (await movements.getRevision(
      movementId: archived.id,
      revisionId: archived.currentRevisionId,
    ))!;
    expect(
      () => assignments.createTeacherCreatedAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(),
        movement: archived,
        revision: revision,
      ),
      throwsA(
        isA<ClassroomException>().having(
          (error) => error.code,
          'code',
          ClassroomError.archived,
        ),
      ),
    );
  });

  test(
    'Teacher-created attempt never awards XP or points at a session',
    () async {
      final movement = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Tin Balance',
        instructions: 'First.',
        requiredProp: TrainingProp.bottle,
      );
      final revision = (await movements.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      ))!;
      final assignment = await assignments.createTeacherCreatedAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(),
        movement: movement,
        revision: revision,
      );
      final attempt = await assignments.startTeacherCreatedAttempt(
        traineeId: 'trainee-1',
        assignment: assignment,
      );
      expect(attempt.awardsGlobalXp, isFalse);
      expect(attempt.sourceSessionId, isNull);
      expect(attempt.rubric, isNull);
      expect(
        attempt.id,
        assignmentAttemptIdForTeacherCreatedDraft(
          assignmentId: assignment.id,
          traineeId: 'trainee-1',
        ),
      );
    },
  );

  test(
    'starting the same Teacher-created assignment again is idempotent',
    () async {
      final movement = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Tin Balance',
        instructions: 'First.',
        requiredProp: TrainingProp.bottle,
      );
      final revision = (await movements.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      ))!;
      final assignment = await assignments.createTeacherCreatedAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(),
        movement: movement,
        revision: revision,
      );
      final first = await assignments.startTeacherCreatedAttempt(
        traineeId: 'trainee-1',
        assignment: assignment,
      );
      final second = await assignments.startTeacherCreatedAttempt(
        traineeId: 'trainee-1',
        assignment: assignment,
      );
      expect(second.id, first.id);
      expect(second.status, first.status);
      expect(second.awardsGlobalXp, isFalse);
      expect(second.sourceSessionId, isNull);
    },
  );

  test(
    'seeded draft Teacher-created attempt promotes without rewriting identity',
    () async {
      final movement = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Tin Balance',
        instructions: 'First.',
        requiredProp: TrainingProp.bottle,
      );
      final revision = (await movements.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      ))!;
      final assignment = await assignments.createTeacherCreatedAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(),
        movement: movement,
        revision: revision,
      );
      final createdAt = DateTime.utc(2026, 8, 1);
      assignments.seedAttempt(
        AssignmentAttempt(
          id: assignmentAttemptIdForTeacherCreatedDraft(
            assignmentId: assignment.id,
            traineeId: 'trainee-1',
          ),
          traineeId: 'trainee-1',
          teacherId: assignment.teacherId,
          groupId: assignment.groupId,
          assignmentId: assignment.id,
          movementId: assignment.movementId,
          revisionId: assignment.revisionId,
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          attemptKind: AssignmentAttemptKind.teacherReviewDraft,
          status: AssignmentAttemptStatus.draft,
          createdAt: createdAt,
        ),
      );
      final started = await assignments.startTeacherCreatedAttempt(
        traineeId: 'trainee-1',
        assignment: assignment,
      );
      expect(started.status, AssignmentAttemptStatus.inProgress);
      expect(started.createdAt, createdAt);
      expect(started.awardsGlobalXp, isFalse);
      expect(started.sourceSessionId, isNull);
    },
  );

  test('mismatched existing Teacher-created attempt fails closed', () async {
    final movement = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'First.',
      requiredProp: TrainingProp.bottle,
    );
    final revision = (await movements.getRevision(
      movementId: movement.id,
      revisionId: movement.currentRevisionId,
    ))!;
    final assignment = await assignments.createTeacherCreatedAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: _group(),
      movement: movement,
      revision: revision,
    );
    assignments.seedAttempt(
      AssignmentAttempt(
        id: assignmentAttemptIdForTeacherCreatedDraft(
          assignmentId: assignment.id,
          traineeId: 'trainee-1',
        ),
        traineeId: 'trainee-1',
        teacherId: 'other-teacher',
        groupId: assignment.groupId,
        assignmentId: assignment.id,
        movementId: assignment.movementId,
        revisionId: assignment.revisionId,
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewDraft,
        status: AssignmentAttemptStatus.inProgress,
      ),
    );
    expect(
      () => assignments.startTeacherCreatedAttempt(
        traineeId: 'trainee-1',
        assignment: assignment,
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

  test(
    'video submission is a new attempt and retry does not rewrite history',
    () async {
      final movement = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Tin Balance',
        instructions: 'First.',
        requiredProp: TrainingProp.bottle,
      );
      final revision = (await movements.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      ))!;
      final assignment = await assignments.createTeacherCreatedAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(),
        movement: movement,
        revision: revision,
      );
      final draft = await assignments.createTeacherReviewSubmissionDraft(
        traineeId: 'trainee-1',
        assignment: assignment,
        attemptId: 'review_sub_first',
      );
      expect(draft.attemptKind, AssignmentAttemptKind.teacherReviewSubmission);
      expect(draft.awardsGlobalXp, isFalse);
      expect(draft.sourceSessionId, isNull);
      final submitted = await assignments.markTeacherReviewSubmitted(
        traineeId: 'trainee-1',
        attempt: draft,
        videoStoragePath:
            'assignment_submissions/teacher-1/g1/${assignment.id}/trainee-1/review_sub_first.mp4',
        videoContentType: 'video/mp4',
        videoSizeBytes: 1200,
        videoDurationMs: 4000,
        submittedAt: DateTime.utc(2026, 8, 20),
        videoExpiresAt: DateTime.utc(2026, 9, 19),
      );
      final reviewed = await assignments.reviewTeacherSubmission(
        teacherId: 'teacher-1',
        attempt: submitted,
        verdict: AssignmentReviewVerdict.needsRetry,
        feedback: 'Keep the tin upright.',
        reviewedAt: DateTime.utc(2026, 8, 21),
        videoExpiresAt: DateTime.utc(2026, 9, 4),
      );
      final replacement = await assignments.createTeacherReviewSubmissionDraft(
        traineeId: 'trainee-1',
        assignment: assignment,
        attemptId: 'review_sub_second',
        supersedesAttemptId: reviewed.id,
      );
      expect(replacement.id, isNot(reviewed.id));
      expect(replacement.supersedesAttemptId, reviewed.id);
      expect(
        assignments.attempts[reviewed.id]!.reviewVerdict,
        AssignmentReviewVerdict.needsRetry,
      );
      expect(
        assignments.attempts[reviewed.id]!.reviewFeedback,
        'Keep the tin upright.',
      );
    },
  );

  test(
    'abandoned draft delete is owner-only and cannot remove the document',
    () async {
      final movement = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Tin Balance',
        instructions: 'First.',
        requiredProp: TrainingProp.bottle,
      );
      final revision = (await movements.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      ))!;
      final assignment = await assignments.createTeacherCreatedAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(),
        movement: movement,
        revision: revision,
      );
      final draft = await assignments.createTeacherReviewSubmissionDraft(
        traineeId: 'trainee-1',
        assignment: assignment,
        attemptId: 'review_sub_abandoned',
      );
      await assignments.markTeacherReviewSubmissionAbandoned(
        traineeId: 'trainee-1',
        attempt: draft,
      );
      final leftover = assignments.attempts[draft.id]!;
      expect(leftover.status, AssignmentAttemptStatus.draft);
      expect(leftover.abandonedAt, isNotNull);
      expect(leftover.isAbandonedTeacherReviewDraft, isTrue);
      expect(leftover.isReviewFacingSubmission, isFalse);
      expect(leftover.awardsGlobalXp, isFalse);

      expect(
        () => assignments.markTeacherReviewSubmitted(
          traineeId: 'trainee-1',
          attempt: leftover,
          videoStoragePath:
              'assignment_submissions/teacher-1/g1/${assignment.id}/trainee-1/review_sub_abandoned.mp4',
          videoContentType: 'video/mp4',
          videoSizeBytes: 1200,
          videoDurationMs: 4000,
          submittedAt: DateTime.utc(2026, 8, 20),
          videoExpiresAt: DateTime.utc(2026, 9, 19),
        ),
        throwsA(isA<ClassroomException>()),
      );

      final submittedDraft = await assignments
          .createTeacherReviewSubmissionDraft(
            traineeId: 'trainee-1',
            assignment: assignment,
            attemptId: 'review_sub_keep',
          );
      final submitted = await assignments.markTeacherReviewSubmitted(
        traineeId: 'trainee-1',
        attempt: submittedDraft,
        videoStoragePath:
            'assignment_submissions/teacher-1/g1/${assignment.id}/trainee-1/review_sub_keep.mp4',
        videoContentType: 'video/mp4',
        videoSizeBytes: 1200,
        videoDurationMs: 4000,
        submittedAt: DateTime.utc(2026, 8, 20),
        videoExpiresAt: DateTime.utc(2026, 9, 19),
      );
      expect(
        () => assignments.markTeacherReviewSubmissionAbandoned(
          traineeId: 'trainee-1',
          attempt: submitted,
        ),
        throwsA(isA<ClassroomException>()),
      );
      expect(assignments.attempts[submitted.id], isNotNull);
    },
  );

  test('teacher-reviewed assignment keeps assessmentSpec absent', () async {
    final movement = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'First.',
      requiredProp: TrainingProp.bottle,
    );
    final revision = (await movements.getRevision(
      movementId: movement.id,
      revisionId: movement.currentRevisionId,
    ))!;
    final assignment = await assignments.createTeacherCreatedAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: _group(),
      movement: movement,
      revision: revision,
    );
    expect(assignment.assessmentMode, AssessmentMode.teacherReviewed);
    expect(assignment.assessmentSpec, isNull);
  });

  test(
    'canonical submission can be withdrawn, checked, revised, and sent once per revision',
    () async {
      final movement = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Tin Balance',
        instructions: 'First.',
        requiredProp: TrainingProp.bottle,
      );
      final revision = (await movements.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      ))!;
      var assignment = await assignments.createTeacherCreatedAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: _group(),
        movement: movement,
        revision: revision,
        maxScore: 80,
      );

      final first = await assignments.getOrCreateTeacherReviewSubmission(
        traineeId: 'trainee-1',
        assignment: assignment,
      );
      final same = await assignments.getOrCreateTeacherReviewSubmission(
        traineeId: 'trainee-1',
        assignment: assignment,
      );
      expect(
        first.id,
        canonicalTeacherReviewSubmissionAttemptId(
          assignmentId: assignment.id,
          traineeId: 'trainee-1',
        ),
      );
      expect(first.status, AssignmentAttemptStatus.inProgress);
      expect(same.id, first.id);

      final submittedAt = DateTime.utc(2026, 8, 20, 10);
      final submitted = await assignments.markTeacherReviewSubmitted(
        traineeId: 'trainee-1',
        attempt: first,
        videoStoragePath: assignmentSubmissionStoragePath(
          teacherId: assignment.teacherId,
          groupId: assignment.groupId,
          assignmentId: assignment.id,
          traineeId: 'trainee-1',
          attemptId: first.id,
        ),
        videoContentType: 'video/mp4',
        videoSizeBytes: 2048,
        videoDurationMs: 4000,
        submittedAt: submittedAt,
        videoExpiresAt: DateTime.utc(2026, 9, 19),
      );
      expect(submitted.status, AssignmentAttemptStatus.submitted);

      final unsubmitting = await assignments.beginTeacherReviewUnsubmit(
        traineeId: 'trainee-1',
        attempt: submitted,
      );
      expect(unsubmitting.status, AssignmentAttemptStatus.unsubmitting);
      await expectLater(
        assignments.getOrCreateTeacherReviewSubmission(
          traineeId: 'trainee-1',
          assignment: assignment,
        ),
        throwsA(
          isA<ClassroomException>().having(
            (error) => error.code,
            'code',
            ClassroomError.invalidState,
          ),
        ),
      );
      final returnedToDraft = await assignments.completeTeacherReviewUnsubmit(
        traineeId: 'trainee-1',
        attempt: unsubmitting,
      );
      expect(returnedToDraft.id, first.id);
      expect(returnedToDraft.status, AssignmentAttemptStatus.inProgress);
      expect(returnedToDraft.videoStoragePath, isNull);
      expect(returnedToDraft.submittedAt, isNull);

      assignment = await assignments.updateTeacherAssignmentMaxScore(
        teacherId: 'teacher-1',
        assignmentId: assignment.id,
        maxScore: 90,
      );
      final resubmitted = await assignments.markTeacherReviewSubmitted(
        traineeId: 'trainee-1',
        attempt: returnedToDraft,
        videoStoragePath: assignmentSubmissionStoragePath(
          teacherId: assignment.teacherId,
          groupId: assignment.groupId,
          assignmentId: assignment.id,
          traineeId: 'trainee-1',
          attemptId: returnedToDraft.id,
        ),
        videoContentType: 'video/mp4',
        videoSizeBytes: 2048,
        videoDurationMs: 4000,
        submittedAt: submittedAt,
        videoExpiresAt: DateTime.utc(2026, 9, 19),
      );
      final checked = await assignments.saveTeacherReview(
        teacherId: 'teacher-1',
        attempt: resubmitted,
        assignment: assignment,
        gradeScore: 87,
        feedback: 'Good control.',
        reviewedAt: DateTime.utc(2026, 8, 21),
      );
      expect(checked.status, AssignmentAttemptStatus.checked);
      expect(checked.gradeScore, 87);
      expect(checked.gradeMaxScore, 90);
      expect(checked.reviewRevision, 1);
      expect(checked.resultSentForCurrentRevision, isFalse);

      final lockedAssignment = (await assignments.getAssignment(
        assignmentId: assignment.id,
      ))!;
      expect(lockedAssignment.gradingLocked, isTrue);
      expect(lockedAssignment.maxScore, 90);
      expect(
        () => assignments.updateTeacherAssignmentMaxScore(
          teacherId: 'teacher-1',
          assignmentId: assignment.id,
          maxScore: 95,
        ),
        throwsA(
          isA<ClassroomException>().having(
            (error) => error.code,
            'code',
            ClassroomError.invalidState,
          ),
        ),
      );

      final sent = await assignments.markTeacherReviewResultSent(
        teacherId: 'teacher-1',
        attempt: checked,
        messageId: 'message-1',
        sentAt: DateTime.utc(2026, 8, 21, 1),
      );
      final retriedSend = await assignments.markTeacherReviewResultSent(
        teacherId: 'teacher-1',
        attempt: sent,
        messageId: 'message-1',
        sentAt: DateTime.utc(2026, 8, 21, 2),
      );
      expect(sent.resultSentRevision, 1);
      expect(sent.resultMessageId, 'message-1');
      expect(retriedSend.resultSentAt, sent.resultSentAt);

      final revised = await assignments.saveTeacherReview(
        teacherId: 'teacher-1',
        attempt: sent,
        assignment: lockedAssignment,
        gradeScore: 80,
        reviewedAt: DateTime.utc(2026, 8, 22),
      );
      expect(revised.reviewRevision, 2);
      expect(revised.resultSentRevision, isNull);
      expect(revised.resultMessageId, isNull);
      expect(
        () => assignments.beginTeacherReviewUnsubmit(
          traineeId: 'trainee-1',
          attempt: revised,
        ),
        throwsA(isA<ClassroomException>()),
      );
    },
  );
}
