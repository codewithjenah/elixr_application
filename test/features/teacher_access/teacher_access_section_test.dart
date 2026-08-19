import 'package:elixr_application/core/theme/app_theme.dart';
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
    groupRepository = InMemoryGroupRepository(
      generateNormalizedCode: () => 'ABCD2345EFGH',
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
    expect(find.text('Waiting for Teacher approval'), findsOneWidget);
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
}
