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
    expect(controller.loading, isFalse);
    expect(controller.errorMessage, isNull);
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
    final failing = _ControllableGroupRepository(repository)
      ..failMembershipsOnListen();
    controller = TeacherDashboardController(
      repository: failing,
      teacherId: 'teacher',
    );
    await controller.start();
    expect(controller.errorMessage, isNotNull);
  });

  test(
    'groups stream fails on initial listen shows blocking safe error',
    () async {
      final failing = _ControllableGroupRepository(repository)
        ..failGroupsOnListen();
      controller = TeacherDashboardController(
        repository: failing,
        teacherId: 'teacher',
      );
      await controller.start();
      expect(controller.loading, isFalse);
      expect(controller.errorMessage, 'Could not load dashboard data.');
      expect(controller.groupsStreamError, isNotNull);
      expect(controller.membershipsStreamError, isNull);
    },
  );

  test(
    'memberships stream fails on initial listen shows blocking safe error',
    () async {
      final failing = _ControllableGroupRepository(repository)
        ..failMembershipsOnListen();
      controller = TeacherDashboardController(
        repository: failing,
        teacherId: 'teacher',
      );
      await controller.start();
      expect(controller.loading, isFalse);
      expect(controller.errorMessage, 'Could not load dashboard data.');
      expect(controller.membershipsStreamError, isNotNull);
      expect(controller.groupsStreamError, isNull);
    },
  );

  test(
    'successful groups event does not erase an active memberships failure',
    () async {
      final controllable = _ControllableGroupRepository(repository)
        ..controlGroups = true
        ..controlMemberships = true;
      controller = TeacherDashboardController(
        repository: controllable,
        teacherId: 'teacher',
      );
      final started = controller.start();
      await _waitForListens(controllable, groups: 1, memberships: 1);
      controllable.latestMemberships.addError(Exception('memberships-down'));
      controllable.latestGroups.add([activeGroup()]);
      await started;

      expect(controller.errorMessage, 'Could not load dashboard data.');
      expect(controller.membershipsStreamError, isNotNull);
      expect(controller.activeGroupCount, 1);

      controllable.latestGroups.add([
        activeGroup(),
        activeGroup(id: 'group-2'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.errorMessage, 'Could not load dashboard data.');
      expect(controller.membershipsStreamError, isNotNull);
      expect(controller.groupsStreamError, isNull);
      expect(controller.activeGroupCount, 2);
    },
  );

  test(
    'successful memberships event does not erase an active groups failure',
    () async {
      final controllable = _ControllableGroupRepository(repository)
        ..controlGroups = true
        ..controlMemberships = true;
      controller = TeacherDashboardController(
        repository: controllable,
        teacherId: 'teacher',
      );
      final started = controller.start();
      await _waitForListens(controllable, groups: 1, memberships: 1);
      controllable.latestGroups.addError(Exception('groups-down'));
      controllable.latestMemberships.add([
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
      ]);
      await started;

      expect(controller.errorMessage, 'Could not load dashboard data.');
      expect(controller.groupsStreamError, isNotNull);
      expect(controller.approvedStudentCount, 1);

      controllable.latestMemberships.add([
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't2'),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(controller.errorMessage, 'Could not load dashboard data.');
      expect(controller.groupsStreamError, isNotNull);
      expect(controller.membershipsStreamError, isNull);
      expect(controller.approvedStudentCount, 2);
    },
  );

  test(
    'later stream error then recovery clears only that stream error',
    () async {
      final controllable = _ControllableGroupRepository(repository)
        ..controlGroups = true
        ..controlMemberships = true;
      controller = TeacherDashboardController(
        repository: controllable,
        teacherId: 'teacher',
      );
      final started = controller.start();
      await _waitForListens(controllable, groups: 1, memberships: 1);
      controllable.latestGroups.add([activeGroup()]);
      controllable.latestMemberships.add([
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
      ]);
      await started;

      expect(controller.errorMessage, isNull);
      expect(controller.activeGroupCount, 1);
      expect(controller.approvedStudentCount, 1);

      controllable.latestGroups.addError(Exception('groups-transient'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.groupsStreamError, isNotNull);
      expect(controller.membershipsStreamError, isNull);
      expect(controller.activeGroupCount, 1);

      controllable.latestMemberships.addError(
        Exception('memberships-transient'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.groupsStreamError, isNotNull);
      expect(controller.membershipsStreamError, isNotNull);

      controllable.latestGroups.add([
        activeGroup(),
        activeGroup(id: 'group-2'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.groupsStreamError, isNull);
      expect(controller.membershipsStreamError, isNotNull);
      expect(controller.errorMessage, 'Could not load dashboard data.');
      expect(controller.activeGroupCount, 2);

      controllable.latestMemberships.add([
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
        membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't2'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(controller.groupsStreamError, isNull);
      expect(controller.membershipsStreamError, isNull);
      expect(controller.errorMessage, isNull);
      expect(controller.approvedStudentCount, 2);
    },
  );

  test('retry replaces subscriptions and ignores stale events', () async {
    final controllable = _ControllableGroupRepository(repository)
      ..controlGroups = true
      ..controlMemberships = true;
    controller = TeacherDashboardController(
      repository: controllable,
      teacherId: 'teacher',
    );
    final started = controller.start();
    await _waitForListens(controllable, groups: 1, memberships: 1);
    final firstGroups = controllable.latestGroups;
    final firstMemberships = controllable.latestMemberships;
    firstGroups.add(const []);
    firstMemberships.add(const []);
    await started;

    final retried = controller.retry();
    await _waitForListens(controllable, groups: 2, memberships: 2);
    expect(controllable.groupsControllers, hasLength(2));
    expect(controllable.membershipsControllers, hasLength(2));
    controllable.latestGroups.add(const []);
    controllable.latestMemberships.add(const []);
    await retried;

    firstGroups.add([activeGroup(id: 'stale-group')]);
    firstMemberships.add([
      membership(
        groupId: 'stale-group',
        teacherId: 'teacher',
        traineeId: 'stale',
      ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.groups.where((group) => group.id == 'stale-group'),
      isEmpty,
    );
    expect(
      controller.memberships.where((m) => m.traineeId == 'stale'),
      isEmpty,
    );
    expect(controller.activeGroupCount, 0);

    controllable.latestGroups.add([activeGroup(id: 'fresh-group')]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.groups.single.id, 'fresh-group');
    expect(controller.activeGroupCount, 1);
  });
}

Future<void> _waitForListens(
  _ControllableGroupRepository repository, {
  required int groups,
  required int memberships,
}) async {
  for (var i = 0; i < 50; i++) {
    if (repository.groupsControllers.length >= groups &&
        repository.membershipsControllers.length >= memberships) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail(
    'Timed out waiting for listens (groups=${repository.groupsControllers.length}, '
    'memberships=${repository.membershipsControllers.length})',
  );
}

class _ControllableGroupRepository implements GroupRepository {
  _ControllableGroupRepository(this.inner);

  final InMemoryGroupRepository inner;
  bool _failGroupsOnListen = false;
  bool _failMembershipsOnListen = false;
  bool controlGroups = false;
  bool controlMemberships = false;

  final List<StreamController<List<ElixrGroup>>> groupsControllers = [];
  final List<StreamController<List<GroupMembership>>> membershipsControllers =
      [];

  void failGroupsOnListen() => _failGroupsOnListen = true;
  void failMembershipsOnListen() => _failMembershipsOnListen = true;

  StreamController<List<ElixrGroup>> get latestGroups => groupsControllers.last;
  StreamController<List<GroupMembership>> get latestMemberships =>
      membershipsControllers.last;

  @override
  Stream<List<GroupMembership>> watchTeacherMemberships({
    required String teacherId,
  }) {
    if (_failMembershipsOnListen) {
      return Stream<List<GroupMembership>>.error(Exception('boom'));
    }
    if (controlMemberships) {
      final controller = StreamController<List<GroupMembership>>();
      membershipsControllers.add(controller);
      return controller.stream;
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
  Stream<List<ElixrGroup>> watchTeacherGroups({required String teacherId}) {
    if (_failGroupsOnListen) {
      return Stream<List<ElixrGroup>>.error(Exception('groups-boom'));
    }
    if (controlGroups) {
      final controller = StreamController<List<ElixrGroup>>();
      groupsControllers.add(controller);
      return controller.stream;
    }
    return inner.watchTeacherGroups(teacherId: teacherId);
  }

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
  Stream<List<GroupMembership>> watchApprovedGroupMembers({
    required String groupId,
    required String teacherId,
  }) => inner.watchApprovedGroupMembers(groupId: groupId, teacherId: teacherId);

  @override
  Future<void> prepareClassroomAccessContext({
    required String teacherId,
    required String traineeId,
    required String groupId,
  }) => inner.prepareClassroomAccessContext(
    teacherId: teacherId,
    traineeId: traineeId,
    groupId: groupId,
  );

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
