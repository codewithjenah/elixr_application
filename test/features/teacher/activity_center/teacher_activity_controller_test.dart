import 'dart:async';
import 'dart:io';

import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/activity_center/activity_read_store.dart';
import 'package:elixr_application/features/teacher/activity_center/teacher_activity_center_screen.dart';
import 'package:elixr_application/features/teacher/activity_center/teacher_activity_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const teacherId = 'teacher';
final now = DateTime.utc(2026, 8, 29, 12);

void main() {
  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;
  late InMemoryChatRepository chat;
  late InMemoryActivityReadStore readStore;

  setUp(() {
    groups = InMemoryGroupRepository();
    assignments = InMemoryClassroomAssignmentRepository();
    chat = InMemoryChatRepository();
    readStore = InMemoryActivityReadStore();
  });

  tearDown(() async {
    groups.dispose();
    assignments.dispose();
    await chat.dispose();
  });

  TeacherActivityController createController({
    GroupRepository? groupRepository,
    ActivityReadStore? store,
  }) => TeacherActivityController(
    groupRepository: groupRepository ?? groups,
    assignmentRepository: assignments,
    chatRepository: chat,
    readStore: store ?? readStore,
    now: () => now,
    periodicTimer: (_, _) => _NoopTimer(),
  );

  test(
    'aggregates all six activity types in deterministic newest-first order',
    () async {
      final assignment = _assignment(dueAt: now.add(const Duration(hours: 24)));
      assignments.seedAssignment(assignment);
      groups.seedMembership(_membership(status: GroupMembershipStatus.pending));
      groups.seedMembership(
        _membership(
          traineeId: 'student-2',
          name: 'Katherine Johnson',
          status: GroupMembershipStatus.approved,
        ),
      );
      assignments.seedAttempt(
        _attempt(
          id: 'new-submission',
          kind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.submitted,
          submittedAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
      assignments.seedAttempt(
        _attempt(
          id: 'retry-submission',
          kind: AssignmentAttemptKind.teacherReviewSubmission,
          status: AssignmentAttemptStatus.submitted,
          submittedAt: now.subtract(const Duration(minutes: 2)),
          supersedesAttemptId: 'previous-attempt',
        ),
      );
      assignments.seedAttempt(
        _attempt(
          id: 'completed',
          kind: AssignmentAttemptKind.practicePointer,
          status: AssignmentAttemptStatus.submitted,
          completedAt: now.subtract(const Duration(minutes: 3)),
        ),
      );
      chat.conversations['conversation'] = ChatConversation(
        id: 'conversation',
        participants: const {
          teacherId: ChatUser(
            id: teacherId,
            displayName: 'Grace',
            role: 'Teacher',
          ),
          'student': ChatUser(
            id: 'student',
            displayName: 'Ada',
            role: 'Trainee',
          ),
        },
        updatedAt: now.subtract(const Duration(minutes: 4)),
        lastMessageId: 'message-1',
        lastMessageBody: 'Can you check this?',
        lastMessageSenderId: 'student',
        lastMessageAt: now.subtract(const Duration(minutes: 4)),
        unreadCounts: const {teacherId: 1},
        readAt: const {},
        status: 'active',
      );

      final controller = createController()..setTeacher(teacherId);
      addTearDown(controller.dispose);
      await _settle();

      expect(controller.loading, isFalse);
      expect(
        controller.activities.map((activity) => activity.type),
        containsAllInOrder([
          TeacherActivityType.joinRequest,
          TeacherActivityType.newSubmission,
          TeacherActivityType.retryResubmission,
          TeacherActivityType.movementCompleted,
          TeacherActivityType.message,
          TeacherActivityType.upcomingDeadline,
        ]),
      );
      expect(controller.activities, hasLength(6));
      expect(
        controller.activities
            .singleWhere(
              (activity) =>
                  activity.type == TeacherActivityType.upcomingDeadline,
            )
            .occurredAt,
        now.subtract(const Duration(hours: 24)),
      );
      expect(
        controller.activities.map((activity) => activity.id),
        containsAll([
          'join_request:group_student',
          'new_submission:new-submission',
          'retry_resubmission:retry-submission',
          'movement_completed:completed',
          'message:conversation:message-1',
          'upcoming_deadline:assignment:${now.add(const Duration(hours: 24)).millisecondsSinceEpoch}',
        ]),
      );
      expect(
        controller.activities
            .singleWhere(
              (activity) => activity.type == TeacherActivityType.newSubmission,
            )
            .destination,
        AppRoutePaths.teacherGroupClasswork(
          'group',
          'assignment',
          traineeId: 'student',
        ),
      );
      expect(
        controller.activities
            .singleWhere(
              (activity) =>
                  activity.type == TeacherActivityType.upcomingDeadline,
            )
            .destination,
        AppRoutePaths.teacherGroupClasswork('group', 'assignment'),
      );
    },
  );

  test(
    'marks activity read locally and restores it for the same teacher',
    () async {
      groups.seedMembership(_membership(status: GroupMembershipStatus.pending));
      final first = createController()..setTeacher(teacherId);
      await _settle();

      await first.markRead(first.activities.single);
      expect(first.unreadCount, 0);
      first.dispose();

      final restored = createController()..setTeacher(teacherId);
      addTearDown(restored.dispose);
      await _settle();
      expect(restored.activities.single.isRead, isTrue);
    },
  );

  test('file read store round-trips account-scoped timestamps', () async {
    final directory = await Directory.systemTemp.createTemp(
      'elixr_activity_read_store_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileActivityReadStore(
      file: File('${directory.path}${Platform.pathSeparator}state.json'),
    );
    final timestamp = now.subtract(const Duration(minutes: 5));

    await store.save(teacherId, {'join_request:1': timestamp});

    expect(await store.load(teacherId), {'join_request:1': timestamp});
    expect(await store.load('another-teacher'), isEmpty);
  });

  test(
    'keeps read state scoped to the teacher and clears old activity on user switch',
    () async {
      groups.seedMembership(_membership(status: GroupMembershipStatus.pending));
      final controller = createController()..setTeacher(teacherId);
      addTearDown(controller.dispose);
      await _settle();
      await controller.markAllRead();

      controller.setTeacher('another-teacher');
      await _settle();
      expect(controller.activities, isEmpty);
      expect(controller.unreadCount, 0);
    },
  );

  test(
    'surfaces stream and local persistence failures without blocking activity state',
    () async {
      groups.seedMembership(_membership(status: GroupMembershipStatus.pending));
      readStore.nextSaveError = StateError('disk unavailable');
      final controller = createController()..setTeacher(teacherId);
      await _settle();

      await controller.markAllRead();
      expect(controller.activities.single.isRead, isTrue);
      expect(
        controller.persistenceMessage,
        'Activity read state could not be saved.',
      );
      controller.dispose();

      final errorController = createController(
        groupRepository: _ErrorGroupRepository(),
      )..setTeacher(teacherId);
      addTearDown(errorController.dispose);
      await _settle();
      expect(errorController.loading, isFalse);
      expect(errorController.hasStreamError, isTrue);
    },
  );

  test('remains loading until local read state has been restored', () async {
    final store = _DelayedActivityReadStore();
    final controller = createController(store: store)..setTeacher(teacherId);
    addTearDown(controller.dispose);
    await _settle();
    expect(controller.loading, isTrue);

    store.complete(<String, DateTime>{});
    await _settle();
    expect(controller.loading, isFalse);
    expect(controller.activities, isEmpty);
  });

  test(
    'disposal releases startup waits when a stream has not emitted',
    () async {
      final delayedGroups = _DelayedGroupRepository();
      addTearDown(() async {
        await delayedGroups.close();
        delayedGroups.dispose();
      });
      final controller = createController(groupRepository: delayedGroups)
        ..setTeacher(teacherId);
      await _settle();

      final restart = controller.retry();
      controller.dispose();
      await restart;
    },
  );

  test('stops reacting to repository updates after disposal', () async {
    final controller = createController()..setTeacher(teacherId);
    await _settle();
    var notificationsAfterDispose = 0;
    controller.addListener(() => notificationsAfterDispose++);
    controller.dispose();

    groups.seedMembership(_membership(status: GroupMembershipStatus.pending));
    await _settle();
    expect(notificationsAfterDispose, 0);
  });

  testWidgets(
    'unread-only filter renders the empty state after all activity is read',
    (tester) async {
      groups.seedMembership(_membership(status: GroupMembershipStatus.pending));
      final controller = createController()..setTeacher(teacherId);
      addTearDown(controller.dispose);
      await tester.pump();
      await tester.pump();
      await controller.markAllRead();

      await tester.pumpWidget(
        ChangeNotifierProvider<TeacherActivityController>.value(
          value: controller,
          child: FluentApp(
            theme: FluentThemeData(),
            home: const TeacherActivityCenterScreen(),
          ),
        ),
      );
      await tester.tap(find.byType(Checkbox));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('You are all caught up'), findsOneWidget);
    },
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GroupMembership _membership({
  String traineeId = 'student',
  String name = 'Ada Lovelace',
  required GroupMembershipStatus status,
}) => GroupMembership(
  id: 'group_$traineeId',
  groupId: 'group',
  teacherId: teacherId,
  traineeId: traineeId,
  traineeDisplayName: name,
  teacherDisplayName: 'Grace Hopper',
  status: status,
  createdAt: now.subtract(const Duration(seconds: 30)),
  updatedAt: now.subtract(const Duration(seconds: 30)),
);

GroupAssignment _assignment({DateTime? dueAt}) => GroupAssignment(
  id: 'assignment',
  teacherId: teacherId,
  groupId: 'group',
  movementId: 'movement',
  revisionId: 'revision',
  origin: MovementOrigin.officialElixr,
  assessmentMode: AssessmentMode.officialGuided,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Hand Stall',
  teacherDisplayName: 'Grace Hopper',
  groupName: 'BSHM 4A',
  officialMovementName: 'Hand Stall',
  dueAt: dueAt,
  createdAt: now,
  updatedAt: now,
);

AssignmentAttempt _attempt({
  required String id,
  required AssignmentAttemptKind kind,
  required AssignmentAttemptStatus status,
  DateTime? submittedAt,
  DateTime? completedAt,
  String? supersedesAttemptId,
}) => AssignmentAttempt(
  id: id,
  traineeId: 'student',
  teacherId: teacherId,
  groupId: 'group',
  assignmentId: 'assignment',
  movementId: 'movement',
  revisionId: 'revision',
  origin: kind == AssignmentAttemptKind.teacherReviewSubmission
      ? MovementOrigin.teacherCreated
      : MovementOrigin.officialElixr,
  assessmentMode: kind == AssignmentAttemptKind.teacherReviewSubmission
      ? AssessmentMode.teacherReviewed
      : AssessmentMode.officialGuided,
  attemptKind: kind,
  status: status,
  submittedAt: submittedAt,
  completedAt: completedAt,
  supersedesAttemptId: supersedesAttemptId,
);

class _ErrorGroupRepository extends InMemoryGroupRepository {
  @override
  Stream<List<GroupMembership>> watchTeacherMemberships({
    required String teacherId,
  }) => Stream<List<GroupMembership>>.error(StateError('stream failed'));
}

class _DelayedGroupRepository extends InMemoryGroupRepository {
  final _memberships = StreamController<List<GroupMembership>>();

  @override
  Stream<List<GroupMembership>> watchTeacherMemberships({
    required String teacherId,
  }) => _memberships.stream;

  Future<void> close() => _memberships.close();
}

class _NoopTimer implements Timer {
  @override
  bool get isActive => true;

  @override
  int get tick => 0;

  @override
  void cancel() {}
}

class _DelayedActivityReadStore implements ActivityReadStore {
  final Completer<Map<String, DateTime>> _load =
      Completer<Map<String, DateTime>>();

  @override
  Future<Map<String, DateTime>> load(String teacherId) => _load.future;

  void complete(Map<String, DateTime> value) => _load.complete(value);

  @override
  Future<void> save(String teacherId, Map<String, DateTime> readAtById) async {}
}
