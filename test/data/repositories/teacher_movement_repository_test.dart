import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/teacher_movement_revision_spec.dart';
import 'package:elixr_application/data/models/teacher_reviewed_movement_spec.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTeacherMovementRepository repo;

  setUp(() {
    var n = 0;
    repo = InMemoryTeacherMovementRepository(
      now: () => DateTime.utc(2026, 8, 20),
      generateId: () => 'tm${++n}',
    );
  });

  tearDown(() => repo.dispose());

  test('create publishes an immutable first revision', () async {
    final movement = await repo.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Balance the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
    expect(movement.currentRevisionId, isNotEmpty);
    final revision = await repo.getRevision(
      movementId: movement.id,
      revisionId: movement.currentRevisionId,
    );
    expect(revision, isNotNull);
    expect(revision!.spec.instructions, 'Balance the tin upright.');
    expect(revision.spec.isTeacherReviewOnly, isTrue);
  });

  test('edit creates a new revision and keeps the old one', () async {
    final created = await repo.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'First instructions.',
      requiredProp: TrainingProp.bottle,
    );
    final firstRevisionId = created.currentRevisionId;
    final edited = await repo.editMovement(
      teacherId: 'teacher-1',
      movementId: created.id,
      title: 'Tin Balance v2',
      instructions: 'Revised instructions.',
      requiredProp: TrainingProp.shaker,
    );
    expect(edited.currentRevisionId, isNot(firstRevisionId));
    expect(
      (await repo.getRevision(
        movementId: created.id,
        revisionId: firstRevisionId,
      ))?.spec.instructions,
      'First instructions.',
    );
    expect(
      (await repo.getRevision(
        movementId: created.id,
        revisionId: edited.currentRevisionId,
      ))?.spec.instructions,
      'Revised instructions.',
    );
  });

  test('unrelated Teacher cannot edit another Teacher movement', () async {
    final created = await repo.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Balance the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
    expect(
      () => repo.editMovement(
        teacherId: 'teacher-2',
        movementId: created.id,
        title: 'Hijack',
        instructions: 'No.',
        requiredProp: TrainingProp.bottle,
      ),
      throwsA(
        isA<ClassroomException>().having(
          (error) => error.code,
          'code',
          ClassroomError.forbidden,
        ),
      ),
    );
  });

  test('template create persists the exact canonical revision shape', () async {
    final movement = await repo.createTemplateScoredMovement(
      teacherId: 'teacher-1',
      title: 'Classroom Wrist Stall',
      instructions: 'Balance the bottle on the wrist.',
      assessment: const AssessmentSpec(laterality: AssessmentLaterality.left),
      safetyGuidance: 'Clear the area.',
    );
    final revision = await repo.getRevision(
      movementId: movement.id,
      revisionId: movement.currentRevisionId,
    );
    expect(revision, isNotNull);
    expect(revision!.assessmentMode, AssessmentMode.templateScored);
    expect(revision.spec, isA<TemplateScoredRevisionSpec>());
    expect(revision.spec.toMap(), {
      'instructions': 'Balance the bottle on the wrist.',
      'required_prop': 'bottle',
      'safety_guidance': 'Clear the area.',
      'assessment': {
        'schema_version': 1,
        'template_id': 'balance_stall.wrist_v1',
        'prop': 'bottle',
        'target': 'wrist',
        'laterality': 'left',
      },
    });
  });

  test('template edit creates a new immutable revision', () async {
    final created = await repo.createTemplateScoredMovement(
      teacherId: 'teacher-1',
      title: 'Classroom Wrist Stall',
      instructions: 'First instructions.',
      assessment: const AssessmentSpec(laterality: AssessmentLaterality.either),
    );
    final firstId = created.currentRevisionId;
    final first = await repo.getRevision(
      movementId: created.id,
      revisionId: firstId,
    );
    final edited = await repo.editTemplateScoredMovement(
      teacherId: 'teacher-1',
      movementId: created.id,
      title: 'Classroom Wrist Stall v2',
      instructions: 'Revised instructions.',
      assessment: const AssessmentSpec(laterality: AssessmentLaterality.right),
    );
    expect(edited.currentRevisionId, isNot(firstId));
    expect(
      (await repo.getRevision(
        movementId: created.id,
        revisionId: firstId,
      ))?.spec.toMap(),
      first!.spec.toMap(),
    );
    expect(
      (await repo.getRevision(
        movementId: created.id,
        revisionId: edited.currentRevisionId,
      ))?.spec.toMap()['assessment'],
      {
        'schema_version': 1,
        'template_id': 'balance_stall.wrist_v1',
        'prop': 'bottle',
        'target': 'wrist',
        'laterality': 'right',
      },
    );
  });

  test('teacher-reviewed edit cannot convert a template movement', () async {
    final created = await repo.createTemplateScoredMovement(
      teacherId: 'teacher-1',
      title: 'Classroom Wrist Stall',
      instructions: 'Balance the bottle.',
      assessment: const AssessmentSpec(laterality: AssessmentLaterality.either),
    );
    expect(
      () => repo.editMovement(
        teacherId: 'teacher-1',
        movementId: created.id,
        title: 'Converted',
        instructions: 'No.',
        requiredProp: TrainingProp.bottle,
      ),
      throwsA(
        isA<ClassroomException>().having(
          (error) => error.code,
          'code',
          ClassroomError.identityMismatch,
        ),
      ),
    );
  });

  test('teacher-reviewed create remains teacher_reviewed', () async {
    final movement = await repo.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Balance the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
    final revision = await repo.getRevision(
      movementId: movement.id,
      revisionId: movement.currentRevisionId,
    );
    expect(revision!.assessmentMode, AssessmentMode.teacherReviewed);
    expect(revision.spec, isA<TeacherReviewedMovementSpec>());
  });
}
