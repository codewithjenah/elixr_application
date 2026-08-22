import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/teacher_movement.dart';
import 'package:elixr_application/data/models/teacher_reviewed_movement_spec.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movement_builder_dialog.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movement_builder_draft.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movements_controller.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movements_screen.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _TrackingMovements extends InMemoryTeacherMovementRepository {
  int createCalls = 0;
  int editCalls = 0;
  int templateCreateCalls = 0;
  int templateEditCalls = 0;

  @override
  Future<TeacherMovement> createMovement({
    required String teacherId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) {
    createCalls += 1;
    return super.createMovement(
      teacherId: teacherId,
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
    );
  }

  @override
  Future<TeacherMovement> editMovement({
    required String teacherId,
    required String movementId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) {
    editCalls += 1;
    return super.editMovement(
      teacherId: teacherId,
      movementId: movementId,
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
    );
  }

  @override
  Future<TeacherMovement> createTemplateScoredMovement({
    required String teacherId,
    required String title,
    required String instructions,
    required AssessmentSpec assessment,
    String? safetyGuidance,
  }) {
    templateCreateCalls += 1;
    return super.createTemplateScoredMovement(
      teacherId: teacherId,
      title: title,
      instructions: instructions,
      assessment: assessment,
      safetyGuidance: safetyGuidance,
    );
  }

  @override
  Future<TeacherMovement> editTemplateScoredMovement({
    required String teacherId,
    required String movementId,
    required String title,
    required String instructions,
    required AssessmentSpec assessment,
    String? safetyGuidance,
  }) {
    templateEditCalls += 1;
    return super.editTemplateScoredMovement(
      teacherId: teacherId,
      movementId: movementId,
      title: title,
      instructions: instructions,
      assessment: assessment,
      safetyGuidance: safetyGuidance,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _TrackingMovements movements;
  late InMemoryGroupRepository groups;
  late InMemoryClassroomAssignmentRepository assignments;
  late TeacherMovementsController controller;

  setUp(() {
    movements = _TrackingMovements();
    groups = InMemoryGroupRepository();
    assignments = InMemoryClassroomAssignmentRepository();
    controller = TeacherMovementsController(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      groupRepository: groups,
      movementRepository: movements,
      assignmentRepository: assignments,
    );
  });

  tearDown(() {
    controller.dispose();
    movements.dispose();
    groups.dispose();
    assignments.dispose();
  });

  Future<void> pumpBuilder(
    WidgetTester tester, {
    TeacherMovement? existing,
    TeacherMovementRevision? existingRevision,
    void Function(TeacherLiveTestDraft draft)? onLiveTest,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: TeacherMovementBuilderDialog(
          existing: existing,
          existingRevision: existingRevision,
          onCreateTeacherReviewed:
              ({
                required title,
                required instructions,
                required requiredProp,
                safetyGuidance,
              }) => controller.createMovement(
                title: title,
                instructions: instructions,
                requiredProp: requiredProp,
                safetyGuidance: safetyGuidance,
              ),
          onEditTeacherReviewed: existing == null
              ? null
              : ({
                  required title,
                  required instructions,
                  required requiredProp,
                  safetyGuidance,
                }) => controller.editMovement(
                  movement: existing,
                  title: title,
                  instructions: instructions,
                  requiredProp: requiredProp,
                  safetyGuidance: safetyGuidance,
                ),
          onCreateTemplateScored:
              ({
                required title,
                required instructions,
                required assessmentSpec,
                safetyGuidance,
              }) => controller.createTemplateScoredMovement(
                title: title,
                instructions: instructions,
                assessment: assessmentSpec,
                safetyGuidance: safetyGuidance,
              ),
          onEditTemplateScored: existing == null
              ? null
              : ({
                  required title,
                  required instructions,
                  required assessmentSpec,
                  safetyGuidance,
                }) => controller.editTemplateScoredMovement(
                  movement: existing,
                  title: title,
                  instructions: instructions,
                  assessment: assessmentSpec,
                  safetyGuidance: safetyGuidance,
                ),
          onOpenLiveTest: onLiveTest,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await controller.start();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider<GroupRepository>.value(value: groups)],
        child: FluentApp(
          theme: AppTheme.dark,
          home: TeacherMovementsScreen(controller: controller),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('teacher reviewed remains the default create path', (
    tester,
  ) async {
    await pumpBuilder(tester);

    expect(find.text('Teacher reviewed'), findsWidgets);
    expect(find.textContaining('No automatic ELIXR score'), findsWidgets);
    expect(find.text('Template scored'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Live Test'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('builder-title')),
      'Tin Balance',
    );
    await tester.enterText(
      find.byKey(const ValueKey('builder-instructions')),
      'Balance the tin upright.',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(movements.createCalls, 1);
    expect(movements.movements.values.single.title, 'Tin Balance');
    expect(
      movements.revisions.values.single.assessmentMode,
      AssessmentMode.teacherReviewed,
    );
  });

  testWidgets('template scored shows only Wrist Stall and locked Bottle', (
    tester,
  ) async {
    await pumpBuilder(tester);

    await tester.tap(
      find.byKey(const ValueKey('assessment-method-template-scored')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Balance / Stall'), findsOneWidget);
    expect(find.text('Wrist Stall'), findsOneWidget);
    expect(find.text('Bottle'), findsWidgets);
    expect(find.text('Either wrist'), findsOneWidget);
    expect(find.text('Left wrist'), findsOneWidget);
    expect(find.text('Right wrist'), findsOneWidget);
    expect(find.textContaining('performer\'s own body'), findsOneWidget);
    expect(find.text('Cocktail Shaker'), findsNothing);
    expect(find.text('Bottle + Shaker'), findsNothing);
    expect(find.text('Grip'), findsNothing);
    expect(find.text('Basic Toss'), findsNothing);
    expect(find.text('Live Test'), findsOneWidget);
    expect(find.byKey(const ValueKey('template-scored-save')), findsOneWidget);
    expect(find.textContaining('threshold'), findsNothing);
    expect(find.textContaining('confidence'), findsNothing);
    expect(find.textContaining('proximity'), findsNothing);
    expect(find.textContaining('hold seconds'), findsNothing);
    expect(find.textContaining('YOLO'), findsNothing);
    expect(
      find.textContaining(
        'Template results are classroom assessment data and do not award global XP',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('Classroom results do not award global XP'),
      findsOneWidget,
    );
  });

  testWidgets(
    'template laterality builds the exact AssessmentSpec for Live Test',
    (tester) async {
      TeacherLiveTestDraft? opened;
      await pumpBuilder(tester, onLiveTest: (draft) => opened = draft);

      await tester.tap(
        find.byKey(const ValueKey('assessment-method-template-scored')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('builder-title')),
        'Wrist Stall check',
      );
      await tester.enterText(
        find.byKey(const ValueKey('builder-instructions')),
        'Hold the bottle still.',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('laterality-right')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('laterality-right')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('template-live-test')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('template-live-test')));
      await tester.pumpAndSettle();

      expect(movements.createCalls, 0);
      expect(opened, isNotNull);
      expect(
        opened!.assessmentSpec,
        const AssessmentSpec(laterality: AssessmentLaterality.right),
      );
      expect(opened!.title, 'Wrist Stall check');
    },
  );

  testWidgets('template mode never invokes teacher-reviewed createMovement', (
    tester,
  ) async {
    await pumpBuilder(tester);
    await tester.tap(
      find.byKey(const ValueKey('assessment-method-template-scored')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('builder-title')),
      'Classroom Wrist Stall',
    );
    await tester.enterText(
      find.byKey(const ValueKey('builder-instructions')),
      'Balance the bottle on the wrist.',
    );
    await tester.tap(find.byKey(const ValueKey('template-scored-save')));
    await tester.pumpAndSettle();
    expect(movements.createCalls, 0);
    expect(movements.templateCreateCalls, 1);
    expect(
      movements.revisions.values.single.assessmentMode,
      AssessmentMode.templateScored,
    );
  });

  testWidgets('existing edit flow remains teacher reviewed', (tester) async {
    final existing = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Balance the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
    final revision = await movements.getRevision(
      movementId: existing.id,
      revisionId: existing.currentRevisionId,
    );

    await pumpBuilder(tester, existing: existing, existingRevision: revision);

    expect(find.text('Teacher reviewed'), findsWidgets);
    expect(find.text('Template scored'), findsNothing);
    expect(find.text('Save revision'), findsOneWidget);
    expect(find.text('Live Test'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('builder-instructions')),
      'Revised tin balance.',
    );
    await tester.tap(find.text('Save revision'));
    await tester.pumpAndSettle();

    expect(movements.editCalls, 1);
    expect(
      movements.revisions.values.last.spec,
      isA<TeacherReviewedMovementSpec>(),
    );
    expect(
      movements.revisions.values.last.assessmentMode,
      AssessmentMode.teacherReviewed,
    );
  });

  testWidgets('My Movements still labels persisted items as teacher reviewed', (
    tester,
  ) async {
    await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Balance the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
    groups.seedGroup(
      const ElixrGroup(
        id: 'g1',
        teacherId: 'teacher-1',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
    );
    await pumpScreen(tester);
    await tester.tap(find.text('My Movements'));
    await tester.pumpAndSettle();

    expect(find.text('Tin Balance'), findsOneWidget);
    expect(
      find.text('Teacher reviewed · No automatic ELIXR score'),
      findsOneWidget,
    );
    expect(find.textContaining('Template scored'), findsNothing);
    expect(find.text('Wrist Stall'), findsNothing);
  });
}
