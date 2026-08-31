import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/assigned_movements/assigned_movements_controller.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:flutter_test/flutter_test.dart';

GroupAssignment _assignment({
  required String id,
  required String groupId,
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
    groupName: groupId == 'g1' ? 'BSHM 4A' : 'Other class',
    officialMovementName: 'Hand Stall',
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
}
