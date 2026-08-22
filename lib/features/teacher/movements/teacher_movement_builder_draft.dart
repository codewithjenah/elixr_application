import '../../../data/models/assessment_mode.dart';
import '../../../data/models/assessment_spec.dart';
import '../../../data/models/training_prop.dart';

/// In-memory Teacher Movement Builder draft.
class TeacherMovementBuilderDraft {
  TeacherMovementBuilderDraft()
    : _assessmentMode = AssessmentMode.teacherReviewed,
      locksAssessmentMode = false,
      title = '',
      instructions = '',
      safetyGuidance = '',
      requiredProp = TrainingProp.bottle,
      laterality = AssessmentLaterality.either;

  TeacherMovementBuilderDraft.editingExisting({
    required this.title,
    required this.instructions,
    required this.requiredProp,
    String? safetyGuidance,
    AssessmentMode assessmentMode = AssessmentMode.teacherReviewed,
    this.laterality = AssessmentLaterality.either,
  }) : _assessmentMode = assessmentMode == AssessmentMode.officialGuided
           ? AssessmentMode.teacherReviewed
           : assessmentMode,
       locksAssessmentMode = true,
       safetyGuidance = safetyGuidance ?? '';

  AssessmentMode _assessmentMode;
  final bool locksAssessmentMode;
  String title;
  String instructions;
  String safetyGuidance;
  TrainingProp requiredProp;
  AssessmentLaterality laterality;

  AssessmentMode get assessmentMode => _assessmentMode;

  set assessmentMode(AssessmentMode value) {
    if (locksAssessmentMode) return;
    _assessmentMode = value;
  }

  bool get isTemplateScored => _assessmentMode == AssessmentMode.templateScored;

  bool get canPersistTeacherReviewed => !isTemplateScored;

  bool get canPersistTemplateScored => isTemplateScored;

  bool get canOpenLiveTest => isTemplateScored;

  AssessmentSpec? get assessmentSpec =>
      isTemplateScored ? buildAssessmentSpec(laterality) : null;

  AssessmentSpec buildAssessmentSpec(AssessmentLaterality selected) {
    return AssessmentSpec(laterality: selected);
  }

  TeacherLiveTestDraft toLiveTestDraft() {
    return TeacherLiveTestDraft(
      title: title.trim().isEmpty ? 'Wrist Stall' : title.trim(),
      instructions: instructions.trim(),
      safetyGuidance: () {
        final trimmed = safetyGuidance.trim();
        return trimmed.isEmpty ? null : trimmed;
      }(),
      assessmentSpec: buildAssessmentSpec(laterality),
    );
  }
}

/// Ephemeral Live Test payload. No Firestore document is required.
class TeacherLiveTestDraft {
  const TeacherLiveTestDraft({
    required this.title,
    required this.instructions,
    required this.assessmentSpec,
    this.safetyGuidance,
  });

  final String title;
  final String instructions;
  final String? safetyGuidance;
  final AssessmentSpec assessmentSpec;

  String get lateralityLabel =>
      lateralityTeacherLabel(assessmentSpec.laterality);
}

String lateralityTeacherLabel(AssessmentLaterality laterality) {
  return switch (laterality) {
    AssessmentLaterality.either => 'Either wrist',
    AssessmentLaterality.left => 'Left wrist',
    AssessmentLaterality.right => 'Right wrist',
  };
}
