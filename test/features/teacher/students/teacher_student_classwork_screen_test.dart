import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/widgets/elix_status_panel.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/students/teacher_student_classwork_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;
  late AuthService auth;

  setUp(() {
    groups = InMemoryGroupRepository();
    assignments = InMemoryClassroomAssignmentRepository();
    auth = phase3TeacherAuth();
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
  });

  tearDown(() {
    groups.dispose();
    assignments.dispose();
    auth.dispose();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherStudentClasswork(
        'trainee',
        groupId: 'group-1',
      ),
      routes: [
        GoRoute(
          path: '/teacher/students/:traineeId/classwork',
          builder: (context, state) => TeacherStudentClassworkScreen(
            traineeId: state.pathParameters['traineeId']!,
            groupId: state.uri.queryParameters['groupId']!,
            assignmentId: state.uri.queryParameters['assignmentId'],
          ),
        ),
        GoRoute(
          path: '/teacher/students/:traineeId/classwork/:assignmentId',
          builder: (context, state) =>
              Text('review:${state.pathParameters['assignmentId']}'),
        ),
        GoRoute(
          path: '/teacher/students/:traineeId',
          builder: (_, _) => const Text('student details'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: groups),
          Provider<ClassroomAssignmentRepository>.value(value: assignments),
        ],
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  GroupAssignment assignment(String id, String title, {DateTime? dueAt}) =>
      GroupAssignment(
        id: id,
        teacherId: 'teacher',
        groupId: 'group-1',
        movementId: 'movement-$id',
        revisionId: 'revision-$id',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        status: GroupAssignmentStatus.active,
        displayTitle: title,
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
        maxScore: 100,
        dueAt: dueAt,
      );

  AssignmentAttempt attempt(
    String id,
    String assignmentId,
    AssignmentAttemptStatus status,
  ) => AssignmentAttempt(
    id: id,
    traineeId: 'trainee',
    teacherId: 'teacher',
    groupId: 'group-1',
    assignmentId: assignmentId,
    movementId: 'movement-$assignmentId',
    revisionId: 'revision-$assignmentId',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: status,
    createdAt: DateTime.utc(2026, 8, 30),
  );

  testWidgets(
    'uses a bounded scrolling classwork viewport and derives filters from attempts',
    (tester) async {
      assignments.seedAssignment(assignment('review', 'Awaiting review'));
      assignments.seedAssignment(assignment('checked', 'Checked work'));
      assignments.seedAssignment(
        assignment('missing', 'Overdue work', dueAt: DateTime.utc(2020)),
      );
      assignments.seedAssignment(
        assignment('active', 'Active work', dueAt: DateTime.utc(2099)),
      );
      assignments.seedAttempt(
        attempt('review-attempt', 'review', AssignmentAttemptStatus.submitted),
      );
      assignments.seedAttempt(
        attempt('checked-attempt', 'checked', AssignmentAttemptStatus.checked),
      );

      await pumpScreen(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const Key('teacher_student_classwork_list')),
        findsOneWidget,
      );
      expect(find.text('Awaiting review'), findsWidgets);
      expect(find.text('Checked work'), findsOneWidget);
      await tester.drag(
        find.byKey(const Key('teacher_student_classwork_list')),
        const Offset(0, -180),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('To review'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Awaiting review'), findsWidgets);
      expect(find.text('Checked work'), findsNothing);
      await tester.tap(find.text('Checked'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Checked work'), findsOneWidget);
      await tester.tap(find.text('Missing'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.text('Overdue work'), findsOneWidget);
      expect(find.text('Active work'), findsNothing);
    },
  );

  testWidgets(
    'remains usable at a narrow desktop viewport and blocks an unauthorized trainee',
    (tester) async {
      groups = InMemoryGroupRepository();
      groups.seedGroup(activeGroup());
      await pumpScreen(tester, size: const Size(700, 720));
      expect(tester.takeException(), isNull);
      expect(find.byType(ElixStatusPanel), findsOneWidget);
      expect(
        find.byKey(const Key('teacher_student_classwork_list')),
        findsNothing,
      );
    },
  );

  testWidgets('opens an assignment in the dedicated review route', (
    tester,
  ) async {
    assignments.seedAssignment(assignment('review', 'Open this assignment'));
    await pumpScreen(tester);

    await tester.tap(find.text('Open this assignment').last);
    await tester.pumpAndSettle();

    expect(find.text('review:review'), findsOneWidget);
  });
}
