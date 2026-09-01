import '../../../data/models/teacher_activity_assessment.dart';
import '../../../data/models/training_prop.dart';

/// In-memory draft for a teacher-reviewed movement.
class TeacherMovementBuilderDraft {
  TeacherMovementBuilderDraft()
    : title = '',
      instructions = '',
      safetyGuidance = '',
      requiredProp = TrainingProp.bottle,
      readiness = const TeacherActivityReadinessSpec(),
      rubricTemplate = TeacherActivityRubricTemplate.standardTechnique,
      maximumScore = TeacherActivityAssessmentContract.defaultMaximumScore,
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
           const TeacherActivityReadinessSpec(),
       rubricTemplate =
           assessment?.rubric.template ??
           TeacherActivityRubricTemplate.standardTechnique,
       maximumScore =
           assessment?.rubric.maximumScore ??
           TeacherActivityAssessmentContract.defaultMaximumScore,
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
      recordingDurationSeconds: recordingDurationSeconds,
      demonstrationVideo: demonstrationVideo,
    );
  }
}
