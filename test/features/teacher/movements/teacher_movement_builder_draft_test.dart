import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movement_builder_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('create draft contains only teacher-reviewed fields', () {
    final draft = TeacherMovementBuilderDraft();

    expect(draft.title, isEmpty);
    expect(draft.instructions, isEmpty);
    expect(draft.safetyGuidance, isEmpty);
    expect(draft.requiredProp, TrainingProp.bottle);
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
  });
}
