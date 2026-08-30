import 'dart:async';

import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/teacher_movement.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_assignment_composer.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _TrackingAssignments extends InMemoryClassroomAssignmentRepository {
  int officialCalls = 0;
  int teacherCreatedCalls = 0;
  Completer<void>? createGate;
  Object? teacherCreatedError;

  @override
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    String? displayInstructions,
  }) async {
    officialCalls++;
    final gate = createGate;
    if (gate != null) await gate.future;
    return super.createOfficialAssignment(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      officialMovementName: officialMovementName,
      dueAt: dueAt,
      displayInstructions: displayInstructions,
    );
  }

  @override
  Future<GroupAssignment> createTeacherCreatedAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    int maxScore = 100,
    DateTime? dueAt,
  }) async {
    teacherCreatedCalls++;
    final error = teacherCreatedError;
    if (error != null) throw error;
    return super.createTeacherCreatedAssignment(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      maxScore: maxScore,
      dueAt: dueAt,
    );
  }
}

class _RevisionReadFailureMovements extends InMemoryTeacherMovementRepository {
  bool failRevisionReads = false;

  @override
  Future<TeacherMovement> createMovement({
    required String teacherId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) async {
    final movement = await super.createMovement(
      teacherId: teacherId,
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
    );
    failRevisionReads = true;
    return movement;
  }

  @override
  Future<TeacherMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  }) {
    if (failRevisionReads) {
      throw StateError('revision read failed');
    }
    return super.getRevision(movementId: movementId, revisionId: revisionId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const group = ElixrGroup(
    id: 'group-1',
    teacherId: 'teacher-1',
    name: 'BSIT-4A',
    status: ElixrGroupStatus.active,
  );

  late InMemoryTeacherMovementRepository movements;
  late _TrackingAssignments assignments;

  setUp(() {
    movements = InMemoryTeacherMovementRepository();
    assignments = _TrackingAssignments();
  });

  tearDown(() {
    movements.dispose();
    assignments.dispose();
  });

  TeacherAssignmentCreationService service() =>
      TeacherAssignmentCreationService(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        assignmentRepository: assignments,
        movementRepository: movements,
      );

  Future<TeacherMovement> createTeacherMovement() {
    return movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Balance the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
  }

  test(
    'shared creation service forwards group, due date, and maximum score',
    () async {
      final dueAt = DateTime.utc(2026, 8, 31, 15, 59, 59, 999);
      final official = await service().create(
        group: group,
        officialMovement: movementCatalog.first,
        dueAt: dueAt,
      );
      expect(official.groupId, group.id);
      expect(official.groupName, group.name);
      expect(official.dueAt, dueAt);

      final customMovement = await createTeacherMovement();
      final custom = await service().create(
        group: group,
        teacherCreatedMovement: customMovement,
        maxScore: 75,
        dueAt: dueAt,
      );
      expect(custom.isTeacherCreated, isTrue);
      expect(custom.groupId, group.id);
      expect(custom.maxScore, 75);
      expect(custom.dueAt, dueAt);
    },
  );

  test(
    'shared creation service rejects an invalid teacher-created score',
    () async {
      final customMovement = await createTeacherMovement();

      await expectLater(
        service().create(
          group: group,
          teacherCreatedMovement: customMovement,
          maxScore: 101,
        ),
        throwsA(isA<Exception>()),
      );
      expect(assignments.teacherCreatedCalls, 0);
    },
  );

  test('shared creation service refreshes a stale movement snapshot', () async {
    final staleMovement = await createTeacherMovement();
    final editedMovement = await movements.editMovement(
      teacherId: 'teacher-1',
      movementId: staleMovement.id,
      title: 'Tin Balance Updated',
      instructions: 'Keep the tin upright throughout.',
      requiredProp: TrainingProp.bottle,
    );

    final assignment = await service().create(
      group: group,
      teacherCreatedMovement: staleMovement,
    );

    expect(assignment.revisionId, editedMovement.currentRevisionId);
    expect(assignment.displayInstructions, 'Keep the tin upright throughout.');
  });

  test(
    'shared creation service refreshes authorization before writing',
    () async {
      var authorizationChecks = 0;
      final guardedService = TeacherAssignmentCreationService(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        assignmentRepository: assignments,
        movementRepository: movements,
        ensureTeacherAuthorization: () async {
          authorizationChecks++;
          return true;
        },
      );

      await guardedService.create(
        group: group,
        officialMovement: movementCatalog.first,
      );

      expect(authorizationChecks, 1);
      expect(assignments.officialCalls, 1);
    },
  );

  Future<void> pumpComposer(
    WidgetTester tester, {
    required TeacherAssignmentCreationService creationService,
    Movement? officialMovement,
    TeacherMovement? teacherCreatedMovement,
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: TeacherAssignmentComposer(
          teacherId: 'teacher-1',
          teacherDisplayName: 'Grace Hopper',
          groups: const [group],
          movementRepository: movements,
          creationService: creationService,
          officialMovement: officialMovement,
          teacherCreatedMovement: teacherCreatedMovement,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('invalid maximum score disables the create action', (
    tester,
  ) async {
    final customMovement = await createTeacherMovement();
    await pumpComposer(
      tester,
      creationService: service(),
      teacherCreatedMovement: customMovement,
    );

    await tester.enterText(
      find.byKey(const Key('teacher_assignment_max_score')),
      '0',
    );
    await tester.pump();

    final createButton = tester.widget<ElixPrimaryButton>(
      find.byKey(const Key('teacher_assignment_create')),
    );
    expect(createButton.onPressed, isNull);
    expect(assignments.teacherCreatedCalls, 0);
  });

  testWidgets('assignment sources switch inside the responsive composer', (
    tester,
  ) async {
    final customMovement = await createTeacherMovement();
    await pumpComposer(tester, creationService: service());

    expect(find.text('Build a practice brief'), findsOneWidget);
    expect(find.byKey(const Key('teacher_assignment_form')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('teacher_assignment_custom_${customMovement.id}')),
      findsOneWidget,
    );
    expect(find.text('My Movements'), findsOneWidget);
  });

  testWidgets('movement management stays out of Assignment Studio', (
    tester,
  ) async {
    final customMovement = await createTeacherMovement();
    await pumpComposer(tester, creationService: service());

    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('teacher_assignment_custom_${customMovement.id}')),
      findsOneWidget,
    );
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('My Movement can create and select a new movement', (
    tester,
  ) async {
    await pumpComposer(tester, creationService: service());

    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('builder-title')), findsNothing);
    expect(find.byKey(const Key('teacher_assignment_movement')), findsNothing);
    await tester.tap(
      find.byKey(const Key('teacher_assignment_create_movement')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('builder-title')), findsOneWidget);
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
    final movement = movements.movements.values.single;
    expect(
      find.byKey(Key('teacher_assignment_custom_${movement.id}')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ElixPrimaryButton>(
            find.byKey(const Key('teacher_assignment_create')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('empty My Movement state has no blank assignment controls', (
    tester,
  ) async {
    await pumpComposer(tester, creationService: service());

    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('teacher_assignment_empty_movement_state')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('builder-title')), findsNothing);
    expect(find.byKey(const Key('teacher_assignment_movement')), findsNothing);
    expect(find.byKey(const Key('teacher_assignment_max_score')), findsNothing);
    expect(
      find.byKey(const Key('teacher_assignment_due_date_toggle')),
      findsNothing,
    );
  });

  testWidgets('quick-create reports a revision reload failure', (tester) async {
    movements.dispose();
    movements = _RevisionReadFailureMovements();
    await pumpComposer(tester, creationService: service());

    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();
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

    expect(find.byKey(const Key('teacher_assignment_error')), findsOneWidget);
    expect(
      find.textContaining('assignment details could not be loaded'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated clicks while creating make one repository write', (
    tester,
  ) async {
    assignments.createGate = Completer<void>();
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
    );

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_create')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_create')));
    await tester.pump();
    expect(assignments.officialCalls, 1);

    await tester.tap(find.byKey(const Key('teacher_assignment_create')));
    await tester.pump();
    expect(assignments.officialCalls, 1);

    assignments.createGate!.complete();
    await tester.pumpAndSettle();
    expect(assignments.assignments, hasLength(1));
  });

  testWidgets('the full-page composer fits the optional due date control', (
    tester,
  ) async {
    final customMovement = await createTeacherMovement();
    await pumpComposer(
      tester,
      creationService: service(),
      teacherCreatedMovement: customMovement,
    );

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_due_date_toggle')),
    );
    await tester.tap(
      find.byKey(const Key('teacher_assignment_due_date_toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('teacher_assignment_due_date')),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Assignment Studio reflows without overflow on a narrow window', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
      size: const Size(760, 900),
    );

    expect(find.byKey(const Key('teacher_assignment_form')), findsOneWidget);
    expect(find.byKey(const Key('teacher_assignment_summary')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assignment errors render in the full-page composer', (
    tester,
  ) async {
    final customMovement = await createTeacherMovement();
    assignments.teacherCreatedError = StateError('write failed');
    await pumpComposer(
      tester,
      creationService: service(),
      teacherCreatedMovement: customMovement,
    );

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_create')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_create')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('teacher_assignment_error')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
