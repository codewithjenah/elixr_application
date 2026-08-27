import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/assigned_movements/assignment_detail_controller.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:flutter_test/flutter_test.dart';

GroupAssignment _assignment({
  required String id,
  String groupId = 'g1',
  String teacherId = 'teacher-1',
}) {
  return GroupAssignment(
    id: id,
    teacherId: teacherId,
    groupId: groupId,
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: MovementOrigin.officialElixr,
    assessmentMode: AssessmentMode.officialGuided,
    status: GroupAssignmentStatus.active,
    displayTitle: 'Hand Stall',
    teacherDisplayName: 'Grace Hopper',
    groupName: 'BSHM 4A',
    officialMovementName: 'Hand Stall',
  );
}

GroupMembership _membership({
  required GroupMembershipStatus status,
  String groupId = 'g1',
  String traineeId = 'trainee-1',
  String teacherId = 'teacher-1',
}) {
  return GroupMembership(
    id: GroupMembership.documentId(groupId: groupId, traineeId: traineeId),
    groupId: groupId,
    teacherId: teacherId,
    traineeId: traineeId,
    traineeDisplayName: 'Ada Lovelace',
    teacherDisplayName: 'Grace Hopper',
    status: status,
  );
}

AssignmentAttempt _pointer({
  required String id,
  required String assignmentId,
  DateTime? createdAt,
  String traineeId = 'trainee-1',
}) {
  return AssignmentAttempt(
    id: id,
    traineeId: traineeId,
    teacherId: 'teacher-1',
    groupId: 'g1',
    assignmentId: assignmentId,
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: MovementOrigin.officialElixr,
    assessmentMode: AssessmentMode.officialGuided,
    attemptKind: AssignmentAttemptKind.practicePointer,
    status: AssignmentAttemptStatus.submitted,
    sourceSessionId: 'session-$id',
    createdAt: createdAt,
  );
}

AssignmentAttempt _abandonedDraft({
  required String assignmentId,
  String traineeId = 'trainee-1',
}) {
  return AssignmentAttempt(
    id: 'abandoned',
    traineeId: traineeId,
    teacherId: 'teacher-1',
    groupId: 'g1',
    assignmentId: assignmentId,
    movementId: 'tm1',
    revisionId: 'rev1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.draft,
    createdAt: DateTime.utc(2026, 8, 22),
    abandonedAt: DateTime.utc(2026, 8, 22),
  );
}

void main() {
  test(
    'filters attempts by assignmentId, newest first, drops abandoned drafts',
    () async {
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
      groups.seedMembership(
        _membership(status: GroupMembershipStatus.approved),
      );

      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(assignments.dispose);
      assignments.seedAssignment(_assignment(id: 'asg-a'));
      assignments.seedAssignment(_assignment(id: 'asg-b'));
      assignments.seedAttempt(
        _pointer(
          id: 'old',
          assignmentId: 'asg-a',
          createdAt: DateTime.utc(2026, 8, 10),
        ),
      );
      assignments.seedAttempt(
        _pointer(
          id: 'new',
          assignmentId: 'asg-a',
          createdAt: DateTime.utc(2026, 8, 20),
        ),
      );
      assignments.seedAttempt(
        _pointer(
          id: 'other',
          assignmentId: 'asg-b',
          createdAt: DateTime.utc(2026, 8, 21),
        ),
      );
      assignments.seedAttempt(_abandonedDraft(assignmentId: 'asg-a'));

      final controller = AssignmentDetailController(
        assignmentId: 'asg-a',
        traineeId: 'trainee-1',
        groupRepository: groups,
        assignmentRepository: assignments,
      );
      addTearDown(controller.dispose);
      await controller.start();

      expect(controller.authorized, isTrue);
      expect(controller.assignment?.id, 'asg-a');
      expect(controller.attempts.map((attempt) => attempt.id), ['new', 'old']);
      expect(controller.latestAttempt?.id, 'new');
      expect(controller.earlierAttempts.map((attempt) => attempt.id), ['old']);
    },
  );

  test('unauthorized membership does not expose attempts', () async {
    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    groups.seedMembership(_membership(status: GroupMembershipStatus.pending));

    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(_assignment(id: 'asg-a'));
    assignments.seedAttempt(
      _pointer(
        id: 'hidden',
        assignmentId: 'asg-a',
        createdAt: DateTime.utc(2026, 8, 20),
      ),
    );

    final controller = AssignmentDetailController(
      assignmentId: 'asg-a',
      traineeId: 'trainee-1',
      groupRepository: groups,
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.start();

    expect(controller.authorized, isFalse);
    expect(controller.attempts, isEmpty);
    expect(controller.loading, isFalse);
  });

  test(
    'latestClipSubmission prefers the turned-in clip over a newer draft',
    () async {
      final groups = InMemoryGroupRepository();
      addTearDown(groups.dispose);
      groups.seedMembership(
        _membership(status: GroupMembershipStatus.approved),
      );

      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(assignments.dispose);
      assignments.seedAssignment(
        const GroupAssignment(
          id: 'asg-clip',
          teacherId: 'teacher-1',
          groupId: 'g1',
          movementId: 'tm1',
          revisionId: 'rev1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          status: GroupAssignmentStatus.active,
          displayTitle: 'Tin Balance',
          teacherDisplayName: 'Grace Hopper',
          groupName: 'BSHM 4A',
        ),
      );
      assignments.seedAttempt(
        AssignmentAttempt(
          id: 'clip-submitted',
          traineeId: 'trainee-1',
          teacherId: 'teacher-1',
          groupId: 'g1',
          assignmentId: 'asg-clip',
          movementId: 'tm1',
          revisionId: 'rev1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.submitted,
          createdAt: DateTime.utc(2026, 8, 20),
          submittedAt: DateTime.utc(2026, 8, 20),
          videoStoragePath:
              'assignment_submissions/teacher-1/g1/asg-clip/trainee-1/clip-submitted.mp4',
          videoContentType: 'video/mp4',
          videoSizeBytes: 2048,
          videoDurationMs: 4000,
          videoExpiresAt: DateTime.utc(2026, 9, 20),
        ),
      );
      assignments.seedAttempt(
        AssignmentAttempt(
          id: 'later-draft',
          traineeId: 'trainee-1',
          teacherId: 'teacher-1',
          groupId: 'g1',
          assignmentId: 'asg-clip',
          movementId: 'tm1',
          revisionId: 'rev1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          attemptKind: AssignmentAttemptKind.teacherReviewDraft,
          status: AssignmentAttemptStatus.inProgress,
          createdAt: DateTime.utc(2026, 8, 21),
        ),
      );

      final controller = AssignmentDetailController(
        assignmentId: 'asg-clip',
        traineeId: 'trainee-1',
        groupRepository: groups,
        assignmentRepository: assignments,
      );
      addTearDown(controller.dispose);
      await controller.start();

      expect(controller.latestAttempt?.id, 'later-draft');
      expect(controller.latestClipSubmission?.id, 'clip-submitted');
    },
  );

  test('dispose cancels subscriptions without notifying', () async {
    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    groups.seedMembership(_membership(status: GroupMembershipStatus.approved));
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(_assignment(id: 'asg-a'));

    final controller = AssignmentDetailController(
      assignmentId: 'asg-a',
      traineeId: 'trainee-1',
      groupRepository: groups,
      assignmentRepository: assignments,
    );
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.start();
    final before = notifications;
    controller.dispose();
    assignments.seedAttempt(
      _pointer(
        id: 'late',
        assignmentId: 'asg-a',
        createdAt: DateTime.utc(2026, 8, 22),
      ),
    );
    expect(notifications, before);
  });
}
