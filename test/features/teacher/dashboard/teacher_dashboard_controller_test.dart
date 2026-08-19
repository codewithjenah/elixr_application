import 'dart:async';

import 'package:elixr_application/features/teacher/dashboard/teacher_dashboard_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../teacher_phase3_test_support.dart';

void main() {
  late InMemoryGroupRepository repository;
  late TeacherDashboardController controller;

  setUp(() {
    var groupCounter = 0;
    repository = InMemoryGroupRepository(
      now: () => DateTime.utc(2026, 8, 19),
      generateGroupId: () => 'group-${++groupCounter}',
    );
    controller = TeacherDashboardController(
      repository: repository,
      teacherId: 'teacher',
    );
  });

  tearDown(() {
    controller.dispose();
    repository.dispose();
  });

  test('no groups shows zero metrics', () async {
    await controller.start();
    expect(controller.activeGroupCount, 0);
    expect(controller.approvedStudentCount, 0);
    expect(controller.pendingRequestCount, 0);
    expect(controller.groupSummaries, isEmpty);
  });

  test('active group count excludes archived groups', () async {
    repository.seedGroup(activeGroup(id: 'group-1'));
    repository.seedGroup(
      activeGroup(id: 'group-2').copyWith(status: ElixrGroupStatus.archived),
    );
    await controller.start();
    expect(controller.activeGroupCount, 1);
  });

  test(
    'approved student count deduplicates trainee ids across groups',
    () async {
      repository.seedGroup(activeGroup(id: 'group-1'));
      repository.seedGroup(activeGroup(id: 'group-2'));
      repository.seedMembership(
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
      );
      repository.seedMembership(
        membership(groupId: 'group-2', teacherId: 'teacher', traineeId: 't1'),
      );
      repository.seedMembership(
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't2'),
      );
      await controller.start();
      expect(controller.approvedStudentCount, 2);
    },
  );

  test('pending request count remains per membership request', () async {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't1',
        status: GroupMembershipStatus.pending,
      ),
    );
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't2',
        status: GroupMembershipStatus.pending,
      ),
    );
    await controller.start();
    expect(controller.pendingRequestCount, 2);
  });

  test('group summaries calculate approved and pending counts', () async {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
    );
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't2',
        status: GroupMembershipStatus.pending,
      ),
    );
    await controller.start();
    expect(controller.groupSummaries.single.approvedCount, 1);
    expect(controller.groupSummaries.single.pendingCount, 1);
  });

  test('unrelated teacher memberships never appear', () async {
    repository.seedMembership(
      membership(groupId: 'group-1', teacherId: 'other', traineeId: 't1'),
    );
    await controller.start();
    expect(controller.memberships, isEmpty);
    expect(controller.approvedStudentCount, 0);
  });

  test('stream errors produce safe UI state', () async {
    final failing = _FailingMembershipStreamRepository(repository);
    controller = TeacherDashboardController(
      repository: failing,
      teacherId: 'teacher',
    );
    failing.failMembershipsOnListen();
    await controller.start();
    expect(controller.errorMessage, isNotNull);
  });
}

class _FailingMembershipStreamRepository implements GroupRepository {
  _FailingMembershipStreamRepository(this.inner);

  final InMemoryGroupRepository inner;
  bool _failOnListen = false;

  void failMembershipsOnListen() => _failOnListen = true;

  @override
  Stream<List<GroupMembership>> watchTeacherMemberships({
    required String teacherId,
  }) {
    if (_failOnListen) {
      return Stream<List<GroupMembership>>.error(Exception('boom'));
    }
    return inner.watchTeacherMemberships(teacherId: teacherId);
  }

  @override
  Future<ElixrGroup> createGroup({
    required String teacherId,
    required String teacherDisplayName,
    required String name,
  }) => inner.createGroup(
    teacherId: teacherId,
    teacherDisplayName: teacherDisplayName,
    name: name,
  );

  @override
  Stream<List<ElixrGroup>> watchTeacherGroups({required String teacherId}) =>
      inner.watchTeacherGroups(teacherId: teacherId);

  @override
  Future<ElixrGroup?> getGroup({required String groupId}) =>
      inner.getGroup(groupId: groupId);

  @override
  Future<void> renameGroup({
    required String groupId,
    required String teacherId,
    required String name,
  }) => inner.renameGroup(groupId: groupId, teacherId: teacherId, name: name);

  @override
  Future<void> archiveGroup({
    required String groupId,
    required String teacherId,
  }) => inner.archiveGroup(groupId: groupId, teacherId: teacherId);

  @override
  Future<GroupInvite> createOrRotateGroupInvite({
    required String groupId,
    required String teacherId,
    required String teacherDisplayName,
  }) => inner.createOrRotateGroupInvite(
    groupId: groupId,
    teacherId: teacherId,
    teacherDisplayName: teacherDisplayName,
  );

  @override
  Future<GroupInvite?> getActiveGroupInvite({required String groupId}) =>
      inner.getActiveGroupInvite(groupId: groupId);

  @override
  Future<GroupInvite> resolveGroupInviteCode(String code) =>
      inner.resolveGroupInviteCode(code);

  @override
  Stream<List<GroupMembership>> watchGroupMemberships({
    required String groupId,
    required String teacherId,
    GroupMembershipStatus? status,
  }) => inner.watchGroupMemberships(
    groupId: groupId,
    teacherId: teacherId,
    status: status,
  );

  @override
  Stream<List<GroupMembership>> watchTraineeMemberships({
    required String traineeId,
  }) => inner.watchTraineeMemberships(traineeId: traineeId);

  @override
  Future<GroupMembership> requestGroupJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  }) => inner.requestGroupJoin(
    traineeId: traineeId,
    traineeDisplayName: traineeDisplayName,
    code: code,
  );

  @override
  Future<void> approveMembership({
    required String membershipId,
    required String teacherId,
  }) =>
      inner.approveMembership(membershipId: membershipId, teacherId: teacherId);

  @override
  Future<void> rejectMembership({
    required String membershipId,
    required String teacherId,
  }) =>
      inner.rejectMembership(membershipId: membershipId, teacherId: teacherId);

  @override
  Future<void> removeMembership({
    required String membershipId,
    required String teacherId,
  }) =>
      inner.removeMembership(membershipId: membershipId, teacherId: teacherId);

  @override
  Future<void> cancelMembership({
    required String membershipId,
    required String traineeId,
  }) =>
      inner.cancelMembership(membershipId: membershipId, traineeId: traineeId);
}
