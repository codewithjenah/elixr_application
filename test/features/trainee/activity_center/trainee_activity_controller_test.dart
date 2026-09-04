import 'dart:async';

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/activity_center/activity_read_store.dart';
import 'package:elixr_application/features/trainee/activity_center/trainee_activity_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 9, 2, 12);

void main() {
  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;
  late InMemoryClassroomAnnouncementRepository announcements;
  late InMemoryActivityReadStore readStore;

  setUp(() {
    groups = InMemoryGroupRepository(now: () => now);
    assignments = InMemoryClassroomAssignmentRepository(
      now: () => now,
      groupRepository: groups,
    );
    announcements = InMemoryClassroomAnnouncementRepository(now: () => now);
    readStore = InMemoryActivityReadStore();
    groups.seedGroup(_group());
    groups.seedMembership(_membership());
  });

  tearDown(() {
    groups.dispose();
    assignments.dispose();
    announcements.dispose();
  });

  TraineeActivityController createController({
    ClassroomAnnouncementRepository? announcementRepository,
  }) => TraineeActivityController(
    groupRepository: groups,
    assignmentRepository: assignments,
    announcementRepository: announcementRepository ?? announcements,
    readStore: readStore,
    now: () => now,
    periodicTimer: (_, _) => _NoopTimer(),
  );

  test('aggregates useful trainee events with stable unique IDs', () async {
    final dueSoon = _assignment(
      id: 'due-soon',
      title: 'Bottle in a Tin',
      dueAt: now.add(const Duration(hours: 24)),
    );
    final overdue = _assignment(
      id: 'overdue',
      title: 'Reverse Grip',
      dueAt: now.subtract(const Duration(hours: 2)),
    );
    final checked = _assignment(id: 'checked', title: 'Hand Stall');
    final returned = _assignment(id: 'returned', title: 'Flat Behind');
    assignments
      ..seedAssignment(dueSoon)
      ..seedAssignment(overdue)
      ..seedAssignment(checked)
      ..seedAssignment(returned)
      ..seedAssignment(
        _assignment(
          id: 'not-for-trainee',
          title: 'Private work',
          audience: AssignmentAudience.individualStudent(const ['someone']),
        ),
      )
      ..seedAttempt(
        _attempt(
          id: 'checked-work',
          assignment: checked,
          status: AssignmentAttemptStatus.checked,
          checkedAt: now.subtract(const Duration(minutes: 5)),
          reviewRevision: 2,
        ),
      )
      ..seedAttempt(
        _attempt(
          id: 'returned-work',
          assignment: returned,
          status: AssignmentAttemptStatus.needsRetry,
          reviewedAt: now.subtract(const Duration(minutes: 4)),
          reviewRevision: 1,
        ),
      );
    final announcement = await announcements.createAnnouncement(
      groupId: 'group',
      teacherId: 'teacher',
      title: 'Practice room update',
      body: 'Use the second station today.',
    );
    await announcements.setPinnedAnnouncement(
      groupId: 'group',
      teacherId: 'teacher',
      announcementId: announcement.id,
    );

    final controller = createController()..setTrainee('trainee');
    addTearDown(controller.dispose);
    await _settle();

    expect(controller.loading, isFalse);
    expect(
      controller.activities.map((activity) => activity.type),
      containsAll(<TraineeActivityType>[
        TraineeActivityType.joinApproved,
        TraineeActivityType.newAssignment,
        TraineeActivityType.dueSoon,
        TraineeActivityType.overdue,
        TraineeActivityType.newAnnouncement,
        TraineeActivityType.pinnedAnnouncement,
        TraineeActivityType.submissionChecked,
        TraineeActivityType.workReturned,
      ]),
    );
    expect(
      controller.activities.any(
        (activity) => activity.title.contains('Private work'),
      ),
      isFalse,
    );
    expect(
      controller.activities.map((activity) => activity.id).toSet().length,
      controller.activities.length,
    );
    expect(
      controller.activities
          .singleWhere(
            (activity) => activity.type == TraineeActivityType.dueSoon,
          )
          .destination,
      AppRoutePaths.assignmentDetail('due-soon'),
    );
    expect(
      controller.activities
          .singleWhere(
            (activity) =>
                activity.type == TraineeActivityType.submissionChecked,
          )
          .id,
      'submission_checked:checked-work:2',
    );
    expect(
      controller.activities
          .singleWhere(
            (activity) => activity.type == TraineeActivityType.joinApproved,
          )
          .id,
      'join_approved:group_trainee',
    );
  });

  test(
    'deadline IDs stay stable across refresh and preserve read state',
    () async {
      assignments.seedAssignment(
        _assignment(
          id: 'due-soon',
          title: 'Bottle in a Tin',
          dueAt: now.add(const Duration(hours: 24)),
        ),
      );
      final controller = createController()..setTrainee('trainee');
      addTearDown(controller.dispose);
      await _settle();
      final reminder = controller.activities.singleWhere(
        (activity) => activity.type == TraineeActivityType.dueSoon,
      );
      await controller.markRead(reminder);
      final beforeIds = controller.activities.map((item) => item.id).toList();

      await controller.retry();
      await _settle();

      expect(controller.activities.map((item) => item.id), beforeIds);
      expect(
        controller.activities
            .singleWhere((item) => item.id == reminder.id)
            .isRead,
        isTrue,
      );
      expect(await readStore.load('trainee:trainee'), contains(reminder.id));
      expect(await readStore.load('trainee'), isEmpty);
    },
  );

  test('announcement IDs remain distinct across classrooms', () async {
    groups
      ..seedGroup(_group(id: 'second', name: 'BSHM 4B'))
      ..seedMembership(_membership(groupId: 'second'));
    final repository = _GroupScopedAnnouncementRepository({
      'group': [
        ClassroomAnnouncement(
          id: 'shared-id',
          groupId: 'group',
          teacherId: 'teacher',
          title: 'First class update',
          body: 'Practice today.',
          createdAt: now.subtract(const Duration(minutes: 10)),
        ),
      ],
      'second': [
        ClassroomAnnouncement(
          id: 'shared-id',
          groupId: 'second',
          teacherId: 'teacher',
          title: 'Second class update',
          body: 'Practice tomorrow.',
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
      ],
    });
    final controller = createController(announcementRepository: repository)
      ..setTrainee('trainee');
    addTearDown(controller.dispose);
    await _settle();

    final updates = controller.activities
        .where(
          (activity) => activity.type == TraineeActivityType.newAnnouncement,
        )
        .toList();
    expect(updates, hasLength(2));
    expect(updates.map((activity) => activity.id).toSet(), hasLength(2));

    await controller.markRead(updates.first);
    expect(
      controller.activities
          .where(
            (activity) =>
                activity.type == TraineeActivityType.newAnnouncement &&
                activity.isRead,
          )
          .length,
      1,
    );
  });

  test('loads recent announcements beyond the first repository page', () async {
    for (var index = 0; index < 35; index++) {
      announcements.seedAnnouncement(
        ClassroomAnnouncement(
          id: 'announcement-$index',
          groupId: 'group',
          teacherId: 'teacher',
          title: 'Update $index',
          body: 'Practice update.',
          createdAt: now.subtract(Duration(minutes: index)),
        ),
      );
    }
    final controller = createController()..setTrainee('trainee');
    addTearDown(controller.dispose);
    await _settle();

    expect(
      controller.activities.where(
        (activity) => activity.type == TraineeActivityType.newAnnouncement,
      ),
      hasLength(35),
    );
  });

  test(
    'checked events require the work and assignment classroom to match',
    () async {
      groups
        ..seedGroup(_group(id: 'other', name: 'BSHM 4B'))
        ..seedMembership(_membership(groupId: 'other'));
      final assignment = _assignment(id: 'checked', title: 'Hand Stall');
      assignments
        ..seedAssignment(assignment)
        ..seedAttempt(
          _attempt(
            id: 'mismatched-work',
            assignment: assignment,
            status: AssignmentAttemptStatus.checked,
            groupId: 'other',
            checkedAt: now.subtract(const Duration(minutes: 5)),
            reviewRevision: 1,
          ),
        );
      final controller = createController()..setTrainee('trainee');
      addTearDown(controller.dispose);
      await _settle();

      expect(
        controller.activities.where(
          (activity) => activity.type == TraineeActivityType.submissionChecked,
        ),
        isEmpty,
      );
    },
  );

  test('archived classrooms and their activity are excluded', () async {
    groups.seedGroup(
      _group(
        id: 'archived',
        status: ElixrGroupStatus.archived,
        name: 'Old class',
      ),
    );
    groups.seedMembership(_membership(groupId: 'archived'));
    assignments.seedAssignment(
      _assignment(
        id: 'archived-work',
        title: 'Old assignment',
        groupId: 'archived',
        groupName: 'Old class',
      ),
    );
    await announcements.createAnnouncement(
      groupId: 'archived',
      teacherId: 'teacher',
      title: 'Old announcement',
      body: 'Archived update',
    );

    final controller = createController()..setTrainee('trainee');
    addTearDown(controller.dispose);
    await _settle();

    expect(
      controller.activities.any(
        (activity) =>
            activity.title.contains('Old') ||
            activity.description.contains('Old class'),
      ),
      isFalse,
    );
  });

  test(
    'attempt stream failure withholds classroom work rather than guessing',
    () async {
      final submitted = _assignment(
        id: 'submitted-work',
        title: 'Submitted work',
        dueAt: now.subtract(const Duration(days: 1)),
      );
      assignments
        ..seedAssignment(submitted)
        ..seedAttempt(
          _attempt(
            id: 'submitted-attempt',
            assignment: submitted,
            status: AssignmentAttemptStatus.submitted,
          ),
        );
      final controller = createController()..setTrainee('trainee');
      addTearDown(controller.dispose);
      await _settle();
      expect(controller.classroomWork.single.latestSubmission, isNotNull);

      controller.attemptsStreamError = StateError('attempt stream failed');

      expect(
        controller.classroomDataStatus,
        TraineeClassroomDataStatus.attemptsFailed,
      );
      expect(controller.classroomWork, isEmpty);
    },
  );

  test(
    'authorized archived submitted work remains in classroom history',
    () async {
      final archived = _assignment(
        id: 'archived-submission',
        title: 'Archived submission',
        dueAt: now.subtract(const Duration(days: 1)),
      ).copyWith(status: GroupAssignmentStatus.archived);
      assignments
        ..seedAssignment(archived)
        ..seedAttempt(
          _attempt(
            id: 'archived-attempt',
            assignment: archived,
            status: AssignmentAttemptStatus.checked,
          ),
        );
      final controller = createController()..setTrainee('trainee');
      addTearDown(controller.dispose);
      await _settle();

      expect(
        controller.classroomWork.map((item) => item.assignment.id),
        contains('archived-submission'),
      );
    },
  );

  test(
    'mark all read reports persistence success and clears badge count',
    () async {
      assignments.seedAssignment(_assignment(id: 'new', title: 'New work'));
      final controller = createController()..setTrainee('trainee');
      addTearDown(controller.dispose);
      await _settle();
      expect(controller.unreadCount, greaterThan(0));

      expect(await controller.markAllRead(), isTrue);
      expect(controller.unreadCount, 0);

      readStore.nextSaveError = StateError('disk full');
      assignments.seedAssignment(_assignment(id: 'newer', title: 'Newer work'));
      await controller.retry();
      await _settle();
      expect(await controller.markAllRead(), isFalse);
      expect(controller.persistenceMessage, isNotNull);
    },
  );
}

ElixrGroup _group({
  String id = 'group',
  String name = 'BSHM 4A',
  ElixrGroupStatus status = ElixrGroupStatus.active,
}) => ElixrGroup(
  id: id,
  teacherId: 'teacher',
  name: name,
  status: status,
  createdAt: now.subtract(const Duration(days: 5)),
  updatedAt: now.subtract(const Duration(days: 5)),
);

GroupMembership _membership({String groupId = 'group'}) => GroupMembership(
  id: GroupMembership.documentId(groupId: groupId, traineeId: 'trainee'),
  groupId: groupId,
  teacherId: 'teacher',
  traineeId: 'trainee',
  traineeDisplayName: 'Ada Lovelace',
  teacherDisplayName: 'Grace Hopper',
  status: GroupMembershipStatus.approved,
  createdAt: now.subtract(const Duration(hours: 2)),
  updatedAt: now.subtract(const Duration(hours: 1)),
);

GroupAssignment _assignment({
  required String id,
  required String title,
  String groupId = 'group',
  String groupName = 'BSHM 4A',
  DateTime? dueAt,
  AssignmentAudience audience = const AssignmentAudience.entireClass(),
}) => GroupAssignment(
  id: id,
  teacherId: 'teacher',
  groupId: groupId,
  movementId: 'movement-$id',
  revisionId: 'revision-$id',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.teacherReviewed,
  status: GroupAssignmentStatus.active,
  displayTitle: title,
  teacherDisplayName: 'Grace Hopper',
  groupName: groupName,
  dueAt: dueAt,
  createdAt: now.subtract(const Duration(minutes: 20)),
  updatedAt: now.subtract(const Duration(minutes: 20)),
  audience: audience,
);

AssignmentAttempt _attempt({
  required String id,
  required GroupAssignment assignment,
  required AssignmentAttemptStatus status,
  String? groupId,
  DateTime? checkedAt,
  DateTime? reviewedAt,
  int? reviewRevision,
}) => AssignmentAttempt(
  id: id,
  traineeId: 'trainee',
  teacherId: 'teacher',
  groupId: groupId ?? assignment.groupId,
  assignmentId: assignment.id,
  movementId: assignment.movementId,
  revisionId: assignment.revisionId,
  origin: assignment.origin,
  assessmentMode: assignment.assessmentMode,
  attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
  status: status,
  submittedAt: now.subtract(const Duration(hours: 3)),
  checkedAt: checkedAt,
  reviewedAt: reviewedAt,
  reviewRevision: reviewRevision,
  reviewVerdict: status == AssignmentAttemptStatus.needsRetry
      ? AssignmentReviewVerdict.needsRetry
      : null,
  gradeScore: status == AssignmentAttemptStatus.checked ? 89 : null,
  gradeMaxScore: status == AssignmentAttemptStatus.checked ? 100 : null,
  createdAt: now.subtract(const Duration(hours: 4)),
);

Future<void> _settle() async {
  for (var index = 0; index < 12; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _NoopTimer implements Timer {
  @override
  bool get isActive => true;

  @override
  int get tick => 0;

  @override
  void cancel() {}
}

class _GroupScopedAnnouncementRepository
    implements ClassroomAnnouncementRepository {
  _GroupScopedAnnouncementRepository(this.itemsByGroup);

  final Map<String, List<ClassroomAnnouncement>> itemsByGroup;

  @override
  Stream<ClassroomAnnouncementPage> watchAnnouncements({
    required String groupId,
    int pageSize = ClassroomAnnouncementRepository.defaultPageSize,
  }) => Stream.value(
    ClassroomAnnouncementPage(
      items: itemsByGroup[groupId] ?? const [],
      hasMore: false,
    ),
  );

  @override
  Future<ClassroomAnnouncementPage> fetchOlderAnnouncements({
    required String groupId,
    required ClassroomAnnouncementCursor startAfter,
    int pageSize = ClassroomAnnouncementRepository.defaultPageSize,
  }) async => const ClassroomAnnouncementPage(items: [], hasMore: false);

  @override
  Future<ClassroomAnnouncement> createAnnouncement({
    required String groupId,
    required String teacherId,
    required String title,
    required String body,
  }) => throw UnimplementedError();

  @override
  Future<void> updateAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
    required String title,
    required String body,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
  }) => throw UnimplementedError();

  @override
  Future<void> setPinnedAnnouncement({
    required String groupId,
    required String teacherId,
    String? announcementId,
  }) => throw UnimplementedError();
}
