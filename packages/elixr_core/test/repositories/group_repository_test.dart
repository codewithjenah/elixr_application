import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryGroupRepository groupRepository;
  late InMemoryTeacherRelationshipRepository relationshipRepository;
  var codeIndex = 0;
  final codes = [
    '7KPMXR4DQ2WT',
    'ABCD2345EFGH',
    'ZZZZ2345YYYY',
    'MNOP2345QRST',
  ];

  setUp(() {
    codeIndex = 0;
    groupRepository = InMemoryGroupRepository(
      generateNormalizedCode: () => codes[codeIndex++ % codes.length],
      now: () => DateTime.utc(2026, 8, 19, 8),
      generateGroupId: () => 'group-$codeIndex',
    );
    relationshipRepository = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => 'RSTU23456ABC',
      now: () => DateTime.utc(2026, 8, 19, 8),
    );
  });

  tearDown(() {
    groupRepository.dispose();
    relationshipRepository.dispose();
  });

  test('Teacher creates multiple groups with distinct invite codes', () async {
    final first = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final second = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4B',
    );
    expect(first.name, 'BSHM 4A');
    expect(second.name, 'BSHM 4B');
    expect(first.inviteCode, isNotNull);
    expect(second.inviteCode, isNotNull);
    expect(first.inviteCode, isNot(equals(second.inviteCode)));
  });

  test('unrelated Teacher cannot mutate another Teacher group', () async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    await expectLater(
      groupRepository.renameGroup(
        groupId: group.id,
        teacherId: 'teacher-2',
        name: 'Hijacked',
      ),
      throwsA(isA<GroupException>()),
    );
  });

  test(
    'membership lifecycle prepares classroom protected-read context',
    () async {
      final group = await groupRepository.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSHM 4A',
      );
      final invite = await groupRepository.getActiveGroupInvite(
        groupId: group.id,
      );
      expect(invite, isNotNull);

      final membership = await groupRepository.requestGroupJoin(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        code: invite!.normalizedCode,
      );
      expect(membership.isPending, isTrue);
      expect(membership.hasClassroomAuthorization, isFalse);

      await groupRepository.approveMembership(
        membershipId: membership.id,
        teacherId: 'teacher-1',
      );
      final approved = groupRepository.memberships[membership.id]!;
      expect(approved.hasClassroomAuthorization, isTrue);
      expect(approved.status, GroupMembershipStatus.approved);

      final context =
          groupRepository
              .classroomAccessContexts[ClassroomTeacherAccessContext.documentId(
            teacherId: 'teacher-1',
            traineeId: 'trainee-1',
          )];
      expect(context?.teacherId, 'teacher-1');
      expect(context?.traineeId, 'trainee-1');
      expect(context?.groupId, group.id);

      expect(relationshipRepository.links, isEmpty);
    },
  );

  test('duplicate pending membership is prevented', () async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = (await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    ))!;
    await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite.normalizedCode,
    );
    await expectLater(
      groupRepository.requestGroupJoin(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        code: invite.normalizedCode,
      ),
      throwsA(
        predicate<GroupException>(
          (error) => error.code == GroupError.alreadyPending,
        ),
      ),
    );
  });

  test('re-request after rejection creates a new pending membership', () async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = (await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    ))!;
    final first = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite.normalizedCode,
    );
    await groupRepository.rejectMembership(
      membershipId: first.id,
      teacherId: 'teacher-1',
    );
    final second = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite.normalizedCode,
    );
    expect(second.isPending, isTrue);
  });

  test('approved Trainee can leave and request to rejoin a class', () async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = (await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    ))!;
    final membership = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite.normalizedCode,
    );
    await groupRepository.approveMembership(
      membershipId: membership.id,
      teacherId: 'teacher-1',
    );

    await groupRepository.leaveMembership(
      membershipId: membership.id,
      traineeId: 'trainee-1',
    );
    expect(
      groupRepository.memberships[membership.id]?.status,
      GroupMembershipStatus.removed,
    );

    final rejoin = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite.normalizedCode,
    );
    expect(rejoin.isPending, isTrue);
  });

  test('removal does not modify teacher_student_links consents', () async {
    await relationshipRepository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    final link = await relationshipRepository.requestTeacherJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: 'RSTU23456ABC',
    );
    await relationshipRepository.approveJoin(
      linkId: link.id,
      teacherId: 'teacher-1',
    );
    await relationshipRepository.grantProgressAccess(
      linkId: link.id,
      traineeId: 'trainee-1',
    );

    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = (await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    ))!;
    final membership = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite.normalizedCode,
    );
    await groupRepository.approveMembership(
      membershipId: membership.id,
      teacherId: 'teacher-1',
    );
    await groupRepository.removeMembership(
      membershipId: membership.id,
      teacherId: 'teacher-1',
    );

    expect(
      relationshipRepository.links[link.id]?.hasEffectiveProgressAccess,
      isTrue,
    );
  });

  test('legacy teacher roster invite still resolves separately', () async {
    await relationshipRepository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    final rosterInvite = await relationshipRepository.resolveRosterCode(
      'RSTU23456ABC',
    );
    expect(rosterInvite.teacherId, 'teacher-1');

    await expectLater(
      groupRepository.resolveGroupInviteCode('RSTU23456ABC'),
      throwsA(isA<GroupException>()),
    );
  });

  test(
    'group invite allocation skips legacy teacher_invites namespace',
    () async {
      groupRepository.legacyTeacherInviteCodes = {'7KPMXR4DQ2WT'};
      final group = await groupRepository.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSHM 4A',
      );
      final invite = await groupRepository.getActiveGroupInvite(
        groupId: group.id,
      );
      expect(invite?.normalizedCode, 'ABCD2345EFGH');
    },
  );

  test('createGroup rolls back when invite provisioning fails', () async {
    final failingRepository = InMemoryGroupRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      maxCodeAttempts: 2,
      now: () => DateTime.utc(2026, 8, 19, 8),
      generateGroupId: () => 'group-rollback',
    );
    failingRepository.legacyTeacherInviteCodes = {'7KPMXR4DQ2WT'};
    addTearDown(failingRepository.dispose);

    await expectLater(
      failingRepository.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSHM 4A',
      ),
      throwsA(
        predicate<GroupException>(
          (error) => error.code == GroupError.collisionExhausted,
        ),
      ),
    );
    expect(failingRepository.groups, isEmpty);
  });

  test('watchGroupMemberships scopes by teacher and group', () async {
    final groupA = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final groupB = await groupRepository.createGroup(
      teacherId: 'teacher-2',
      teacherDisplayName: 'Other Teacher',
      name: 'Other Class',
    );
    final inviteA = (await groupRepository.getActiveGroupInvite(
      groupId: groupA.id,
    ))!;
    final inviteB = (await groupRepository.getActiveGroupInvite(
      groupId: groupB.id,
    ))!;
    final membershipA = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: inviteA.normalizedCode,
    );
    await groupRepository.requestGroupJoin(
      traineeId: 'trainee-2',
      traineeDisplayName: 'Other Trainee',
      code: inviteB.normalizedCode,
    );

    final sameGroupSameTeacher = await groupRepository
        .watchGroupMemberships(
          groupId: groupA.id,
          teacherId: 'teacher-1',
          status: GroupMembershipStatus.pending,
        )
        .first;
    expect(sameGroupSameTeacher.map((m) => m.id), [membershipA.id]);

    final sameGroupDifferentTeacher = await groupRepository
        .watchGroupMemberships(
          groupId: groupA.id,
          teacherId: 'teacher-2',
          status: GroupMembershipStatus.pending,
        )
        .first;
    expect(sameGroupDifferentTeacher, isEmpty);

    final differentGroupSameTeacher = await groupRepository
        .watchGroupMemberships(
          groupId: groupB.id,
          teacherId: 'teacher-1',
          status: GroupMembershipStatus.pending,
        )
        .first;
    expect(differentGroupSameTeacher, isEmpty);
  });

  test(
    'watchGroupMemberships filters by status and orders newest first',
    () async {
      final group = await groupRepository.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSHM 4A',
      );
      final invite = (await groupRepository.getActiveGroupInvite(
        groupId: group.id,
      ))!;
      final older = await groupRepository.requestGroupJoin(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        code: invite.normalizedCode,
      );
      await groupRepository.approveMembership(
        membershipId: older.id,
        teacherId: 'teacher-1',
      );
      final newer = await groupRepository.requestGroupJoin(
        traineeId: 'trainee-2',
        traineeDisplayName: 'Alan Turing',
        code: invite.normalizedCode,
      );

      final approved = await groupRepository
          .watchGroupMemberships(
            groupId: group.id,
            teacherId: 'teacher-1',
            status: GroupMembershipStatus.approved,
          )
          .first;
      expect(approved.map((m) => m.id), [older.id]);

      final pending = await groupRepository
          .watchGroupMemberships(
            groupId: group.id,
            teacherId: 'teacher-1',
            status: GroupMembershipStatus.pending,
          )
          .first;
      expect(pending.map((m) => m.id), [newer.id]);
    },
  );

  test('watchTeacherMemberships scopes by owning teacher', () async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = (await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    ))!;
    await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite.normalizedCode,
    );
    await groupRepository.requestGroupJoin(
      traineeId: 'trainee-2',
      traineeDisplayName: 'Alan Turing',
      code: invite.normalizedCode,
    );

    final owned = await groupRepository
        .watchTeacherMemberships(teacherId: 'teacher-1')
        .first;
    expect(owned, hasLength(2));

    final otherTeacher = await groupRepository
        .watchTeacherMemberships(teacherId: 'teacher-2')
        .first;
    expect(otherTeacher, isEmpty);
  });

  test(
    'watchApprovedGroupMembers returns only approved members of that group',
    () async {
      final groupA = await groupRepository.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSHM 4A',
      );
      final groupB = await groupRepository.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSHM 4B',
      );
      final inviteA = (await groupRepository.getActiveGroupInvite(
        groupId: groupA.id,
      ))!;
      final inviteB = (await groupRepository.getActiveGroupInvite(
        groupId: groupB.id,
      ))!;
      final adaA = await groupRepository.requestGroupJoin(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        code: inviteA.normalizedCode,
      );
      await groupRepository.approveMembership(
        membershipId: adaA.id,
        teacherId: 'teacher-1',
      );
      final alanA = await groupRepository.requestGroupJoin(
        traineeId: 'trainee-2',
        traineeDisplayName: 'Alan Turing',
        code: inviteA.normalizedCode,
      );
      expect(alanA.isPending, isTrue);
      final adaB = await groupRepository.requestGroupJoin(
        traineeId: 'trainee-3',
        traineeDisplayName: 'Grace Hopper',
        code: inviteB.normalizedCode,
      );
      await groupRepository.approveMembership(
        membershipId: adaB.id,
        teacherId: 'teacher-1',
      );

      final approvedA = await groupRepository
          .watchApprovedGroupMembers(groupId: groupA.id, teacherId: 'teacher-1')
          .first;
      expect(approvedA.map((m) => m.traineeId), ['trainee-1']);

      final approvedB = await groupRepository
          .watchApprovedGroupMembers(groupId: groupB.id, teacherId: 'teacher-1')
          .first;
      expect(approvedB.map((m) => m.traineeId), ['trainee-3']);
    },
  );
}
