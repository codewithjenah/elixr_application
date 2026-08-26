import 'package:elixr_application/core/auth/teacher_auth_messages.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/features/teacher/groups/teacher_groups_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'teacher_phase3_test_support.dart';

class _SpyGroupRepository implements GroupRepository {
  _SpyGroupRepository(this.inner);

  final InMemoryGroupRepository inner;
  final List<String> privilegedCalls = [];
  final List<
    ({String groupId, String teacherId, GroupMembershipStatus? status})
  >
  membershipWatchCalls = [];
  Object? throwOnNextWrite;
  Object? throwOnNextPendingStream;
  Object? throwOnNextApprovedStream;

  Future<T> _record<T>(String operation, Future<T> Function() action) async {
    privilegedCalls.add(operation);
    final pending = throwOnNextWrite;
    if (pending != null) {
      throwOnNextWrite = null;
      throw pending;
    }
    return action();
  }

  @override
  Future<ElixrGroup> createGroup({
    required String teacherId,
    required String teacherDisplayName,
    required String name,
  }) {
    return _record(
      'createGroup',
      () => inner.createGroup(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        name: name,
      ),
    );
  }

  @override
  Stream<List<ElixrGroup>> watchTeacherGroups({required String teacherId}) {
    return inner.watchTeacherGroups(teacherId: teacherId);
  }

  @override
  Future<ElixrGroup?> getGroup({required String groupId}) {
    return inner.getGroup(groupId: groupId);
  }

  @override
  Future<void> renameGroup({
    required String groupId,
    required String teacherId,
    required String name,
  }) {
    return _record(
      'renameGroup',
      () =>
          inner.renameGroup(groupId: groupId, teacherId: teacherId, name: name),
    );
  }

  @override
  Future<void> archiveGroup({
    required String groupId,
    required String teacherId,
  }) {
    return _record(
      'archiveGroup',
      () => inner.archiveGroup(groupId: groupId, teacherId: teacherId),
    );
  }

  @override
  Future<GroupInvite> createOrRotateGroupInvite({
    required String groupId,
    required String teacherId,
    required String teacherDisplayName,
  }) {
    return _record(
      'rotateInvite',
      () => inner.createOrRotateGroupInvite(
        groupId: groupId,
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
      ),
    );
  }

  @override
  Future<GroupInvite?> getActiveGroupInvite({required String groupId}) {
    return inner.getActiveGroupInvite(groupId: groupId);
  }

  @override
  Future<GroupInvite> resolveGroupInviteCode(String code) {
    return inner.resolveGroupInviteCode(code);
  }

  @override
  Stream<List<GroupMembership>> watchGroupMemberships({
    required String groupId,
    required String teacherId,
    GroupMembershipStatus? status,
  }) {
    membershipWatchCalls.add((
      groupId: groupId,
      teacherId: teacherId,
      status: status,
    ));
    final stream = inner.watchGroupMemberships(
      groupId: groupId,
      teacherId: teacherId,
      status: status,
    );
    final pendingError = throwOnNextPendingStream;
    if (pendingError != null && status == GroupMembershipStatus.pending) {
      throwOnNextPendingStream = null;
      return Stream<List<GroupMembership>>.error(pendingError);
    }
    final approvedError = throwOnNextApprovedStream;
    if (approvedError != null && status == GroupMembershipStatus.approved) {
      throwOnNextApprovedStream = null;
      return Stream<List<GroupMembership>>.error(approvedError);
    }
    return stream;
  }

  @override
  Stream<List<GroupMembership>> watchTeacherMemberships({
    required String teacherId,
  }) {
    return inner.watchTeacherMemberships(teacherId: teacherId);
  }

  @override
  Stream<List<GroupMembership>> watchTraineeMemberships({
    required String traineeId,
  }) {
    return inner.watchTraineeMemberships(traineeId: traineeId);
  }

  @override
  Stream<List<GroupMembership>> watchApprovedGroupMembers({
    required String groupId,
    required String teacherId,
  }) {
    return inner.watchApprovedGroupMembers(
      groupId: groupId,
      teacherId: teacherId,
    );
  }

  @override
  Future<void> prepareClassroomAccessContext({
    required String teacherId,
    required String traineeId,
    required String groupId,
  }) {
    return inner.prepareClassroomAccessContext(
      teacherId: teacherId,
      traineeId: traineeId,
      groupId: groupId,
    );
  }

