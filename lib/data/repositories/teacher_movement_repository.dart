import '../models/assessment_mode.dart';
import '../models/classroom_exceptions.dart';
import '../models/teacher_movement.dart';
import '../models/teacher_reviewed_movement_spec.dart';
import '../models/training_prop.dart';

abstract class TeacherMovementRepository {
  Future<TeacherMovement> createMovement({
    required String teacherId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  });

  /// Publishes a new immutable revision and points [currentRevisionId] at it.
  Future<TeacherMovement> editMovement({
    required String teacherId,
    required String movementId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  });

  Future<void> archiveMovement({
    required String teacherId,
    required String movementId,
  });

  Stream<List<TeacherMovement>> watchTeacherMovements({
    required String teacherId,
  });

  Future<TeacherMovement?> getMovement({required String movementId});

  Future<TeacherMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  });
}

ClassroomException _malformed(String message) =>
    ClassroomException(ClassroomError.malformed, message);

TeacherReviewedMovementSpec buildTeacherReviewedSpec({
  required String title,
  required String instructions,
  required TrainingProp requiredProp,
  String? safetyGuidance,
}) {
  final titleError = TeacherReviewedMovementSpec.validateTitle(title);
  if (titleError != null) throw _malformed(titleError);
  final instructionsError = TeacherReviewedMovementSpec.validateInstructions(
    instructions,
  );
  if (instructionsError != null) throw _malformed(instructionsError);
  final safetyError = TeacherReviewedMovementSpec.validateSafetyGuidance(
    safetyGuidance,
  );
  if (safetyError != null) throw _malformed(safetyError);
  return TeacherReviewedMovementSpec(
    instructions: instructions.trim(),
    requiredProp: requiredProp,
    safetyGuidance: () {
      final trimmed = safetyGuidance?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      return trimmed;
    }(),
  );
}

Map<String, dynamic> teacherMovementRootPayload({
  required String teacherId,
  required String title,
  required String currentRevisionId,
  required String status,
  required Object createdAt,
  required Object updatedAt,
}) {
  return {
    'teacher_id': teacherId,
    'title': title.trim(),
    'status': status,
    'current_revision_id': currentRevisionId,
    'schema_version': TeacherMovement.currentSchemaVersion,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
}

Map<String, dynamic> teacherMovementRevisionPayload({
  required String movementId,
  required String teacherId,
  required TeacherReviewedMovementSpec spec,
  required Object createdAt,
}) {
  return {
    'movement_id': movementId,
    'teacher_id': teacherId,
    'schema_version': TeacherReviewedMovementSpec.currentSchemaVersion,
    'assessment_mode': AssessmentMode.teacherReviewed.wireValue,
    'spec': spec.toMap(),
    'created_at': createdAt,
  };
}

void ensureRevisionAssessmentMode({
  required TeacherMovementRevision? revision,
  required AssessmentMode expected,
}) {
  if (revision == null) {
    throw const ClassroomException(ClassroomError.notFound);
  }
  if (revision.assessmentMode != expected) {
    throw const ClassroomException(
      ClassroomError.identityMismatch,
      'Assessment mode cannot change for an existing movement.',
    );
  }
}
