import '../../../data/models/training_prop.dart';

/// In-memory draft for a teacher-reviewed movement.
class TeacherMovementBuilderDraft {
  TeacherMovementBuilderDraft()
    : title = '',
      instructions = '',
      safetyGuidance = '',
      requiredProp = TrainingProp.bottle;

  TeacherMovementBuilderDraft.editingExisting({
    required this.title,
    required this.instructions,
    required this.requiredProp,
    String? safetyGuidance,
  }) : safetyGuidance = safetyGuidance ?? '';

  String title;
  String instructions;
  String safetyGuidance;
  TrainingProp requiredProp;
}
