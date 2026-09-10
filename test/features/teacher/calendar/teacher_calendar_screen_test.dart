import 'dart:async';

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/calendar/teacher_calendar_models.dart';
import 'package:elixr_application/features/teacher/calendar/teacher_calendar_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

GroupAssignment _assignment({
  String id = 'assignment-1',
  String groupId = 'group-1',
  DateTime? dueAt,
  String title = 'Bottle balance',
}) => GroupAssignment(
  id: id,
  teacherId: 'teacher',
  groupId: groupId,
  movementId: 'movement-1',
  revisionId: 'revision-1',
  origin: MovementOrigin.officialElixr,
  assessmentMode: AssessmentMode.officialGuided,
  status: GroupAssignmentStatus.active,
  displayTitle: title,
  teacherDisplayName: 'Grace Hopper',
  groupName: 'Stored name',
  officialMovementName: 'Hand Stall',
  dueAt: dueAt ?? DateTime.utc(2026, 9, 4, 14),
);

ElixrGroup _group(String id, String name) => ElixrGroup(
  id: id,
  teacherId: 'teacher',
  name: name,
  status: ElixrGroupStatus.active,
);

Widget _app({
  required AuthService auth,
  required Stream<List<GroupAssignment>> assignments,
  required Stream<List<ElixrGroup>> groups,
}) {
  final router = GoRouter(
    initialLocation: AppRoutePaths.teacherCalendar,
    routes: [
      GoRoute(
        path: AppRoutePaths.teacherCalendar,
        builder: (_, _) => TeacherCalendarScreen(
          now: () => DateTime.utc(2026, 9, 4, 12),
          assignmentsLoader: ({required teacherId}) => assignments,
          groupsLoader: ({required teacherId}) => groups,
        ),
      ),
      GoRoute(
        path: '/teacher/groups/:groupId/classwork/:assignmentId',
        builder: (_, _) => const Text('Teacher classwork destination'),
      ),
    ],
  );
  return ChangeNotifierProvider<AuthService>.value(
    value: auth,
    child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
  );
}

class _TrackingAssignmentsRepository
    extends InMemoryClassroomAssignmentRepository {
  final watchedTeacherIds = <String>[];

  @override
  Stream<List<GroupAssignment>> watchTeacherAssignments({
    required String teacherId,
  }) {
    watchedTeacherIds.add(teacherId);
    return super.watchTeacherAssignments(teacherId: teacherId);
  }
}

class _TrackingGroupsRepository extends InMemoryGroupRepository {
  final watchedTeacherIds = <String>[];

  @override
  Stream<List<ElixrGroup>> watchTeacherGroups({required String teacherId}) {
    watchedTeacherIds.add(teacherId);
    return super.watchTeacherGroups(teacherId: teacherId);
  }
}

