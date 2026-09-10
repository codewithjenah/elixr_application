import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_panel_card.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/grades/teacher_grades_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

class _FailingWatchGroupRepository extends InMemoryGroupRepository {
  @override
  Stream<List<ElixrGroup>> watchTeacherGroups({required String teacherId}) {
    return Stream<List<ElixrGroup>>.error(Exception('unavailable'));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;
  late AuthService auth;
  var assignmentSeq = 0;

  setUp(() {
    assignmentSeq = 0;
    groups = InMemoryGroupRepository(now: () => DateTime.utc(2026, 8, 26));
    assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 8, 26),
      generateId: () => 'asg-${assignmentSeq++}',
    );
    auth = phase3TeacherAuth();
  });

  tearDown(() {
    groups.dispose();
    assignments.dispose();
    auth.dispose();
  });

  Future<void> pumpGradesIdle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<GoRouter> pumpGrades(
    WidgetTester tester, {
    String location = AppRoutePaths.teacherGrades,
    GroupRepository? groupRepository,
    ClassroomAssignmentRepository? assignmentRepository,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherGrades,
          pageBuilder: (context, state) => NoTransitionPage<void>(
            key: const ValueKey(AppRoutePaths.teacherGrades),
            child: TeacherGradesScreen(
              initialGroupId: state
                  .uri
                  .queryParameters[AppRoutePaths.teacherGradesGroupQuery],
            ),
          ),
        ),
        GoRoute(
          path: AppRoutePaths.teacherGroups,
          builder: (context, state) => const Text('classrooms-home'),
        ),
        GoRoute(
          path: '/teacher/groups/:groupId/classwork/:assignmentId',
          builder: (context, state) => Text(
            'classwork:${state.pathParameters['groupId']}:'
            '${state.pathParameters['assignmentId']}:'
            '${state.uri.queryParameters['traineeId'] ?? ''}',
          ),
        ),
        GoRoute(
          path: '${AppRoutePaths.teacherStudents}/:traineeId',
          builder: (context, state) => Text(
            'student:${state.pathParameters['traineeId']}:'
            '${state.uri.queryParameters['groupId']}',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: groupRepository ?? groups),
          Provider<ClassroomAssignmentRepository>.value(
            value: assignmentRepository ?? assignments,
          ),
        ],
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await pumpGradesIdle(tester);
    return router;
  }

  Future<({ElixrGroup group, GroupAssignment assignment})> seedClassroom({
    required String id,
    required String name,
    required String traineeId,
    required String traineeName,
    required String movementName,
    DateTime? createdAt,
  }) async {
    final timestamp = createdAt ?? DateTime.utc(2026, 8, 26);
    groups.seedGroup(
      ElixrGroup(
        id: id,
        teacherId: 'teacher',
        name: name,
        status: ElixrGroupStatus.active,
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    );
    groups.seedMembership(
      membership(
        groupId: id,
        teacherId: 'teacher',
        traineeId: traineeId,
        traineeName: traineeName,
      ),
    );
    final assignment = await assignments.createOfficialAssignment(
      teacherId: 'teacher',
      teacherDisplayName: 'Grace Hopper',
      group: groups.groups[id]!,
      officialMovementName: movementName,
      allowedProp: TrainingProp.bottle,
    );
    return (group: groups.groups[id]!, assignment: assignment);
  }

  testWidgets('empty teacher grades destination explains missing classrooms', (
    tester,
  ) async {
    await pumpGrades(tester);

    expect(find.text('Grades'), findsWidgets);
    expect(
      find.byKey(const Key('teacher_grades_no_classrooms')),
      findsOneWidget,
    );
    expect(find.text('Open Classrooms'), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_grades_classroom_selector')),
      findsNothing,
    );
  });

  testWidgets('one classroom is selected and shows that gradebook', (
    tester,
  ) async {
    await seedClassroom(
      id: 'group-a',
      name: 'Class A',
      traineeId: 't-ada',
      traineeName: 'Ada Lovelace',
      movementName: 'Normal Grip',
    );
    await pumpGrades(
      tester,
      location: AppRoutePaths.teacherGradesForGroup('group-a'),
    );

    expect(
      find.byKey(const Key('teacher_grades_classroom_selector')),
      findsOneWidget,
    );
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Normal Grip'), findsOneWidget);
    expect(find.textContaining('1 students'), findsOneWidget);
  });

  testWidgets('requested classroom loads that gradebook among several', (
    tester,
  ) async {
    await seedClassroom(
      id: 'group-a',
      name: 'Class A',
      traineeId: 't-ada',
      traineeName: 'Ada Lovelace',
      movementName: 'Normal Grip',
      createdAt: DateTime.utc(2026, 8, 20),
    );
    await seedClassroom(
      id: 'group-b',
      name: 'Class B',
      traineeId: 't-alan',
      traineeName: 'Alan Turing',
      movementName: 'Hand Stall',
      createdAt: DateTime.utc(2026, 8, 21),
    );
    await pumpGrades(
      tester,
      location: AppRoutePaths.teacherGradesForGroup('group-b'),
    );

    expect(find.text('Alan Turing'), findsOneWidget);
    expect(find.text('Hand Stall'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);
    expect(find.text('Normal Grip'), findsNothing);
  });

  testWidgets('switching classrooms does not keep the previous grade matrix', (
    tester,
  ) async {
    await seedClassroom(
      id: 'group-a',
      name: 'Class A',
      traineeId: 't-ada',
      traineeName: 'Ada Lovelace',
      movementName: 'Normal Grip',
      createdAt: DateTime.utc(2026, 8, 20),
    );
    await seedClassroom(
      id: 'group-b',
      name: 'Class B',
      traineeId: 't-alan',
      traineeName: 'Alan Turing',
      movementName: 'Hand Stall',
      createdAt: DateTime.utc(2026, 8, 21),
    );
    await pumpGrades(
      tester,
      location: AppRoutePaths.teacherGradesForGroup('group-a'),
    );

    expect(
      tester
          .widget<ComboBox<String>>(
            find.byKey(const Key('teacher_grades_classroom_selector')),
          )
          .value,
      'group-a',
    );
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Normal Grip'), findsOneWidget);
    expect(find.text('Alan Turing'), findsNothing);
    expect(find.text('Hand Stall'), findsNothing);

    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('teacher_grades_classroom_selector')),
        )
        .onChanged!('group-b');
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await pumpGradesIdle(tester);

    expect(find.text('Alan Turing'), findsOneWidget);
    expect(find.text('Hand Stall'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);
    expect(find.text('Normal Grip'), findsNothing);
  });

  testWidgets('gradebook cells still open the existing classwork destination', (
    tester,
  ) async {
    final seeded = await seedClassroom(
      id: 'group-a',
      name: 'Class A',
      traineeId: 't-ada',
      traineeName: 'Ada Lovelace',
      movementName: 'Normal Grip',
    );
    await pumpGrades(
      tester,
      location: AppRoutePaths.teacherGradesForGroup(seeded.group.id),
    );

    final header = find.ancestor(
      of: find.text('Normal Grip'),
      matching: find.byType(ElixHoverSurface),
    );
    expect(header, findsOneWidget);
    await tester.tap(header);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('classwork:group-a:${seeded.assignment.id}:'),
      findsOneWidget,
    );
  });

  testWidgets(
    'selected classroom with no students shows the pane empty state',
    (tester) async {
      groups.seedGroup(activeGroup(id: 'empty', name: 'Empty Class'));
      await pumpGrades(
        tester,
        location: AppRoutePaths.teacherGradesForGroup('empty'),
      );

      expect(find.text('No students in this class yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'unauthorized classroom query does not show another class grades',
    (tester) async {
      await seedClassroom(
        id: 'group-a',
        name: 'Class A',
        traineeId: 't-ada',
        traineeName: 'Ada Lovelace',
        movementName: 'Normal Grip',
      );
      groups.seedGroup(
        activeGroup(
          id: 'foreign',
          teacherId: 'someone-else',
          name: 'Foreign Class',
        ),
      );

      await pumpGrades(
        tester,
        location: AppRoutePaths.teacherGradesForGroup('foreign'),
      );

      expect(
        find.byKey(const Key('teacher_grades_unauthorized')),
        findsOneWidget,
      );
      expect(find.text('Ada Lovelace'), findsNothing);
      expect(find.text('Normal Grip'), findsNothing);
      expect(
        find.byKey(const Key('teacher_grades_classroom_selector')),
        findsOneWidget,
      );
    },
  );

  testWidgets('repository load failure shows the safe error state', (
    tester,
  ) async {
    final failing = _FailingWatchGroupRepository();
    addTearDown(failing.dispose);

    await pumpGrades(tester, groupRepository: failing);

    expect(find.byKey(const Key('teacher_grades_load_error')), findsOneWidget);
    expect(find.text('Could not load groups.'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);
  });
}
