import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/teacher/groups/teacher_group_detail_screen.dart';
import 'package:elixr_application/features/teacher/groups/teacher_groups_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository repository;
  late FakePublicProfileRepository profiles;
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
    profiles = FakePublicProfileRepository();
  });

  tearDown(() {
    repository.dispose();
  });

  Future<TeacherGroupsController> controllerFor(String teacherId) async {
    final controller = TeacherGroupsController(
      repository: repository,
      teacherId: teacherId,
      teacherDisplayName: 'Grace Hopper',
      ensureTeacherAuthorization: () async => true,
      publicProfileRepository: profiles,
    );
    return controller;
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    required TeacherGroupsController controller,
    required String groupId,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherGroup(groupId),
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherGroups,
          builder: (context, state) => const Text('groups home'),
          routes: [
            GoRoute(
              path: ':groupId',
              builder: (context, state) => MultiProvider(
                providers: [Provider<GroupRepository>.value(value: repository)],
                child: TeacherGroupDetailScreen(
                  groupId: groupId,
                  controller: controller,
                ),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      FluentApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pump();
  }

  testWidgets('detail shows join code, pending students, and members', (
    tester,
  ) async {
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final invite = await repository.getActiveGroupInvite(groupId: group.id);
    final pending = await repository.requestGroupJoin(
      traineeId: 'trainee-pending',
      traineeDisplayName: 'Alan Turing',
      code: invite!.normalizedCode,
    );
    final approved = await repository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite.normalizedCode,
    );
    await repository.approveMembership(
      membershipId: approved.id,
      teacherId: 'teacher-1',
    );

    final controller = await controllerFor('teacher-1');
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);

    await pumpDetail(tester, controller: controller, groupId: group.id);

    expect(find.text('BSIT-4A'), findsWidgets);
    expect(find.text('Active'), findsWidgets);
    expect(find.byKey(const Key('teacher_group_invite_code')), findsOneWidget);
    expect(find.text(invite.displayCode), findsOneWidget);
    expect(find.text('Alan Turing'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(
      find.byKey(Key('teacher_group_approve_${pending.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('teacher_group_remove_${approved.id}')),
      findsOneWidget,
    );
  });

  testWidgets('back returns to the groups card grid', (tester) async {
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final controller = await controllerFor('teacher-1');
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);

    await pumpDetail(tester, controller: controller, groupId: group.id);

    await tester.tap(find.byKey(const Key('teacher_group_back')));
    await tester.pumpAndSettle();

    expect(find.text('groups home'), findsOneWidget);
  });

  testWidgets('unknown or foreign class shows unauthorized copy', (
    tester,
  ) async {
    final other = await repository.createGroup(
      teacherId: 'teacher-2',
      teacherDisplayName: 'Other Teacher',
      name: 'Other Class',
    );
    final controller = await controllerFor('teacher-1');
    addTearDown(controller.dispose);
    await controller.startForGroup(other.id);

    await pumpDetail(tester, controller: controller, groupId: other.id);

    expect(find.byKey(const Key('teacher_group_unauthorized')), findsOneWidget);
    expect(find.text('This class is not available.'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);
  });
}
