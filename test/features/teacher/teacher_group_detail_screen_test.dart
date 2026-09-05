import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_editorial_header.dart';
import 'package:elixr_application/core/widgets/elix_panel_card.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_application/core/widgets/movement_image.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/data/repositories/teacher_movement_repository.dart';
import 'package:elixr_application/features/teacher/groups/teacher_group_detail_screen.dart';
import 'package:elixr_application/features/teacher/groups/teacher_groups_controller.dart';
import 'package:elixr_application/features/teacher/classwork/teacher_classwork_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository repository;
  late FakePublicProfileRepository profiles;
  late InMemoryClassroomAssignmentRepository defaultAssignments;
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
    defaultAssignments = InMemoryClassroomAssignmentRepository();
  });

  tearDown(() {
    repository.dispose();
    defaultAssignments.dispose();
  });

  Future<TeacherGroupsController> controllerFor(
    String teacherId, {
    ClassroomAssignmentRepository? assignmentRepository,
  }) async {
    final controller = TeacherGroupsController(
      repository: repository,
      teacherId: teacherId,
      teacherDisplayName: 'Grace Hopper',
      ensureTeacherAuthorization: () async => true,
      publicProfileRepository: profiles,
      assignmentRepository: assignmentRepository ?? defaultAssignments,
      watchAssignmentSummaries: false,
    );
    return controller;
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    required TeacherGroupsController controller,
    required String groupId,
    TeacherMovementRepository? movementRepository,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final classwork = TeacherClassworkController(
      teacherId: controller.teacherId,
      teacherDisplayName: controller.teacherDisplayName,
      groupId: groupId,
      groupRepository: repository,
      assignmentRepository: controller.assignmentRepository!,
      approvedMembershipsProvider: () => controller.approvedMemberships,
      approvedMembershipsListenable: controller,
    );
    await classwork.start();
    addTearDown(classwork.dispose);

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
                  classworkController: classwork,
                  movementRepository: movementRepository,
                ),
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/teacher/groups/:groupId/classwork/:assignmentId',
          builder: (context, state) => Text(
            'classwork:${state.pathParameters['groupId']}:'
            '${state.pathParameters['assignmentId']}',
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
      FluentApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  for (final classroom in [true, false]) {
    testWidgets(
      '${classroom ? 'classroom' : 'assignment'} deletion pending, failure, retry and success',
      (tester) async {
        final assignments = _PendingDeleteRepository();
        addTearDown(assignments.dispose);
        final group = await repository.createGroup(
          teacherId: 'teacher-1',
          teacherDisplayName: 'Grace Hopper',
          name: 'BSIT-4A',
        );
        final assignment = await assignments.createOfficialAssignment(
          teacherId: 'teacher-1',
          teacherDisplayName: 'Grace Hopper',
          group: group,
          officialMovementName: 'Normal Grip',
        );
        final controller = await controllerFor(
          'teacher-1',
          assignmentRepository: assignments,
        );
        addTearDown(controller.dispose);
        await controller.startForGroup(group.id);
        await pumpDetail(tester, controller: controller, groupId: group.id);
        if (classroom) {
          controller.setTab(TeacherGroupDetailTab.announcements);
          await tester.pump();
        }
        final open = find.byKey(
          Key(
            classroom
                ? 'teacher_group_delete_classroom'
                : 'teacher_group_delete_assignment_${assignment.id}',
          ),
        );
        await tester.ensureVisible(open);
        await tester.tap(open);
        await tester.pumpAndSettle();
        final prefix = classroom ? 'teacher_group' : 'teacher_assignment';
        final field = find.byKey(Key('${prefix}_delete_confirmation'));
        await tester.enterText(
          field,
          classroom ? 'DELETE CLASSROOM' : 'DELETE ASSIGNMENT',
        );
        await tester.pump();
        final confirm = find.byKey(Key('${prefix}_confirm_delete'));
        final submit = tester.widget<FilledButton>(confirm).onPressed!;
        submit();
        submit(); // Exercise a stale callback before the disabled button rebuilds.
        await tester.pump();
        expect(assignments.deleteCalls, 1);
        expect(find.text('Deleting...'), findsOneWidget);
        expect(
          find.descendant(of: confirm, matching: find.byType(ProgressRing)),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
        final cancel = find.widgetWithText(Button, 'Cancel');
        expect(tester.widget<Button>(cancel).onPressed, isNull);
        expect(tester.widget<TextBox>(field).enabled, isFalse);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.binding.handlePopRoute();
        await tester.tapAt(const Offset(5, 5));
        await tester.pump();
        expect(find.text('Deleting...'), findsOneWidget);
        assignments.pending.completeError(
          const ClassroomException(
            ClassroomError.forbidden,
            'Deletion denied.',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Deleting...'), findsNothing);
        expect(
          find.descendant(
            of: find.byType(ContentDialog),
            matching: find.text('Deletion denied.'),
          ),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
        expect(tester.widget<Button>(cancel).onPressed, isNotNull);
        expect(tester.widget<TextBox>(field).enabled, isTrue);
        assignments.pending = Completer<void>();
        await tester.tap(confirm);
        await tester.pump();
        expect(assignments.deleteCalls, 2);
        expect(find.text('Deleting...'), findsOneWidget);
        assignments.pending.complete();
        await tester.pumpAndSettle();
        expect(find.byType(ContentDialog), findsNothing);
        if (classroom) {
          expect(find.text('groups home'), findsOneWidget);
          expect(controller.selectedGroup, isNull);
        } else {
          expect(assignments.assignments, isEmpty);
          expect(
            find.byKey(Key('teacher_group_assignment_${assignment.id}')),
            findsNothing,
          );
          expect(find.text('groups home'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
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
    expect(
      find.byKey(const Key('teacher_group_pending_join_badge')),
      findsOneWidget,
    );
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('teacher_group_tab_announcements')));
    await tester.pumpAndSettle();
    expect(find.text('Active'), findsWidgets);
    expect(find.byKey(const Key('teacher_group_invite_code')), findsOneWidget);
    expect(find.text(invite.displayCode), findsOneWidget);

    await tester.tap(find.byKey(const Key('teacher_group_tab_assignments')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('teacher_group_assignments_section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('teacher_group_pending_section')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('teacher_group_members_section')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('teacher_group_tab_students')));
    await tester.pumpAndSettle();

    expect(find.text('Alan Turing'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Teachers'), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_group_members_section')),
      findsOneWidget,
    );
    expect(find.text('1 student'), findsOneWidget);
    expect(
      find.byKey(Key('teacher_group_teacher_avatar_${group.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('teacher_group_approve_${pending.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('teacher_group_remove_${approved.id}')),
      findsOneWidget,
    );
    expect(find.text('Remove from class'), findsOneWidget);
  });

  testWidgets('group detail separates assignments and students into tabs', (
    tester,
  ) async {
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final controller = await controllerFor('teacher-1');
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);

    await pumpDetail(tester, controller: controller, groupId: group.id);

    expect(controller.tab, TeacherGroupDetailTab.classwork);
    expect(
      find.byKey(const Key('teacher_group_tab_assignments')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('teacher_group_tab_grades')), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_group_pending_join_badge')),
      findsNothing,
    );
    expect(find.text('Waiting to join'), findsNothing);

    await tester.tap(find.byKey(const Key('teacher_group_tab_grades')));
    await tester.pumpAndSettle();
    expect(controller.tab, TeacherGroupDetailTab.grades);
    expect(
      find.byKey(const Key('teacher_group_grades_section')),
      findsOneWidget,
    );
    expect(find.text('No students in this class yet.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('teacher_group_tab_students')));
    await tester.pumpAndSettle();

    expect(controller.tab, TeacherGroupDetailTab.students);
    expect(
      find.byKey(const Key('teacher_group_assignments_section')),
      findsNothing,
    );
    expect(find.text('Waiting to join'), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_group_members_section')),
      findsOneWidget,
    );
  });

  testWidgets('People tab pending badge follows membership stream updates', (
    tester,
  ) async {
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final controller = await controllerFor('teacher-1');
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);
    await pumpDetail(tester, controller: controller, groupId: group.id);

    expect(
      find.byKey(const Key('teacher_group_pending_join_badge')),
      findsNothing,
    );

    final invite = await repository.getActiveGroupInvite(groupId: group.id);
    final membership = await repository.requestGroupJoin(
      traineeId: 'trainee-pending',
      traineeDisplayName: 'Alan Turing',
      code: invite!.normalizedCode,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('teacher_group_pending_join_badge')),
      findsOneWidget,
    );
    expect(find.text('1'), findsOneWidget);

    await repository.rejectMembership(
      membershipId: membership.id,
      teacherId: 'teacher-1',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('teacher_group_pending_join_badge')),
      findsNothing,
    );
  });

  testWidgets('approved student identity opens class-aware student detail', (
    tester,
  ) async {
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final invite = await repository.getActiveGroupInvite(groupId: group.id);
    final approved = await repository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    await repository.approveMembership(
      membershipId: approved.id,
      teacherId: 'teacher-1',
    );
    final controller = await controllerFor('teacher-1');
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);
    await pumpDetail(tester, controller: controller, groupId: group.id);

    await tester.tap(find.byKey(const Key('teacher_group_tab_students')));
    await tester.pumpAndSettle();
    final studentIdentity = find.byKey(
      Key('teacher_group_member_open_${approved.id}'),
    );
    await tester.ensureVisible(studentIdentity);
    await tester.tap(studentIdentity);
    await tester.pumpAndSettle();

    expect(find.text('student:trainee-1:${group.id}'), findsOneWidget);
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

    expect(
      tester.getTopLeft(find.byKey(const Key('teacher_group_back'))).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(ElixEditorialPageHeader)).dy,
      ),
    );

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

  testWidgets('active group shows only its streamed assignments', (
    tester,
  ) async {
    var assignmentId = 0;
    final assignments = InMemoryClassroomAssignmentRepository(
      now: () => DateTime.utc(2026, 8, 26),
      generateId: () => 'active-assignment-${assignmentId++}',
    );
    addTearDown(assignments.dispose);
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final other = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4B',
    );
    final own = await assignments.createOfficialAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: group,
      officialMovementName: 'Normal Grip',
    );
    await assignments.createOfficialAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: other,
      officialMovementName: 'Hand Stall',
    );

    final controller = await controllerFor(
      'teacher-1',
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);

    await pumpDetail(tester, controller: controller, groupId: group.id);

    expect(
      find.byKey(const Key('teacher_group_assignments_section')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('teacher_group_assignment_${own.id}')),
      findsOneWidget,
    );
    expect(find.text('Normal Grip'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MovementImage && widget.movementName == 'Normal Grip',
      ),
      findsOneWidget,
    );
    expect(find.text('Hand Stall'), findsNothing);

    final openClasswork = find.byKey(Key('teacher_classwork_open_${own.id}'));
    await tester.ensureVisible(openClasswork);
    await tester.tap(openClasswork);
    await tester.pumpAndSettle();

    expect(find.text('classwork:${group.id}:${own.id}'), findsOneWidget);
  });

  testWidgets(
    'Grades renders a populated matrix and supports hovering its header',
    (tester) async {
      final assignments = InMemoryClassroomAssignmentRepository(
        now: () => DateTime.utc(2026, 8, 26),
      );
      addTearDown(assignments.dispose);
      final group = await repository.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSIT-4A',
      );
      final invite = await repository.getActiveGroupInvite(groupId: group.id);
      final membership = await repository.requestGroupJoin(
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        code: invite!.normalizedCode,
      );
      await repository.approveMembership(
        membershipId: membership.id,
        teacherId: 'teacher-1',
      );
      final assignment = await assignments.createOfficialAssignment(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        group: group,
        officialMovementName: 'Normal Grip',
      );
      final controller = await controllerFor(
        'teacher-1',
        assignmentRepository: assignments,
      );
      addTearDown(controller.dispose);
      await controller.startForGroup(group.id);

      await pumpDetail(tester, controller: controller, groupId: group.id);
      await tester.tap(find.byKey(const Key('teacher_group_tab_grades')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('teacher_group_grades_section')),
        findsOneWidget,
      );
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text('Normal Grip'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final header = find.ancestor(
        of: find.text(assignment.displayTitle),
        matching: find.byType(ElixHoverSurface),
      );
      expect(header, findsOneWidget);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(header));
      await mouse.moveTo(tester.getCenter(header));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.tap(header);
      await tester.pumpAndSettle();
      expect(
        find.text('classwork:${group.id}:${assignment.id}'),
        findsOneWidget,
      );
    },
  );

  testWidgets('teacher can edit the deadline and archive an assignment', (
    tester,
  ) async {
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final assignment = await assignments.createOfficialAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: group,
      officialMovementName: 'Normal Grip',
    );
    final controller = await controllerFor(
      'teacher-1',
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);

    await pumpDetail(tester, controller: controller, groupId: group.id);

    final edit = find.byKey(
      Key('teacher_group_edit_assignment_${assignment.id}'),
    );
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();

    expect(find.text('Edit assignment'), findsOneWidget);
    final dueDateToggle = find.byKey(
      const Key('teacher_assignment_due_date_toggle'),
    );
    await tester.ensureVisible(dueDateToggle);
    await tester.tap(dueDateToggle);
    await tester.pump();
    final save = find.byKey(const Key('teacher_assignment_save_changes'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(
      (await assignments.getAssignment(assignmentId: assignment.id))!.dueAt,
      isNotNull,
    );
    final archive = find.byKey(
      Key('teacher_group_archive_assignment_${assignment.id}'),
    );
    await tester.ensureVisible(archive);
    await tester.tap(archive);
    await tester.pumpAndSettle();
    expect(find.text('Archive this assignment?'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('teacher_assignment_confirm_archive')),
    );
    await tester.pumpAndSettle();

    final archived = await assignments.getAssignment(
      assignmentId: assignment.id,
    );
    expect(archived!.isActive, isFalse);
    expect(find.textContaining('Archived'), findsOneWidget);
    expect(
      find.byKey(Key('teacher_group_edit_assignment_${assignment.id}')),
      findsNothing,
    );
  });

  testWidgets('official assignment editor stays open when saving fails', (
    tester,
  ) async {
    final assignments = _FailingAssignmentUpdateRepository();
    addTearDown(assignments.dispose);
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final assignment = await assignments.createOfficialAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: group,
      officialMovementName: 'Normal Grip',
    );
    final controller = await controllerFor(
      'teacher-1',
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);

    await pumpDetail(tester, controller: controller, groupId: group.id);
    final edit = find.byKey(
      Key('teacher_group_edit_assignment_${assignment.id}'),
    );
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('teacher_assignment_save_changes'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text('Edit assignment'), findsOneWidget);
    expect(find.byKey(const Key('teacher_assignment_error')), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_assignment_save_changes')),
      findsOneWidget,
    );
  });

  testWidgets('Teacher Activity edits persist and can be edited again', (
    tester,
  ) async {
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    const assignmentId = 'teacher-created-assignment';
    assignments.seedAssignment(
      GroupAssignment(
        id: assignmentId,
        teacherId: 'teacher-1',
        groupId: group.id,
        movementId: 'movement-1',
        revisionId: 'revision-1',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        status: GroupAssignmentStatus.active,
        displayTitle: 'Tin Balance',
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSIT-4A',
        maxScore: 100,
      ),
    );
    final controller = await controllerFor(
      'teacher-1',
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);
    await pumpDetail(tester, controller: controller, groupId: group.id);

    final editAssignment = find.byKey(
      const Key('teacher_group_edit_assignment_$assignmentId'),
    );
    await tester.ensureVisible(editAssignment);
    await tester.tap(editAssignment);
    await tester.pumpAndSettle();
    expect(find.text('Edit assignment'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('teacher_assignment_topic')),
      'Bottle control',
    );
    final save = find.byKey(const Key('teacher_assignment_save_changes'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final updated = await assignments.getAssignment(assignmentId: assignmentId);
    expect(updated?.maxScore, 100);
    expect(updated?.topic, 'Bottle control');

    await tester.ensureVisible(editAssignment);
    await tester.tap(editAssignment);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextBox>(find.byKey(const Key('teacher_assignment_topic')))
          .controller
          ?.text,
      'Bottle control',
    );
  });

  testWidgets(
    'active group assignment section exposes an empty state and action',
    (tester) async {
      final assignments = InMemoryClassroomAssignmentRepository();
      addTearDown(assignments.dispose);
      final group = await repository.createGroup(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        name: 'BSIT-4A',
      );
      final controller = await controllerFor(
        'teacher-1',
        assignmentRepository: assignments,
      );
      addTearDown(controller.dispose);
      await controller.startForGroup(group.id);

      await pumpDetail(tester, controller: controller, groupId: group.id);

      expect(
        find.byKey(const Key('teacher_group_assignments_empty')),
        findsOneWidget,
      );
      expect(find.text('No classwork yet.'), findsOneWidget);
      expect(
        find.text('Create an assignment to give this class its next movement.'),
        findsOneWidget,
      );
      expect(find.text('New assignment'), findsOneWidget);
      final createButton = tester.widget<ElixPrimaryButton>(
        find.byKey(const Key('teacher_group_create_assignment')),
      );
      expect(createButton.onPressed, isNotNull);
    },
  );

  testWidgets('archived group keeps assignments but disables creation', (
    tester,
  ) async {
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(assignments.dispose);
    final active = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final historical = await assignments.createOfficialAssignment(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      group: active,
      officialMovementName: 'Normal Grip',
    );
    await repository.archiveGroup(groupId: active.id, teacherId: 'teacher-1');

    final controller = await controllerFor(
      'teacher-1',
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.startForGroup(active.id);

    await pumpDetail(tester, controller: controller, groupId: active.id);

    expect(
      find.byKey(Key('teacher_group_assignment_${historical.id}')),
      findsOneWidget,
    );
    final createButton = tester.widget<ElixPrimaryButton>(
      find.byKey(const Key('teacher_group_create_assignment')),
    );
    expect(createButton.onPressed, isNull);
    expect(
      find.byKey(const Key('teacher_group_archived_assignments_message')),
      findsOneWidget,
    );

    controller.setTab(TeacherGroupDetailTab.announcements);
    await tester.pump();

    final unarchive = tester.widget<Button>(
      find.byKey(const Key('teacher_group_unarchive_classroom')),
    );
    expect(unarchive.onPressed, isNotNull);
    await tester.tap(
      find.byKey(const Key('teacher_group_unarchive_classroom')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unarchive this classroom?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('teacher_group_confirm_unarchive')));
    await tester.pumpAndSettle();
    expect(repository.groups[active.id]?.status, ElixrGroupStatus.active);
    expect(find.byKey(const Key('elix_toast')), findsOneWidget);
    expect(find.text('Unarchived BSIT-4A.'), findsOneWidget);
  });

  testWidgets('classroom composer locks the opened group', (tester) async {
    final assignments = InMemoryClassroomAssignmentRepository();
    final movements = InMemoryTeacherMovementRepository();
    addTearDown(assignments.dispose);
    addTearDown(movements.dispose);
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final controller = await controllerFor(
      'teacher-1',
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);

    await pumpDetail(
      tester,
      controller: controller,
      groupId: group.id,
      movementRepository: movements,
    );
    await tester.tap(find.byKey(const Key('teacher_group_create_assignment')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('teacher_assignment_locked_group')),
      findsOneWidget,
    );
    expect(find.text('BSIT-4A'), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('teacher_assignment_class')), findsNothing);
  });

  testWidgets('group composer can create a new Teacher Activity', (
    tester,
  ) async {
    final assignments = InMemoryClassroomAssignmentRepository();
    final movements = InMemoryTeacherMovementRepository();
    addTearDown(assignments.dispose);
    addTearDown(movements.dispose);
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final controller = await controllerFor(
      'teacher-1',
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);

    await pumpDetail(
      tester,
      controller: controller,
      groupId: group.id,
      movementRepository: movements,
    );
    await tester.tap(find.byKey(const Key('teacher_group_create_assignment')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_source_mine')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('teacher_assignment_movement')), findsNothing);
    expect(find.byKey(const ValueKey('builder-title')), findsNothing);
    await tester.tap(
      find.byKey(const Key('teacher_assignment_create_movement')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('builder-title')),
      'Tin Balance',
    );
    await tester.enterText(
      find.byKey(const ValueKey('builder-instructions')),
      'Balance the tin upright.',
    );
    await tester.tap(find.text('Create').last);
    await tester.pumpAndSettle();

    expect(movements.movements, hasLength(1));
    expect(
      tester
          .widget<ElixPrimaryButton>(
            find.byKey(const Key('teacher_assignment_publish_now')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('classroom composer writes to the opened group', (tester) async {
    final assignments = InMemoryClassroomAssignmentRepository(
      generateId: () => 'classroom-assignment',
    );
    final movements = InMemoryTeacherMovementRepository();
    addTearDown(assignments.dispose);
    addTearDown(movements.dispose);
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final controller = await controllerFor(
      'teacher-1',
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);

    await pumpDetail(
      tester,
      controller: controller,
      groupId: group.id,
      movementRepository: movements,
    );
    await tester.tap(find.byKey(const Key('teacher_group_create_assignment')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_publish_now')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_publish_now')));
    await tester.pumpAndSettle();

    expect(assignments.assignments, hasLength(1));
    expect(assignments.assignments.values.single.groupId, group.id);
    expect(assignments.assignments.values.single.groupName, 'BSIT-4A');
    expect(
      find.byKey(const Key('teacher_assignment_locked_group')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('teacher_group_assignment_classroom-assignment')),
      findsOneWidget,
    );
  });

  testWidgets('classroom composer can create a teacher-created assignment', (
    tester,
  ) async {
    final assignments = InMemoryClassroomAssignmentRepository(
      generateId: () => 'classroom-custom-assignment',
    );
    final movements = InMemoryTeacherMovementRepository();
    addTearDown(assignments.dispose);
    addTearDown(movements.dispose);
    final group = await repository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSIT-4A',
    );
    final customMovement = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Balance the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
    final controller = await controllerFor(
      'teacher-1',
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.startForGroup(group.id);

    await pumpDetail(
      tester,
      controller: controller,
      groupId: group.id,
      movementRepository: movements,
    );
    await tester.tap(find.byKey(const Key('teacher_group_create_assignment')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_source_mine')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_publish_now')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_publish_now')));
    await tester.pumpAndSettle();

    expect(assignments.assignments, hasLength(1));
    final created = assignments.assignments.values.single;
    expect(created.groupId, group.id);
    expect(created.movementId, customMovement.id);
    expect(created.maxScore, 50);
    expect(created.activityAssessment, isNotNull);
  });
}

class _FailingAssignmentUpdateRepository
    extends InMemoryClassroomAssignmentRepository {
  @override
  Future<GroupAssignment> updateAssignmentSettings({
    required String teacherId,
    required String assignmentId,
    DateTime? dueAt,
    int? maxScore,
    String? topic,
  }) {
    throw const ClassroomException(ClassroomError.conflict);
  }
}

class _PendingDeleteRepository extends InMemoryClassroomAssignmentRepository {
  Completer<void> pending = Completer<void>();
  int deleteCalls = 0;
  @override
  Future<void> permanentlyDeleteAssignment({
    required String teacherId,
    required String assignmentId,
    required String confirmation,
  }) async {
    deleteCalls++;
    await pending.future;
    await super.permanentlyDeleteAssignment(
      teacherId: teacherId,
      assignmentId: assignmentId,
      confirmation: confirmation,
    );
  }

  @override
  Future<void> permanentlyDeleteClassroom({
    required String teacherId,
    required String groupId,
    required String confirmation,
  }) async {
    deleteCalls++;
    await pending.future;
  }
}
