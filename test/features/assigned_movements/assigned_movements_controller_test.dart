import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_policy.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/assigned_movements/assigned_movements_controller.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../teacher/teacher_phase3_test_support.dart';

GroupAssignment _assignment({
  required String id,
  required String groupId,
  String teacherId = 'teacher-1',
  MovementOrigin origin = MovementOrigin.officialElixr,
  TeacherActivityAssessmentConfig? activityAssessment,
  AssignmentAttemptPolicy attemptPolicy = AssignmentAttemptPolicy.legacyDefault,
}) {
  return GroupAssignment(
    id: id,
    teacherId: teacherId,
    groupId: groupId,
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: origin,
    assessmentMode: origin == MovementOrigin.teacherCreated
        ? AssessmentMode.teacherReviewed
        : AssessmentMode.officialGuided,
    status: GroupAssignmentStatus.active,
    displayTitle: 'Hand Stall',
    teacherDisplayName: 'Grace Hopper',
    groupName: groupId == 'g1' ? 'BSHM 4A' : 'Other class',
    officialMovementName: origin == MovementOrigin.officialElixr
        ? 'Hand Stall'
        : null,
    activityAssessment: activityAssessment,
    attemptPolicy: attemptPolicy,
  );
}

AssignmentAttempt _activityAttempt({
  required String id,
  required String assignmentId,
  required TeacherActivityAssessmentConfig assessment,
  required DateTime createdAt,
  DateTime? recordingStartedAt,
}) {
  return AssignmentAttempt(
    id: id,
    traineeId: 'trainee-1',
    teacherId: 'teacher-1',
    groupId: 'g1',
    assignmentId: assignmentId,
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.submitted,
    createdAt: createdAt,
    recordingStartedAt: recordingStartedAt,
    activityAssessmentSnapshot: assessment,
    assignmentConfigurationRevision: 1,
  );
}

