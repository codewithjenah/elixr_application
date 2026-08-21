import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movements_controller.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official catalog is the enabled 12 ELIXR movements', () async {
    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    final movements = InMemoryTeacherMovementRepository();
    addTearDown(movements.dispose);
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);

    final controller = TeacherMovementsController(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      groupRepository: groups,
      movementRepository: movements,
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.start();

    expect(controller.officialCatalog, hasLength(12));
    expect(
      controller.officialCatalog.map((movement) => movement.name),
      unorderedEquals(
        movementCatalog.where((m) => m.enabled).map((m) => m.name),
      ),
    );
    expect(
      controller.officialCatalog.any(
        (movement) => movement.name == 'Arm Stall',
      ),
      isFalse,
    );
  });

  test('assign official movement to own active group', () async {
    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    groups.seedGroup(
      const ElixrGroup(
        id: 'g1',
        teacherId: 'teacher-1',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
    );
    final movements = InMemoryTeacherMovementRepository();
    addTearDown(movements.dispose);
    final assignments = InMemoryClassroomAssignmentRepository(
      generateId: () => 'asg-hand',
    );
    addTearDown(assignments.dispose);

    final controller = TeacherMovementsController(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      groupRepository: groups,
      movementRepository: movements,
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.start();

    final handStall = controller.officialCatalog.firstWhere(
      (movement) => movement.name == 'Hand Stall',
    );
    await controller.assignOfficial(
      movement: handStall,
      group: groups.groups['g1']!,
    );
    expect(controller.assignments, hasLength(1));
    expect(controller.assignments.single.officialMovementName, 'Hand Stall');
    expect(controller.groupName('g1'), 'BSHM 4A');
    expect(handStall.supportedProps, contains(TrainingProp.bottle));
  });

  test(
    'review queue excludes draft and abandoned teacher_review_submission attempts',
    () async {
      final groups = InMemoryGroupRepository();
      addTearDown(groups.dispose);
      final movements = InMemoryTeacherMovementRepository();
      addTearDown(movements.dispose);
      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(assignments.dispose);
      assignments.seedAttempt(
        AssignmentAttempt(
          id: 'review_sub_draft',
          traineeId: 'trainee-1',
          teacherId: 'teacher-1',
          groupId: 'g1',
          assignmentId: 'asg1',
          movementId: 'tm1',
          revisionId: 'rev1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.draft,
          createdAt: DateTime.utc(2026, 8, 20),
        ),
      );
      assignments.seedAttempt(
        AssignmentAttempt(
          id: 'review_sub_ready',
          traineeId: 'trainee-1',
          teacherId: 'teacher-1',
          groupId: 'g1',
          assignmentId: 'asg1',
          movementId: 'tm1',
          revisionId: 'rev1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.submitted,
          createdAt: DateTime.utc(2026, 8, 21),
          submittedAt: DateTime.utc(2026, 8, 21),
          videoStoragePath:
              'assignment_submissions/teacher-1/g1/asg1/trainee-1/review_sub_ready.mp4',
          videoContentType: 'video/mp4',
          videoSizeBytes: 2048,
          videoDurationMs: 4000,
          videoExpiresAt: DateTime.utc(2026, 9, 20),
        ),
      );

      assignments.seedAttempt(
        AssignmentAttempt(
          id: 'review_sub_abandoned',
          traineeId: 'trainee-1',
          teacherId: 'teacher-1',
          groupId: 'g1',
          assignmentId: 'asg1',
          movementId: 'tm1',
          revisionId: 'rev1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.draft,
          createdAt: DateTime.utc(2026, 8, 22),
          abandonedAt: DateTime.utc(2026, 8, 22),
        ),
      );

      final controller = TeacherMovementsController(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        groupRepository: groups,
        movementRepository: movements,
        assignmentRepository: assignments,
      );
      addTearDown(controller.dispose);
      await controller.start();

      expect(controller.reviewQueue, hasLength(1));
      expect(controller.reviewQueue.single.id, 'review_sub_ready');
      expect(
        controller.reviewQueue.every(
          (attempt) => attempt.isReviewFacingSubmission,
        ),
        isTrue,
      );
    },
  );
}
