import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/teacher_movement.dart';
import 'package:elixr_application/data/models/teacher_movement_revision_spec.dart';
import 'package:elixr_application/data/models/teacher_reviewed_movement_spec.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/teacher_movement_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _wristAssessment({String laterality = 'either'}) {
  return {
    'schema_version': 1,
    'template_id': 'balance_stall.wrist_v1',
    'prop': 'bottle',
    'target': 'wrist',
    'laterality': laterality,
  };
}

Map<String, dynamic> _templateSpec({
  String requiredProp = 'bottle',
  String? safetyGuidance,
  Map<String, dynamic>? assessment,
  Map<String, dynamic>? extra,
}) {
  return {
    'instructions': 'Balance the bottle on the wrist.',
    'required_prop': requiredProp,
    'safety_guidance': ?safetyGuidance,
    'assessment': assessment ?? _wristAssessment(),
    ...?extra,
  };
}

Map<String, dynamic> _teacherReviewedSpec({String? safetyGuidance}) {
  return {
    'instructions': 'Hold the bottle still.',
    'required_prop': 'bottle',
    'capability': 'teacher_review_only',
    'safety_guidance': ?safetyGuidance,
  };
}

Map<String, dynamic> _revisionMap({
  required String assessmentMode,
  required Object spec,
}) {
  return {
    'movement_id': 'tm1',
    'teacher_id': 'teacher-1',
    'schema_version': 1,
    'assessment_mode': assessmentMode,
    'spec': spec,
  };
}

