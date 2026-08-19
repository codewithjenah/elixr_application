import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/features/teacher/students/teacher_student_detail_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../teacher_phase3_test_support.dart';

void main() {
  late InMemoryGroupRepository groups;
  late FakeTeacherLinksRepository links;
  late TrackingTeacherProgressRepository progress;
  late FakePublicProfileRepository profiles;
  late TeacherStudentDetailController controller;

  setUp(() {
    groups = InMemoryGroupRepository(now: () => DateTime.utc(2026, 8, 19));
    links = FakeTeacherLinksRepository();
    progress = TrackingTeacherProgressRepository();
    profiles = FakePublicProfileRepository();
    controller = TeacherStudentDetailController(
      groupRepository: groups,
      relationshipRepository: links,
      progressRepository: progress,
      publicProfileRepository: profiles,
      teacherId: 'teacher',
      traineeId: 'trainee',
    );
  });

  tearDown(() {
    controller.dispose();
    groups.dispose();
  });

  Future<void> boot() async {
    await controller.start();
    await pumpEventQueue();
  }

  void seedApprovedMembership() {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
  }

  test(
    'guessed uid with no membership is unauthorized and never loads progress',
    () async {
      await boot();
      expect(controller.state, TeacherStudentDetailState.unauthorized);
      expect(progress.summaryWatches, isEmpty);
      expect(progress.sessionFetches, isEmpty);
    },
  );

  test(
    'pending membership blocks progress and coaching privilege state',
    () async {
      groups.seedGroup(activeGroup());
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 'trainee',
          status: GroupMembershipStatus.pending,
        ),
      );
      await boot();
      expect(controller.state, TeacherStudentDetailState.pending);
      expect(progress.summaryWatches, isEmpty);
    },
  );

  test('removed-only membership shows inactive relationship', () async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
        status: GroupMembershipStatus.removed,
      ),
    );
    await boot();
    expect(controller.state, TeacherStudentDetailState.relationshipRemoved);
    expect(progress.summaryWatches, isEmpty);
  });

  test('approved membership without legacy link waits for access', () async {
    seedApprovedMembership();
    await boot();
    links.emit(const []);
    await pumpEventQueue();
    expect(controller.state, TeacherStudentDetailState.waitingForAccess);
    expect(progress.summaryWatches, isEmpty);
  });

  test('approved link without progress access waits for access', () async {
    seedApprovedMembership();
    await boot();
    links.emit([
      TeacherStudentLink(
        id: 'teacher_trainee',
        teacherId: 'teacher',
        traineeId: 'trainee',
        teacherDisplayName: 'Teacher',
        traineeDisplayName: 'Trainee',
        status: TeacherStudentLinkStatus.approved,
        createdAt: DateTime.utc(2026, 8, 19),
        updatedAt: DateTime.utc(2026, 8, 19),
      ),
    ]);
    await pumpEventQueue();
    expect(controller.state, TeacherStudentDetailState.waitingForAccess);
  });

  test('effective progress access loads summary and sessions', () async {
    seedApprovedMembership();
    progress.inner.setSummary('trainee', sampleSummary());
    progress.inner.sessions['trainee'] = [sampleSession()];
    await boot();
    links.emit([approvedProgressLink()]);
    await pumpEventQueue();
    expect(controller.state, TeacherStudentDetailState.ready);
    expect(progress.summaryWatches, ['trainee']);
    expect(progress.sessionFetches, ['trainee']);
  });

  test('valid access with no data is empty', () async {
    seedApprovedMembership();
    progress.inner.setSummary('trainee', null);
    await boot();
    links.emit([approvedProgressLink()]);
    await pumpEventQueue();
    expect(controller.state, TeacherStudentDetailState.empty);
  });

  test('progress access withdrawn clears protected data', () async {
    seedApprovedMembership();
    progress.inner.setSummary('trainee', sampleSummary());
    progress.inner.sessions['trainee'] = [sampleSession()];
    await boot();
    links.emit([approvedProgressLink()]);
    await pumpEventQueue();
    expect(controller.state, TeacherStudentDetailState.ready);

    links.emit([
      approvedProgressLink().copyWith(
        progressAccess: TeacherProgressAccess.none,
      ),
    ]);
    await pumpEventQueue();
    expect(controller.state, TeacherStudentDetailState.accessWithdrawn);
    expect(controller.summary, isNull);
    expect(controller.sessions, isEmpty);
  });

  test('classroom membership removed clears visible progress', () async {
    seedApprovedMembership();
    progress.inner.setSummary('trainee', sampleSummary());
    progress.inner.sessions['trainee'] = [sampleSession()];
    await boot();
    links.emit([approvedProgressLink()]);
    await pumpEventQueue();

    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
        status: GroupMembershipStatus.removed,
      ),
    );
    await pumpEventQueue();
    expect(controller.state, TeacherStudentDetailState.relationshipRemoved);
    expect(controller.summary, isNull);
  });

  test('private profile shows badge while progress still loads', () async {
    seedApprovedMembership();
    progress.inner.setSummary('trainee', sampleSummary());
    progress.inner.sessions['trainee'] = [sampleSession()];
    await boot();
    profiles.emitProfile(
      'trainee',
      const PublicProfile(
        userId: 'trainee',
        displayName: 'Private Trainee',
        visibility: ProfileVisibility.private,
      ),
    );
    links.emit([approvedProgressLink()]);
    await pumpEventQueue();
    expect(controller.isPrivateProfile, isTrue);
    expect(controller.state, TeacherStudentDetailState.ready);
  });

  test('pagination preserves loaded sessions on later failure', () async {
    seedApprovedMembership();
    progress.inner.setSummary('trainee', sampleSummary());
    progress.inner.sessions['trainee'] = [
      sampleSession(id: 'one'),
      sampleSession(id: 'two'),
    ];
    await boot();
    links.emit([approvedProgressLink()]);
    await pumpEventQueue();
    await controller.loadMore();
    await pumpEventQueue();
    expect(controller.sessions, isNotEmpty);
  });

  test('selected group id resolves to the Teacher group name', () async {
    seedApprovedMembership();
    await boot();
    expect(controller.selectedGroupId, 'group-1');
    expect(controller.groupNameForId('group-1'), 'BSHM 4A');
    expect(controller.selectedGroupName, 'BSHM 4A');
    expect(controller.classroomGroupCaption, 'Classroom group: BSHM 4A');
    expect(controller.hasClassroomAuthorization, isTrue);
  });

  test(
    'renaming a Teacher group updates selectedGroupName reactively',
    () async {
      seedApprovedMembership();
      await boot();
      expect(controller.selectedGroupName, 'BSHM 4A');

      await groups.renameGroup(
        groupId: 'group-1',
        teacherId: 'teacher',
        name: 'BSHM 4B',
      );
      await pumpEventQueue();

      expect(controller.selectedGroupId, 'group-1');
      expect(controller.selectedGroupName, 'BSHM 4B');
      expect(controller.classroomGroupCaption, 'Classroom group: BSHM 4B');
      expect(controller.hasClassroomAuthorization, isTrue);
    },
  );

  test(
    'missing group metadata does not expose the id or revoke classroom authorization',
    () async {
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 'trainee',
        ),
      );
      await boot();
      links.emit(const []);
      await pumpEventQueue();

      expect(controller.selectedGroupId, 'group-1');
      expect(controller.groupNameForId('group-1'), isNull);
      expect(controller.selectedGroupName, isNull);
      expect(controller.classroomGroupCaption, 'Group name unavailable');
      expect(
        controller.displayNameForGroupId('group-1'),
        'Group name unavailable',
      );
      expect(controller.hasClassroomAuthorization, isTrue);
      expect(controller.state, TeacherStudentDetailState.waitingForAccess);
    },
  );

  test(
    'group metadata stream failure keeps classroom authorization and selectedGroupId',
    () async {
      final failing = _FailingTeacherGroupsRepository(groups);
      controller.dispose();
      controller = TeacherStudentDetailController(
        groupRepository: failing,
        relationshipRepository: links,
        progressRepository: progress,
        publicProfileRepository: profiles,
        teacherId: 'teacher',
        traineeId: 'trainee',
      );
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 'trainee',
        ),
      );
      await controller.start();
      await pumpEventQueue();
      links.emit(const []);
      await pumpEventQueue();

      expect(controller.selectedGroupId, 'group-1');
      expect(controller.selectedGroupName, isNull);
      expect(controller.classroomGroupCaption, 'Group name unavailable');
      expect(controller.hasClassroomAuthorization, isTrue);
      expect(controller.state, TeacherStudentDetailState.waitingForAccess);
      expect(controller.state, isNot(TeacherStudentDetailState.unauthorized));
      expect(
        controller.state,
        isNot(TeacherStudentDetailState.connectionRequired),
      );
    },
  );
}