GroupMembership _membership({
  required String groupId,
  required GroupMembershipStatus status,
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

void main() {
  test(
    'Activity cards retain complete attempt history for eligibility',
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
        _membership(groupId: 'g1', status: GroupMembershipStatus.approved),
      );
      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(assignments.dispose);
      final assessment = TeacherActivityAssessmentConfig.newActivityDefaults();
      assignments.seedAssignment(
        _assignment(
          id: 'activity',
          groupId: 'g1',
          origin: MovementOrigin.teacherCreated,
          activityAssessment: assessment,
          attemptPolicy: AssignmentAttemptPolicy.finite(2),
        ),
      );
      assignments.seedAttempt(
        _activityAttempt(
          id: 'activity-old',
          assignmentId: 'activity',
          assessment: assessment,
          createdAt: DateTime.utc(2026, 9, 1),
          recordingStartedAt: DateTime.utc(2026, 9, 1),
        ),
      );
      assignments.seedAttempt(
        _activityAttempt(
          id: 'activity-current',
          assignmentId: 'activity',
          assessment: assessment,
          createdAt: DateTime.utc(2026, 9, 2),
          recordingStartedAt: DateTime.utc(2026, 9, 2),
        ),
      );

      final controller = AssignedMovementsController(
        traineeId: 'trainee-1',
        groupRepository: groups,
        assignmentRepository: assignments,
      );
      addTearDown(controller.dispose);
      await controller.start();

      expect(controller.items.single.attempt?.id, 'activity-current');
      expect(
        controller.items.single.activityAttempts.map((attempt) => attempt.id),
        containsAll(['activity-old', 'activity-current']),
      );
    },
  );

  test('only approved memberships expose assignments', () async {
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
    groups.seedGroup(
      const ElixrGroup(
        id: 'g2',
        teacherId: 'teacher-1',
        name: 'Pending class',
        status: ElixrGroupStatus.active,
      ),
    );
    groups.seedMembership(
      _membership(groupId: 'g1', status: GroupMembershipStatus.approved),
    );
    groups.seedMembership(
      _membership(groupId: 'g2', status: GroupMembershipStatus.pending),
    );

    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(_assignment(id: 'asg-approved', groupId: 'g1'));
    assignments.seedAssignment(_assignment(id: 'asg-pending', groupId: 'g2'));

    final controller = AssignedMovementsController(
      traineeId: 'trainee-1',
      groupRepository: groups,
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.start();

    expect(controller.items.map((item) => item.assignment.id), [
      'asg-approved',
    ]);
    expect(controller.items.single.assignment.groupName, 'BSHM 4A');
    expect(
      controller.items.single.assignment.teacherDisplayName,
      'Grace Hopper',
    );
  });

  test('empty state when the trainee has no approved groups', () async {
    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(_assignment(id: 'asg1', groupId: 'g1'));

    final controller = AssignedMovementsController(
      traineeId: 'trainee-1',
      groupRepository: groups,
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.items, isEmpty);
    expect(controller.errorMessage, isNull);
  });

  test('filterGroupId keeps assignments from that class only', () async {
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
    groups.seedGroup(
      const ElixrGroup(
        id: 'g2',
        teacherId: 'teacher-1',
        name: 'BSHM 4B',
        status: ElixrGroupStatus.active,
      ),
    );
    groups.seedMembership(
      _membership(groupId: 'g1', status: GroupMembershipStatus.approved),
    );
    groups.seedMembership(
      _membership(groupId: 'g2', status: GroupMembershipStatus.approved),
    );

    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(_assignment(id: 'asg-a', groupId: 'g1'));
    assignments.seedAssignment(_assignment(id: 'asg-b', groupId: 'g2'));

    final controller = AssignedMovementsController(
      traineeId: 'trainee-1',
      groupRepository: groups,
      assignmentRepository: assignments,
      filterGroupId: 'g1',
    );
    addTearDown(controller.dispose);
    await controller.start();

    expect(controller.items.map((item) => item.assignment.id), ['asg-a']);
  });

  test('fixed-group fetch still requires an approved membership', () async {
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
      _membership(groupId: 'g1', status: GroupMembershipStatus.removed),
    );

    final assignments = InMemoryClassroomAssignmentRepository(
      groupRepository: groups,
    );
    addTearDown(assignments.dispose);
    assignments.seedAssignment(_assignment(id: 'asg-a', groupId: 'g1'));

    final controller = AssignedMovementsController(
      traineeId: 'trainee-1',
      groupRepository: groups,
      assignmentRepository: assignments,
      filterGroupId: 'g1',
    );
    addTearDown(controller.dispose);
    await controller.start();

    expect(controller.items, isEmpty);
    expect(controller.errorMessage, isNull);
  });

  test(
    'assignment loading completes before teacher profile pictures arrive',
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
        _membership(groupId: 'g1', status: GroupMembershipStatus.approved),
      );

      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(assignments.dispose);
      assignments.seedAssignment(_assignment(id: 'asg-a', groupId: 'g1'));
      assignments.seedAssignment(
        _assignment(id: 'asg-b', groupId: 'g1', teacherId: 'teacher-1'),
      );

      final profiles = FakePublicProfileRepository();
      final controller = AssignedMovementsController(
        traineeId: 'trainee-1',
        groupRepository: groups,
        assignmentRepository: assignments,
        publicProfileRepository: profiles,
      );
      addTearDown(controller.dispose);
      await controller.start();

      expect(controller.loading, isFalse);
      expect(controller.items.map((item) => item.assignment.id), [
        'asg-a',
        'asg-b',
      ]);
      expect(
        controller.items.every((item) => item.teacherProfilePictureUrl == null),
        isTrue,
      );
      expect(
        profiles.watchedUserIds.where((id) => id == 'teacher-1').length,
        1,
      );

      profiles.emitProfile(
        'teacher-1',
        const PublicProfile(
          userId: 'teacher-1',
          displayName: 'Grace Hopper',
          visibility: ProfileVisibility.public,
          profilePictureUrl: 'https://example.test/grace.png',
        ),
      );
      await pumpEventQueue();

      expect(
        controller.items.map((item) => item.teacherProfilePictureUrl).toSet(),
        {'https://example.test/grace.png'},
      );

      profiles.emitProfile(
        'teacher-1',
        const PublicProfile(
          userId: 'teacher-1',
          displayName: 'Grace Hopper',
          visibility: ProfileVisibility.public,
        ),
      );
      await pumpEventQueue();
      expect(
        controller.items.every((item) => item.teacherProfilePictureUrl == null),
        isTrue,
      );
    },
  );

  test('watches each unique teacher id once across assignments', () async {
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
    groups.seedGroup(
      const ElixrGroup(
        id: 'g2',
        teacherId: 'teacher-2',
        name: 'BSHM 4B',
        status: ElixrGroupStatus.active,
      ),
    );
    groups.seedMembership(
      _membership(groupId: 'g1', status: GroupMembershipStatus.approved),
    );
    groups.seedMembership(
      _membership(
        groupId: 'g2',
        status: GroupMembershipStatus.approved,
        teacherId: 'teacher-2',
      ),
    );

    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    assignments.seedAssignment(_assignment(id: 'asg-a', groupId: 'g1'));
    assignments.seedAssignment(
      _assignment(id: 'asg-b', groupId: 'g1', teacherId: 'teacher-1'),
    );
    assignments.seedAssignment(
      _assignment(id: 'asg-c', groupId: 'g2', teacherId: 'teacher-2'),
    );

    final profiles = FakePublicProfileRepository();
    final controller = AssignedMovementsController(
      traineeId: 'trainee-1',
      groupRepository: groups,
      assignmentRepository: assignments,
      publicProfileRepository: profiles,
    );
    addTearDown(controller.dispose);
    await controller.start();
    await pumpEventQueue();

    expect(profiles.watchedUserIds.toSet(), {'teacher-1', 'teacher-2'});
    expect(profiles.watchedUserIds.where((id) => id == 'teacher-1').length, 1);
    expect(profiles.watchedUserIds.where((id) => id == 'teacher-2').length, 1);
  });
}
