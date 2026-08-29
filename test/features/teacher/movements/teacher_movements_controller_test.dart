import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movements_controller.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
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

  test('deletes only teacher-created movements with no assignments', () async {
    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    const group = ElixrGroup(
      id: 'g1',
      teacherId: 'teacher-1',
      name: 'BSHM 4A',
      status: ElixrGroupStatus.active,
    );
    groups.seedGroup(group);
    final movements = InMemoryTeacherMovementRepository();
    addTearDown(movements.dispose);
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    final removable = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Balance the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
    final assigned = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Front Flip',
      instructions: 'Practice a controlled front flip.',
      requiredProp: TrainingProp.bottle,
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

    expect(controller.canDeleteMovement(removable), isTrue);
    await controller.deleteMovement(removable);
    expect(await movements.getMovement(movementId: removable.id), isNull);

    await controller.assignTeacherCreated(movement: assigned, group: group);
    expect(controller.hasAssignmentsForMovement(assigned), isTrue);
    expect(controller.canDeleteMovement(assigned), isFalse);

    await controller.deleteMovement(assigned);
    expect(await movements.getMovement(movementId: assigned.id), isNotNull);
    expect(
      controller.errorMessage,
      'This movement cannot be deleted because it is used by an assignment.',
    );
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

  test('roster counts include not-turned-in approved members', () async {
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
    GroupMembership member(String traineeId, String name) {
      return GroupMembership(
        id: GroupMembership.documentId(groupId: 'g1', traineeId: traineeId),
        groupId: 'g1',
        teacherId: 'teacher-1',
        traineeId: traineeId,
        traineeDisplayName: name,
        teacherDisplayName: 'Grace Hopper',
        status: GroupMembershipStatus.approved,
      );
    }

    groups.seedMembership(member('t-awaiting', 'Ada'));
    groups.seedMembership(member('t-approved', 'Alan'));
    groups.seedMembership(member('t-retry', 'Grace'));
    groups.seedMembership(member('t-missing', 'Katherine'));
    groups.seedMembership(member('t-abandoned', 'Margaret'));

    final movements = InMemoryTeacherMovementRepository();
    addTearDown(movements.dispose);
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(
      const GroupAssignment(
        id: 'asg1',
        teacherId: 'teacher-1',
        groupId: 'g1',
        movementId: 'tm1',
        revisionId: 'rev1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Basic Bottle Balances',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
      ),
    );

    AssignmentAttempt reviewAttempt({
      required String id,
      required String traineeId,
      required AssignmentAttemptStatus status,
      AssignmentReviewVerdict? verdict,
      DateTime? abandonedAt,
    }) {
      return AssignmentAttempt(
        id: id,
        traineeId: traineeId,
        teacherId: 'teacher-1',
        groupId: 'g1',
        assignmentId: 'asg1',
        movementId: 'tm1',
        revisionId: 'rev1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
        status: status,
        createdAt: DateTime.utc(2026, 8, 20),
        submittedAt: abandonedAt == null ? DateTime.utc(2026, 8, 20) : null,
        videoStoragePath: abandonedAt == null
            ? 'assignment_submissions/teacher-1/g1/asg1/$traineeId/$id.mp4'
            : null,
        videoContentType: abandonedAt == null ? 'video/mp4' : null,
        videoSizeBytes: abandonedAt == null ? 2048 : null,
        videoDurationMs: abandonedAt == null ? 4000 : null,
        videoExpiresAt: abandonedAt == null ? DateTime.utc(2026, 9, 20) : null,
        reviewVerdict: verdict,
        reviewedAt: verdict == null ? null : DateTime.utc(2026, 8, 21),
        abandonedAt: abandonedAt,
      );
    }

    assignments.seedAttempt(
      reviewAttempt(
        id: 'awaiting',
        traineeId: 't-awaiting',
        status: AssignmentAttemptStatus.submitted,
      ),
    );
    assignments.seedAttempt(
      reviewAttempt(
        id: 'approved',
        traineeId: 't-approved',
        status: AssignmentAttemptStatus.approved,
        verdict: AssignmentReviewVerdict.approved,
      ),
    );
    assignments.seedAttempt(
      reviewAttempt(
        id: 'retry',
        traineeId: 't-retry',
        status: AssignmentAttemptStatus.needsRetry,
        verdict: AssignmentReviewVerdict.needsRetry,
      ),
    );
    assignments.seedAttempt(
      reviewAttempt(
        id: 'abandoned',
        traineeId: 't-abandoned',
        status: AssignmentAttemptStatus.draft,
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

    final counts = controller.rosterCountsFor('asg1');
    expect(counts.turnedIn, 3);
    expect(counts.awaitingReview, 1);
    expect(counts.approved, 1);
    expect(counts.needsRetry, 1);
    expect(counts.notTurnedIn, 2);
    expect(controller.approvedMembersForGroup('g1'), hasLength(5));
    expect(
      controller.approvedMembersForGroup('g1').map((m) => m.traineeId).toList(),
      ['t-awaiting', 't-approved', 't-retry', 't-missing', 't-abandoned'],
    );
    expect(
      controller.latestVisibleAttemptFor(
        assignmentId: 'asg1',
        traineeId: 't-abandoned',
      ),
      isNull,
    );
    expect(
      controller.latestVisibleAttemptFor(
        assignmentId: 'asg1',
        traineeId: 't-missing',
      ),
      isNull,
    );
  });
}