void main() {
  testWidgets('shows an empty state when the teacher has no deadlines', (
    tester,
  ) async {
    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      _app(auth: auth, assignments: Stream.value([]), groups: Stream.value([])),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('teacher_calendar_empty')), findsOneWidget);
    expect(
      find.text('Assignment deadlines from your classrooms will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('opens the existing Teacher classwork destination for an event', (
    tester,
  ) async {
    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      _app(
        auth: auth,
        assignments: Stream.value([_assignment()]),
        groups: Stream.value([
          const ElixrGroup(
            id: 'group-1',
            teacherId: 'teacher',
            name: 'BSHM 4A',
            status: ElixrGroupStatus.active,
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    final event = find.byKey(const Key('teacher_calendar_event_assignment-1'));
    await tester.scrollUntilVisible(event, 120);
    await tester.tap(event);
    await tester.pumpAndSettle();

    expect(find.text('Teacher classwork destination'), findsOneWidget);
  });

  testWidgets('uses named teacherId repository loaders by default', (
    tester,
  ) async {
    final auth = phase3TeacherAuth();
    final assignments = _TrackingAssignmentsRepository();
    final groups = _TrackingGroupsRepository();
    addTearDown(auth.dispose);
    addTearDown(assignments.dispose);
    addTearDown(groups.dispose);
    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherCalendar,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherCalendar,
          builder: (_, _) =>
              TeacherCalendarScreen(now: () => DateTime.utc(2026, 9, 4, 12)),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<ClassroomAssignmentRepository>.value(value: assignments),
          Provider<GroupRepository>.value(value: groups),
        ],
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(assignments.watchedTeacherIds, ['teacher']);
    expect(groups.watchedTeacherIds, ['teacher']);
  });

  testWidgets('shows summary counts and selected-day events for today', (
    tester,
  ) async {
    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      _app(
        auth: auth,
        assignments: Stream.value([
          _assignment(id: 'overdue', dueAt: DateTime.utc(2026, 9, 3)),
          _assignment(),
          _assignment(
            id: 'upcoming',
            dueAt: DateTime.utc(2026, 9, 4, 18),
            title: 'Later drill',
          ),
        ]),
        groups: Stream.value([_group('group-1', 'BSHM 4A')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('teacher_calendar_due_today')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('teacher_calendar_overdue')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(find.text('Bottle balance'), findsOneWidget);
    expect(find.text('Later drill'), findsNothing);
    expect(find.text('BSHM 4A'), findsWidgets);
    expect(find.text('Due today'), findsWidgets);
    expect(find.text('Open classwork'), findsOneWidget);
  });

  testWidgets('classroom filter updates selected-day events and overview', (
    tester,
  ) async {
    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      _app(
        auth: auth,
        assignments: Stream.value([
          _assignment(title: 'Class A drill'),
          _assignment(
            id: 'assignment-2',
            groupId: 'group-2',
            title: 'Class B drill',
          ),
        ]),
        groups: Stream.value([
          _group('group-1', 'BSHM 4A'),
          _group('group-2', 'BSHM 4B'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Class A drill'), findsOneWidget);
    expect(find.text('Class B drill'), findsOneWidget);

    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('teacher_calendar_classroom_filter')),
        )
        .onChanged!('group-2');
    await tester.pumpAndSettle();

    expect(find.text('Class A drill'), findsNothing);
    expect(find.text('Class B drill'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('teacher_calendar_classrooms')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('deadline filter hides non-matching selected-day work', (
    tester,
  ) async {
    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      _app(
        auth: auth,
        assignments: Stream.value([
          _assignment(),
          _assignment(
            id: 'upcoming',
            dueAt: DateTime.utc(2026, 9, 4, 18),
            title: 'Later drill',
          ),
        ]),
        groups: Stream.value([_group('group-1', 'BSHM 4A')]),
      ),
    );
    await tester.pumpAndSettle();

    tester
        .widget<ComboBox<TeacherDeadlineFilter>>(
          find.byKey(const Key('teacher_calendar_deadline_filter')),
        )
        .onChanged!(TeacherDeadlineFilter.upcoming);
    await tester.pumpAndSettle();

    expect(find.text('Bottle balance'), findsNothing);
    expect(find.text('No matching deadlines'), findsOneWidget);

    tester
        .widget<ComboBox<TeacherDeadlineFilter>>(
          find.byKey(const Key('teacher_calendar_deadline_filter')),
        )
        .onChanged!(TeacherDeadlineFilter.dueToday);
    await tester.pumpAndSettle();

    expect(find.text('Bottle balance'), findsOneWidget);
  });

  testWidgets('filter empty state can clear filters', (tester) async {
    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      _app(
        auth: auth,
        assignments: Stream.value([_assignment()]),
        groups: Stream.value([
          _group('group-1', 'BSHM 4A'),
          _group('group-2', 'BSHM 4B'),
        ]),
      ),
    );
    await tester.pumpAndSettle();

    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('teacher_calendar_classroom_filter')),
        )
        .onChanged!('group-2');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('teacher_calendar_filter_empty')),
      findsOneWidget,
    );
    await tester.tap(find.text('Clear filters').first);
    await tester.pumpAndSettle();
    expect(find.text('Bottle balance'), findsOneWidget);
  });

  testWidgets('keeps unauthorized classrooms off the calendar', (tester) async {
    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      _app(
        auth: auth,
        assignments: Stream.value([
          _assignment(),
          _assignment(id: 'hidden', groupId: 'hidden', title: 'Hidden drill'),
        ]),
        groups: Stream.value([_group('group-1', 'BSHM 4A')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bottle balance'), findsOneWidget);
    expect(find.text('Hidden drill'), findsNothing);
  });

  testWidgets('narrow desktop width stacks without overflow', (tester) async {
    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);
    await tester.binding.setSurfaceSize(const Size(720, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      _app(
        auth: auth,
        assignments: Stream.value([_assignment()]),
        groups: Stream.value([_group('group-1', 'BSHM 4A')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Bottle balance'), findsOneWidget);
    expect(find.text('Open classwork'), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_calendar_classroom_filter')),
      findsOneWidget,
    );
  });

  testWidgets('medium desktop width keeps filters and agenda usable', (
    tester,
  ) async {
    final auth = phase3TeacherAuth();
    addTearDown(auth.dispose);
    await tester.binding.setSurfaceSize(const Size(1024, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      _app(
        auth: auth,
        assignments: Stream.value([_assignment()]),
        groups: Stream.value([_group('group-1', 'BSHM 4A')]),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Due today'), findsWidgets);
    tester
        .widget<ComboBox<TeacherDeadlineFilter>>(
          find.byKey(const Key('teacher_calendar_deadline_filter')),
        )
        .onChanged!(TeacherDeadlineFilter.upcoming);
    await tester.pumpAndSettle();
    expect(find.text('No matching deadlines'), findsOneWidget);
  });
}
