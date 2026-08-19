import 'package:elixr_application/features/teacher/groups/teacher_groups_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryGroupRepository repository;
  late TeacherGroupsController controller;

  setUp(() {
    repository = InMemoryGroupRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 19),
    );
    controller = TeacherGroupsController(
      repository: repository,
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
  });

  tearDown(() {
    controller.dispose();
    repository.dispose();
  });

  test('starts empty then creates a group with invite code', () async {
    await controller.start();
    expect(controller.groups, isEmpty);

    await controller.createGroup('BSHM 4A');
    expect(controller.groups, hasLength(1));
    expect(controller.selectedGroup?.name, 'BSHM 4A');
    expect(controller.activeInvite?.displayCode, '7KPM-XR4D-Q2WT');
  });

  test('approve and remove membership lifecycle', () async {
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = (await repository.getActiveGroupInvite(groupId: group.id))!;
    final membership = await repository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite.normalizedCode,
    );
    await controller.start();
    await controller.selectGroup(group);
    expect(controller.pendingMemberships.single.id, membership.id);

    await controller.approveMembership(membership);
    expect(
      repository.memberships[membership.id]?.hasClassroomAuthorization,
      isTrue,
    );

    await controller.removeMembership(repository.memberships[membership.id]!);
    expect(
      repository.memberships[membership.id]?.status,
      GroupMembershipStatus.removed,
    );
  });
}
