import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher_access/teacher_access_controller.dart';
import 'package:elixr_application/services/join_code_resolver.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTeacherRelationshipRepository relationshipRepository;
  late InMemoryGroupRepository groupRepository;
  late JoinCodeResolver joinCodeResolver;
  late TeacherAccessController controller;

  setUp(() async {
    relationshipRepository = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 16),
    );
    var groupCodeIndex = 0;
    const groupCodes = ['ABCD2345EFGH', 'ZZZZ2345YYYY', 'MNOP2345QRST'];
    groupRepository = InMemoryGroupRepository(
      generateNormalizedCode: () =>
          groupCodes[groupCodeIndex++ % groupCodes.length],
      now: () => DateTime.utc(2026, 8, 16),
    );
    joinCodeResolver = JoinCodeResolver(groupRepository: groupRepository);
    await relationshipRepository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    controller = TeacherAccessController(
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
    );
  });

  tearDown(() {
    controller.dispose();
    relationshipRepository.dispose();
    groupRepository.dispose();
  });

  test('legacy Teacher roster code is not accepted as a class code', () async {
    await controller.start();
    controller.setCodeInput('7kpm-xr4d-q2wt');
    await controller.resolveCode();
    expect(controller.joinStep, JoinTeacherStep.enterCode);
    expect(controller.resolvedGroupInvite, isNull);
    expect(controller.joinError, 'No class is using that code.');
    expect(controller.pendingJoinCount, 0);
  });

  test('group invite resolves and creates pending membership', () async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    await controller.start();
    controller.setCodeInput(invite!.normalizedCode);
    await controller.resolveCode();
    expect(controller.resolvedGroupInvite?.groupId, group.id);
    expect(await controller.confirmJoin(), isTrue);
    expect(controller.pendingGroupMemberships.single.groupId, group.id);
    expect(relationshipRepository.links, isEmpty);
    expect(controller.pendingJoinCount, 1);
  });

  test('approved classes load assignment previews', () async {
    final assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 8, 16),
    );
    addTearDown(assignments.dispose);
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    final membership = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    await groupRepository.approveMembership(
      membershipId: membership.id,
      teacherId: 'teacher-1',
    );
    await assignments.createOfficialAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: group,
      officialMovementName: 'Normal Grip',
    );
    final previewController = TeacherAccessController(
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      assignmentRepository: assignments,
    );
    addTearDown(previewController.dispose);

    await previewController.start();
    await pumpEventQueue();

    expect(
      previewController.assignmentsFor(group.id).single.displayTitle,
      'Normal Grip',
    );
  });
}
