import 'dart:async';
import 'dart:ui';

import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_application/core/widgets/movement_image.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/teacher_movement.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/teacher_movement_revision_spec.dart';
import 'package:elixr_application/data/models/teacher_reviewed_movement_spec.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movement_builder_dialog.dart';
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
  TeacherActivityAssessmentConfig? lastAssessment;

  @override
  Future<TeacherMovement> createMovement({
    required String teacherId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
    TeacherActivityAssessmentConfig? assessment,
  }) {
    createCalls += 1;
    lastAssessment = assessment;
    return super.createMovement(
      teacherId: teacherId,
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: assessment,
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
    TeacherActivityAssessmentConfig? assessment,
  }) {
    editCalls += 1;
    lastAssessment = assessment;
    return super.editMovement(
      teacherId: teacherId,
      movementId: movementId,
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: assessment,
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
    TeacherReviewedSaveCallback? onCreate,
    TeacherActivitySaveCallback? onCreateActivity,
    Size size = const Size(1280, 900),
    FluentThemeData? theme,
    TextScaler? textScaler,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      FluentApp(
        theme: theme ?? AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: TeacherMovementBuilderDialog(
          existing: existing,
          existingRevision: existingRevision,
          onCreateTeacherReviewed:
              onCreate ??
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
          onCreateActivity: onCreateActivity,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: TeacherMovementsScreen(controller: controller),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('builder exposes only teacher-reviewed fields', (tester) async {
    await pumpBuilder(tester);

    expect(find.text('Teacher reviewed'), findsOneWidget);
    expect(find.textContaining('No automatic ELIXR score'), findsOneWidget);
    expect(find.byKey(const ValueKey('builder-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('builder-instructions')), findsOneWidget);
    expect(find.byKey(const ValueKey('builder-safety')), findsOneWidget);
    expect(find.bySemanticsLabel('Title'), findsOneWidget);
    expect(find.bySemanticsLabel('Instructions'), findsOneWidget);
    expect(find.bySemanticsLabel('Required prop'), findsOneWidget);
    expect(find.bySemanticsLabel('Guidance for trainees'), findsOneWidget);
    expect(find.bySemanticsLabel('Hand readiness'), findsOneWidget);
    expect(find.bySemanticsLabel('Body readiness'), findsOneWidget);
    expect(find.bySemanticsLabel('Rubric template'), findsOneWidget);
    expect(find.bySemanticsLabel('Maximum score'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('builder-rubric-criteria-table')),
      findsOneWidget,
    );
    expect(find.text('What the Teacher assesses'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.bySemanticsLabel('Default attempts'), findsNothing);
    expect(find.bySemanticsLabel('Recording duration'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('builder-demo-media-placeholder')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('builder-demo-upload')), findsOneWidget);
    expect(find.byKey(const ValueKey('builder-demo-record')), findsOneWidget);
    expect(find.text('Template scored'), findsNothing);
    expect(find.text('Live Test'), findsNothing);
    expect(find.text('Create'), findsOneWidget);

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

  testWidgets('builder forwards a valid Teacher Activity assessment', (
    tester,
  ) async {
    TeacherActivityAssessmentConfig? saved;
    await pumpBuilder(
      tester,
      onCreateActivity:
          ({
            required title,
            required instructions,
            required requiredProp,
            required assessment,
            safetyGuidance,
          }) async {
            saved = assessment;
          },
    );
    await tester.enterText(
      find.byKey(const ValueKey('builder-title')),
      'Tin Balance',
    );
    await tester.enterText(
      find.byKey(const ValueKey('builder-instructions')),
      'Balance the tin upright.',
    );
    await tester.tap(find.byKey(const ValueKey('teacher-reviewed-save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.rubric.maximumScore, 50);
    expect(saved!.recordingDurationSeconds, 30);
  });

  testWidgets('builder validates a custom maximum score before saving', (
    tester,
  ) async {
    await pumpBuilder(tester);
    await tester.enterText(
      find.byKey(const ValueKey('builder-title')),
      'Tin Balance',
    );
    await tester.enterText(
      find.byKey(const ValueKey('builder-instructions')),
      'Balance the tin upright.',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('builder-max-score-preset')),
    );
    await tester.tap(find.byKey(const ValueKey('builder-max-score-preset')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom maximum score').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('builder-custom-max-score')),
      '101',
    );
    await tester.tap(find.byKey(const ValueKey('teacher-reviewed-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('builder-validation')), findsOneWidget);
    expect(
      find.text('Choose a valid maximum score from 1 to 100.'),
      findsOneWidget,
    );
    expect(movements.createCalls, 0);
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

    expect(find.text('Teacher reviewed'), findsOneWidget);
    expect(find.text('Save revision'), findsOneWidget);
    expect(find.text('Template scored'), findsNothing);
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
  });

  testWidgets('builder prevents duplicate saves while creation is in flight', (
    tester,
  ) async {
    final gate = Completer<void>();
    var calls = 0;
    await pumpBuilder(
      tester,
      onCreate:
          ({
            required title,
            required instructions,
            required requiredProp,
            safetyGuidance,
          }) async {
            calls++;
            await gate.future;
          },
    );
    await tester.enterText(
      find.byKey(const ValueKey('builder-title')),
      'Tin Balance',
    );
    await tester.enterText(
      find.byKey(const ValueKey('builder-instructions')),
      'Balance the tin upright.',
    );

    await tester.tap(find.byKey(const ValueKey('teacher-reviewed-save')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('teacher-reviewed-save')));
    await tester.pump();

    expect(calls, 1);
    expect(
      tester
          .widget<ElixPrimaryButton>(
            find.byKey(const ValueKey('teacher-reviewed-save')),
          )
          .isLoading,
      isTrue,
    );

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'builder keeps validation local and does not submit invalid data',
    (tester) async {
      await pumpBuilder(tester);

      await tester.tap(find.byKey(const ValueKey('teacher-reviewed-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('builder-validation')), findsOneWidget);
      expect(find.textContaining('Title'), findsAtLeastNWidgets(1));
      expect(movements.createCalls, 0);
    },
  );

  testWidgets('builder saves the selected prop and optional safety guidance', (
    tester,
  ) async {
    await pumpBuilder(tester);
    await tester.enterText(
      find.byKey(const ValueKey('builder-title')),
      'Shaker Pass',
    );
    await tester.enterText(
      find.byKey(const ValueKey('builder-instructions')),
      'Pass the shaker cleanly between hands.',
    );
    await tester.ensureVisible(find.text('Bottle').last);
    await tester.tap(find.text('Bottle').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cocktail Shaker').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('builder-safety')));
    await tester.enterText(
      find.byKey(const ValueKey('builder-safety')),
      'Keep the floor dry.',
    );

    await tester.tap(find.byKey(const ValueKey('teacher-reviewed-save')));
    await tester.pumpAndSettle();

    final revision = movements.revisions.values.single;
    final spec = revision.spec as TeacherReviewedMovementSpec;
    expect(spec.requiredProp, TrainingProp.shaker);
    expect(spec.safetyGuidance, 'Keep the floor dry.');
  });

  testWidgets('builder keeps footer actions accessible in a compact window', (
    tester,
  ) async {
    await pumpBuilder(tester, size: const Size(720, 560));

    final save = find.byKey(const ValueKey('teacher-reviewed-save'));
    final initialSaveRect = tester.getRect(save);
    await tester.ensureVisible(find.byKey(const ValueKey('builder-safety')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('builder-safety')), findsOneWidget);
    expect(tester.getRect(save), initialSaveRect);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(560));
  });

  testWidgets(
    'builder uses a desktop two-column layout with bounded multiline fields',
    (tester) async {
      await pumpBuilder(tester, size: const Size(1366, 768));

      final practiceSetup = find.text('Practice setup');
      final safetyHeading = find.text('Safety guidance');
      final safetyField = find.byKey(const ValueKey('builder-safety'));
      final save = find.byKey(const ValueKey('teacher-reviewed-save'));
      final initialSafetyRect = tester.getRect(safetyField);

      expect(
        tester.getTopLeft(practiceSetup).dy,
        closeTo(tester.getTopLeft(safetyHeading).dy, 1),
      );
      expect(initialSafetyRect.bottom, lessThan(tester.getTopLeft(save).dy));

      await tester.enterText(
        safetyField,
        List<String>.filled(40, 'Keep the practice area clear.').join('\n'),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(tester.getRect(safetyField).height, initialSafetyRect.height);
      expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(768));
    },
  );

  testWidgets('builder collapses its lower form area at narrow widths', (
    tester,
  ) async {
    await pumpBuilder(tester, size: const Size(680, 900));

    expect(
      tester.getTopLeft(find.text('Safety guidance')).dy,
      greaterThan(tester.getTopLeft(find.text('Practice setup')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('builder preserves accessible footer actions at large text', (
    tester,
  ) async {
    await pumpBuilder(
      tester,
      size: const Size(720, 560),
      textScaler: const TextScaler.linear(1.5),
    );

    final save = find.byKey(const ValueKey('teacher-reviewed-save'));
    expect(tester.takeException(), isNull);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(560));
  });

  testWidgets('builder renders with light and high-contrast palettes', (
    tester,
  ) async {
    for (final theme in [
      AppTheme.light,
      AppTheme.dark,
      AppTheme.highContrastDark,
    ]) {
      await pumpBuilder(tester, theme: theme);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('builder-title')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('teacher-reviewed-save')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Official ELIXR list shows catalog movement images', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('Normal Grip'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MovementImage && widget.movementName == 'Normal Grip',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Teacher Activities library exposes its two curriculum sections',
    (tester) async {
      await pumpScreen(tester);

      expect(find.text('Official ELIXR'), findsOneWidget);
      expect(find.text('Teacher Activities'), findsAtLeastNWidgets(1));
      expect(find.text('Assignments'), findsNothing);
      expect(find.text('Reviews'), findsNothing);
      expect(find.byType(ToggleButton), findsNWidgets(2));
    },
  );

  testWidgets(
    'movement list clips cards below the persistent curriculum tabs',
    (tester) async {
      await pumpScreen(tester);

      final list = tester.widget<ListView>(find.byType(ListView).first);

      expect(list.clipBehavior, Clip.hardEdge);
    },
  );

  testWidgets(
    'Official movement Assign to class opens the shared studio and filters classes',
    (tester) async {
      groups.seedGroup(
        const ElixrGroup(
          id: 'active-group',
          teacherId: 'teacher-1',
          name: 'Active Class',
          status: ElixrGroupStatus.active,
        ),
      );
      groups.seedGroup(
        const ElixrGroup(
          id: 'archived-group',
          teacherId: 'teacher-1',
          name: 'Archived Class',
          status: ElixrGroupStatus.archived,
        ),
      );
      await pumpScreen(tester);

      await tester.tap(
        find.byKey(const Key('teacher_movement_assign_official_Normal Grip')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Assign to class'), findsOneWidget);
      expect(
        find.byKey(const Key('teacher_assignment_movement_title')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('teacher_assignment_source')), findsNothing);
      expect(find.text('Normal Grip'), findsAtLeastNWidgets(1));
      expect(find.text('Active Class'), findsAtLeastNWidgets(1));
      expect(find.text('Archived Class'), findsNothing);
    },
  );

  testWidgets('Teacher Activity Assign to class preserves Activity context', (
    tester,
  ) async {
    final movement = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Balance the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
    groups.seedGroup(
      const ElixrGroup(
        id: 'active-group',
        teacherId: 'teacher-1',
        name: 'Active Class',
        status: ElixrGroupStatus.active,
      ),
    );
    await pumpScreen(tester);
    await tester.tap(find.text('Teacher Activities').last);
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(Key('teacher_movement_assign_custom_${movement.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assign to class'), findsOneWidget);
    expect(find.text('Tin Balance'), findsAtLeastNWidgets(1));
    expect(find.byKey(const Key('teacher_assignment_source')), findsNothing);
    expect(find.byKey(const Key('teacher_assignment_max_score')), findsNothing);
  });

  testWidgets('Official ELIXR card lifts on hover', (tester) async {
    await pumpScreen(tester);
    final title = find.text('Normal Grip');
    final before = tester.getTopLeft(title);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(title));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(title).dy, lessThan(before.dy));
  });

  testWidgets('Official ELIXR hover does not lift when motion is reduced', (
    tester,
  ) async {
    await pumpScreen(tester, disableAnimations: true);
    final title = find.text('Normal Grip');
    final before = tester.getTopLeft(title);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(title));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(title).dy, before.dy);
  });

  testWidgets('Teacher Activities label persisted items as teacher reviewed', (
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
    await tester.tap(find.text('Teacher Activities').last);
    await tester.pumpAndSettle();

    expect(find.text('Tin Balance'), findsOneWidget);
    expect(
      find.text('Teacher-reviewed Activity · No automatic ELIXR score'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is MovementImage && widget.movementName == 'Tin Balance',
      ),
      findsOneWidget,
    );
    expect(find.text('Template scored'), findsNothing);
  });

  testWidgets('historical template movement is read-only in the builder', (
    tester,
  ) async {
    const movementId = 'legacy-movement';
    const revisionId = 'legacy-revision';
    const movement = TeacherMovement(
      id: movementId,
      teacherId: 'teacher-1',
      title: 'Historical Wrist Stall',
      status: TeacherMovementStatus.active,
      currentRevisionId: revisionId,
    );
    const revision = TeacherMovementRevision(
      id: revisionId,
      movementId: movementId,
      teacherId: 'teacher-1',
      assessmentMode: AssessmentMode.templateScored,
      spec: TemplateScoredRevisionSpec(
        instructions: 'Historical instructions.',
        requiredProp: TrainingProp.bottle,
        assessment: AssessmentSpec(laterality: AssessmentLaterality.either),
      ),
    );

    await pumpBuilder(tester, existing: movement, existingRevision: revision);

    expect(find.text('Historical template scoring'), findsOneWidget);
    expect(
      find.textContaining('Automatic template assessment has been retired'),
      findsOneWidget,
    );
    expect(find.text('Save revision'), findsNothing);
    expect(find.text('Template scored'), findsNothing);
    expect(
      tester
          .widget<TextBox>(find.byKey(const ValueKey('builder-title')))
          .enabled,
      isFalse,
    );
  });
}
