import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/teacher_movement.dart';
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

  test('create publishes an immutable teacher-reviewed revision', () async {
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

    expect(revision, isNotNull);
    expect(revision!.assessmentMode, AssessmentMode.teacherReviewed);
    expect(revision.spec, isA<TeacherReviewedMovementSpec>());
    expect(revision.spec.isTeacherReviewOnly, isTrue);
  });

  test('edit creates a new teacher-reviewed revision', () async {
    final created = await repo.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'First instructions.',
      requiredProp: TrainingProp.bottle,
    );
    final edited = await repo.editMovement(
      teacherId: 'teacher-1',
      movementId: created.id,
      title: 'Tin Balance v2',
      instructions: 'Revised instructions.',
      requiredProp: TrainingProp.shaker,
    );

    expect(edited.currentRevisionId, isNot(created.currentRevisionId));
    expect(
      (await repo.getRevision(
        movementId: created.id,
        revisionId: edited.currentRevisionId,
      ))!.spec.instructions,
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

  test(
    'historical template movements remain readable but not archivable',
    () async {
      const movementId = 'legacy-movement';
      const revisionId = 'legacy-revision';
      repo.movements[movementId] = const TeacherMovement(
        id: movementId,
        teacherId: 'teacher-1',
        title: 'Historical Wrist Stall',
        status: TeacherMovementStatus.active,
        currentRevisionId: revisionId,
      );
      repo.revisions['$movementId/$revisionId'] = const TeacherMovementRevision(
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

      expect(await repo.getMovement(movementId: movementId), isNotNull);
      expect(
        (await repo.getRevision(
          movementId: movementId,
          revisionId: revisionId,
        ))!.isRetiredTemplate,
        isTrue,
      );
      expect(
        () => repo.archiveMovement(
          teacherId: 'teacher-1',
          movementId: movementId,
        ),
        throwsA(
          isA<ClassroomException>().having(
            (error) => error.code,
            'code',
            ClassroomError.identityMismatch,
          ),
        ),
      );
    },
  );
}
