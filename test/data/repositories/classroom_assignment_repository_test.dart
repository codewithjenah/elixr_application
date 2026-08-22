import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_ids.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/rubric_assessment.dart';
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

  test(
    'template assignment freezes AssessmentSpec from the revision',
    () async {
      final movement = await movements.createTemplateScoredMovement(
        teacherId: 'teacher-1',
        title: 'Classroom Wrist Stall',
        instructions: 'Balance the bottle on the wrist.',
        assessment: const AssessmentSpec(laterality: AssessmentLaterality.left),
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
      expect(assignment.assessmentMode, AssessmentMode.templateScored);
      expect(
        assignment.assessmentSpec,
        const AssessmentSpec(laterality: AssessmentLaterality.left),
      );

      await movements.editTemplateScoredMovement(
        teacherId: 'teacher-1',
        movementId: movement.id,
        title: 'Classroom Wrist Stall v2',
        instructions: 'Revised.',
        assessment: const AssessmentSpec(
          laterality: AssessmentLaterality.right,
        ),
      );
      expect(
        assignment.assessmentSpec,
        const AssessmentSpec(laterality: AssessmentLaterality.left),
      );
      expect(assignment.revisionId, revision.id);
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

  test('template score identity comes only from the assignment', () async {
    final movement = await movements.createTemplateScoredMovement(
      teacherId: 'teacher-1',
      title: 'Classroom Wrist Stall',
      instructions: 'Balance the bottle on the wrist.',
      assessment: const AssessmentSpec(laterality: AssessmentLaterality.either),
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
    const rubric = RubricAssessment(
      technique: 3,
      stability: 2,
      completion: 3,
      propPositioning: 2,
    );
    final attempt = await assignments.createTemplateScoreAttempt(
      traineeId: 'trainee-1',
      assignment: assignment,
      rubric: rubric,
      durationSeconds: 11,
      completedAt: DateTime.utc(2026, 8, 22, 4),
    );
    expect(attempt.attemptKind, AssignmentAttemptKind.templateScore);
    expect(attempt.teacherId, assignment.teacherId);
    expect(attempt.groupId, assignment.groupId);
    expect(attempt.movementId, assignment.movementId);
    expect(attempt.revisionId, assignment.revisionId);
    expect(attempt.assignmentId, assignment.id);
    expect(attempt.assessmentMode, AssessmentMode.templateScored);
    expect(attempt.awardsGlobalXp, isFalse);
    expect(attempt.sourceSessionId, isNull);
    expect(attempt.rubric?.total, 10);
    expect(attempt.id, startsWith('template_score_'));

    final second = await assignments.createTemplateScoreAttempt(
      traineeId: 'trainee-1',
      assignment: assignment,
      rubric: rubric,
      durationSeconds: 12,
      completedAt: DateTime.utc(2026, 8, 22, 5),
    );
    expect(second.id, isNot(attempt.id));
  });
}
