import 'package:elixr_application/data/models/classroom_exceptions.dart';
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
}
