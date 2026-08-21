import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_submission_limits.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:elixr_application/data/repositories/in_memory_assignment_submission_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('submitLocalClip never awards XP and uses a new attempt', () async {
    final assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 8, 20),
      generateId: () => 'asg1',
    );
    addTearDown(assignments.dispose);
    final movements = InMemoryTeacherMovementRepository(
      now: () => DateTime.utc(2026, 8, 20),
      generateId: () => 'tm1',
    );
    addTearDown(movements.dispose);
    final movement = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Hold the tin.',
      requiredProp: TrainingProp.bottle,
    );
    final revision = (await movements.getRevision(
      movementId: movement.id,
      revisionId: movement.currentRevisionId,
    ))!;
    final assignment = await assignments.createTeacherCreatedAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: const ElixrGroup(
        id: 'g1',
        teacherId: 'teacher-1',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
      movement: movement,
      revision: revision,
    );
    final deleted = <String>{};
    final submissions = InMemoryAssignmentSubmissionRepository(
      classroom: assignments,
      now: () => DateTime.utc(2026, 8, 20),
      deletedPaths: deleted,
    );

    final submitted = await submissions.submitLocalClip(
      traineeId: 'trainee-1',
      assignment: assignment,
      clip: const SubmissionRecordResult(
        localPath: r'C:\Temp\elixr_submissions\clip.mp4',
        durationMs: 3500,
        sizeBytes: 2048,
        contentType: 'video/mp4',
      ),
    );

    expect(
      submitted.attemptKind,
      AssignmentAttemptKind.teacherReviewSubmission,
    );
    expect(submitted.status, AssignmentAttemptStatus.submitted);
    expect(submitted.awardsGlobalXp, isFalse);
    expect(submitted.sourceSessionId, isNull);
    expect(
      submitted.videoStoragePath,
      assignmentSubmissionStoragePath(
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: assignment.id,
        traineeId: 'trainee-1',
        attemptId: submitted.id,
      ),
    );
    expect(submitted.id, startsWith('review_sub_'));
  });

  test('object-not-found reconcile is not fatal', () async {
    final assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 9, 20),
    );
    addTearDown(assignments.dispose);
    const path =
        'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_old.mp4';
    assignments.seedAttempt(
      AssignmentAttempt(
        id: 'review_sub_old',
        traineeId: 'trainee-1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: 'asg1',
        movementId: 'tm1',
        revisionId: 'rev1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: AssignmentAttemptStatus.approved,
        videoStoragePath: path,
        videoContentType: 'video/mp4',
        videoSizeBytes: 100,
        videoDurationMs: 1000,
        submittedAt: DateTime.utc(2026, 8, 1),
        reviewedAt: DateTime.utc(2026, 8, 2),
        reviewVerdict: AssignmentReviewVerdict.approved,
        videoExpiresAt: DateTime.utc(2026, 8, 16),
      ),
    );
    final submissions = InMemoryAssignmentSubmissionRepository(
      classroom: assignments,
      now: () => DateTime.utc(2026, 9, 20),
      missingPaths: {path},
    );
    await submissions.reconcileExpiredVideos(
      actorId: 'teacher-1',
      attempts: assignments.attempts.values.toList(),
    );
    final updated = assignments.attempts['review_sub_old']!;
    expect(updated.videoStoragePath, isNull);
    expect(updated.reviewVerdict, AssignmentReviewVerdict.approved);
    expect(updated.status, AssignmentAttemptStatus.approved);
    expect(updated.deletionFailed, isFalse);
  });
}
