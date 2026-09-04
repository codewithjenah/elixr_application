import 'dart:async';

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/teacher/calendar/teacher_calendar_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

GroupAssignment _assignment() => GroupAssignment(
  id: 'assignment-1',
  teacherId: 'teacher',
  groupId: 'group-1',
  movementId: 'movement-1',
  revisionId: 'revision-1',
  origin: MovementOrigin.officialElixr,
  assessmentMode: AssessmentMode.officialGuided,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Bottle balance',
  teacherDisplayName: 'Grace Hopper',
  groupName: 'Stored name',
  officialMovementName: 'Hand Stall',
  dueAt: DateTime.utc(2026, 9, 4, 14),
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
          assignmentsLoader: (_) => assignments,
          groupsLoader: (_) => groups,
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

    final event = find.byKey(
      const Key('teacher_calendar_event_assignment-1'),
    );
    await tester.scrollUntilVisible(event, 120);
    await tester.tap(event);
    await tester.pumpAndSettle();

    expect(find.text('Teacher classwork destination'), findsOneWidget);
  });
}
