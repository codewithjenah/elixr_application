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
}