  @override
  Future<GroupMembership> requestGroupJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  }) {
    return inner.requestGroupJoin(
      traineeId: traineeId,
      traineeDisplayName: traineeDisplayName,
      code: code,
    );
  }

  @override
  Future<void> approveMembership({
    required String membershipId,
    required String teacherId,
  }) {
    return _record(
      'approveMembership',
      () => inner.approveMembership(
        membershipId: membershipId,
        teacherId: teacherId,
      ),
    );
  }

  @override
  Future<void> rejectMembership({
    required String membershipId,
    required String teacherId,
  }) {
    return _record(
      'rejectMembership',
      () => inner.rejectMembership(
        membershipId: membershipId,
        teacherId: teacherId,
      ),
    );
  }

  @override
  Future<void> removeMembership({
    required String membershipId,
    required String teacherId,
  }) {
    return _record(
      'removeMembership',
      () => inner.removeMembership(
        membershipId: membershipId,
        teacherId: teacherId,
      ),
    );
  }

  @override
  Future<void> cancelMembership({
    required String membershipId,
    required String traineeId,
  }) {
    return inner.cancelMembership(
      membershipId: membershipId,
      traineeId: traineeId,
    );
  }
}

void main() {
  late InMemoryGroupRepository memory;
  late _SpyGroupRepository repository;
  late FakePublicProfileRepository profiles;
  late TeacherGroupsController controller;
  late bool authorizationOk;
  Object? authorizationError;
  var authorizationCalls = 0;
  var inviteCodeIndex = 0;
  var groupIdIndex = 0;

  const inviteCodes = ['7KPMXR4DQ2WT', 'ABCDEFGH2345'];

  Future<bool> ensureTeacherAuthorization() async {
    authorizationCalls++;
    final error = authorizationError;
    if (error != null) throw error;
    return authorizationOk;
  }

  setUp(() {
    inviteCodeIndex = 0;
    groupIdIndex = 0;
    authorizationOk = true;
    authorizationError = null;
    authorizationCalls = 0;
    memory = InMemoryGroupRepository(
      generateNormalizedCode: () => inviteCodes[inviteCodeIndex++],
      generateGroupId: () => 'group-${groupIdIndex++}',
      now: () => DateTime.utc(2026, 8, 19),
    );
    repository = _SpyGroupRepository(memory);
    profiles = FakePublicProfileRepository();
    controller = TeacherGroupsController(
      repository: repository,
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      ensureTeacherAuthorization: ensureTeacherAuthorization,
      publicProfileRepository: profiles,
    );
  });

  tearDown(() {
    controller.dispose();
    memory.dispose();
  });

  Future<GroupMembership> seedPendingMembership() async {
    final group = await memory.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = (await memory.getActiveGroupInvite(groupId: group.id))!;
    final membership = await memory.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite.normalizedCode,
    );
    await controller.start();
    await controller.selectGroup(group);
    return membership;
  }

  test('starts empty then creates a group with invite code', () async {
    await controller.start();
    expect(controller.groups, isEmpty);

    final group = await controller.createGroup('BSHM 4A');
    expect(controller.groups, hasLength(1));
    expect(group?.name, 'BSHM 4A');
    expect(controller.selectedGroup, isNull);
    expect(controller.activeInvite, isNull);
    expect(repository.privilegedCalls, contains('createGroup'));

    await controller.selectGroup(group!);
    expect(controller.selectedGroup?.name, 'BSHM 4A');
    expect(controller.activeInvite?.displayCode, '7KPM-XR4D-Q2WT');
  });

  test('approve and remove membership lifecycle', () async {
    final membership = await seedPendingMembership();
    expect(controller.pendingMemberships.single.id, membership.id);

    await controller.approveMembership(membership);
    expect(
      memory.memberships[membership.id]?.hasClassroomAuthorization,
      isTrue,
    );

    await controller.removeMembership(memory.memberships[membership.id]!);
    expect(
      memory.memberships[membership.id]?.status,
      GroupMembershipStatus.removed,
    );
  });

  test(
    'approveMembership calls repository when authorization refresh succeeds',
    () async {
      final membership = await seedPendingMembership();

      await controller.approveMembership(membership);

      expect(authorizationCalls, 1);
      expect(repository.privilegedCalls, contains('approveMembership'));
      expect(
        memory.memberships[membership.id]?.status,
        GroupMembershipStatus.approved,
      );
      expect(controller.busy, isFalse);
    },
  );

  test(
    'approveMembership does not call repository when authorization refresh fails',
    () async {
      final membership = await seedPendingMembership();
      authorizationOk = false;

      await controller.approveMembership(membership);

      expect(authorizationCalls, 1);
      expect(repository.privilegedCalls, isEmpty);
      expect(
        memory.memberships[membership.id]?.status,
        GroupMembershipStatus.pending,
      );
      expect(
        controller.errorMessage,
        TeacherAuthMessages.teacherAuthorizationRefreshRequired,
      );
      expect(controller.busy, isFalse);
    },
  );

  test(
    'approveMembership does not write when authorization refresh throws',
    () async {
      final membership = await seedPendingMembership();
      authorizationError = Exception('cloud_firestore/permission-denied');

      await controller.approveMembership(membership);

      expect(authorizationCalls, 1);
      expect(repository.privilegedCalls, isEmpty);
      expect(
        memory.memberships[membership.id]?.status,
        GroupMembershipStatus.pending,
      );
      expect(
        controller.errorMessage,
        TeacherAuthMessages.teacherAuthorizationRefreshRequired,
      );
      expect(
        controller.errorMessage,
        isNot(contains('cloud_firestore/permission-denied')),
      );
      expect(controller.busy, isFalse);
    },
  );

  test('rejectMembership works after verified authorization', () async {
    final membership = await seedPendingMembership();

    await controller.rejectMembership(membership);

    expect(authorizationCalls, 1);
    expect(repository.privilegedCalls, contains('rejectMembership'));
    expect(
      memory.memberships[membership.id]?.status,
      GroupMembershipStatus.rejected,
    );
  });

  test('removeMembership works after verified authorization', () async {
    final membership = await seedPendingMembership();
    await controller.approveMembership(membership);
    authorizationCalls = 0;
    repository.privilegedCalls.clear();

    await controller.removeMembership(memory.memberships[membership.id]!);

    expect(authorizationCalls, 1);
    expect(repository.privilegedCalls, contains('removeMembership'));
    expect(
      memory.memberships[membership.id]?.status,
      GroupMembershipStatus.removed,
    );
  });

  test('createGroup requires authorization refresh', () async {
    await controller.start();
    authorizationOk = false;

    await controller.createGroup('BSHM 4A');

    expect(authorizationCalls, 1);
    expect(repository.privilegedCalls, isEmpty);
    expect(memory.groups, isEmpty);
    expect(
      controller.errorMessage,
      TeacherAuthMessages.teacherAuthorizationRefreshRequired,
    );
  });

  test('renameSelectedGroup requires authorization refresh', () async {
    await controller.start();
    final group = await controller.createGroup('BSHM 4A');
    await controller.selectGroup(group!);
    authorizationCalls = 0;
    repository.privilegedCalls.clear();
    authorizationOk = false;

    await controller.renameSelectedGroup('BSHM 4B');

    expect(authorizationCalls, 1);
    expect(repository.privilegedCalls, isEmpty);
    expect(controller.selectedGroup?.name, 'BSHM 4A');
    expect(
      controller.errorMessage,
      TeacherAuthMessages.teacherAuthorizationRefreshRequired,
    );
  });

  test('archiveSelectedGroup requires authorization refresh', () async {
    await controller.start();
    final group = await controller.createGroup('BSHM 4A');
    await controller.selectGroup(group!);
    final groupId = controller.selectedGroup!.id;
    authorizationCalls = 0;
    repository.privilegedCalls.clear();
    authorizationOk = false;

    await controller.archiveSelectedGroup();

    expect(authorizationCalls, 1);
    expect(repository.privilegedCalls, isEmpty);
    expect(memory.groups[groupId]?.status, ElixrGroupStatus.active);
    expect(controller.selectedGroup?.id, groupId);
    expect(
      controller.errorMessage,
      TeacherAuthMessages.teacherAuthorizationRefreshRequired,
    );
  });

  test('rotateInvite requires authorization refresh', () async {
    await controller.start();
    final group = await controller.createGroup('BSHM 4A');
    await controller.selectGroup(group!);
    final originalCode = controller.activeInvite?.normalizedCode;
    authorizationCalls = 0;
    repository.privilegedCalls.clear();
    authorizationOk = false;

    await controller.rotateInvite();

    expect(authorizationCalls, 1);
    expect(repository.privilegedCalls, isEmpty);
    expect(controller.activeInvite?.normalizedCode, originalCode);
    expect(
      controller.errorMessage,
      TeacherAuthMessages.teacherAuthorizationRefreshRequired,
    );
  });

  test(
    'repository throw after successful auth shows a safe failure and resets busy',
    () async {
      final membership = await seedPendingMembership();
      repository.throwOnNextWrite = Exception(
        '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
      );

      await controller.approveMembership(membership);

      expect(authorizationCalls, 1);
      expect(repository.privilegedCalls, contains('approveMembership'));
      expect(
        memory.memberships[membership.id]?.status,
        GroupMembershipStatus.pending,
      );
      expect(controller.errorMessage, 'Could not approve that request.');
      expect(controller.errorMessage, isNot(contains('cloud_firestore')));
      expect(controller.errorMessage, isNot(contains('permission-denied')));
      expect(controller.busy, isFalse);
    },
  );

  test('raw Firebase exception never becomes errorMessage', () async {
    final membership = await seedPendingMembership();
    repository.throwOnNextWrite = Exception(
      'cloud_firestore/permission-denied token=eyJhbGci uid=teacher-1',
    );

    await controller.approveMembership(membership);

    expect(controller.errorMessage, isNotNull);
    expect(controller.errorMessage, isNot(contains('cloud_firestore')));
    expect(controller.errorMessage, isNot(contains('permission-denied')));
    expect(controller.errorMessage, isNot(contains('token=')));
    expect(controller.errorMessage, isNot(contains('uid=')));
    expect(controller.errorMessage, isNot(contains('eyJ')));
  });

  test(
    'selectGroup subscribes with authenticated teacherId and statuses',
    () async {
      final group = await memory.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSHM 4A',
      );
      await controller.start();
      repository.membershipWatchCalls.clear();

      await controller.selectGroup(group);

      expect(
        repository.membershipWatchCalls,
        containsAll([
          (
            groupId: group.id,
            teacherId: 'teacher-1',
            status: GroupMembershipStatus.pending,
          ),
          (
            groupId: group.id,
            teacherId: 'teacher-1',
            status: GroupMembershipStatus.approved,
          ),
        ]),
      );
    },
  );

  test('openGroupById selects an owned class and rejects others', () async {
    final group = await memory.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final other = await memory.createGroup(
      teacherId: 'teacher-2',
      teacherDisplayName: 'Other Teacher',
      name: 'Other Class',
    );
    await controller.start();

    await controller.openGroupById(group.id);
    expect(controller.unauthorized, isFalse);
    expect(controller.selectedGroup?.id, group.id);
    expect(controller.activeInvite, isNotNull);

    await controller.openGroupById(other.id);
    expect(controller.unauthorized, isTrue);
    expect(controller.selectedGroup, isNull);
    expect(controller.errorMessage, 'This class is not available.');
  });

  test('startForGroup marks missing classes unauthorized', () async {
    await controller.startForGroup('missing');
    expect(controller.loading, isFalse);
    expect(controller.unauthorized, isTrue);
    expect(controller.selectedGroup, isNull);
    expect(controller.errorMessage, 'This class is not available.');
  });

  test('unrelated Teacher membership data does not appear', () async {
    final group = await memory.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final otherGroup = await memory.createGroup(
      teacherId: 'teacher-2',
      teacherDisplayName: 'Other Teacher',
      name: 'Other Class',
    );
    final otherInvite = (await memory.getActiveGroupInvite(
      groupId: otherGroup.id,
    ))!;
    final otherMembership = await memory.requestGroupJoin(
      traineeId: 'trainee-2',
      traineeDisplayName: 'Other Trainee',
      code: otherInvite.normalizedCode,
    );
    await memory.approveMembership(
      membershipId: otherMembership.id,
      teacherId: 'teacher-2',
    );

    await controller.start();
    await controller.selectGroup(group);

    expect(controller.approvedMemberships, isEmpty);
    expect(controller.pendingMemberships, isEmpty);
  });

  test(
    'approved stream error shows safe message and preserves last state',
    () async {
      final membership = await seedPendingMembership();
      await controller.approveMembership(membership);
      expect(controller.approvedMemberships, hasLength(1));
      repository.throwOnNextApprovedStream = Exception(
        'cloud_firestore/permission-denied',
      );

      await controller.selectGroup(controller.selectedGroup!);

      expect(controller.errorMessage, 'Could not load members.');
      expect(controller.errorMessage, isNot(contains('cloud_firestore')));
      expect(controller.approvedMemberships, hasLength(1));
    },
  );

  test('pending stream error shows safe message', () async {
    final group = await memory.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    await controller.start();
    repository.throwOnNextPendingStream = Exception(
      'cloud_firestore/permission-denied',
    );

    await controller.selectGroup(group);

    expect(controller.errorMessage, 'Could not load pending requests.');
    expect(controller.errorMessage, isNot(contains('cloud_firestore')));
  });

  test('maps member public profile pictures and drops them on clear', () async {
    final membership = await seedPendingMembership();
    await controller.approveMembership(membership);
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

    controller.clearSelection();
    await pumpEventQueue();

    expect(controller.profilePictureUrlFor('trainee-1'), isNull);
  });

  test(
    'stops watching profiles for members who leave the selected group',
    () async {
      final membership = await seedPendingMembership();
      await controller.approveMembership(membership);
      await pumpEventQueue();
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
      expect(controller.profilePictureUrlFor('trainee-1'), isNotNull);

      await controller.removeMembership(memory.memberships[membership.id]!);
      await pumpEventQueue();

      expect(controller.approvedMemberships, isEmpty);
      expect(controller.profilePictureUrlFor('trainee-1'), isNull);
    },
  );
}
