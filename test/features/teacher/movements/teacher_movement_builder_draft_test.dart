import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/models/teacher_activity_assessment.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movement_builder_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('create draft contains Teacher Activity assessment defaults', () {
    final draft = TeacherMovementBuilderDraft();

    expect(draft.title, isEmpty);
    expect(draft.instructions, isEmpty);
    expect(draft.safetyGuidance, isEmpty);
    expect(draft.requiredProp, TrainingProp.bottle);
    expect(draft.readiness.hands, ActivityHandRequirement.none);
    expect(draft.readiness.body, ActivityBodyRequirement.none);
    expect(
      draft.rubricTemplate,
      TeacherActivityRubricTemplate.standardTechnique,
    );
    expect(draft.maximumScore, 50);
    expect(draft.recordingDurationSeconds, 30);
    expect(draft.buildAssessment(), isNotNull);
  });

  test('editing draft preserves the teacher-reviewed fields', () {
    final draft = TeacherMovementBuilderDraft.editingExisting(
      title: 'Tin Balance',
      instructions: 'Balance the tin.',
      requiredProp: TrainingProp.shaker,
      safetyGuidance: 'Clear space.',
    );

    expect(draft.title, 'Tin Balance');
    expect(draft.instructions, 'Balance the tin.');
    expect(draft.requiredProp, TrainingProp.shaker);
    expect(draft.safetyGuidance, 'Clear space.');
    expect(draft.buildAssessment()!.rubric.maximumScore, 50);
  });

  test('draft rejects an invalid custom maximum score', () {
    final draft = TeacherMovementBuilderDraft()..maximumScore = 101;

    expect(draft.hasValidMaximumScore, isFalse);
    expect(draft.buildAssessment(), isNull);
  });
}
