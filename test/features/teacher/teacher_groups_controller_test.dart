import 'package:elixr_application/core/auth/teacher_auth_messages.dart';
import 'package:elixr_application/features/teacher/groups/teacher_groups_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _SpyGroupRepository implements GroupRepository {
  _SpyGroupRepository(this.inner);

  final InMemoryGroupRepository inner;
  final List<String> privilegedCalls = [];
  Object? throwOnNextWrite;

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
    GroupMembershipStatus? status,
  }) {
    return inner.watchGroupMemberships(groupId: groupId, status: status);
  }

  @override
  Stream<List<GroupMembership>> watchTraineeMemberships({
    required String traineeId,
  }) {
    return inner.watchTraineeMemberships(traineeId: traineeId);
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
  late TeacherGroupsController controller;
  late bool authorizationOk;
  Object? authorizationError;
  var authorizationCalls = 0;
  var inviteCodeIndex = 0;

  const inviteCodes = ['7KPMXR4DQ2WT', 'ABCDEFGH2345'];

  Future<bool> ensureTeacherAuthorization() async {
    authorizationCalls++;
    final error = authorizationError;
    if (error != null) throw error;
    return authorizationOk;
  }

  setUp(() {
    inviteCodeIndex = 0;
    authorizationOk = true;
    authorizationError = null;
    authorizationCalls = 0;
    memory = InMemoryGroupRepository(
      generateNormalizedCode: () => inviteCodes[inviteCodeIndex++],
      now: () => DateTime.utc(2026, 8, 19),
    );
    repository = _SpyGroupRepository(memory);
    controller = TeacherGroupsController(
      repository: repository,
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      ensureTeacherAuthorization: ensureTeacherAuthorization,
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

    await controller.createGroup('BSHM 4A');
    expect(controller.groups, hasLength(1));
    expect(controller.selectedGroup?.name, 'BSHM 4A');
    expect(controller.activeInvite?.displayCode, '7KPM-XR4D-Q2WT');
    expect(repository.privilegedCalls, contains('createGroup'));
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
    await controller.createGroup('BSHM 4A');
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
    await controller.createGroup('BSHM 4A');
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
    await controller.createGroup('BSHM 4A');
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
}
