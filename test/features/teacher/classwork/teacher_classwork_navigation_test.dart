import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher/classwork/teacher_classwork_controller.dart';
import 'package:elixr_application/features/teacher/groups/teacher_group_detail_screen.dart';
import 'package:elixr_application/features/teacher/groups/teacher_groups_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('classwork hierarchy exposes one contextual back action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final groups = InMemoryGroupRepository();
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(groups.dispose);
    addTearDown(assignments.dispose);
    final group = await groups.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final invite = await groups.getActiveGroupInvite(groupId: group.id);
    final membership = await groups.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    await groups.approveMembership(
      membershipId: membership.id,
      teacherId: 'teacher-1',
    );
    final assignment = await assignments.createOfficialAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: group,
      officialMovementName: 'Normal Grip',
    );
    final groupController = TeacherGroupsController(
      repository: groups,
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      ensureTeacherAuthorization: () async => true,
      assignmentRepository: assignments,
      watchAssignmentSummaries: false,
    );
    addTearDown(groupController.dispose);
    await groupController.startForGroup(group.id);
    final classworkController = TeacherClassworkController(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      groupId: group.id,
      groupRepository: groups,
      assignmentRepository: assignments,
      initialAssignmentId: assignment.id,
      approvedMembershipsProvider: () => groupController.approvedMemberships,
      approvedMembershipsListenable: groupController,
    );
    addTearDown(classworkController.dispose);
    await classworkController.start();

    Widget detail() => Provider<GroupRepository>.value(
      value: groups,
      child: TeacherGroupDetailScreen(
        groupId: group.id,
        controller: groupController,
        classworkController: classworkController,
      ),
    );

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherGroupClasswork(
        group.id,
        assignment.id,
      ),
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherGroups,
          builder: (context, state) => const Text('groups home'),
          routes: [
            GoRoute(path: ':groupId', builder: (context, state) => detail()),
          ],
        ),
        GoRoute(
          path: '/teacher/groups/:groupId/classwork/:assignmentId',
          builder: (context, state) => detail(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      FluentApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('teacher_group_back')), findsNothing);
    expect(find.byKey(const Key('teacher_classwork_back')), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_classwork_back_to_roster')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('teacher_classwork_student_trainee-1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('teacher_group_back')), findsNothing);
    expect(find.byKey(const Key('teacher_classwork_back')), findsNothing);
    expect(
      find.byKey(const Key('teacher_classwork_back_to_roster')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('teacher_classwork_back_to_roster')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('teacher_classwork_back')), findsOneWidget);
    expect(find.byKey(const Key('teacher_group_back')), findsNothing);

    await tester.tap(find.byKey(const Key('teacher_classwork_back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('teacher_group_back')), findsOneWidget);
    expect(find.byKey(const Key('teacher_classwork_back')), findsNothing);
  });
}
