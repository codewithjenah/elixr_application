import 'dart:async';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
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

class _FakeTeacherProfiles extends PublicProfileRepository {
  final _controllers = <String, StreamController<PublicProfile?>>{};

  @override
  Stream<PublicProfile?> watchProfileRoot(String userId) {
    return _controllers
        .putIfAbsent(
          userId,
          () => StreamController<PublicProfile?>.broadcast(sync: true),
        )
        .stream;
  }

  void emit(String userId, PublicProfile? profile) {
    _controllers[userId]?.add(profile);
  }

  void dispose() {
    for (final controller in _controllers.values) {
      unawaited(controller.close());
    }
    _controllers.clear();
  }
}

void main() {
  late InMemoryTeacherRelationshipRepository relationshipRepository;
  late InMemoryGroupRepository groupRepository;
  late InMemoryClassroomAssignmentRepository assignments;
  late JoinCodeResolver joinCodeResolver;
  late _FakeTeacherProfiles profiles;
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
    joinCodeResolver = JoinCodeResolver(groupRepository: groupRepository);
    profiles = _FakeTeacherProfiles();
    await relationshipRepository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    controller = TeacherAccessController(
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      assignmentRepository: assignments,
      publicProfileRepository: profiles,
    );
  });

  tearDown(() {
    controller.dispose();
    profiles.dispose();
    relationshipRepository.dispose();
    groupRepository.dispose();
    assignments.dispose();
  });

  testWidgets('resolves class and requires explicit join confirmation', (
    tester,
  ) async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    await pumpAccess(
      tester,
      controller,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
    );
    await tester.tap(find.byKey(const Key('teacher_access_join_toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('teacher_access_roster_code')),
      invite!.displayCode,
    );
    await tester.tap(find.byKey(const Key('teacher_access_resolve_code')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('BSHM 4A · Grace Hopper'), findsOneWidget);
    expect(relationshipRepository.links, isEmpty);

    await tester.tap(find.byKey(const Key('teacher_access_confirm_join')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.pendingGroupMemberships.single.requestVersion, 1);
    expect(
      find.textContaining('Waiting for Grace Hopper to accept you'),
      findsOneWidget,
    );
    expect(find.text('Waiting for a teacher'), findsNothing);
    expect(find.text('Waiting to join a class'), findsNothing);
  });

  testWidgets('pending class request is Trainee-cancellable', (tester) async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    final membership = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    await pumpAccess(
      tester,
      controller,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
    );
    await controller.cancelPendingGroup(membership);
    await tester.pump();
    expect(
      find.byKey(const Key('teacher_access_pending_empty')),
      findsOneWidget,
    );
  });

  testWidgets('legacy Teacher waits are excluded from class requests', (
    tester,
  ) async {
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
    expect(find.text('Waiting for your teacher to accept you'), findsNothing);
    expect(controller.pendingJoinCount, 1);
  });

  testWidgets('approved legacy Teacher link is not rendered', (tester) async {
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
    expect(find.byKey(Key('teacher_access_evidence_${link.id}')), findsNothing);
    expect(find.text('Share saved images'), findsNothing);
    expect(find.text('Teachers not in a class'), findsNothing);
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

      final joinCard = tester.getRect(
        find.byKey(const Key('teacher_access_join_card')),
      );
      final pendingCard = tester.getRect(
        find.byKey(const Key('teacher_access_pending_card')),
      );
      expect(pendingCard.top, joinCard.top);
      expect(pendingCard.left, greaterThan(joinCard.right));
      expect(pendingCard.width, joinCard.width);
      expect(pendingCard.height, joinCard.height);
      expect(joinCard.height, lessThan(140));
      expect(pendingCard.height, lessThan(140));

      await tester.tap(find.byKey(const Key('teacher_access_join_toggle')));
      await tester.pumpAndSettle();
      final expandedJoinCard = tester.getRect(
        find.byKey(const Key('teacher_access_join_card')),
      );
      expect(expandedJoinCard.height, greaterThan(joinCard.height));

      await tester.tap(find.byKey(const Key('teacher_access_join_toggle')));
      await tester.pumpAndSettle();
      final collapsedJoinCard = tester.getRect(
        find.byKey(const Key('teacher_access_join_card')),
      );
      expect(collapsedJoinCard.height, joinCard.height);

      await tester.tap(find.byKey(const Key('teacher_access_pending_toggle')));
      await tester.pumpAndSettle();
      final expandedPendingCard = tester.getRect(
        find.byKey(const Key('teacher_access_pending_card')),
      );
      expect(expandedPendingCard.height, greaterThan(pendingCard.height));

      await tester.tap(find.byKey(const Key('teacher_access_pending_toggle')));
      await tester.pumpAndSettle();
      final collapsedPendingCard = tester.getRect(
        find.byKey(const Key('teacher_access_pending_card')),
      );
      expect(collapsedPendingCard.height, pendingCard.height);
    },
  );

  testWidgets(
    'join code field and Continue button share the same height on a wide layout',
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

      final fieldSize = tester.getSize(
        find.byKey(const Key('teacher_access_roster_code')),
      );
      final buttonSize = tester.getSize(
        find.byKey(const Key('teacher_access_resolve_code')),
      );
      expect(buttonSize.height, fieldSize.height);
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

  testWidgets('approved class card displays the teacher profile picture', (
    tester,
  ) async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    final membership = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    await groupRepository.approveMembership(
      membershipId: membership.id,
      teacherId: 'teacher-1',
    );

    await pumpAccess(
      tester,
      controller,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
    );
    profiles.emit(
      'teacher-1',
      const PublicProfile(
        userId: 'teacher-1',
        displayName: 'Grace Hopper',
        visibility: ProfileVisibility.public,
        profilePictureUrl: 'https://example.test/grace.png',
      ),
    );
    await tester.pump();

    final avatar = tester.widget<ProfileAvatarWidget>(
      find.byKey(Key('teacher_access_group_teacher_avatar_${group.id}')),
    );
    expect(avatar.networkImageUrl, 'https://example.test/grace.png');

    profiles.emit('teacher-1', null);
    await tester.pump();

    final fallbackAvatar = tester.widget<ProfileAvatarWidget>(
      find.byKey(Key('teacher_access_group_teacher_avatar_${group.id}')),
    );
    expect(fallbackAvatar.networkImageUrl, isNull);
    expect(fallbackAvatar.initials, 'GH');
  });

  testWidgets('Trainee can leave an approved class from its card menu', (
    tester,
  ) async {
    final group = await groupRepository.createGroup(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      name: 'BSHM 4A',
    );
    final invite = await groupRepository.getActiveGroupInvite(
      groupId: group.id,
    );
    final membership = await groupRepository.requestGroupJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      code: invite!.normalizedCode,
    );
    await groupRepository.approveMembership(
      membershipId: membership.id,
      teacherId: 'teacher-1',
    );

    await pumpAccess(
      tester,
      controller,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
      onOpenClass: (_) {},
    );

    await tester.tap(find.byKey(Key('class_card_more_${group.id}')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('teacher_access_leave_group_${membership.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Leave BSHM 4A?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('teacher_access_confirm_leave')));
    await tester.pumpAndSettle();

    expect(
      groupRepository.memberships[membership.id]?.status,
      GroupMembershipStatus.removed,
    );
    expect(find.byKey(Key('teacher_access_group_${group.id}')), findsNothing);
  });
}
