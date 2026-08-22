import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movement_builder_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('create draft defaults to teacher reviewed and persistable', () {
    final draft = TeacherMovementBuilderDraft();

    expect(draft.assessmentMode, AssessmentMode.teacherReviewed);
    expect(draft.canPersistTeacherReviewed, isTrue);
    expect(draft.canPersistTemplateScored, isFalse);
    expect(draft.canOpenLiveTest, isFalse);
    expect(draft.assessmentSpec, isNull);
    expect(draft.requiredProp, TrainingProp.bottle);
    expect(draft.laterality, AssessmentLaterality.either);
  });

  test('template scored builds the canonical five-field AssessmentSpec', () {
    final draft = TeacherMovementBuilderDraft()
      ..assessmentMode = AssessmentMode.templateScored
      ..title = 'Classroom Wrist Stall'
      ..instructions = 'Balance the bottle on the wrist.'
      ..safetyGuidance = 'Clear the area.'
      ..laterality = AssessmentLaterality.left;

    expect(draft.canPersistTeacherReviewed, isFalse);
    expect(draft.canPersistTemplateScored, isTrue);
    expect(draft.canOpenLiveTest, isTrue);
    expect(
      draft.assessmentSpec,
      const AssessmentSpec(laterality: AssessmentLaterality.left),
    );
    expect(draft.assessmentSpec!.toMap(), {
      'schema_version': 1,
      'template_id': 'balance_stall.wrist_v1',
      'prop': 'bottle',
      'target': 'wrist',
      'laterality': 'left',
    });
  });

  test('template laterality maps either, left, and right exactly', () {
    final draft = TeacherMovementBuilderDraft()
      ..assessmentMode = AssessmentMode.templateScored;

    expect(
      draft.buildAssessmentSpec(AssessmentLaterality.either).laterality,
      AssessmentLaterality.either,
    );
    expect(
      draft.buildAssessmentSpec(AssessmentLaterality.left).laterality,
      AssessmentLaterality.left,
    );
    expect(
      draft.buildAssessmentSpec(AssessmentLaterality.right).laterality,
      AssessmentLaterality.right,
    );
  });

  test('template draft locks Bottle and Wrist Stall identifiers', () {
    final spec = TeacherMovementBuilderDraft().buildAssessmentSpec(
      AssessmentLaterality.right,
    );

    expect(spec.schemaVersion, 1);
    expect(spec.templateId, AssessmentTemplateId.balanceStallWristV1);
    expect(spec.prop, AssessmentProp.bottle);
    expect(spec.target, AssessmentTarget.wrist);
    expect(spec.prop.wireValue, 'bottle');
    expect(spec.templateId.wireValue, 'balance_stall.wrist_v1');
  });

  test('live test draft carries presentation fields and typed spec', () {
    final draft = TeacherMovementBuilderDraft()
      ..assessmentMode = AssessmentMode.templateScored
      ..title = 'Wrist Stall check'
      ..instructions = 'Hold the bottle still.'
      ..safetyGuidance = 'Use a practice bottle.'
      ..laterality = AssessmentLaterality.right;

    final live = draft.toLiveTestDraft();
    expect(live.title, 'Wrist Stall check');
    expect(live.instructions, 'Hold the bottle still.');
    expect(live.safetyGuidance, 'Use a practice bottle.');
    expect(
      live.assessmentSpec,
      const AssessmentSpec(laterality: AssessmentLaterality.right),
    );
  });

  test('editing an existing movement stays teacher reviewed', () {
    final draft = TeacherMovementBuilderDraft.editingExisting(
      title: 'Tin Balance',
      instructions: 'Balance the tin.',
      requiredProp: TrainingProp.shaker,
      safetyGuidance: 'Clear space.',
    );

    expect(draft.assessmentMode, AssessmentMode.teacherReviewed);
    expect(draft.locksAssessmentMode, isTrue);
    expect(draft.canOpenLiveTest, isFalse);
    draft.assessmentMode = AssessmentMode.templateScored;
    expect(draft.assessmentMode, AssessmentMode.teacherReviewed);
    expect(draft.canPersistTeacherReviewed, isTrue);
    expect(draft.canPersistTemplateScored, isFalse);
  });

  test('editing a template movement stays template scored', () {
    final draft = TeacherMovementBuilderDraft.editingExisting(
      title: 'Classroom Wrist Stall',
      instructions: 'Balance the bottle.',
      requiredProp: TrainingProp.bottle,
      assessmentMode: AssessmentMode.templateScored,
      laterality: AssessmentLaterality.right,
    );

    expect(draft.assessmentMode, AssessmentMode.templateScored);
    expect(draft.locksAssessmentMode, isTrue);
    expect(draft.canPersistTemplateScored, isTrue);
    expect(draft.canOpenLiveTest, isTrue);
    expect(draft.laterality, AssessmentLaterality.right);
    draft.assessmentMode = AssessmentMode.teacherReviewed;
    expect(draft.assessmentMode, AssessmentMode.templateScored);
  });
}
