import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/features/teacher_access/teacher_access_controller.dart';
import 'package:elixr_application/features/teacher_access/teacher_access_section.dart';
import 'package:elixr_application/services/join_code_resolver.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../teacher/teacher_phase3_test_support.dart';

Future<void> pumpAccess(
  WidgetTester tester,
  TeacherAccessController controller, {
  required GroupRepository groupRepository,
  required JoinCodeResolver joinCodeResolver,
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
            child: TeacherAccessSection(controller: controller, isActive: true),
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
  late JoinCodeResolver joinCodeResolver;
  late TeacherAccessController controller;

  setUp(() async {
    relationshipRepository = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 16),
    );
    var groupCodeIndex = 0;
    const groupCodes = ['ABCD2345EFGH', 'ZZZZ2345YYYY', 'MNOP2345QRST'];
    groupRepository = InMemoryGroupRepository(
      generateNormalizedCode: () =>
          groupCodes[groupCodeIndex++ % groupCodes.length],
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
    );
  });

  tearDown(() {
    controller.dispose();
    relationshipRepository.dispose();
    groupRepository.dispose();
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

      expect(find.text('Waiting for class'), findsOneWidget);
      expect(find.text('My classes'), findsOneWidget);
      expect(find.text('Join a class'), findsOneWidget);
      expect(find.text('Waiting to join a class'), findsOneWidget);
      expect(find.text('Your classes'), findsOneWidget);
      expect(
        find.byKey(const Key('teacher_access_roster_code')),
        findsOneWidget,
      );
    },
  );

  testWidgets('each approved class lists only its own classmates', (
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

    final profiles = FakePublicProfileRepository();
    controller.dispose();
    controller = TeacherAccessController(
      relationshipRepository: relationshipRepository,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
      privateImageSavingEnabled: true,
      publicProfileRepository: profiles,
    );
    profiles.emitProfile(
      'trainee-2',
      const PublicProfile(
        userId: 'trainee-2',
        displayName: 'Alan Turing',
        visibility: ProfileVisibility.public,
        profilePictureUrl: 'https://example.test/alan.png',
      ),
    );

    await pumpAccess(
      tester,
      controller,
      groupRepository: groupRepository,
      joinCodeResolver: joinCodeResolver,
    );
    await tester.pump();

    expect(find.text('BSHM 4A'), findsOneWidget);
    expect(find.text('BSHM 4B'), findsOneWidget);
    expect(find.text('Ada Lovelace (you)'), findsNWidgets(2));
    expect(find.text('Alan Turing'), findsOneWidget);
    expect(
      find.byKey(Key('teacher_access_group_${groupA.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('teacher_access_group_${groupB.id}')),
      findsOneWidget,
    );
    expect(find.byType(ProfileAvatarWidget), findsNWidgets(3));
    expect(
      find.byKey(Key('teacher_access_classmate_avatar_${groupA.id}_trainee-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('teacher_access_classmate_avatar_${groupA.id}_trainee-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('teacher_access_classmate_avatar_${groupB.id}_trainee-1')),
      findsOneWidget,
    );

    final alanAvatar = tester.widget<ProfileAvatarWidget>(
      find.byKey(Key('teacher_access_classmate_avatar_${groupA.id}_trainee-2')),
    );
    expect(alanAvatar.initials, 'AT');
    expect(alanAvatar.networkImageUrl, 'https://example.test/alan.png');

    final adaAvatar = tester.widget<ProfileAvatarWidget>(
      find.byKey(Key('teacher_access_classmate_avatar_${groupA.id}_trainee-1')),
    );
    expect(adaAvatar.initials, 'AL');
    expect(adaAvatar.networkImageUrl, isNull);
  });
}
