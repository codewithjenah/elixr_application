import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/teacher_access/teacher_access_controller.dart';
import 'package:elixr_application/features/teacher_access/teacher_access_section.dart';
import 'package:elixr_application/services/join_code_resolver.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> pumpAccess(
  WidgetTester tester,
  TeacherAccessController controller, {
  required GroupRepository groupRepository,
  required JoinCodeResolver joinCodeResolver,
  void Function(String groupId)? onOpenClass,
}) async {
  await tester.pumpWidget(
    FluentApp(
      theme: AppTheme.dark,
      home: MultiProvider(
        providers: [
          Provider<GroupRepository>.value(value: groupRepository),
          Provider<JoinCodeResolver>.value(value: joinCodeResolver),
        ],
        child: ScaffoldPage(
          content: SingleChildScrollView(
            child: TeacherAccessSection(
              controller: controller,
              isActive: true,
              onOpenClass: onOpenClass,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late InMemoryTeacherRelationshipRepository relationshipRepository;
  late InMemoryGroupRepository groupRepository;
  late InMemoryClassroomAssignmentRepository assignments;
  late JoinCodeResolver joinCodeResolver;
  late TeacherAccessController controller;

  setUp(() async {
    relationshipRepository = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 16),
    );
    var groupCodeIndex = 0;
    var groupIdIndex = 0;
    const groupCodes = ['ABCD2345EFGH', 'ZZZZ2345YYYY', 'MNOP2345QRST'];
    groupRepository = InMemoryGroupRepository(
      generateNormalizedCode: () =>
          groupCodes[groupCodeIndex++ % groupCodes.length],
      generateGroupId: () => 'group-${groupIdIndex++}',
      now: () => DateTime.utc(2026, 8, 16),
    );
    assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 8, 16),
    );
    joinCodeResolver = JoinCodeResolver(
      groupRepository: groupRepository,
      relationshipRepository: relationshipRepository,
    );
    await relationshipRepository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    controller = TeacherAccessController(
      relationshipRepository: relationshipRepository,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      privateImageSavingEnabled: true,
      assignmentRepository: assignments,
    );
  });

  tearDown(() {
    controller.dispose();
    relationshipRepository.dispose();
    groupRepository.dispose();
    assignments.dispose();
  });

  testWidgets('resolves Teacher and requires explicit join confirmation', (
    tester,
  ) async {
    await pumpAccess(
      tester,
      controller,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
    );
    await tester.enterText(
      find.byKey(const Key('teacher_access_roster_code')),
      '7KPM-XR4D-Q2WT',
    );
    await tester.tap(find.byKey(const Key('teacher_access_resolve_code')));
    await tester.pump();
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(relationshipRepository.links, isEmpty);

    await tester.tap(find.byKey(const Key('teacher_access_confirm_join')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.pending.single.requestVersion, 2);
    expect(find.text('Waiting for your teacher to accept you'), findsOneWidget);
    expect(find.text('Waiting for a teacher'), findsNothing);
    expect(find.text('Waiting to join a class'), findsNothing);
  });

  testWidgets('pending request is Trainee-cancellable', (tester) async {
    final link = await relationshipRepository.requestTeacherJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: '7KPMXR4DQ2WT',
    );
    await pumpAccess(
      tester,
      controller,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
    );
    await controller.cancelPending(link);
    await tester.pump();
    expect(
      find.byKey(const Key('teacher_access_pending_empty')),
      findsOneWidget,
    );
  });

  testWidgets('class and teacher waits share one pending list', (tester) async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    await relationshipRepository.requestTeacherJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: '7KPMXR4DQ2WT',
    );

    await pumpAccess(
      tester,
      controller,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
    );
    await tester.pump();

    expect(find.text('Waiting to join'), findsOneWidget);
    expect(find.text('Waiting to join a class'), findsNothing);
    expect(find.text('Waiting for a teacher'), findsNothing);
    expect(find.text('BSHM 4A'), findsOneWidget);
    expect(
      find.textContaining('Waiting for Grace Hopper to accept you'),
      findsOneWidget,
    );
    expect(find.text('Waiting for your teacher to accept you'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(controller.pendingJoinCount, 2);
  });

  testWidgets('evidence sharing appears only after progress access', (
    tester,
  ) async {
    final link = await relationshipRepository.requestTeacherJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: '7KPMXR4DQ2WT',
    );
    await relationshipRepository.approveJoin(
      linkId: link.id,
      teacherId: 'teacher-1',
    );
    await relationshipRepository.grantProgressAccess(
      linkId: link.id,
      traineeId: 'trainee-1',
    );
    await pumpAccess(
      tester,
      controller,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
    );
    expect(
      find.byKey(Key('teacher_access_evidence_${link.id}')),
      findsOneWidget,
    );
    expect(find.text('Share saved images'), findsOneWidget);
    expect(find.text('Teachers not in a class'), findsOneWidget);
  });

  testWidgets(
    'fills a wide desktop surface with metric tiles and paired cards',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpAccess(
        tester,
        controller,
        groupRepository: groupRepository,
        joinCodeResolver: joinCodeResolver,
      );

      expect(find.text('Waiting'), findsOneWidget);
      expect(find.text('My classes'), findsOneWidget);
      expect(find.text('Join a class'), findsOneWidget);
      expect(find.text('Waiting to join'), findsOneWidget);
      expect(find.text('Waiting to join a class'), findsNothing);
      expect(find.text('Waiting for a teacher'), findsNothing);
      expect(find.text('Your classes'), findsOneWidget);
      expect(find.text('Linked teachers'), findsNothing);
      expect(find.text('Teachers not in a class'), findsNothing);
      expect(
        find.byKey(const Key('teacher_access_roster_code')),
        findsOneWidget,
      );
    },
  );

  testWidgets('approved classes are compact cards that open the class page', (
    tester,
  ) async {
    final groupA = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final groupB = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4B',
    );
    final inviteA = await groupRepository.getActiveGroupInvite(
      groupId: groupA.id,
    );
    final inviteB = await groupRepository.getActiveGroupInvite(
      groupId: groupB.id,
    );
    final adaA = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: inviteA!.normalizedCode,
    );
    final alanA = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-2',
      traineeDisplayName: 'Alan Turing',
      code: inviteA.normalizedCode,
    );
    final adaB = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: inviteB!.normalizedCode,
    );
    await groupRepository.approveMembership(
      membershipId: adaA.id,
      teacherId: 'teacher-1',
    );
    await groupRepository.approveMembership(
      membershipId: alanA.id,
      teacherId: 'teacher-1',
    );
    await groupRepository.approveMembership(
      membershipId: adaB.id,
      teacherId: 'teacher-1',
    );
    await assignments.createOfficialAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: groupA,
      officialMovementName: 'Normal Grip',
      dueAt: DateTime(2026, 8, 31),
    );

    String? openedGroupId;
    await pumpAccess(
      tester,
      controller,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
      onOpenClass: (groupId) => openedGroupId = groupId,
    );
    await tester.pump();

    expect(find.text('BSHM 4A'), findsOneWidget);
    expect(find.text('BSHM 4B'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsNWidgets(2));
    expect(find.text('Normal Grip'), findsOneWidget);
    expect(find.text('Ada Lovelace (you)'), findsNothing);
    expect(find.text('Alan Turing'), findsNothing);
    expect(find.text('Classmates'), findsNothing);
    expect(
      find.byKey(Key('teacher_access_group_${groupA.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('teacher_access_group_${groupB.id}')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(Key('teacher_access_group_${groupA.id}')),
    );
    await tester.tap(find.byKey(Key('teacher_access_group_${groupA.id}')));
    await tester.pump();
    expect(openedGroupId, groupA.id);
  });
}
