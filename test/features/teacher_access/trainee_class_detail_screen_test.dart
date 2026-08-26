import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher_access/trainee_class_detail_controller.dart';
import 'package:elixr_application/features/teacher_access/trainee_class_detail_screen.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

Future<void> pumpClassDetail(
  WidgetTester tester, {
  required TraineeClassDetailController controller,
  required GroupRepository groupRepository,
  required ClassroomAssignmentRepository assignmentRepository,
}) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: AppRoutePaths.teacherAccessClass(controller.groupId),
    routes: [
      GoRoute(
        path: AppRoutePaths.teacherAccess,
        builder: (context, state) => const Text('classes home'),
        routes: [
          GoRoute(
            path: ':groupId',
            builder: (context, state) => MultiProvider(
              providers: [
                Provider<GroupRepository>.value(value: groupRepository),
                Provider<ClassroomAssignmentRepository>.value(
                  value: assignmentRepository,
                ),
              ],
              child: TraineeClassDetailScreen(
                groupId: controller.groupId,
                controller: controller,
              ),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '${AppRoutePaths.assignedPracticePrefix}/:assignmentId',
        builder: (context, state) =>
            Text('practice:${state.pathParameters['assignmentId']}'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    FluentApp.router(theme: AppTheme.dark, routerConfig: router),
  );
  await tester.pump();
}

GroupAssignment _assignment({
  required String id,
  required String groupId,
  required String title,
}) {
  return GroupAssignment(
    id: id,
    teacherId: 'teacher-1',
    groupId: groupId,
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: MovementOrigin.officialElixr,
    assessmentMode: AssessmentMode.officialGuided,
    status: GroupAssignmentStatus.active,
    displayTitle: title,
    teacherDisplayName: 'Grace Hopper',
    groupName: 'BSHM 4A',
    officialMovementName: 'Hand Stall',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository groupRepository;
  late InMemoryClassroomAssignmentRepository assignmentRepository;

  setUp(() {
    var groupCodeIndex = 0;
    var groupIdIndex = 0;
    const groupCodes = ['ABCD2345EFGH', 'ZZZZ2345YYYY', 'MNOP2345QRST'];
    groupRepository = InMemoryGroupRepository(
      generateNormalizedCode: () =>
          groupCodes[groupCodeIndex++ % groupCodes.length],
      generateGroupId: () => 'group-${groupIdIndex++}',
      now: () => DateTime.utc(2026, 8, 16),
    );
    assignmentRepository = InMemoryClassroomAssignmentRepository();
  });

  tearDown(() {
    groupRepository.dispose();
    assignmentRepository.dispose();
  });

  Future<ElixrGroup> approvedClass({
    required String name,
    List<String> extraTraineeIds = const [],
  }) async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: name,
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    final ada = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    await groupRepository.approveMembership(
      membershipId: ada.id,
      teacherId: 'teacher-1',
    );
    for (final extraId in extraTraineeIds) {
      final extra = await groupRepository.requestGroupJoin(
        traineeId: extraId,
        traineeDisplayName: 'Alan Turing',
        code: invite.normalizedCode,
      );
      await groupRepository.approveMembership(
        membershipId: extra.id,
        teacherId: 'teacher-1',
      );
    }
    return group;
  }

  testWidgets('classwork lists assignments for the opened class', (
    tester,
  ) async {
    final group = await approvedClass(name: 'BSHM 4A');
    assignmentRepository.seedAssignment(
      _assignment(id: 'asg-a', groupId: group.id, title: 'Hand Stall'),
    );
    final controller = TraineeClassDetailController(
      groupId: group.id,
      traineeId: 'trainee-1',
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );
    addTearDown(controller.dispose);
    await controller.start();

    await pumpClassDetail(
      tester,
      controller: controller,
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );

    expect(find.text('Hand Stall'), findsWidgets);
    expect(find.text('Ada Lovelace (you)'), findsNothing);
  });

  testWidgets('people tab lists classmates for that class only', (
    tester,
  ) async {
    final groupA = await approvedClass(
      name: 'BSHM 4A',
      extraTraineeIds: ['trainee-2'],
    );
    await approvedClass(name: 'BSHM 4B');
    final controller = TraineeClassDetailController(
      groupId: groupA.id,
      traineeId: 'trainee-1',
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );
    addTearDown(controller.dispose);
    await controller.start();
    controller.setTab(TraineeClassDetailTab.people);

    await pumpClassDetail(
      tester,
      controller: controller,
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );

    expect(find.text('Ada Lovelace (you)'), findsOneWidget);
    expect(find.text('Alan Turing'), findsOneWidget);
    expect(find.text('BSHM 4B'), findsNothing);
    expect(
      find.byKey(Key('teacher_access_classmate_avatar_${groupA.id}_trainee-2')),
      findsOneWidget,
    );
    final alanAvatar = tester.widget<ProfileAvatarWidget>(
      find.byKey(Key('teacher_access_classmate_avatar_${groupA.id}_trainee-2')),
    );
    expect(alanAvatar.initials, 'AT');
    expect(alanAvatar.networkImageUrl, isNull);
  });

  testWidgets('classwork tab can switch to people', (tester) async {
    final group = await approvedClass(
      name: 'BSHM 4A',
      extraTraineeIds: ['trainee-2'],
    );
    final controller = TraineeClassDetailController(
      groupId: group.id,
      traineeId: 'trainee-1',
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );
    addTearDown(controller.dispose);
    await controller.start();

    await pumpClassDetail(
      tester,
      controller: controller,
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );

    expect(find.text('Ada Lovelace (you)'), findsNothing);
    await tester.tap(find.byKey(const Key('teacher_access_class_tab_people')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.tab, TraineeClassDetailTab.people);
    expect(find.text('Ada Lovelace (you)'), findsOneWidget);
  });

  testWidgets('unauthorized membership shows an error panel', (tester) async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final controller = TraineeClassDetailController(
      groupId: group.id,
      traineeId: 'trainee-1',
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );
    addTearDown(controller.dispose);
    await controller.start();

    await pumpClassDetail(
      tester,
      controller: controller,
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
    );

    expect(
      find.byKey(const Key('teacher_access_class_unauthorized')),
      findsOneWidget,
    );
  });
}
