import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/features/teacher_access/teacher_access_controller.dart';
import 'package:elixr_application/services/join_code_resolver.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../teacher/teacher_phase3_test_support.dart';

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

  test(
    'classroom-backed Teachers are omitted from legacy-only links',
    () async {
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
      final legacyLink = await relationshipRepository.requestTeacherJoin(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        code: '7KPMXR4DQ2WT',
      );
      await relationshipRepository.approveJoin(
        linkId: legacyLink.id,
        teacherId: 'teacher-1',
      );

      await controller.start();

      expect(controller.classroomTeacherIds, contains('teacher-1'));
      expect(controller.legacyOnlyApproved, isEmpty);
    },
  );

  test('approved group membership loads classmates for that class', () async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    final ada = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    final alan = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-2',
      traineeDisplayName: 'Alan Turing',
      code: invite.normalizedCode,
    );
    await groupRepository.approveMembership(
      membershipId: ada.id,
      teacherId: 'teacher-1',
    );
    await groupRepository.approveMembership(
      membershipId: alan.id,
      teacherId: 'teacher-1',
    );

    await controller.start();
    await pumpEventQueue();

    expect(
      controller.membersForGroup(group.id).map((m) => m.traineeId).toSet(),
      {'trainee-1', 'trainee-2'},
    );
  });

  test('maps classmate public profile pictures', () async {
    final profiles = FakePublicProfileRepository();
    controller.dispose();
    controller = TeacherAccessController(
      relationshipRepository: relationshipRepository,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      publicProfileRepository: profiles,
    );
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    final ada = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    await groupRepository.approveMembership(
      membershipId: ada.id,
      teacherId: 'teacher-1',
    );

    await controller.start();
    await pumpEventQueue();

    expect(profiles.watchedUserIds, contains('trainee-1'));
    expect(controller.profilePictureUrlFor('trainee-1'), isNull);

    profiles.emitProfile(
      'trainee-1',
      const PublicProfile(
        userId: 'trainee-1',
        displayName: 'Ada Lovelace',
        visibility: ProfileVisibility.public,
        profilePictureUrl: 'https://example.test/ada.png',
      ),
    );
    await pumpEventQueue();

    expect(
      controller.profilePictureUrlFor('trainee-1'),
      'https://example.test/ada.png',
    );
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
