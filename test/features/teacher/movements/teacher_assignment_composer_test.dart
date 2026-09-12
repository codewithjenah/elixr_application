import 'dart:async';
import 'dart:io';

import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/elix_primary_button.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/assignment_attempt_policy.dart';
import 'package:elixr_application/data/models/activity_learning_material.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/teacher_movement.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/data/repositories/activity_learning_material_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_assignment_composer.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

class _TrackingAssignments extends InMemoryClassroomAssignmentRepository {
  _TrackingAssignments({required InMemoryGroupRepository groupRepository})
    : super(groupRepository: groupRepository);

  int officialCalls = 0;
  int teacherCreatedCalls = 0;
  Completer<void>? createGate;
  Object? teacherCreatedError;
  AssignmentAudience? lastAudience;
  TrainingProp? lastAllowedProp;
  TeacherActivityAssessmentConfig? lastActivityAssessment;
  String? lastDisplayTitle;
  String? lastDisplayInstructions;
  String? lastDisplaySafetyGuidance;
  DateTime? lastPublishAt;
  DateTime? lastDueAt;

  @override
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    required TrainingProp allowedProp,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    String? displayInstructions,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.legacyDefault,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) async {
    officialCalls++;
    lastAudience = audience;
    lastAllowedProp = allowedProp;
    lastPublishAt = publishAt;
    lastDueAt = dueAt;
    final gate = createGate;
    if (gate != null) await gate.future;
    return super.createOfficialAssignment(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      officialMovementName: officialMovementName,
      allowedProp: allowedProp,
      dueAt: dueAt,
      status: status,
      publishAt: publishAt,
      displayInstructions: displayInstructions,
      attemptPolicy: attemptPolicy,
      audience: audience,
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
    TeacherActivityAssessmentConfig? activityAssessment,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.teacherActivityDefault,
    String? displayTitle,
    String? displayInstructions,
    String? displaySafetyGuidance,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) async {
    teacherCreatedCalls++;
    lastAudience = audience;
    lastActivityAssessment = activityAssessment;
    lastPublishAt = publishAt;
    lastDueAt = dueAt;
    lastDisplayTitle = displayTitle;
    lastDisplayInstructions = displayInstructions;
    lastDisplaySafetyGuidance = displaySafetyGuidance;
    final error = teacherCreatedError;
    if (error != null) throw error;
    return super.createTeacherCreatedAssignment(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      maxScore: maxScore,
      activityAssessment: activityAssessment,
      attemptPolicy: attemptPolicy,
      displayTitle: displayTitle,
      displayInstructions: displayInstructions,
      displaySafetyGuidance: displaySafetyGuidance,
      dueAt: dueAt,
      status: status,
      publishAt: publishAt,
      audience: audience,
    );
  }
}

class _SafetyFailureAssignments extends _TrackingAssignments {
  _SafetyFailureAssignments({required super.groupRepository});

  @override
  Future<bool> hasTraineeWork({required String assignmentId}) {
    throw StateError('temporary safety lookup failure');
  }
}

class _TraineeWorkAssignments extends _TrackingAssignments {
  _TraineeWorkAssignments({required super.groupRepository});

