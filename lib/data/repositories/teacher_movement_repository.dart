import 'dart:io';

import '../models/assessment_mode.dart';
import '../models/assessment_spec.dart';
import '../models/classroom_exceptions.dart';
import '../models/teacher_movement.dart';
import '../models/teacher_activity_assessment.dart';
import '../models/teacher_movement_revision_spec.dart';
import '../models/teacher_reviewed_movement_spec.dart';
import '../models/training_prop.dart';

abstract class TeacherMovementRepository {
  /// Downloads a private Activity demonstration to a local playback cache.
  Future<File> openActivityDemonstration(TeacherActivityVideoMetadata metadata);

  /// Releases a file returned by [openActivityDemonstration].
  Future<void> releaseActivityDemonstration(File localFile);

  /// Uploads a locally validated MP4 used as a reusable Teacher Activity demo.
  ///
  /// The returned metadata is deliberately storage-path-only: callers persist it
  /// inside a new immutable movement revision instead of relying on a public URL.
  Future<TeacherActivityVideoMetadata> uploadActivityDemonstration({
    required String teacherId,
    required File localFile,
    required Duration duration,
    required TeacherActivityDemoSource source,
    String? assignmentId,
  });

  Future<TeacherMovement> createMovement({
    required String teacherId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
    TeacherActivityAssessmentConfig? assessment,
    AssessmentSpec? automaticAssessment,
  });

  /// Publishes a new immutable revision and points [currentRevisionId] at it.
  Future<TeacherMovement> editMovement({
    required String teacherId,
    required String movementId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
    TeacherActivityAssessmentConfig? assessment,
    AssessmentSpec? automaticAssessment,
  });

  Future<void> archiveMovement({
    required String teacherId,
    required String movementId,
  });

  /// Permanently removes an unused Teacher-created movement and its revisions.
  Future<void> deleteMovement({
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

TeacherMovementRevisionSpec buildTeacherMovementSpec({
  required String title,
  required String instructions,
  required TrainingProp requiredProp,
  String? safetyGuidance,
  TeacherActivityAssessmentConfig? assessment,
  AssessmentSpec? automaticAssessment,
}) {
  if (automaticAssessment != null && assessment != null) {
    throw _malformed(
      'Choose Teacher Review or Automatic ELIXR Assessment, not both.',
    );
  }
  if (automaticAssessment != null) {
    return buildTemplateScoredSpec(
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: automaticAssessment,
    );
  }
  return buildTeacherReviewedSpec(
    title: title,
    instructions: instructions,
    requiredProp: requiredProp,
    safetyGuidance: safetyGuidance,
    assessment: assessment,
  );
}

TemplateScoredRevisionSpec buildTemplateScoredSpec({
  required String title,
  required String instructions,
  required TrainingProp requiredProp,
  required AssessmentSpec assessment,
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
  if (requiredProp != TrainingProp.bottle) {
    throw _malformed('Wrist Stall uses a Bottle.');
  }
  if (!assessment.isWritableWristStallV1) {
    throw _malformed('Choose Left wrist or Right wrist.');
  }
  return TemplateScoredRevisionSpec(
    instructions: instructions.trim(),
    requiredProp: TrainingProp.bottle,
    safetyGuidance: () {
      final trimmed = safetyGuidance?.trim();
      if (trimmed == null || trimmed.isEmpty) return null;
      return trimmed;
    }(),
    assessment: assessment,
  );
}

TeacherReviewedMovementSpec buildTeacherReviewedSpec({
  required String title,
  required String instructions,
  required TrainingProp requiredProp,
  String? safetyGuidance,
  TeacherActivityAssessmentConfig? assessment,
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
    assessment:
        assessment ?? TeacherActivityAssessmentConfig.newActivityDefaults(),
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
  required TeacherMovementRevisionSpec spec,
  required Object createdAt,
}) {
  final mode = spec is TemplateScoredRevisionSpec
      ? AssessmentMode.templateScored
      : AssessmentMode.teacherReviewed;
  final schemaVersion = spec is TemplateScoredRevisionSpec
      ? TeacherMovement.currentSchemaVersion
      : TeacherReviewedMovementSpec.currentSchemaVersion;
  return {
    'movement_id': movementId,
    'teacher_id': teacherId,
    'schema_version': schemaVersion,
    'assessment_mode': mode.wireValue,
    'spec': switch (spec) {
      final TeacherReviewedMovementSpec reviewed => reviewed.toMap(),
      final TemplateScoredRevisionSpec template => template.toMap(),
      _ => throw StateError('Unsupported Teacher-created revision spec.'),
    },
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