void main() {
  group('TemplateScoredRevisionSpec', () {
    test('parses a golden Wrist Stall wrapper', () {
      final spec = TemplateScoredRevisionSpec.tryFrom(_templateSpec());
      expect(spec, isNotNull);
      expect(spec!.instructions, 'Balance the bottle on the wrist.');
      expect(spec.requiredProp, TrainingProp.bottle);
      expect(spec.safetyGuidance, isNull);
      expect(spec.isTeacherReviewOnly, isFalse);
      expect(
        spec.assessment.templateId,
        AssessmentTemplateId.balanceStallWristV1,
      );
      expect(spec.assessment.laterality, AssessmentLaterality.either);
    });

    test(
      'parses an existing historical wrapper without a write serializer',
      () {
        final spec = TemplateScoredRevisionSpec.tryFrom(
          _templateSpec(safetyGuidance: 'Clear the area.'),
        );
        expect(spec, isNotNull);
        expect(spec!.safetyGuidance, 'Clear the area.');
        expect(spec.isTeacherReviewOnly, isFalse);
      },
    );

    test('exposes presentation fields and optional safety guidance', () {
      final spec = TemplateScoredRevisionSpec.tryFrom(
        _templateSpec(safetyGuidance: 'Keep elbows close.'),
      );
      expect(spec, isNotNull);
      expect(spec!.instructions, isNotEmpty);
      expect(spec.requiredProp, TrainingProp.bottle);
      expect(spec.safetyGuidance, 'Keep elbows close.');
    });

    test('rejects required_prop that disagrees with assessment.prop', () {
      expect(
        TemplateScoredRevisionSpec.tryFrom(
          _templateSpec(requiredProp: 'shaker'),
        ),
        isNull,
      );
    });

    test('rejects unknown wrapper keys', () {
      expect(
        TemplateScoredRevisionSpec.tryFrom(
          _templateSpec(extra: {'capability': 'teacher_review_only'}),
        ),
        isNull,
      );
      expect(
        TemplateScoredRevisionSpec.tryFrom(
          _templateSpec(extra: {'threshold': 0.4}),
        ),
        isNull,
      );
      expect(
        TemplateScoredRevisionSpec.tryFrom(
          _templateSpec(extra: {'hold_seconds': 2}),
        ),
        isNull,
      );
    });

    test('rejects a malformed nested AssessmentSpec', () {
      expect(
        TemplateScoredRevisionSpec.tryFrom(
          _templateSpec(assessment: _wristAssessment()..['threshold'] = 0.2),
        ),
        isNull,
      );
    });
  });

  group('TeacherReviewedMovementSpec backward compatibility', () {
    test('parses the Phase 5/6 persisted shape exactly', () {
      final spec = TeacherReviewedMovementSpec.tryFrom(
        _teacherReviewedSpec(safetyGuidance: 'Spot the trainee.'),
      );
      expect(spec, isNotNull);
      expect(spec!.instructions, 'Hold the bottle still.');
      expect(spec.requiredProp, TrainingProp.bottle);
      expect(spec.capability, TeacherReviewedMovementSpec.teacherReviewOnly);
      expect(spec.safetyGuidance, 'Spot the trainee.');
      expect(spec.isTeacherReviewOnly, isTrue);
    });

    test('toMap keeps the Phase 5/6 field shape', () {
      const spec = TeacherReviewedMovementSpec(
        instructions: 'Hold the bottle still.',
        requiredProp: TrainingProp.bottle,
        safetyGuidance: 'Spot the trainee.',
      );
      expect(spec.toMap(), {
        'instructions': 'Hold the bottle still.',
        'required_prop': 'bottle',
        'capability': 'teacher_review_only',
        'safety_guidance': 'Spot the trainee.',
      });
      expect(spec.toMap().containsKey('assessment'), isFalse);
      expect(spec.toMap().containsKey('template_id'), isFalse);
    });

    test('title, instructions, and safety guidance validators still apply', () {
      expect(TeacherReviewedMovementSpec.validateTitle(''), isNotNull);
      expect(TeacherReviewedMovementSpec.validateTitle('Wrist Stall'), isNull);
      expect(TeacherReviewedMovementSpec.validateInstructions(''), isNotNull);
      expect(
        TeacherReviewedMovementSpec.validateInstructions('Balance the bottle.'),
        isNull,
      );
      expect(TeacherReviewedMovementSpec.validateSafetyGuidance(''), isNull);
      expect(
        TeacherReviewedMovementSpec.validateSafetyGuidance('Clear space.'),
        isNull,
      );
    });
  });

  group('TeacherMovementRevision dispatch', () {
    test('parses an existing teacher_reviewed fixture', () {
      final revision = TeacherMovementRevision.tryFromMap(
        _revisionMap(
          assessmentMode: 'teacher_reviewed',
          spec: _teacherReviewedSpec(),
        ),
        id: 'rev1',
      );
      expect(revision, isNotNull);
      expect(revision!.assessmentMode, AssessmentMode.teacherReviewed);
      expect(revision.spec, isA<TeacherReviewedMovementSpec>());
      expect(revision.spec.instructions, 'Hold the bottle still.');
      expect(revision.spec.requiredProp, TrainingProp.bottle);
      expect(revision.spec.isTeacherReviewOnly, isTrue);
    });

    test('parses a valid template_scored fixture', () {
      final revision = TeacherMovementRevision.tryFromMap(
        _revisionMap(
          assessmentMode: 'template_scored',
          spec: _templateSpec(safetyGuidance: 'Clear the area.'),
        ),
        id: 'rev2',
      );
      expect(revision, isNotNull);
      expect(revision!.assessmentMode, AssessmentMode.templateScored);
      expect(revision.spec, isA<TemplateScoredRevisionSpec>());
      expect(revision.spec.instructions, 'Balance the bottle on the wrist.');
      expect(revision.spec.requiredProp, TrainingProp.bottle);
      expect(revision.spec.safetyGuidance, 'Clear the area.');
      expect(revision.spec.isTeacherReviewOnly, isFalse);
    });

    test('rejects teacher_reviewed plus a template spec payload', () {
      expect(
        TeacherMovementRevision.tryFromMap(
          _revisionMap(
            assessmentMode: 'teacher_reviewed',
            spec: _templateSpec(),
          ),
          id: 'rev3',
        ),
        isNull,
      );
    });

    test('rejects template_scored plus a teacher-review-only payload', () {
      expect(
        TeacherMovementRevision.tryFromMap(
          _revisionMap(
            assessmentMode: 'template_scored',
            spec: _teacherReviewedSpec(),
          ),
          id: 'rev4',
        ),
        isNull,
      );
    });

    test('rejects official_guided Teacher-created revisions', () {
      expect(
        TeacherMovementRevision.tryFromMap(
          _revisionMap(
            assessmentMode: 'official_guided',
            spec: _teacherReviewedSpec(),
          ),
          id: 'rev5',
        ),
        isNull,
      );
      expect(
        TeacherMovementRevision.tryFromMap(
          _revisionMap(
            assessmentMode: 'official_guided',
            spec: _templateSpec(),
          ),
          id: 'rev6',
        ),
        isNull,
      );
    });

    test('rejects a malformed template spec without falling back', () {
      expect(
        TeacherMovementRevision.tryFromMap(
          _revisionMap(
            assessmentMode: 'template_scored',
            spec: _templateSpec(
              assessment: _wristAssessment()..['eval'] = '1+1',
            ),
          ),
          id: 'rev7',
        ),
        isNull,
      );
      expect(
        TeacherMovementRevision.tryFromMap(
          _revisionMap(
            assessmentMode: 'template_scored',
            spec: _templateSpec(requiredProp: 'shaker'),
          ),
          id: 'rev8',
        ),
        isNull,
      );
      expect(
        TeacherMovementRevision.tryFromMap(
          _revisionMap(
            assessmentMode: 'template_scored',
            spec: _templateSpec(extra: {'formula': 'x'}),
          ),
          id: 'rev9',
        ),
        isNull,
      );
    });
  });

  group('Firestore write path remains teacher_reviewed-only', () {
    test('revision payload helper still emits the Phase 5/6 shape', () {
      const spec = TeacherReviewedMovementSpec(
        instructions: 'Hold the bottle still.',
        requiredProp: TrainingProp.bottle,
      );
      final payload = teacherMovementRevisionPayload(
        movementId: 'tm1',
        teacherId: 'teacher-1',
        spec: spec,
        createdAt: 'server',
      );
      expect(payload['assessment_mode'], 'teacher_reviewed');
      expect(payload['spec'], spec.toMap());
      expect((payload['spec'] as Map)['capability'], 'teacher_review_only');
      expect((payload['spec'] as Map).containsKey('assessment'), isFalse);
    });
  });
}