  @override
  Future<bool> hasTraineeWork({required String assignmentId}) async => true;
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
    TeacherActivityAssessmentConfig? assessment,
  }) async {
    final movement = await super.createMovement(
      teacherId: teacherId,
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: assessment,
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

class _MaterialRepository implements ActivityLearningMaterialRepository {
  final List<String> listedAssignmentIds = [];
  final List<String> linkedAssignmentIds = [];
  final List<String> removedMaterialIds = [];
  List<ActivityLearningMaterial> materials = const [];
  bool failList = false;

  @override
  Future<ActivityLearningMaterial> addLink({
    required String assignmentId,
    required String displayName,
    required Uri url,
  }) {
    linkedAssignmentIds.add(assignmentId);
    return Future.value(
      ActivityLearningMaterial(
        id: 'link-${linkedAssignmentIds.length}',
        assignmentId: assignmentId,
        type: ActivityLearningMaterialType.link,
        displayName: displayName,
        externalUrl: url,
      ),
    );
  }

  @override
  Future<ActivityMaterialUpload> beginUpload({
    required String assignmentId,
    required ActivityLearningMaterialType type,
    required String displayName,
    required String declaredContentType,
    required int sizeBytes,
  }) => throw UnimplementedError();

  @override
  Future<ActivityMaterialUploadStatus> getUploadStatus({
    required String uploadId,
  }) => throw UnimplementedError();

  @override
  Future<List<ActivityLearningMaterial>> list({required String assignmentId}) {
    listedAssignmentIds.add(assignmentId);
    if (failList) return Future.error(StateError('material load failed'));
    return Future.value(materials);
  }

  @override
  Future<File> openFile(ActivityLearningMaterial material) =>
      throw UnimplementedError();

  @override
  Future<void> remove({
    required String assignmentId,
    required String materialId,
  }) async {
    removedMaterialIds.add(materialId);
    materials = materials
        .where((material) => material.id != materialId)
        .toList();
  }

  @override
  Future<void> uploadStagedFile({
    required ActivityMaterialUpload upload,
    required File file,
  }) => throw UnimplementedError();
}

Future<void> _enablePublicationScheduling(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const Key('teacher_assignment_schedule_toggle')),
  );
  await tester.tap(find.byKey(const Key('teacher_assignment_schedule_toggle')));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const group = ElixrGroup(
    id: 'group-1',
    teacherId: 'teacher-1',
    name: 'BSIT-4A',
    status: ElixrGroupStatus.active,
  );
  const otherGroup = ElixrGroup(
    id: 'group-2',
    teacherId: 'teacher-1',
    name: 'BSIT-4B',
    status: ElixrGroupStatus.active,
  );

  late InMemoryTeacherMovementRepository movements;
  late InMemoryGroupRepository groups;
  late _TrackingAssignments assignments;

  setUp(() {
    var movementId = 0;
    movements = InMemoryTeacherMovementRepository(
      generateId: () => 'movement-${++movementId}',
    );
    groups = InMemoryGroupRepository();
    groups.seedGroup(group);
    groups.seedGroup(otherGroup);
    for (final trainee in const [
      ('trainee-1', 'Ada Lovelace'),
      ('trainee-2', 'Katherine Johnson'),
      ('trainee-3', 'Alan Turing'),
    ]) {
      groups.seedMembership(
        GroupMembership(
          id: GroupMembership.documentId(
            groupId: group.id,
            traineeId: trainee.$1,
          ),
          groupId: group.id,
          teacherId: group.teacherId,
          traineeId: trainee.$1,
          traineeDisplayName: trainee.$2,
          teacherDisplayName: 'Grace Hopper',
          status: GroupMembershipStatus.approved,
        ),
      );
    }
    groups.seedMembership(
      GroupMembership(
        id: GroupMembership.documentId(
          groupId: otherGroup.id,
          traineeId: 'trainee-4',
        ),
        groupId: otherGroup.id,
        teacherId: otherGroup.teacherId,
        traineeId: 'trainee-4',
        traineeDisplayName: 'Margaret Hamilton',
        teacherDisplayName: 'Grace Hopper',
        status: GroupMembershipStatus.approved,
      ),
    );
    assignments = _TrackingAssignments(groupRepository: groups);
  });

  tearDown(() {
    movements.dispose();
    groups.dispose();
    assignments.dispose();
  });

  TeacherAssignmentCreationService service() =>
      TeacherAssignmentCreationService(
        teacherId: 'teacher-1',
        teacherDisplayName: 'Grace Hopper',
        assignmentRepository: assignments,
        movementRepository: movements,
        groupRepository: groups,
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
    'official Body Grip, Wrist Stall, and Double Forearm persist exact props',
    () async {
      Movement byName(String name) =>
          movementCatalog.firstWhere((movement) => movement.name == name);

      final body = await service().create(
        group: group,
        officialMovement: byName('Body Grip'),
        officialAllowedProp: TrainingProp.bottle,
      );
      expect(body.officialMovementName, 'Body Grip');
      expect(body.allowedProp, TrainingProp.bottle);

      final wristBottle = await service().create(
        group: group,
        officialMovement: byName('Wrist Stall'),
        officialAllowedProp: TrainingProp.bottle,
      );
      expect(wristBottle.officialMovementName, 'Wrist Stall');
      expect(wristBottle.allowedProp, TrainingProp.bottle);

      final wristShaker = await service().create(
        group: group,
        officialMovement: byName('Wrist Stall'),
        officialAllowedProp: TrainingProp.shaker,
      );
      expect(wristShaker.allowedProp, TrainingProp.shaker);

      final doubleForearm = await service().create(
        group: group,
        officialMovement: byName('Double Forearm Stall'),
        officialAllowedProp: TrainingProp.bottle,
      );
      expect(doubleForearm.officialMovementName, 'Double Forearm Stall');
      expect(doubleForearm.allowedProp, TrainingProp.bottle);

      await expectLater(
        service().create(
          group: group,
          officialMovement: byName('Body Grip'),
          officialAllowedProp: TrainingProp.shaker,
        ),
        throwsA(isA<ClassroomException>()),
      );
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

  test(
    'shared creation service forwards and validates targeted audiences',
    () async {
      final selected = AssignmentAudience.selectedStudents(const [
        'trainee-1',
        'trainee-2',
      ]);

      final assignment = await service().create(
        group: group,
        audience: selected,
        officialMovement: movementCatalog.first,
      );

      expect(assignment.audience.type, AssignmentAudienceType.selectedStudents);
      expect(assignment.audience.targetTraineeIds, ['trainee-1', 'trainee-2']);
      expect(
        assignments.lastAudience?.targetTraineeIds,
        selected.targetTraineeIds,
      );

      final customMovement = await createTeacherMovement();
      final individual = await service().create(
        group: group,
        audience: AssignmentAudience.individualStudent(const ['trainee-1']),
        teacherCreatedMovement: customMovement,
      );
      expect(individual.isTeacherCreated, isTrue);
      expect(
        individual.audience.type,
        AssignmentAudienceType.individualStudent,
      );
      expect(individual.audience.targetTraineeIds, ['trainee-1']);

      await expectLater(
        service().create(
          group: group,
          audience: AssignmentAudience.individualStudent(const ['trainee-4']),
          officialMovement: movementCatalog.first,
        ),
        throwsA(isA<Exception>()),
      );
      expect(assignments.officialCalls, 1);
      expect(assignments.teacherCreatedCalls, 1);
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
        groupRepository: groups,
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
    TrainingProp? initialOfficialProp,
    TeacherMovement? teacherCreatedMovement,
    GroupAssignment? existingAssignment,
    List<ElixrGroup> availableGroups = const [group],
    ElixrGroup? lockedGroup,
    ActivityLearningMaterialRepository? materialRepository,
    Size size = const Size(1280, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ElixShadThemeBridge(
          child: TeacherAssignmentComposer(
            teacherId: 'teacher-1',
            teacherDisplayName: 'Grace Hopper',
            groups: availableGroups,
            movementRepository: movements,
            groupRepository: groups,
            lockedGroup: lockedGroup,
            creationService: creationService,
            officialMovement: officialMovement,
            initialOfficialProp: initialOfficialProp,
            teacherCreatedMovement: teacherCreatedMovement,
            existingAssignment: existingAssignment,
            materialRepository: materialRepository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (teacherCreatedMovement != null) {
      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_customize_activity')),
      );
      tester
          .widget<ToggleSwitch>(
            find.byKey(const Key('teacher_assignment_customize_activity')),
          )
          .onChanged!(true);
      await tester.pumpAndSettle();
    }
  }

  Future<DateTime> scheduleAt(
    WidgetTester tester, {
    required int hour,
    required int minute,
    required String period,
  }) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
    );
    await _enablePublicationScheduling(tester);
    final date = tester
        .widget<shad.ShadDatePicker>(
          find.byKey(const Key('teacher_assignment_publish_date')),
        )
        .selected!;
    final timePicker = tester.widget<shad.ShadTimePicker>(
      find.byKey(const Key('teacher_assignment_publish_time')),
    );
    expect(timePicker.showSeconds, isFalse);
    expect(timePicker.minHour, 1);
    expect(timePicker.maxHour, 12);
    expect(find.textContaining('Manila'), findsNothing);
    timePicker.onChanged!(
      shad.ShadTimeOfDay(
        hour: hour,
        minute: minute,
        second: 0,
        period: period == 'AM' ? shad.ShadDayPeriod.am : shad.ShadDayPeriod.pm,
      ),
    );
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_schedule')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_schedule')));
    await tester.pumpAndSettle();

    final publishAt = assignments.lastPublishAt;
    expect(publishAt, isNotNull);
    final displayedCivilTime = publishAt!.toUtc().add(const Duration(hours: 8));
    final expectedHour = switch (period) {
      'AM' => hour == 12 ? 0 : hour,
      _ => hour == 12 ? 12 : hour + 12,
    };
    expect(displayedCivilTime.year, date.year);
    expect(displayedCivilTime.month, date.month);
    expect(displayedCivilTime.day, date.day);
    expect(displayedCivilTime.hour, expectedHour);
    expect(displayedCivilTime.minute, minute);
    expect(
      assignments.assignments.values.single.status,
      GroupAssignmentStatus.scheduled,
    );
    return publishAt;
  }

  Future<void> enableDueDate(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_due_date_toggle')),
    );
    await tester.tap(
      find.byKey(const Key('teacher_assignment_due_date_toggle')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> saveDraft(WidgetTester tester) async {
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_save_draft')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_save_draft')));
    await tester.pumpAndSettle();
  }

  testWidgets('deadline time controls appear only after enabling a due date', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
    );

    expect(find.byKey(const Key('teacher_assignment_due_date')), findsNothing);
    expect(find.byKey(const Key('teacher_assignment_due_hour')), findsNothing);
    expect(
      find.byKey(const Key('teacher_assignment_due_minute')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('teacher_assignment_due_period')),
      findsNothing,
    );

    await enableDueDate(tester);

    final date = tester.widget<DatePicker>(
      find.byKey(const Key('teacher_assignment_due_date')),
    );
    final manilaNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    final expectedDate = DateTime(
      manilaNow.year,
      manilaNow.month,
      manilaNow.day,
    );
    expect(date.selected, expectedDate);
    expect(find.text('Default is today at 11:59 PM.'), findsOneWidget);
    expect(
      tester
          .widget<ComboBox<int>>(
            find.byKey(const Key('teacher_assignment_due_hour')),
          )
          .value,
      11,
    );
    expect(
      tester
          .widget<ComboBox<int>>(
            find.byKey(const Key('teacher_assignment_due_minute')),
          )
          .value,
      59,
    );
    expect(
      tester
          .widget<ComboBox<String>>(
            find.byKey(const Key('teacher_assignment_due_period')),
          )
          .value,
      'PM',
    );
  });

  testWidgets('deadline stores the selected Manila date and 12-hour time', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
    );
    await enableDueDate(tester);
    tester
        .widget<shad.ShadDatePicker>(
          find.byKey(const Key('teacher_assignment_due_date')),
        )
        .onChanged!(DateTime(2026, 9, 15));
    tester
        .widget<shad.ShadTimePicker>(
          find.byKey(const Key('teacher_assignment_due_time')),
        )
        .onChanged!(
      const shad.ShadTimeOfDay(
        hour: 8,
        minute: 30,
        second: 0,
        period: shad.ShadDayPeriod.pm,
      ),
    );
    await tester.pump();

    await saveDraft(tester);
    expect(assignments.lastDueAt, DateTime.utc(2026, 9, 15, 12, 30));
  });

  testWidgets('deadline handles an AM minute and midnight conversion', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
    );
    await enableDueDate(tester);
    final dueDate = find.byKey(const Key('teacher_assignment_due_date'));
    tester.widget<DatePicker>(dueDate).onChanged!(DateTime(2026, 9, 16));
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_due_hour')),
        )
        .onChanged!(9);
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_due_minute')),
        )
        .onChanged!(7);
    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('teacher_assignment_due_period')),
        )
        .onChanged!('AM');
    await tester.pump();
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_due_hour')),
        )
        .onChanged!(12);
    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('teacher_assignment_due_period')),
        )
        .onChanged!('AM');
    await tester.pump();
    await saveDraft(tester);
    expect(assignments.lastDueAt, DateTime.utc(2026, 9, 15, 16, 7));
  });

  testWidgets('deadline converts 12 PM to Manila noon', (tester) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
    );
    await enableDueDate(tester);
    tester
        .widget<DatePicker>(
          find.byKey(const Key('teacher_assignment_due_date')),
        )
        .onChanged!(DateTime(2026, 9, 17));
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_due_hour')),
        )
        .onChanged!(12);
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_due_minute')),
        )
        .onChanged!(0);
    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('teacher_assignment_due_period')),
        )
        .onChanged!('PM');
    await tester.pump();
    await saveDraft(tester);
    expect(assignments.lastDueAt, DateTime.utc(2026, 9, 17, 4));
  });

  testWidgets(
    'deadline date and time changes preserve their other components',
    (tester) async {
      await pumpComposer(
        tester,
        creationService: service(),
        officialMovement: movementCatalog.first,
      );
      await enableDueDate(tester);
      final date = find.byKey(const Key('teacher_assignment_due_date'));
      tester.widget<DatePicker>(date).onChanged!(DateTime(2026, 9, 18));
      tester
          .widget<ComboBox<int>>(
            find.byKey(const Key('teacher_assignment_due_hour')),
          )
          .onChanged!(8);
      tester
          .widget<ComboBox<int>>(
            find.byKey(const Key('teacher_assignment_due_minute')),
          )
          .onChanged!(30);
      tester
          .widget<ComboBox<String>>(
            find.byKey(const Key('teacher_assignment_due_period')),
          )
          .onChanged!('PM');
      await tester.pump();
      tester.widget<DatePicker>(date).onChanged!(DateTime(2026, 9, 19));
      await tester.pump();
      expect(
        tester
            .widget<ComboBox<int>>(
              find.byKey(const Key('teacher_assignment_due_hour')),
            )
            .value,
        8,
      );
      expect(
        tester
            .widget<ComboBox<int>>(
              find.byKey(const Key('teacher_assignment_due_minute')),
            )
            .value,
        30,
      );
      expect(
        tester
            .widget<ComboBox<String>>(
              find.byKey(const Key('teacher_assignment_due_period')),
            )
            .value,
        'PM',
      );
      await saveDraft(tester);
      expect(assignments.lastDueAt, DateTime.utc(2026, 9, 19, 12, 30));
    },
  );

  testWidgets('editing initializes deadline controls from the stored instant', (
    tester,
  ) async {
    final existing = await service().create(
      group: group,
      officialMovement: movementCatalog.first,
      dueAt: DateTime.utc(2026, 9, 15, 12, 30),
    );
    await pumpComposer(
      tester,
      creationService: service(),
      existingAssignment: existing,
    );

    final date = tester.widget<DatePicker>(
      find.byKey(const Key('teacher_assignment_due_date')),
    );
    expect(date.selected, DateTime(2026, 9, 15));
    expect(
      tester
          .widget<ComboBox<int>>(
            find.byKey(const Key('teacher_assignment_due_hour')),
          )
          .value,
      8,
    );
    expect(
      tester
          .widget<ComboBox<int>>(
            find.byKey(const Key('teacher_assignment_due_minute')),
          )
          .value,
      30,
    );
    expect(
      tester
          .widget<ComboBox<String>>(
            find.byKey(const Key('teacher_assignment_due_period')),
          )
          .value,
      'PM',
    );
  });

  testWidgets('disabling a deadline saves a null dueAt', (tester) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
    );
    await enableDueDate(tester);
    await tester.tap(
      find.byKey(const Key('teacher_assignment_due_date_toggle')),
    );
    await tester.pump();
    await saveDraft(tester);
    expect(assignments.lastDueAt, isNull);
  });

  testWidgets(
    'publication scheduling is optional and reveals controls only when enabled',
    (tester) async {
      await pumpComposer(
        tester,
        creationService: service(),
        officialMovement: movementCatalog.first,
      );

      expect(
        find.byKey(const Key('teacher_assignment_schedule_toggle')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_assignment_publish_date')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('teacher_assignment_publish_hour')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('teacher_assignment_publish_minute')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('teacher_assignment_publish_period')),
        findsNothing,
      );
      expect(
        tester
            .widget<Button>(
              find.byKey(const Key('teacher_assignment_schedule')),
            )
            .onPressed,
        isNull,
      );

      await _enablePublicationScheduling(tester);
      expect(
        find.byKey(const Key('teacher_assignment_publish_date')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_assignment_publish_hour')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_assignment_publish_minute')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_assignment_publish_period')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('teacher_assignment_schedule_toggle')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('teacher_assignment_publish_date')),
        findsNothing,
      );
    },
  );

  testWidgets('Save Draft omits publishAt when scheduling is off', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
    );
    await saveDraft(tester);
    expect(assignments.lastPublishAt, isNull);
    expect(
      assignments.assignments.values.single.status,
      GroupAssignmentStatus.draft,
    );
  });

  testWidgets('Publish Now omits publishAt when scheduling is off', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
    );
    final publish = find.byKey(const Key('teacher_assignment_publish_now'));
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pumpAndSettle();

    expect(assignments.lastPublishAt, isNull);
    expect(
      assignments.assignments.values.single.status,
      GroupAssignmentStatus.active,
    );
  });

  testWidgets('scheduled publication requires an exact later deadline', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
    );
    await _enablePublicationScheduling(tester);
    final publishDate = tester
        .widget<DatePicker>(
          find.byKey(const Key('teacher_assignment_publish_date')),
        )
        .selected!;
    await enableDueDate(tester);
    tester
        .widget<DatePicker>(
          find.byKey(const Key('teacher_assignment_due_date')),
        )
        .onChanged!(publishDate);
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_due_hour')),
        )
        .onChanged!(9);
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_due_minute')),
        )
        .onChanged!(0);
    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('teacher_assignment_due_period')),
        )
        .onChanged!('AM');
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_schedule')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_schedule')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('teacher_assignment_error')), findsOneWidget);
    expect(assignments.lastPublishAt, isNull);

    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_due_minute')),
        )
        .onChanged!(1);
    await tester.pump();
    await tester.tap(find.byKey(const Key('teacher_assignment_schedule')));
    await tester.pumpAndSettle();
    expect(assignments.lastPublishAt, isNotNull);
  });

  testWidgets('scheduled publication converts 12:00 AM to hour zero', (
    tester,
  ) async {
    final midnight = await scheduleAt(
      tester,
      hour: 12,
      minute: 0,
      period: 'AM',
    );
    expect(midnight.toUtc().add(const Duration(hours: 8)).hour, 0);
  });

  testWidgets('scheduled publication converts 12:00 PM to hour twelve', (
    tester,
  ) async {
    final noon = await scheduleAt(tester, hour: 12, minute: 0, period: 'PM');
    expect(noon.toUtc().add(const Duration(hours: 8)).hour, 12);
  });

  testWidgets('scheduled publication converts 1:30 PM to hour thirteen', (
    tester,
  ) async {
    final afternoon = await scheduleAt(
      tester,
      hour: 1,
      minute: 30,
      period: 'PM',
    );
    final afternoonCivil = afternoon.toUtc().add(const Duration(hours: 8));
    expect(afternoonCivil.hour, 13);
    expect(afternoonCivil.minute, 30);
  });

  testWidgets('scheduled publication preserves arbitrary selected minutes', (
    tester,
  ) async {
    final scheduled = await scheduleAt(
      tester,
      hour: 9,
      minute: 7,
      period: 'AM',
    );
    expect(scheduled.toUtc().add(const Duration(hours: 8)).minute, 7);
  });

  testWidgets('Teacher Activity scheduler exposes every minute', (
    tester,
  ) async {
    final customMovement = await createTeacherMovement();
    await pumpComposer(
      tester,
      creationService: service(),
      teacherCreatedMovement: customMovement,
    );
    await _enablePublicationScheduling(tester);

    final minuteBox = tester.widget<ComboBox<int>>(
      find.byKey(const Key('teacher_assignment_publish_minute')),
    );
    expect(
      minuteBox.items!.map((item) => item.value),
      orderedEquals(List<int>.generate(60, (index) => index)),
    );
  });

  testWidgets('Teacher Activity scheduling preserves an arbitrary minute', (
    tester,
  ) async {
    final customMovement = await createTeacherMovement();
    await pumpComposer(
      tester,
      creationService: service(),
      teacherCreatedMovement: customMovement,
    );
    await _enablePublicationScheduling(tester);
    final date = tester
        .widget<DatePicker>(
          find.byKey(const Key('teacher_assignment_publish_date')),
        )
        .selected!;

    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_publish_hour')),
        )
        .onChanged!(11);
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_publish_minute')),
        )
        .onChanged!(59);
    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('teacher_assignment_publish_period')),
        )
        .onChanged!('PM');
    await tester.pump();

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_schedule')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_schedule')));
    await tester.pumpAndSettle();

    expect(
      assignments.lastPublishAt,
      DateTime.utc(date.year, date.month, date.day, 15, 59),
    );
  });

  testWidgets('invalid maximum score disables the create action', (
    tester,
  ) async {
    final customMovement = await createTeacherMovement();
    await pumpComposer(
      tester,
      creationService: service(),
      teacherCreatedMovement: customMovement,
    );

    tester
        .widget<ComboBox<String>>(
          find.byKey(const Key('teacher_assignment_maximum_preset')),
        )
        .onChanged!('custom');
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('teacher_assignment_max_score')),
      '0',
    );
    await tester.pump();

    final createButton = tester.widget<ElixPrimaryButton>(
      find.byKey(const Key('teacher_assignment_publish_now')),
    );
    expect(createButton.onPressed, isNull);
    expect(assignments.teacherCreatedCalls, 0);
  });

  testWidgets(
    'learning materials are inline, optional, and queue a valid link',
    (tester) async {
      final materials = _MaterialRepository();
      await pumpComposer(
        tester,
        creationService: service(),
        officialMovement: movementCatalog.first,
        materialRepository: materials,
      );

      expect(
        find.byKey(const Key('teacher_assignment_choose_material_file')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_assignment_material_link_url')),
        findsOneWidget,
      );
      expect(find.text('Add material'), findsNothing);
      await tester.enterText(
        find.byKey(const Key('teacher_assignment_material_link_name')),
        'Grip guide',
      );
      await tester.enterText(
        find.byKey(const Key('teacher_assignment_material_link_url')),
        'https://example.com/grip',
      );
      final addLink = find.byKey(
        const Key('teacher_assignment_add_material_link'),
      );
      await tester.ensureVisible(addLink);
      await tester.tap(addLink);
      await tester.pumpAndSettle();

      expect(find.text('Grip guide'), findsOneWidget);
      expect(materials.linkedAssignmentIds, isEmpty);
      final publish = find.byKey(const Key('teacher_assignment_publish_now'));
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pumpAndSettle();

      expect(assignments.officialCalls, 1);
      expect(materials.linkedAssignmentIds, [
        assignments.assignments.values.single.id,
      ]);
    },
  );

  testWidgets('an invalid inline resource link is rejected before publishing', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
      materialRepository: _MaterialRepository(),
    );

    await tester.enterText(
      find.byKey(const Key('teacher_assignment_material_link_url')),
      'file:///not-a-resource',
    );
    final addLink = find.byKey(
      const Key('teacher_assignment_add_material_link'),
    );
    await tester.ensureVisible(addLink);
    await tester.tap(addLink);
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.text('Enter a valid HTTP or HTTPS resource link.'),
      findsOneWidget,
    );
    expect(find.text('No materials added yet.'), findsOneWidget);
  });

  testWidgets('edit preloads activity configuration and existing materials', (
    tester,
  ) async {
    final activity = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Recorded tin balance',
      instructions: 'Keep the tin upright.',
      requiredProp: TrainingProp.bottle,
      assessment: TeacherActivityAssessmentConfig(
        readiness: const TeacherActivityReadinessSpec(),
        rubric: TeacherActivityRubric.builtIn(
          TeacherActivityRubricTemplate.controlConsistency,
          50,
        ),
        recordingDurationSeconds: 45,
      ),
    );
    final assignment = await service().create(
      group: group,
      teacherCreatedMovement: activity,
      maxScore: 50,
      activityAssessment: TeacherActivityAssessmentConfig(
        readiness: const TeacherActivityReadinessSpec(),
        rubric: TeacherActivityRubric.builtIn(
          TeacherActivityRubricTemplate.controlConsistency,
          50,
        ),
        recordingDurationSeconds: 45,
      ),
      displayTitle: 'Balance recording',
      displayInstructions: 'Keep the tin upright.',
    );
    final materials = _MaterialRepository()
      ..materials = [
        ActivityLearningMaterial(
          id: 'material-1',
          assignmentId: assignment.id,
          type: ActivityLearningMaterialType.pdf,
          displayName: 'Balance guide.pdf',
          sizeBytes: 1024,
        ),
      ];

    await pumpComposer(
      tester,
      creationService: service(),
      existingAssignment: assignment,
      materialRepository: materials,
    );

    expect(materials.listedAssignmentIds, [assignment.id]);
    expect(find.text('Balance guide.pdf'), findsOneWidget);
    expect(
      tester
          .widget<ComboBox<int>>(
            find.byKey(const Key('teacher_assignment_recording_duration')),
          )
          .value,
      45,
    );
    expect(
      tester
          .widget<TextBox>(find.byKey(const Key('teacher_assignment_title')))
          .controller!
          .text,
      'Balance recording',
    );
  });

  testWidgets('edit changes recording duration without recreating assignment', (
    tester,
  ) async {
    final activity = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Recorded tin balance',
      instructions: 'Keep the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
    final assignment = await service().create(
      group: group,
      teacherCreatedMovement: activity,
      displayTitle: 'Balance recording',
      displayInstructions: 'Keep the tin upright.',
    );

    await pumpComposer(
      tester,
      creationService: service(),
      existingAssignment: assignment,
      materialRepository: _MaterialRepository(),
    );
    tester
        .widget<ComboBox<int>>(
          find.byKey(const Key('teacher_assignment_recording_duration')),
        )
        .onChanged!(60);
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_save_changes')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_save_changes')));
    await tester.pumpAndSettle();

    final saved = await assignments.getAssignment(assignmentId: assignment.id);
    expect(assignments.teacherCreatedCalls, 1);
    expect(saved?.id, assignment.id);
    expect(saved?.activityAssessment?.recordingDurationSeconds, 60);
    expect(saved?.configurationRevision, assignment.configurationRevision + 1);
  });

  testWidgets(
    'Teacher Activity edit hydrates its stored movement and no-change Save preserves its identity',
    (tester) async {
      await createTeacherMovement();
      final persistedMovement = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Stored activity',
        instructions: 'Keep the bottle centered throughout the recording.',
        requiredProp: TrainingProp.shaker,
      );
      final assignment = await service().create(
        group: group,
        teacherCreatedMovement: persistedMovement,
        displayTitle: 'Stored activity assignment',
        displayInstructions:
            'Keep the bottle centered throughout the recording.',
      );

      await pumpComposer(
        tester,
        creationService: service(),
        existingAssignment: assignment,
        materialRepository: _MaterialRepository(),
      );

      expect(
        find.byKey(Key('teacher_assignment_custom_${persistedMovement.id}')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.tap(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.pumpAndSettle();

      final saved = await assignments.getAssignment(
        assignmentId: assignment.id,
      );
      expect(saved?.movementId, assignment.movementId);
      expect(saved?.revisionId, assignment.revisionId);
      expect(saved?.origin, assignment.origin);
      expect(
        saved?.activityAssessment?.toMap(),
        assignment.activityAssessment?.toMap(),
      );
      expect(
        saved?.audience.targetTraineeIds,
        assignment.audience.targetTraineeIds,
      );
      expect(saved?.attemptPolicy.toMap(), assignment.attemptPolicy.toMap());
    },
  );

  testWidgets(
    'edit preserves a historical activity revision and shows a newly selected activity configuration',
    (tester) async {
      final first = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Pinned activity',
        instructions: 'Keep the bottle centered.',
        requiredProp: TrainingProp.bottle,
        assessment: TeacherActivityAssessmentConfig(
          readiness: const TeacherActivityReadinessSpec(
            hands: ActivityHandRequirement.twoHands,
            body: ActivityBodyRequirement.upperBody,
          ),
          rubric: TeacherActivityRubric.builtIn(
            TeacherActivityRubricTemplate.standardTechnique,
            40,
          ),
          recordingDurationSeconds: 45,
        ),
      );
      final assignment = await service().create(
        group: group,
        teacherCreatedMovement: first,
      );
      final advanced = await movements.editMovement(
        teacherId: 'teacher-1',
        movementId: first.id,
        title: first.title,
        instructions: 'The reusable activity has advanced.',
        requiredProp: TrainingProp.bottle,
      );
      expect(advanced.currentRevisionId, isNot(assignment.revisionId));
      final second = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Replacement activity',
        instructions: 'Use the shaker with a controlled finish.',
        requiredProp: TrainingProp.shaker,
        assessment: TeacherActivityAssessmentConfig(
          readiness: const TeacherActivityReadinessSpec(
            hands: ActivityHandRequirement.oneHand,
            body: ActivityBodyRequirement.upperBody,
          ),
          rubric: TeacherActivityRubric.builtIn(
            TeacherActivityRubricTemplate.controlConsistency,
            30,
          ),
          recordingDurationSeconds: 60,
        ),
      );

      await pumpComposer(
        tester,
        creationService: service(),
        existingAssignment: assignment,
        materialRepository: _MaterialRepository(),
      );

      expect(
        find.byKey(Key('teacher_assignment_custom_${first.id}')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(Key('teacher_assignment_select_${second.id}')),
      );
      await tester.tap(
        find.byKey(Key('teacher_assignment_select_${second.id}')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Cocktail Shaker · One hand visible · Upper body visible · '
          'Control & Consistency, 30 points · 60s · no demonstration',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.tap(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.pumpAndSettle();

      final saved = await assignments.getAssignment(
        assignmentId: assignment.id,
      );
      expect(saved?.movementId, second.id);
      expect(saved?.revisionId, second.currentRevisionId);
      expect(saved?.activityAssessment?.rubric.maximumScore, 30);
      expect(saved?.activityAssessment?.recordingDurationSeconds, 60);
    },
  );

  testWidgets(
    'editing preserves a pinned revision after the reusable Activity advances',
    (tester) async {
      final activity = await createTeacherMovement();
      final assignment = await service().create(
        group: group,
        teacherCreatedMovement: activity,
      );
      final pinnedRevisionId = assignment.revisionId;
      await movements.editMovement(
        teacherId: 'teacher-1',
        movementId: activity.id,
        title: activity.title,
        instructions: 'The reusable Activity is now v2.',
        requiredProp: TrainingProp.bottle,
      );

      await pumpComposer(
        tester,
        creationService: service(),
        existingAssignment: assignment,
        materialRepository: _MaterialRepository(),
      );

      expect(
        find.text(
          'This assignment uses an older saved version of this Activity.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.tap(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.pumpAndSettle();

      final saved = await assignments.getAssignment(
        assignmentId: assignment.id,
      );
      expect(saved?.id, assignment.id);
      expect(saved?.revisionId, pinnedRevisionId);
    },
  );

  testWidgets(
    'Use latest version updates the summary and persists the current revision',
    (tester) async {
      final activity = await createTeacherMovement();
      final assignment = await service().create(
        group: group,
        teacherCreatedMovement: activity,
      );
      final newerAssessment = TeacherActivityAssessmentConfig(
        readiness: const TeacherActivityReadinessSpec(
          hands: ActivityHandRequirement.oneHand,
          body: ActivityBodyRequirement.upperBody,
        ),
        rubric: TeacherActivityRubric.builtIn(
          TeacherActivityRubricTemplate.controlConsistency,
          30,
        ),
        recordingDurationSeconds: 60,
      );
      final advanced = await movements.editMovement(
        teacherId: 'teacher-1',
        movementId: activity.id,
        title: activity.title,
        instructions: 'The reusable Activity is now v2.',
        requiredProp: TrainingProp.shaker,
        assessment: newerAssessment,
      );

      await pumpComposer(
        tester,
        creationService: service(),
        existingAssignment: assignment,
        materialRepository: _MaterialRepository(),
      );
      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_use_latest_revision')),
      );
      await tester.tap(
        find.byKey(const Key('teacher_assignment_use_latest_revision')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Cocktail Shaker · One hand visible · Upper body visible · '
          'Control & Consistency, 30 points · 60s · no demonstration',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.tap(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.pumpAndSettle();

      final saved = await assignments.getAssignment(
        assignmentId: assignment.id,
      );
      expect(saved?.movementId, activity.id);
      expect(saved?.revisionId, advanced.currentRevisionId);
      expect(saved?.activityAssessment?.rubric.maximumScore, 30);
      expect(saved?.activityAssessment?.recordingDurationSeconds, 60);
    },
  );

  testWidgets(
    'reselecting the original Activity deliberately uses its current revision',
    (tester) async {
      final first = await createTeacherMovement();
      final assignment = await service().create(
        group: group,
        teacherCreatedMovement: first,
      );
      final advanced = await movements.editMovement(
        teacherId: 'teacher-1',
        movementId: first.id,
        title: first.title,
        instructions: 'The original Activity is now v2.',
        requiredProp: TrainingProp.bottle,
      );
      final second = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Replacement activity',
        instructions: 'Use the replacement activity.',
        requiredProp: TrainingProp.shaker,
      );

      await pumpComposer(
        tester,
        creationService: service(),
        existingAssignment: assignment,
        materialRepository: _MaterialRepository(),
      );
      await tester.ensureVisible(
        find.byKey(Key('teacher_assignment_select_${second.id}')),
      );
      await tester.tap(
        find.byKey(Key('teacher_assignment_select_${second.id}')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(Key('teacher_assignment_select_${first.id}')),
      );
      await tester.tap(
        find.byKey(Key('teacher_assignment_select_${first.id}')),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.tap(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.pumpAndSettle();

      final saved = await assignments.getAssignment(
        assignmentId: assignment.id,
      );
      expect(saved?.movementId, first.id);
      expect(saved?.revisionId, advanced.currentRevisionId);
    },
  );

  testWidgets(
    'an active assignment with trainee work cannot use the latest Activity version',
    (tester) async {
      assignments = _TraineeWorkAssignments(groupRepository: groups);
      final activity = await createTeacherMovement();
      final assignment = await service().create(
        group: group,
        teacherCreatedMovement: activity,
      );
      await movements.editMovement(
        teacherId: 'teacher-1',
        movementId: activity.id,
        title: activity.title,
        instructions: 'The reusable Activity is now v2.',
        requiredProp: TrainingProp.bottle,
      );

      await pumpComposer(
        tester,
        creationService: service(),
        existingAssignment: assignment,
        materialRepository: _MaterialRepository(),
      );

      expect(
        find.byKey(const Key('teacher_assignment_use_latest_revision')),
        findsNothing,
      );
      expect(
        find.textContaining('trainee work already exists'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'an archived pinned Activity remains editable without becoming a new choice',
    (tester) async {
      final activity = await createTeacherMovement();
      final assignment = await service().create(
        group: group,
        teacherCreatedMovement: activity,
      );
      await movements.editMovement(
        teacherId: 'teacher-1',
        movementId: activity.id,
        title: activity.title,
        instructions: 'The archived Activity is now on a newer revision.',
        requiredProp: TrainingProp.bottle,
      );
      await movements.archiveMovement(
        teacherId: 'teacher-1',
        movementId: activity.id,
      );

      await pumpComposer(
        tester,
        creationService: service(),
        existingAssignment: assignment,
        materialRepository: _MaterialRepository(),
      );

      expect(
        find.byKey(Key('teacher_assignment_custom_${activity.id}')),
        findsOneWidget,
      );
      expect(find.text('Balance the tin upright.'), findsWidgets);
      expect(
        find.text('The archived Activity is now on a newer revision.'),
        findsNothing,
      );
      await tester.enterText(
        find.byKey(const Key('teacher_assignment_topic')),
        'Archived activity safe edit',
      );
      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.tap(
        find.byKey(const Key('teacher_assignment_save_changes')),
      );
      await tester.pumpAndSettle();

      final saved = await assignments.getAssignment(
        assignmentId: assignment.id,
      );
      expect(saved?.movementId, activity.id);
      expect(saved?.revisionId, assignment.revisionId);
      expect(saved?.topic, 'Archived activity safe edit');
    },
  );

  testWidgets(
    'an archived Activity is not listed when creating a new assignment',
    (tester) async {
      final activity = await createTeacherMovement();
      await movements.archiveMovement(
        teacherId: 'teacher-1',
        movementId: activity.id,
      );

      await pumpComposer(tester, creationService: service());
      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_source_mine')),
      );
      await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('teacher_assignment_custom_${activity.id}')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('teacher_assignment_empty_movement_state')),
        findsOneWidget,
      );
    },
  );

  testWidgets('Official draft edit switches to a Teacher Activity', (
    tester,
  ) async {
    final activity = await createTeacherMovement();
    final officialDraft = await service().create(
      group: group,
      officialMovement: movementCatalog.first,
      status: GroupAssignmentStatus.draft,
    );
    await pumpComposer(
      tester,
      creationService: service(),
      existingAssignment: officialDraft,
      materialRepository: _MaterialRepository(),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('teacher_assignment_custom_${activity.id}')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_save_draft')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_save_draft')));
    await tester.pumpAndSettle();
    final teacherActivity = await assignments.getAssignment(
      assignmentId: officialDraft.id,
    );
    expect(teacherActivity?.isTeacherCreated, isTrue);
    expect(teacherActivity?.movementId, activity.id);
    expect(teacherActivity?.activityAssessment, isNotNull);
  });

  testWidgets('Teacher Activity draft edit switches to an Official movement', (
    tester,
  ) async {
    final activity = await createTeacherMovement();
    final draft = await service().create(
      group: group,
      teacherCreatedMovement: activity,
      status: GroupAssignmentStatus.draft,
    );
    await pumpComposer(
      tester,
      creationService: service(),
      existingAssignment: draft,
      materialRepository: _MaterialRepository(),
    );
    await tester.tap(
      find.byKey(const Key('teacher_assignment_source_official')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_save_draft')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_save_draft')));
    await tester.pumpAndSettle();
    final saved = await assignments.getAssignment(assignmentId: draft.id);
    expect(saved?.isOfficial, isTrue);
    expect(saved?.activityAssessment, isNull);
    expect(saved?.allowedProp, isNotNull);
  });

  testWidgets(
    'draft edit can change classroom and clears old targeted trainees',
    (tester) async {
      final draft = await service().create(
        group: group,
        officialMovement: movementCatalog.first,
        status: GroupAssignmentStatus.draft,
        audience: AssignmentAudience.individualStudent(['trainee-1']),
      );
      await pumpComposer(
        tester,
        creationService: service(),
        existingAssignment: draft,
        availableGroups: const [group, otherGroup],
        lockedGroup: group,
        materialRepository: _MaterialRepository(),
      );
      tester
          .widget<ComboBox<String>>(
            find.byKey(const Key('teacher_assignment_class')),
          )
          .onChanged!('group-2');
      await tester.pumpAndSettle();
      expect(find.text('Select one trainee.'), findsNothing);
      expect(
        tester
            .widget<Button>(
              find.byKey(const Key('teacher_assignment_save_draft')),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'failed trainee-work lookup locks semantic editing and offers Retry',
    (tester) async {
      assignments = _SafetyFailureAssignments(groupRepository: groups);
      final existing = await service().create(
        group: group,
        officialMovement: movementCatalog.first,
        status: GroupAssignmentStatus.draft,
      );
      await pumpComposer(
        tester,
        creationService: service(),
        existingAssignment: existing,
        materialRepository: _MaterialRepository(),
      );
      expect(
        find.byKey(const Key('teacher_assignment_retry_edit_safety')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ComboBox<String>>(
              find.byKey(const Key('teacher_assignment_class')),
            )
            .onChanged,
        isNull,
      );
    },
  );

  testWidgets('edit removes an existing material only when changes are saved', (
    tester,
  ) async {
    final assignment = await service().create(
      group: group,
      officialMovement: movementCatalog.first,
    );
    final materials = _MaterialRepository()
      ..materials = [
        ActivityLearningMaterial(
          id: 'material-1',
          assignmentId: assignment.id,
          type: ActivityLearningMaterialType.link,
          displayName: 'Safety reference',
          externalUrl: Uri.parse('https://example.com/safety'),
        ),
      ];

    await pumpComposer(
      tester,
      creationService: service(),
      existingAssignment: assignment,
      materialRepository: materials,
    );
    final remove = find.widgetWithText(Button, 'Remove');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pump();
    expect(materials.removedMaterialIds, isEmpty);
    expect(find.text('Will be removed when you save changes'), findsOneWidget);

    final save = find.byKey(const Key('teacher_assignment_save_changes'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(materials.removedMaterialIds, ['material-1']);
  });

  testWidgets('editing a draft saves edited values privately', (tester) async {
    final draft = await service().create(
      group: group,
      officialMovement: movementCatalog.first,
      status: GroupAssignmentStatus.draft,
      topic: 'Original topic',
    );

    await pumpComposer(
      tester,
      creationService: service(),
      existingAssignment: draft,
      materialRepository: _MaterialRepository(),
    );

    expect(find.text('DRAFT ASSIGNMENT'), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_assignment_save_draft')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('teacher_assignment_publish_draft')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextBox>(find.byKey(const Key('teacher_assignment_topic')))
          .controller!
          .text,
      'Original topic',
    );

    await tester.enterText(
      find.byKey(const Key('teacher_assignment_topic')),
      'Saved privately',
    );
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_save_draft')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_save_draft')));
    await tester.pumpAndSettle();
    final saved = await assignments.getAssignment(assignmentId: draft.id);
    expect(saved?.status, GroupAssignmentStatus.draft);
    expect(saved?.topic, 'Saved privately');
  });

  testWidgets('publishing a draft saves its latest edits first', (
    tester,
  ) async {
    final draft = await service().create(
      group: group,
      officialMovement: movementCatalog.first,
      status: GroupAssignmentStatus.draft,
      topic: 'Original topic',
    );
    await pumpComposer(
      tester,
      creationService: service(),
      existingAssignment: draft,
      materialRepository: _MaterialRepository(),
    );
    await tester.enterText(
      find.byKey(const Key('teacher_assignment_topic')),
      'Ready to publish',
    );
    final publish = find.byKey(const Key('teacher_assignment_publish_draft'));
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pumpAndSettle();
    final published = await assignments.getAssignment(assignmentId: draft.id);
    expect(published?.status, GroupAssignmentStatus.active);
    expect(published?.topic, 'Ready to publish');
  });

  testWidgets(
    'Teacher Activity defaults prefill and assignment overrides publish a v2 snapshot',
    (tester) async {
      final defaults = TeacherActivityAssessmentConfig(
        readiness: TeacherActivityReadinessSpec(
          hands: ActivityHandRequirement.twoHands,
          body: ActivityBodyRequirement.upperBody,
        ),
        rubric: TeacherActivityRubric.builtIn(
          TeacherActivityRubricTemplate.controlConsistency,
          50,
        ),
        recordingDurationSeconds: 45,
      );
      final activity = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Shaker control',
        instructions: 'Keep the shaker controlled.',
        safetyGuidance: 'Leave clear space around you.',
        requiredProp: TrainingProp.shaker,
        assessment: defaults,
      );
      await pumpComposer(
        tester,
        creationService: service(),
        teacherCreatedMovement: activity,
      );
      await tester.pumpAndSettle();

      expect(find.text('Shaker control'), findsWidgets);
      expect(
        tester
            .widget<ComboBox<String>>(
              find.byKey(const Key('teacher_assignment_attempt_policy')),
            )
            .value,
        '3',
      );
      expect(find.text('Control & Consistency'), findsWidgets);

      await tester.enterText(
        find.byKey(const Key('teacher_assignment_title')),
        'Shaker control — Group A',
      );
      final duration = tester.widget<ComboBox<int>>(
        find.byKey(const Key('teacher_assignment_recording_duration')),
      );
      duration.onChanged!(60);
      await tester.pump();
      final publish = find.byKey(const Key('teacher_assignment_publish_now'));
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pumpAndSettle();

      expect(assignments.teacherCreatedCalls, 1);
      expect(assignments.lastDisplayTitle, 'Shaker control — Group A');
      expect(assignments.lastActivityAssessment?.recordingDurationSeconds, 60);
      expect(
        assignments.lastActivityAssessment?.readiness.hands,
        ActivityHandRequirement.twoHands,
      );
    },
  );

  testWidgets('custom rubric requires exact points before publishing', (
    tester,
  ) async {
    final activity = await createTeacherMovement();
    await pumpComposer(
      tester,
      creationService: service(),
      teacherCreatedMovement: activity,
    );
    await tester.pumpAndSettle();

    final template = tester.widget<ComboBox<TeacherActivityRubricTemplate>>(
      find.byKey(const Key('teacher_assignment_rubric_template')),
    );
    template.onChanged!(TeacherActivityRubricTemplate.custom);
    await tester.pump();
    expect(
      find.byKey(const Key('teacher_assignment_custom_criterion_0')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<ElixPrimaryButton>(
            find.byKey(const Key('teacher_assignment_publish_now')),
          )
          .onPressed,
      isNull,
    );

    for (var index = 1; index <= 3; index++) {
      await tester.enterText(
        find.byKey(Key('teacher_assignment_criterion_${index}_description')),
        'Teacher-visible criterion $index.',
      );
      await tester.enterText(
        find.byKey(Key('teacher_assignment_criterion_${index}_points')),
        index == 3 ? '10' : '20',
      );
    }
    await tester.pump();
    expect(
      tester
          .widget<ElixPrimaryButton>(
            find.byKey(const Key('teacher_assignment_publish_now')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'targeted audience selection is visible, counted, and forwarded',
    (tester) async {
      await pumpComposer(
        tester,
        creationService: service(),
        officialMovement: movementCatalog.first,
      );

      final entireChoice = find.byKey(
        const Key('teacher_assignment_audience_entire'),
      );
      expect(
        tester
            .widget<RadioButton>(
              find.descendant(
                of: entireChoice,
                matching: find.byType(RadioButton),
              ),
            )
            .checked,
        isTrue,
      );

      final selectedChoice = find.byKey(
        const Key('teacher_assignment_audience_selected'),
      );
      await tester.ensureVisible(selectedChoice);
      await tester.tap(selectedChoice);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('teacher_assignment_roster')),
        findsOneWidget,
      );
      expect(find.text('0 selected'), findsOneWidget);
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const Key('teacher_assignment_publish_now')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(
        find.byKey(const Key('teacher_assignment_trainee_trainee-1')),
      );
      await tester.tap(
        find.byKey(const Key('teacher_assignment_trainee_trainee-2')),
      );
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_publish_now')),
      );
      await tester.tap(find.byKey(const Key('teacher_assignment_publish_now')));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();

      expect(assignments.officialCalls, 1);
      expect(
        assignments.lastAudience?.type,
        AssignmentAudienceType.selectedStudents,
      );
      expect(
        assignments.lastAudience?.targetTraineeIds,
        containsAll(['trainee-1', 'trainee-2']),
      );
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets(
    'individual mode and classroom changes clear stale hidden targets',
    (tester) async {
      await pumpComposer(
        tester,
        creationService: service(),
        officialMovement: movementCatalog.first,
        availableGroups: const [group, otherGroup],
      );

      final individualChoice = find.byKey(
        const Key('teacher_assignment_audience_individual'),
      );
      await tester.ensureVisible(individualChoice);
      await tester.tap(individualChoice);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('teacher_assignment_trainee_trainee-1')),
      );
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      final classroom = find.byKey(const Key('teacher_assignment_class'));
      await tester.ensureVisible(classroom);
      expect(tester.widget<ComboBox<String>>(classroom).value, group.id);
      tester.widget<ComboBox<String>>(classroom).onChanged!(otherGroup.id);
      await tester.pump();
      expect(tester.widget<ComboBox<String>>(classroom).value, otherGroup.id);
      expect(find.text('0 selected'), findsOneWidget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();

      expect(
        find.byKey(const Key('teacher_assignment_trainee_trainee-1')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('teacher_assignment_trainee_trainee-4')),
        findsOneWidget,
      );
      expect(find.text('0 selected'), findsOneWidget);

      final entireChoice = find.byKey(
        const Key('teacher_assignment_audience_entire'),
      );
      await tester.ensureVisible(entireChoice);
      await tester.tap(entireChoice);
      await tester.pump();
      expect(find.byKey(const Key('teacher_assignment_roster')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets('classroom-first flow publishes an individual assignment', (
    tester,
  ) async {
    await pumpComposer(tester, creationService: service(), lockedGroup: group);

    final individualChoice = find.byKey(
      const Key('teacher_assignment_audience_individual'),
    );
    await tester.ensureVisible(individualChoice);
    await tester.tap(individualChoice);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('teacher_assignment_trainee_trainee-2')),
    );
    await tester.pump();

    final publish = find.byKey(const Key('teacher_assignment_publish_now'));
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();

    expect(assignments.officialCalls, 1);
    expect(
      assignments.lastAudience?.type,
      AssignmentAudienceType.individualStudent,
    );
    expect(assignments.lastAudience?.targetTraineeIds, ['trainee-2']);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('assignment sources switch inside the responsive composer', (
    tester,
  ) async {
    final customMovement = await createTeacherMovement();
    await pumpComposer(tester, creationService: service());

    expect(find.byKey(const Key('teacher_assignment_form')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_source_mine')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('teacher_assignment_custom_${customMovement.id}')),
      findsOneWidget,
    );
    expect(find.text('Teacher Activities'), findsOneWidget);
  });

  testWidgets(
    'Teacher Activity details are read-only until Use this activity is pressed',
    (tester) async {
      final selected = await createTeacherMovement();
      final detailed = await movements.createMovement(
        teacherId: 'teacher-1',
        title: 'Advanced Pour',
        instructions: 'Keep the bottle vertical, then pour with control.',
        requiredProp: TrainingProp.bottle,
        safetyGuidance: 'Keep clear space around your practice area.',
        assessment: TeacherActivityAssessmentConfig(
          readiness: const TeacherActivityReadinessSpec(
            hands: ActivityHandRequirement.twoHands,
            body: ActivityBodyRequirement.upperBody,
          ),
          rubric: const TeacherActivityRubric(
            template: TeacherActivityRubricTemplate.custom,
            maximumScore: 30,
            criteria: [
              TeacherActivityRubricCriterion(
                id: 'setup',
                label: 'Safe setup',
                description: 'Starts with a stable, clear practice space.',
                maximumPoints: 10,
              ),
              TeacherActivityRubricCriterion(
                id: 'control',
                label: 'Bottle control',
                description: 'Maintains steady control through the pour.',
                maximumPoints: 10,
              ),
              TeacherActivityRubricCriterion(
                id: 'finish',
                label: 'Clean finish',
                description: 'Finishes deliberately and safely.',
                maximumPoints: 10,
              ),
            ],
          ),
          recordingDurationSeconds: 45,
          demonstrationVideo: TeacherActivityVideoMetadata(
            storagePath: 'teacher-1/demos/advanced-pour.mp4',
            contentType: 'video/mp4',
            sizeBytes: 2048,
            durationMs: 12000,
            source: TeacherActivityDemoSource.recorded,
          ),
        ),
      );
      await pumpComposer(tester, creationService: service());

      await tester.ensureVisible(
        find.byKey(const Key('teacher_assignment_source_mine')),
      );
      await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('teacher_assignment_view_details_${detailed.id}')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(Key('teacher_assignment_select_${selected.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('teacher_assignment_view_details_${detailed.id}')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Advanced Pour'), findsWidgets);
      expect(find.text('Required training prop: Bottle'), findsOneWidget);
      expect(
        find.text('Keep the bottle vertical, then pour with control.'),
        findsWidgets,
      );
      expect(find.text('Safety'), findsOneWidget);
      expect(find.text('Hands: Two hands visible'), findsOneWidget);
      expect(find.text('Body: Upper body visible'), findsOneWidget);
      expect(find.text('Template: Custom'), findsOneWidget);
      expect(find.text('Maximum score: 30'), findsOneWidget);
      expect(find.text('Safe setup · 10 points'), findsOneWidget);
      expect(find.text('Recording duration: 45 seconds'), findsOneWidget);
      expect(
        find.text('Demonstration video: Available · recorded'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('teacher_assignment_activity_details_use')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(
        find.byKey(const Key('teacher_assignment_activity_details_close')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Advanced Pour'), findsWidgets);

      await tester.tap(
        find.byKey(Key('teacher_assignment_view_details_${detailed.id}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('teacher_assignment_activity_details_use')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('teacher_assignment_activity_details_use')),
        findsNothing,
      );
      expect(selected.id, isNot(detailed.id));
    },
  );

  testWidgets('Teacher Activity details omit absent safety guidance', (
    tester,
  ) async {
    final activity = await createTeacherMovement();
    await pumpComposer(tester, creationService: service());
    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_source_mine')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('teacher_assignment_view_details_${activity.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Safety'), findsNothing);
    expect(find.text('Recording duration: 30 seconds'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('teacher_assignment_activity_details_close')),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('movement management stays out of Assignment Studio', (
    tester,
  ) async {
    final customMovement = await createTeacherMovement();
    await pumpComposer(tester, creationService: service());

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_source_mine')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_source_mine')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('teacher_assignment_custom_${customMovement.id}')),
      findsOneWidget,
    );
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('Teacher Activity can create and select a new activity', (
    tester,
  ) async {
    await pumpComposer(tester, creationService: service());

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_source_mine')),
    );
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
    await tester.tap(find.byKey(const ValueKey('teacher-reviewed-save')));
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
            find.byKey(const Key('teacher_assignment_publish_now')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('empty Teacher Activity state has no blank assignment controls', (
    tester,
  ) async {
    await pumpComposer(tester, creationService: service());

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_source_mine')),
    );
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

    await tester.ensureVisible(
      find.byKey(const Key('teacher_assignment_source_mine')),
    );
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
    await tester.tap(find.byKey(const ValueKey('teacher-reviewed-save')));
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
      find.byKey(const Key('teacher_assignment_publish_now')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_publish_now')));
    await tester.pump();
    expect(assignments.officialCalls, 1);

    await tester.tap(find.byKey(const Key('teacher_assignment_publish_now')));
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

  testWidgets(
    'Assignment Studio uses a sticky action footer on a narrow window',
    (tester) async {
      await pumpComposer(
        tester,
        creationService: service(),
        officialMovement: movementCatalog.first,
        size: const Size(760, 900),
      );

      expect(find.byKey(const Key('teacher_assignment_form')), findsOneWidget);
      expect(find.byKey(const Key('teacher_assignment_summary')), findsNothing);
      expect(
        find.byKey(const Key('teacher_assignment_publish_now')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_assignment_save_draft')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('teacher_assignment_schedule')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide editor scroll keeps the summary actions reachable', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
      size: const Size(1280, 720),
    );

    expect(find.byKey(const Key('teacher_assignment_summary')), findsOneWidget);
    final editor = find.byKey(const Key('teacher_assignment_editor_scroll'));
    await tester.drag(editor, const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('teacher_assignment_publish_now')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('teacher_assignment_save_draft')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('teacher_assignment_schedule')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow editor scroll leaves its sticky actions unobscured', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: movementCatalog.first,
      size: const Size(760, 720),
    );

    final editor = find.byKey(const Key('teacher_assignment_editor_scroll'));
    await tester.drag(editor, const Offset(0, -1000));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('teacher_assignment_publish_now')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('teacher_assignment_schedule')).hitTestable(),
      findsOneWidget,
    );
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
      find.byKey(const Key('teacher_assignment_publish_now')),
    );
    await tester.tap(find.byKey(const Key('teacher_assignment_publish_now')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('teacher_assignment_error')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  Movement officialByName(String name) =>
      movementCatalog.firstWhere((movement) => movement.name == name);

  Future<void> publishAssignment(WidgetTester tester) async {
    final publish = find.byKey(const Key('teacher_assignment_publish_now'));
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }

  testWidgets(
    'Activity Library Hand Stall Cocktail Shaker pins and persists shaker',
    (tester) async {
      await pumpComposer(
        tester,
        creationService: service(),
        officialMovement: officialByName('Hand Stall'),
        initialOfficialProp: TrainingProp.shaker,
      );

      expect(find.text('Hand Stall'), findsAtLeastNWidgets(1));
      expect(find.text('Cocktail Shaker'), findsAtLeastNWidgets(1));
      expect(
        find.text('Official ELIXR guided assessment · Cocktail Shaker'),
        findsAtLeastNWidgets(1),
      );
      expect(
        find.byKey(const Key('teacher_assignment_official_prop')),
        findsOneWidget,
      );
      expect(find.byType(ComboBox<TrainingProp>), findsNothing);

      await publishAssignment(tester);

      expect(assignments.officialCalls, 1);
      expect(assignments.lastAllowedProp, TrainingProp.shaker);
      expect(
        assignments.assignments.values.single.allowedProp,
        TrainingProp.shaker,
      );
      expect(
        assignments.assignments.values.single.officialMovementName,
        'Hand Stall',
      );
      await tester.pump(const Duration(milliseconds: 200));
    },
  );

  testWidgets('Activity Library Hand Stall Bottle pins and persists bottle', (
    tester,
  ) async {
    await pumpComposer(
      tester,
      creationService: service(),
      officialMovement: officialByName('Hand Stall'),
      initialOfficialProp: TrainingProp.bottle,
    );

    expect(find.text('Bottle'), findsAtLeastNWidgets(1));
    expect(
      find.text('Official ELIXR guided assessment · Bottle'),
      findsAtLeastNWidgets(1),
    );

    await publishAssignment(tester);

    expect(assignments.officialCalls, 1);
    expect(assignments.lastAllowedProp, TrainingProp.bottle);
    expect(
      assignments.assignments.values.single.allowedProp,
      TrainingProp.bottle,
    );
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets(
    'unsupported Activity Library prop fails closed instead of defaulting',
    (tester) async {
      await pumpComposer(
        tester,
        creationService: service(),
        officialMovement: officialByName('Body Grip'),
        initialOfficialProp: TrainingProp.shaker,
      );

      expect(find.text('Choose a supported training prop'), findsOneWidget);
      expect(find.text('Cocktail Shaker'), findsNothing);
      expect(
        tester
            .widget<ElixPrimaryButton>(
              find.byKey(const Key('teacher_assignment_publish_now')),
            )
            .onPressed,
        isNull,
      );
      expect(assignments.officialCalls, 0);
    },
  );

  test(
    'creation service rejects unsupported officialAllowedProp without fallback',
    () async {
      await expectLater(
        service().create(
          group: group,
          officialMovement: officialByName('Hand Stall'),
          officialAllowedProp: TrainingProp.bottleAndShaker,
        ),
        throwsA(isA<ClassroomException>()),
      );
      expect(assignments.officialCalls, 0);
    },
  );

  testWidgets(
    'classroom-first multi-prop selection still chooses and persists Cocktail Shaker',
    (tester) async {
      await pumpComposer(
        tester,
        creationService: service(),
        lockedGroup: group,
      );

      final handStall = find.byKey(
        const Key('teacher_assignment_official_Hand Stall'),
      );
      await tester.ensureVisible(handStall);
      await tester.pumpAndSettle();
      await tester.tap(handStall);
      await tester.pumpAndSettle();

      final propBox = find.byKey(const Key('teacher_assignment_official_prop'));
      expect(propBox, findsOneWidget);
      expect(
        tester.widget<ComboBox<TrainingProp>>(propBox).value,
        TrainingProp.bottle,
      );

      tester.widget<ComboBox<TrainingProp>>(propBox).onChanged!(
        TrainingProp.shaker,
      );
      await tester.pump();
      expect(
        tester.widget<ComboBox<TrainingProp>>(propBox).value,
        TrainingProp.shaker,
      );

      final oneFinger = find.byKey(
        const Key('teacher_assignment_official_One Finger Stall'),
      );
      await tester.ensureVisible(oneFinger);
      await tester.pumpAndSettle();
      await tester.tap(oneFinger);
      await tester.pump();
      expect(
        tester.widget<ComboBox<TrainingProp>>(propBox).value,
        TrainingProp.bottle,
      );

      tester.widget<ComboBox<TrainingProp>>(propBox).onChanged!(
        TrainingProp.shaker,
      );
      await tester.pump();

      await publishAssignment(tester);

      expect(assignments.officialCalls, 1);
      expect(assignments.lastAllowedProp, TrainingProp.shaker);
      expect(
        assignments.assignments.values.single.officialMovementName,
        'One Finger Stall',
      );
      expect(
        assignments.assignments.values.single.allowedProp,
        TrainingProp.shaker,
      );
      await tester.pump(const Duration(milliseconds: 200));
    },
  );
}
