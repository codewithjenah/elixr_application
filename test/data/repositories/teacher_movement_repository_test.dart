import 'dart:io';

import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/teacher_movement.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/data/models/teacher_movement_revision_spec.dart';
import 'package:elixr_application/data/models/teacher_reviewed_movement_spec.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/data/repositories/teacher_movement_repository.dart';
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

  test(
    'demo upload returns bounded opaque metadata without a public URL',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'elixr_demo_test_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final clip = File('${directory.path}${Platform.pathSeparator}demo.mp4');
      await clip.writeAsBytes(<int>[0, 0, 0, 24, 102, 116, 121, 112]);

      final metadata = await repo.uploadActivityDemonstration(
        teacherId: 'teacher-1',
        localFile: clip,
        duration: const Duration(seconds: 12),
        source: TeacherActivityDemoSource.uploaded,
      );

      expect(
        metadata.storagePath,
        startsWith('teacher_activity_demos/teacher-1/'),
      );
      expect(metadata.storagePath, endsWith('.mp4'));
      expect(metadata.contentType, 'video/mp4');
      expect(metadata.sizeBytes, 8);
      expect(metadata.durationMs, 12000);
      expect(metadata.source, TeacherActivityDemoSource.uploaded);
      expect(repo.demonstrationMedia[metadata.storagePath], metadata);
    },
  );

  test('demo upload rejects clips over the contract duration', () async {
    final directory = await Directory.systemTemp.createTemp('elixr_demo_test_');
    addTearDown(() => directory.delete(recursive: true));
    final clip = File('${directory.path}${Platform.pathSeparator}demo.mp4');
    await clip.writeAsBytes(<int>[1]);

    expect(
      () => repo.uploadActivityDemonstration(
        teacherId: 'teacher-1',
        localFile: clip,
        duration: const Duration(seconds: 61),
        source: TeacherActivityDemoSource.recorded,
      ),
      throwsA(isA<ClassroomException>()),
    );
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

  test('delete removes an unused movement and every revision', () async {
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

    await repo.deleteMovement(teacherId: 'teacher-1', movementId: created.id);

    expect(await repo.getMovement(movementId: created.id), isNull);
    expect(
      await repo.getRevision(
        movementId: created.id,
        revisionId: created.currentRevisionId,
      ),
      isNull,
    );
    expect(
      await repo.getRevision(
        movementId: created.id,
        revisionId: edited.currentRevisionId,
      ),
      isNull,
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
    'historical template movements remain readable and archivable',
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
        ))!.isTemplateScored,
        isTrue,
      );
      await repo.archiveMovement(
        teacherId: 'teacher-1',
        movementId: movementId,
      );
      expect(
        (await repo.getMovement(movementId: movementId))!.status,
        TeacherMovementStatus.archived,
      );
    },
  );

  test(
    'create publishes an immutable Wrist Stall automatic revision',
    () async {
      final movement = await repo.createMovement(
        teacherId: 'teacher-1',
        title: 'Classroom Wrist Stall',
        instructions: 'Balance the bottle on the left wrist.',
        requiredProp: TrainingProp.bottle,
        automaticAssessment: const AssessmentSpec(
          laterality: AssessmentLaterality.left,
        ),
      );
      final revision = await repo.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      );
      expect(revision!.assessmentMode, AssessmentMode.templateScored);
      expect(
        (revision.spec as TemplateScoredRevisionSpec).assessment.laterality,
        AssessmentLaterality.left,
      );

      await expectLater(
        repo.createMovement(
          teacherId: 'teacher-1',
          title: 'Either Wrist Stall',
          instructions: 'Balance the bottle on either wrist.',
          requiredProp: TrainingProp.bottle,
          automaticAssessment: const AssessmentSpec(
            laterality: AssessmentLaterality.either,
          ),
        ),
        throwsA(isA<ClassroomException>()),
      );
    },
  );

  test(
    'createMovement Teacher Review payload matches repository batch maps',
    () {
      const teacherId = 'teacher-1';
      const movementId = 'tmTeacherReview';
      const revisionId = 'revTeacherReview';
      const createdAt = 'SERVER_TIMESTAMP';
      final spec = buildTeacherMovementSpec(
        title: 'Tin Balance',
        instructions: 'Balance the tin upright.',
        requiredProp: TrainingProp.bottle,
      );
      final root = teacherMovementRootPayload(
        teacherId: teacherId,
        title: 'Tin Balance',
        currentRevisionId: revisionId,
        status: TeacherMovementStatus.active.name,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final revision = teacherMovementRevisionPayload(
        movementId: movementId,
        teacherId: teacherId,
        spec: spec,
        createdAt: createdAt,
      );

      expect(root.keys.toSet(), {
        'teacher_id',
        'title',
        'status',
        'current_revision_id',
        'schema_version',
        'created_at',
        'updated_at',
      });
      expect(root['teacher_id'], teacherId);
      expect(root['title'], 'Tin Balance');
      expect(root['status'], 'active');
      expect(root['current_revision_id'], revisionId);
      expect(root['schema_version'], 1);
      expect(root['created_at'], createdAt);
      expect(root['updated_at'], createdAt);

      expect(revision.keys.toSet(), {
        'movement_id',
        'teacher_id',
        'schema_version',
        'assessment_mode',
        'spec',
        'created_at',
      });
      expect(revision['movement_id'], movementId);
      expect(revision['teacher_id'], teacherId);
      expect(revision['schema_version'], 2);
      expect(revision['assessment_mode'], 'teacher_reviewed');
      expect(revision['created_at'], createdAt);

      final specMap = revision['spec'] as Map<String, dynamic>;
      expect(specMap.keys.toSet(), {
        'instructions',
        'required_prop',
        'capability',
        'activity_assessment',
      });
      expect(specMap['instructions'], 'Balance the tin upright.');
      expect(specMap['required_prop'], 'bottle');
      expect(specMap['capability'], 'teacher_review_only');

      final assessment = specMap['activity_assessment'] as Map<String, dynamic>;
      expect(assessment.keys.toSet(), {
        'schema_version',
        'readiness',
        'rubric',
        'recording_duration_seconds',
      });
      expect(assessment['schema_version'], 3);
      expect(assessment['readiness'], {'hands': 'none', 'body': 'none'});
      expect(assessment['recording_duration_seconds'], 30);
      final rubric = assessment['rubric'] as Map<String, dynamic>;
      expect(rubric['template_id'], 'standard_technique');
      expect(rubric['maximum_score'], 50);
      final criteria = rubric['criteria'] as List<dynamic>;
      expect(criteria, hasLength(4));
      expect(criteria.map((item) => (item as Map)['id']), [
        'setup',
        'technique',
        'control',
        'finish',
      ]);
      expect(criteria[0], {
        'id': 'setup',
        'label': 'Setup',
        'description': 'Uses the required setup and starting position.',
        'maximum_points': 10,
        'weight': 20,
      });
      expect(criteria[1], {
        'id': 'technique',
        'label': 'Technique',
        'description':
            'Performs the demonstrated technique safely and accurately.',
        'maximum_points': 20,
        'weight': 40,
      });
      expect(criteria[2], {
        'id': 'control',
        'label': 'Control',
        'description':
            'Maintains deliberate control of props and body position.',
        'maximum_points': 13,
        'weight': 25,
      });
      expect(criteria[3], {
        'id': 'finish',
        'label': 'Finish',
        'description':
            'Completes the movement with a stable, intentional finish.',
        'maximum_points': 7,
        'weight': 15,
      });
      expect(
        criteria.fold<int>(
          0,
          (sum, item) => sum + ((item as Map)['maximum_points'] as int),
        ),
        50,
      );
      for (final criterion in criteria) {
        expect((criterion as Map).keys.toSet(), {
          'id',
          'label',
          'description',
          'maximum_points',
          'weight',
        });
      }
    },
  );

  test(
    'createMovement Automatic Wrist Stall Left payload matches repository batch maps',
    () {
      const teacherId = 'teacher-1';
      const movementId = 'tmWristLeft';
      const revisionId = 'revWristLeft';
      const createdAt = 'SERVER_TIMESTAMP';
      final spec = buildTeacherMovementSpec(
        title: 'Classroom Wrist Stall',
        instructions: 'Balance the bottle on the left wrist.',
        requiredProp: TrainingProp.bottle,
        automaticAssessment: const AssessmentSpec(
          laterality: AssessmentLaterality.left,
        ),
      );
      final root = teacherMovementRootPayload(
        teacherId: teacherId,
        title: 'Classroom Wrist Stall',
        currentRevisionId: revisionId,
        status: TeacherMovementStatus.active.name,
        createdAt: createdAt,
        updatedAt: createdAt,
      );
      final revision = teacherMovementRevisionPayload(
        movementId: movementId,
        teacherId: teacherId,
        spec: spec,
        createdAt: createdAt,
      );

      expect(root.keys.toSet(), {
        'teacher_id',
        'title',
        'status',
        'current_revision_id',
        'schema_version',
        'created_at',
        'updated_at',
      });
      expect(root['teacher_id'], teacherId);
      expect(root['status'], 'active');
      expect(root['current_revision_id'], revisionId);
      expect(root['schema_version'], 1);

      expect(revision['schema_version'], 1);
      expect(revision['assessment_mode'], 'template_scored');
      final specMap = revision['spec'] as Map<String, dynamic>;
      expect(specMap.keys.toSet(), {
        'instructions',
        'required_prop',
        'assessment',
      });
      expect(specMap['required_prop'], 'bottle');
      expect(specMap['assessment'], {
        'schema_version': 1,
        'template_id': 'balance_stall.wrist_v1',
        'prop': 'bottle',
        'target': 'wrist',
        'laterality': 'left',
      });
    },
  );
}
