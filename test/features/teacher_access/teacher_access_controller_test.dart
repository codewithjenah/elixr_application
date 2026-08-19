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
    groupRepository = InMemoryGroupRepository(
      generateNormalizedCode: () => 'ABCD2345EFGH',
      now: () => DateTime.utc(2026, 8, 16),
    );
    joinCodeResolver = JoinCodeResolver(
      groupRepository: groupRepository,
      relationshipRepository: relationshipRepository,
    );
    await relationshipRepository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    controller = TeacherAccessController(
      relationshipRepository: relationshipRepository,
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

  test('resolve and explicit confirmation create a V2 join request', () async {
    await controller.start();
    controller.setCodeInput('7kpm-xr4d-q2wt');
    await controller.resolveCode();
    expect(
      controller.resolvedTeacherInvite?.teacherDisplayName,
      'Grace Hopper',
    );
    expect(controller.pending, isEmpty);

    expect(await controller.confirmJoin(), isTrue);
    expect(controller.pending.single.requestVersion, 2);
    expect(controller.pending.single.teacherDisplayName, 'Grace Hopper');
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
    expect(controller.resolvedKind, JoinCodeKind.groupInvite);
    expect(await controller.confirmJoin(), isTrue);
    expect(controller.pendingGroupMemberships.single.groupId, group.id);
    expect(relationshipRepository.links, isEmpty);
  });

  test('Trainee can cancel a pending request', () async {
    await controller.start();
    controller.setCodeInput('7KPMXR4DQ2WT');
    await controller.resolveCode();
    await controller.confirmJoin();
    await controller.cancelPending(controller.pending.single);
    expect(controller.pending, isEmpty);
  });
}
