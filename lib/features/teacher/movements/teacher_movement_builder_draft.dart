import '../../../data/models/teacher_activity_assessment.dart';
import '../../../data/models/training_prop.dart';

/// In-memory draft for a teacher-reviewed movement.
class TeacherMovementBuilderDraft {
  TeacherMovementBuilderDraft()
    : title = '',
      instructions = '',
      safetyGuidance = '',
      requiredProp = TrainingProp.bottle,
      readiness = TeacherActivityReadinessSpec.legacy(TrainingProp.bottle),
      rubricTemplate = TeacherActivityRubricTemplate.standardTechnique,
      maximumScore = TeacherActivityAssessmentContract.defaultMaximumScore,
      attemptPolicy = TeacherActivityAttemptPolicy.defaultPolicy,
      recordingDurationSeconds =
          TeacherActivityAssessmentContract.defaultRecordingDurationSeconds;

  TeacherMovementBuilderDraft.editingExisting({
    required this.title,
    required this.instructions,
    required this.requiredProp,
    String? safetyGuidance,
    TeacherActivityAssessmentConfig? assessment,
  }) : safetyGuidance = safetyGuidance ?? '',
       readiness =
           assessment?.readiness ??
           TeacherActivityReadinessSpec.legacy(requiredProp),
       rubricTemplate =
           assessment?.rubric.template ??
           TeacherActivityRubricTemplate.standardTechnique,
       maximumScore =
           assessment?.rubric.maximumScore ??
           TeacherActivityAssessmentContract.defaultMaximumScore,
       attemptPolicy =
           assessment?.attemptPolicy ??
           TeacherActivityAttemptPolicy.defaultPolicy,
       recordingDurationSeconds =
           assessment?.recordingDurationSeconds ??
           TeacherActivityAssessmentContract.defaultRecordingDurationSeconds,
       demonstrationVideo = assessment?.demonstrationVideo;

  String title;
  String instructions;
  String safetyGuidance;
  TrainingProp requiredProp;
  TeacherActivityReadinessSpec readiness;
  TeacherActivityRubricTemplate rubricTemplate;
  int maximumScore;
  TeacherActivityAttemptPolicy attemptPolicy;
  int recordingDurationSeconds;
  TeacherActivityVideoMetadata? demonstrationVideo;

  bool get usesCustomMaximumScore => !TeacherActivityAssessmentContract
      .supportedMaximumScores
      .contains(maximumScore);

  bool get hasValidMaximumScore => maximumScore >= 1 && maximumScore <= 100;

  TeacherActivityAssessmentConfig? buildAssessment() {
    if (!hasValidMaximumScore ||
        rubricTemplate == TeacherActivityRubricTemplate.custom) {
      return null;
    }
    return TeacherActivityAssessmentConfig(
      readiness: readiness,
      rubric: TeacherActivityRubric.builtIn(rubricTemplate, maximumScore),
      attemptPolicy: attemptPolicy,
      recordingDurationSeconds: recordingDurationSeconds,
      demonstrationVideo: demonstrationVideo,
    );
  }
}