class _FailingTeacherGroupsRepository implements GroupRepository {
  _FailingTeacherGroupsRepository(this.inner);

  final InMemoryGroupRepository inner;

  @override
  Stream<List<ElixrGroup>> watchTeacherGroups({required String teacherId}) {
    return Stream.error(Exception('group metadata unavailable'));
  }

  @override
  Stream<List<GroupMembership>> watchTeacherMemberships({
    required String teacherId,
  }) => inner.watchTeacherMemberships(teacherId: teacherId);

  @override
  Future<ElixrGroup> createGroup({
    required String teacherId,
    required String teacherDisplayName,
    required String name,
  }) => throw UnimplementedError();

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
  }) => throw UnimplementedError();

  @override
  Future<GroupInvite?> getActiveGroupInvite({required String groupId}) =>
      throw UnimplementedError();

  @override
  Future<GroupInvite> resolveGroupInviteCode(String code) =>
      throw UnimplementedError();

  @override
  Stream<List<GroupMembership>> watchGroupMemberships({
    required String groupId,
    required String teacherId,
    GroupMembershipStatus? status,
  }) => throw UnimplementedError();

  @override
  Stream<List<GroupMembership>> watchTraineeMemberships({
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<GroupMembership> requestGroupJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  }) => throw UnimplementedError();

  @override
  Future<void> approveMembership({
    required String membershipId,
    required String teacherId,
  }) => throw UnimplementedError();

  @override
  Future<void> rejectMembership({
    required String membershipId,
    required String teacherId,
  }) => throw UnimplementedError();

  @override
  Future<void> removeMembership({
    required String membershipId,
    required String teacherId,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelMembership({
    required String membershipId,
    required String traineeId,
  }) => throw UnimplementedError();
}
