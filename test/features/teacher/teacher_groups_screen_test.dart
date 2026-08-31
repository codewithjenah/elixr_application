import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/groups/teacher_groups_controller.dart';
import 'package:elixr_application/features/teacher/groups/teacher_groups_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository repository;
  late InMemoryClassroomAssignmentRepository assignments;
  late AuthService auth;
  var groupIdIndex = 0;
  var inviteCodeIndex = 0;

  const inviteCodes = ['ABCD2345EFGH', 'ZZZZ2345YYYY', 'MNOP2345QRST'];

  setUp(() {
    groupIdIndex = 0;
    inviteCodeIndex = 0;
    repository = InMemoryGroupRepository(
      generateNormalizedCode: () =>
          inviteCodes[inviteCodeIndex++ % inviteCodes.length],
      generateGroupId: () => 'group-${groupIdIndex++}',
      now: () => DateTime.utc(2026, 8, 26),
    );
    assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 8, 26),
    );
    auth = phase3TeacherAuth();
  });

  tearDown(() {
    repository.dispose();
    assignments.dispose();
    auth.dispose();
  });

  Future<void> pumpGroups(
    WidgetTester tester, {
    TeacherGroupsController? controller,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherGroups,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherGroups,
          builder: (context, state) =>
              TeacherGroupsScreen(controller: controller),
          routes: [
            GoRoute(
              path: ':groupId',
              builder: (context, state) =>
                  Text('detail:${state.pathParameters['groupId']}'),
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
          Provider<ClassroomAssignmentRepository>.value(value: assignments),
        ],
        child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('empty groups shows create copy instead of a side panel', (
    tester,
  ) async {
    await pumpGroups(tester);

    expect(find.byKey(const Key('teacher_groups_empty')), findsOneWidget);
    expect(
      find.text('Select a class to see its students and join code.'),
      findsNothing,
    );
  });

  testWidgets('groups render as cards that open a dedicated class page', (
    tester,
  ) async {
    final groupA = await repository.createGroup(
      teacherId: 'teacher',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final groupB = await repository.createGroup(
      teacherId: 'teacher',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4B',
    );
    final inviteA = await repository.getActiveGroupInvite(groupId: groupA.id);
    final ada = await repository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: inviteA!.normalizedCode,
    );
    await repository.approveMembership(
      membershipId: ada.id,
      teacherId: 'teacher',
    );
    await assignments.createOfficialAssignment(
      teacherId: 'teacher',
      teacherDisplayName: 'Grace Hopper',
      group: groupA,
      officialMovementName: 'Normal Grip',
      dueAt: DateTime(2026, 8, 31),
    );

    await pumpGroups(tester);

    expect(find.text('BSIT-4A'), findsOneWidget);
    expect(find.text('BSHM 4B'), findsOneWidget);
    expect(find.text('Active'), findsNWidgets(3));
    expect(find.text('Grace Hopper'), findsNWidgets(2));
    expect(find.text('Students and join code'), findsNothing);
    expect(find.text('Open classwork'), findsNothing);
    expect(find.text('Normal Grip'), findsOneWidget);
    expect(find.byKey(Key('teacher_group_card_${groupA.id}')), findsOneWidget);
    expect(find.byKey(Key('teacher_group_card_${groupB.id}')), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);
    expect(
      find.text('Select a class to see its students and join code.'),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(Key('teacher_group_card_${groupA.id}')),
    );
    await tester.tap(find.byKey(Key('teacher_group_card_${groupA.id}')));
    await tester.pumpAndSettle();

    expect(find.text('detail:${groupA.id}'), findsOneWidget);
  });

  testWidgets('creating a group opens the new class page', (tester) async {
    final controller = TeacherGroupsController(
      repository: repository,
      teacherId: 'teacher',
      teacherDisplayName: 'Grace Hopper',
      ensureTeacherAuthorization: () async => true,
    );
    addTearDown(controller.dispose);
    await controller.start();

    await pumpGroups(tester, controller: controller);

    await tester.tap(find.byKey(const Key('teacher_groups_create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('teacher_groups_create_name')),
      'BSIT-4A',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('detail:group-0'), findsOneWidget);
    expect(controller.selectedGroup, isNull);
  });
}
