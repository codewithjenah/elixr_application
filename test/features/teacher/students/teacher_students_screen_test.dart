import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/features/teacher/students/teacher_student_models.dart';
import 'package:elixr_application/features/teacher/students/teacher_students_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository repository;
  late AuthService auth;

  setUp(() {
    repository = InMemoryGroupRepository(now: () => DateTime.utc(2026, 8, 19));
    auth = phase3TeacherAuth();
  });

  tearDown(() {
    repository.dispose();
    auth.dispose();
  });

  Future<void> pumpStudents(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
  }) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherStudents,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherStudents,
          builder: (context, state) => const TeacherStudentsScreen(),
          routes: [
            GoRoute(
              path: ':traineeId',
              builder: (context, state) => Text(
                'detail:${state.pathParameters['traineeId']}:${state.uri.queryParameters['groupId'] ?? ''}',
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: repository),
        ],
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void seedApprovedPair() {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't1',
        traineeName: 'Ada Lovelace',
      ),
    );
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't2',
        traineeName: 'Alan Turing',
      ),
    );
  }

  testWidgets(
    'approved roster renders toolbar and rows without unbounded flex',
    (tester) async {
      seedApprovedPair();
      await pumpStudents(tester);

      expectNoUnboundedFlex(tester);
      expect(find.widgetWithText(TextBox, 'Search by name'), findsOneWidget);
      expect(find.byType(ComboBox<String?>), findsOneWidget);
      expect(find.text('All classes'), findsWidgets);
      expect(find.byType(ComboBox<TeacherStudentStatusFilter>), findsOneWidget);
      expect(find.text('Approved'), findsWidgets);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Alan Turing'), findsOneWidget);
      expect(find.byType(CustomScrollView), findsOneWidget);
    },
  );

  testWidgets('roster layout holds at 1600x900', (tester) async {
    seedApprovedPair();
    await pumpStudents(tester, size: const Size(1600, 900));

    expectNoUnboundedFlex(tester);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Alan Turing'), findsOneWidget);
  });

  testWidgets('roster longer than the viewport scrolls independently', (
    tester,
  ) async {
    repository.seedGroup(activeGroup());
    for (var i = 0; i < 24; i++) {
      repository.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 't$i',
          traineeName: 'Student ${i.toString().padLeft(2, '0')}',
        ),
      );
    }
    await pumpStudents(tester, size: const Size(1280, 720));

    expectNoUnboundedFlex(tester);
    expect(find.text('Student 00'), findsOneWidget);
    expect(find.text('Student 23'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -4000));
    await tester.pumpAndSettle();

    expectNoUnboundedFlex(tester);
    expect(find.text('Student 23'), findsOneWidget);
  });

  testWidgets('search and status filter still hide unmatched students', (
    tester,
  ) async {
    seedApprovedPair();
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't3',
        traineeName: 'Grace Hopper',
        status: GroupMembershipStatus.pending,
      ),
    );
    await pumpStudents(tester);

    await tester.enterText(find.byType(TextBox), 'ada');
    await tester.pump();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Alan Turing'), findsNothing);

    await tester.enterText(find.byType(TextBox), '');
    await tester.pump();
    await tester.tap(find.text('Approved').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pending').last);
    await tester.pumpAndSettle();

    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);
    expect(find.text('Alan Turing'), findsNothing);
  });

  testWidgets('empty class still shows that class on its own', (tester) async {
    repository.seedGroup(activeGroup());
    await pumpStudents(tester);

    expectNoUnboundedFlex(tester);
    expect(find.text('BSHM 4A'), findsOneWidget);
    expect(find.text('No students in this class yet.'), findsOneWidget);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  testWidgets('students stay in separate class groups', (tester) async {
    repository.seedGroup(activeGroup(id: 'group-1', name: 'BSHM 4A'));
    repository.seedGroup(activeGroup(id: 'group-2', name: 'BSHM 4B'));
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't1',
        traineeName: 'Ada Lovelace',
      ),
    );
    repository.seedMembership(
      membership(
        groupId: 'group-2',
        teacherId: 'teacher',
        traineeId: 't2',
        traineeName: 'Alan Turing',
      ),
    );
    await pumpStudents(tester);

    expectNoUnboundedFlex(tester);
    expect(find.text('BSHM 4A'), findsOneWidget);
    expect(find.text('BSHM 4B'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Alan Turing'), findsOneWidget);
  });

  testWidgets('filter miss shows match-empty copy', (tester) async {
    seedApprovedPair();
    await pumpStudents(tester);

    await tester.enterText(find.byType(TextBox), 'no-such-student');
    await tester.pump();

    expectNoUnboundedFlex(tester);
    expect(find.text('No students match the current filters.'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);
  });

  testWidgets('opening a student keeps approved group context in the route', (
    tester,
  ) async {
    seedApprovedPair();
    await pumpStudents(tester);

    await tester.tap(find.widgetWithText(Button, 'Open details').first);
    await tester.pumpAndSettle();

    expect(find.text('detail:t1:group-1'), findsOneWidget);
  });
}

void expectNoUnboundedFlex(WidgetTester tester) {
  final exception = tester.takeException();
  expect(exception, isNull);
}
