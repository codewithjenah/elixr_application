import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:elixr_core/models/elixr_group.dart';

import '../models/assessment_mode.dart';
import '../models/assignment_attempt.dart';
import '../models/assignment_attempt_ids.dart';
import '../models/assignment_submission_limits.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/movement_origin.dart';
import '../models/teacher_movement.dart';
import '../models/teacher_reviewed_movement_spec.dart';
import '../models/training_prop.dart';

abstract class ClassroomAssignmentRepository {
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    String? displayInstructions,
  });

  Future<GroupAssignment> createTeacherCreatedAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    int maxScore = 100,
    DateTime? dueAt,
  });

  Future<void> archiveAssignment({
    required String teacherId,
    required String assignmentId,
  });

  Future<GroupAssignment?> getAssignment({required String assignmentId});

  Stream<List<GroupAssignment>> watchTeacherAssignments({
    required String teacherId,
  });

  Future<List<GroupAssignment>> fetchAssignmentsForGroup({
    required String groupId,
  });

  Stream<List<AssignmentAttempt>> watchAttemptsForAssignment({
    required String teacherId,
    required String assignmentId,
  });

  Stream<List<AssignmentAttempt>> watchAttemptsForTeacher({
    required String teacherId,
  });

  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  });

  Future<AssignmentAttempt?> getAttempt({required String attemptId});

  Future<AssignmentAttempt> startTeacherCreatedAttempt({
    required String traineeId,
    required GroupAssignment assignment,
  });

  Future<AssignmentAttempt> createTeacherReviewSubmissionDraft({
    required String traineeId,
    required GroupAssignment assignment,
    String? supersedesAttemptId,
    String? attemptId,
  });

  /// Returns the one reusable submission document for this trainee and
  /// assignment. It never creates a second submission after a prior submit.
  Future<AssignmentAttempt> getOrCreateTeacherReviewSubmission({
    required String traineeId,
    required GroupAssignment assignment,
  });

  Future<void> markTeacherReviewSubmissionAbandoned({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? abandonedAt,
    DateTime? videoDeletedAt,
    bool deletionFailed = false,
    DateTime? deletionFailedAt,
  });

  Future<AssignmentAttempt> markTeacherReviewSubmitted({
    required String traineeId,
    required AssignmentAttempt attempt,
    required String videoStoragePath,
    required String videoContentType,
    required int videoSizeBytes,
    required int videoDurationMs,
    required DateTime submittedAt,
    required DateTime videoExpiresAt,
  });

  /// Atomically claims an unchecked submission for withdrawal. A failed
  /// Storage delete leaves the document in `unsubmitting` so this operation
  /// can be retried safely.
  Future<AssignmentAttempt> beginTeacherReviewUnsubmit({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? startedAt,
  });

  /// Clears the clip metadata and returns the same submission document to
  /// `in_progress` after its Storage object has been deleted.
  Future<AssignmentAttempt> completeTeacherReviewUnsubmit({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? completedAt,
  });

  Future<AssignmentAttempt> saveTeacherReview({
    required String teacherId,
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
    required int gradeScore,
    String? feedback,
    DateTime? reviewedAt,
  });

  Future<GroupAssignment> updateTeacherAssignmentMaxScore({
    required String teacherId,
    required String assignmentId,
    required int maxScore,
  });

  Future<AssignmentAttempt> markTeacherReviewResultSent({
    required String teacherId,
    required AssignmentAttempt attempt,
    required String messageId,
    DateTime? sentAt,
  });

  Future<AssignmentAttempt> reviewTeacherSubmission({
    required String teacherId,
    required AssignmentAttempt attempt,
    required AssignmentReviewVerdict verdict,
    String? feedback,
    required DateTime reviewedAt,
    required DateTime videoExpiresAt,
  });

  Future<void> markSubmissionVideoDeleted({
    required String actorId,
    required AssignmentAttempt attempt,
    required DateTime deletedAt,
  });

  Future<void> markSubmissionDeletionFailed({
    required String actorId,
    required AssignmentAttempt attempt,
    required DateTime failedAt,
  });
}

void ensureTeacherOwnsActiveGroup({
  required String teacherId,
  required ElixrGroup group,
}) {
  if (group.teacherId != teacherId) {
    throw const ClassroomException(ClassroomError.forbidden);
  }
  if (!group.isActive) {
    throw const ClassroomException(ClassroomError.inactive);
  }
}

Map<String, dynamic> officialAssignmentPayload({
  required String teacherId,
  required String teacherDisplayName,
  required ElixrGroup group,
  required String officialMovementName,
  required String displayInstructions,
  DateTime? dueAt,
  required Object createdAt,
  required Object updatedAt,
}) {
  final identity = officialElixrIdentityForName(officialMovementName);
  if (identity == null) {
    throw ClassroomException(
      ClassroomError.unofficial,
      'Not an official ELIXR movement.',
    );
  }
  return {
    'teacher_id': teacherId,
    'group_id': group.id,
    'movement_id': identity.movementId,
    'revision_id': identity.revisionId,
    'origin': MovementOrigin.officialElixr.wireValue,
    'assessment_mode': AssessmentMode.officialGuided.wireValue,
    'status': GroupAssignmentStatus.active.name,
    'official_movement_name': identity.catalogName,
    'display_title': identity.catalogName,
    'teacher_display_name': teacherDisplayName.trim(),
    'group_name': group.name,
    'created_at': createdAt,
    'updated_at': updatedAt,
    if (displayInstructions.trim().isNotEmpty)
      'display_instructions': displayInstructions.trim(),
    'due_at': ?dueAt,
  };
}

Map<String, dynamic> teacherCreatedAssignmentPayload({
  required String teacherId,
  required String teacherDisplayName,
  required ElixrGroup group,
  required TeacherMovement movement,
  required TeacherMovementRevision revision,
  int maxScore = 100,
  DateTime? dueAt,
  required Object createdAt,
  required Object updatedAt,
}) {
  ensureTeacherAssignmentMaxScore(maxScore);
  if (movement.teacherId != teacherId || revision.teacherId != teacherId) {
    throw const ClassroomException(ClassroomError.forbidden);
  }
  if (revision.movementId != movement.id) {
    throw const ClassroomException(ClassroomError.identityMismatch);
  }
  if (!movement.isActive) {
    throw const ClassroomException(ClassroomError.archived);
  }
  if (revision.id != movement.currentRevisionId) {
    throw const ClassroomException(
      ClassroomError.identityMismatch,
      'Assign the current revision of this movement.',
    );
  }

  if (revision.assessmentMode != AssessmentMode.teacherReviewed ||
      revision.spec is! TeacherReviewedMovementSpec) {
    throw const ClassroomException(
      ClassroomError.identityMismatch,
      'Retired template-scored movements are read-only and cannot be assigned.',
    );
  }

  final payload = <String, dynamic>{
    'teacher_id': teacherId,
    'group_id': group.id,
    'movement_id': movement.id,
    'revision_id': revision.id,
    'origin': MovementOrigin.teacherCreated.wireValue,
    'assessment_mode': AssessmentMode.teacherReviewed.wireValue,
    'status': GroupAssignmentStatus.active.name,
    'display_title': movement.title,
    'display_instructions': revision.spec.instructions,
    'display_safety_guidance': ?revision.spec.safetyGuidance,
    'allowed_prop': revision.spec.requiredProp.protocolValue,
    'teacher_display_name': teacherDisplayName.trim(),
    'group_name': group.name,
    'max_score': maxScore,
    'grading_locked': false,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'due_at': ?dueAt,
  };

  return payload;
}

void ensureTeacherAssignmentMaxScore(int maxScore) {
  if (maxScore < 1 || maxScore > 100) {
    throw const ClassroomException(
      ClassroomError.invalidGrade,
      'Maximum score must be between 1 and 100.',
    );
  }
}

void ensureTeacherReviewGrade({
  required int gradeScore,
  required int maxScore,
}) {
  ensureTeacherAssignmentMaxScore(maxScore);
  if (gradeScore < 0 || gradeScore > maxScore) {
    throw const ClassroomException(
      ClassroomError.invalidGrade,
      'Grade must be between 0 and the assignment maximum.',
    );
  }
}

void ensureTeacherReviewSubmissionVideo({
  required AssignmentAttempt attempt,
  required String videoStoragePath,
  required String videoContentType,
  required int videoSizeBytes,
  required int videoDurationMs,
  required DateTime submittedAt,
  required DateTime videoExpiresAt,
}) {
  final expectedPath = assignmentSubmissionStoragePath(
    teacherId: attempt.teacherId,
    groupId: attempt.groupId,
    assignmentId: attempt.assignmentId,
    traineeId: attempt.traineeId,
    attemptId: attempt.id,
  );
  if (videoStoragePath != expectedPath ||
      videoContentType != AssignmentSubmissionLimits.contentType ||
      videoSizeBytes <= 0 ||
      videoSizeBytes > AssignmentSubmissionLimits.maxSizeBytes ||
      videoDurationMs <= 0 ||
      videoDurationMs > AssignmentSubmissionLimits.maxDurationMs ||
      submittedAt.toUtc().isAfter(videoExpiresAt.toUtc())) {
    throw const ClassroomException(
      ClassroomError.malformed,
      'Submission clip metadata is invalid.',
    );
  }
}

AssignmentAttempt teacherCreatedDraftAttempt({
  required String traineeId,
  required GroupAssignment assignment,
  DateTime? createdAt,
}) {
  if (!assignment.isTeacherCreated) {
    throw const ClassroomException(ClassroomError.identityMismatch);
  }
  if (!assignment.isActive) {
    throw const ClassroomException(ClassroomError.inactive);
  }
  if (assignment.assessmentMode != AssessmentMode.teacherReviewed) {
    throw const ClassroomException(ClassroomError.identityMismatch);
  }
  return AssignmentAttempt(
    id: assignmentAttemptIdForTeacherCreatedDraft(
      assignmentId: assignment.id,
      traineeId: traineeId,
    ),
    traineeId: traineeId,
    teacherId: assignment.teacherId,
    groupId: assignment.groupId,
    assignmentId: assignment.id,
    movementId: assignment.movementId,
    revisionId: assignment.revisionId,
    origin: MovementOrigin.teacherCreated,
    assessmentMode: assignment.assessmentMode,
    attemptKind: AssignmentAttemptKind.teacherReviewDraft,
    status: AssignmentAttemptStatus.inProgress,
    createdAt: createdAt,
  );
}

/// Exact Phase 5 identity required before reusing a Teacher-created attempt.
bool isReusableTeacherCreatedStartAttempt({
  required AssignmentAttempt attempt,
  required String traineeId,
  required GroupAssignment assignment,
}) {
  return attempt.traineeId == traineeId &&
      attempt.teacherId == assignment.teacherId &&
      attempt.groupId == assignment.groupId &&
      attempt.assignmentId == assignment.id &&
      attempt.movementId == assignment.movementId &&
      attempt.revisionId == assignment.revisionId &&
      attempt.origin == MovementOrigin.teacherCreated &&
      attempt.assessmentMode == AssessmentMode.teacherReviewed &&
      attempt.attemptKind == AssignmentAttemptKind.teacherReviewDraft &&
      attempt.awardsGlobalXp == false &&
      attempt.sourceSessionId == null &&
      (attempt.status == AssignmentAttemptStatus.draft ||
          attempt.status == AssignmentAttemptStatus.inProgress);
}

AssignmentAttempt teacherCreatedAttemptWithStatus({
  required AssignmentAttempt attempt,
  required AssignmentAttemptStatus status,
}) {
  return attempt.copyWith(status: status);
}

/// Create the canonical draft first. Only read an existing document after a
/// permission-denied write, which is how Firestore evaluates `set` on an
/// already-created deterministic ID (update, not create).
Future<AssignmentAttempt> startTeacherCreatedAttemptWorkflow({
  required String traineeId,
  required GroupAssignment assignment,
  required Future<void> Function(AssignmentAttempt draft) create,
  required Future<AssignmentAttempt?> Function(String attemptId) readExisting,
  required Future<AssignmentAttempt> Function(AssignmentAttempt existing)
  promoteDraftToInProgress,
  required bool Function(Object error) isPermissionDenied,
}) async {
  final draft = teacherCreatedDraftAttempt(
    traineeId: traineeId,
    assignment: assignment,
  );
  try {
    await create(draft);
    return draft;
  } catch (error) {
    if (!isPermissionDenied(error)) rethrow;
  }

  final existing = await readExisting(draft.id);
  if (existing == null) {
    throw const ClassroomException(ClassroomError.notFound);
  }
  if (!isReusableTeacherCreatedStartAttempt(
    attempt: existing,
    traineeId: traineeId,
    assignment: assignment,
  )) {
    throw const ClassroomException(ClassroomError.identityMismatch);
  }
  if (existing.status == AssignmentAttemptStatus.inProgress) {
    return existing;
  }
  return promoteDraftToInProgress(existing);
}

TrainingProp? assignmentAllowedProp(GroupAssignment assignment) {
  return assignment.allowedProp;
}

AssignmentAttempt teacherReviewSubmissionDraftAttempt({
  required String traineeId,
  required GroupAssignment assignment,
  required String attemptId,
  String? supersedesAttemptId,
  DateTime? createdAt,
}) {
  if (!assignment.isTeacherCreated) {
    throw const ClassroomException(ClassroomError.identityMismatch);
  }
  if (!assignment.isActive) {
    throw const ClassroomException(ClassroomError.inactive);
  }
  if (assignment.assessmentMode != AssessmentMode.teacherReviewed) {
    throw const ClassroomException(ClassroomError.identityMismatch);
  }
  return AssignmentAttempt(
    id: attemptId,
    traineeId: traineeId,
    teacherId: assignment.teacherId,
    groupId: assignment.groupId,
    assignmentId: assignment.id,
    movementId: assignment.movementId,
    revisionId: assignment.revisionId,
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.draft,
    createdAt: createdAt,
    supersedesAttemptId: supersedesAttemptId,
  );
}

AssignmentAttempt canonicalTeacherReviewSubmissionAttempt({
  required String traineeId,
  required GroupAssignment assignment,
  DateTime? createdAt,
}) {
  if (!assignment.isTeacherCreated ||
      assignment.assessmentMode != AssessmentMode.teacherReviewed) {
    throw const ClassroomException(ClassroomError.identityMismatch);
  }
  if (!assignment.isActive) {
    throw const ClassroomException(ClassroomError.inactive);
  }
  return AssignmentAttempt(
    id: assignmentAttemptIdForCanonicalTeacherReviewSubmission(
      assignmentId: assignment.id,
      traineeId: traineeId,
    ),
    traineeId: traineeId,
    teacherId: assignment.teacherId,
    groupId: assignment.groupId,
    assignmentId: assignment.id,
    movementId: assignment.movementId,
    revisionId: assignment.revisionId,
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.inProgress,
    createdAt: createdAt,
  );
}

bool isReusableCanonicalTeacherReviewSubmission({
  required AssignmentAttempt attempt,
  required String traineeId,
  required GroupAssignment assignment,
}) {
  return attempt.isCanonicalTeacherReviewSubmission &&
      attempt.traineeId == traineeId &&
      attempt.teacherId == assignment.teacherId &&
      attempt.groupId == assignment.groupId &&
      attempt.assignmentId == assignment.id &&
      attempt.movementId == assignment.movementId &&
      attempt.revisionId == assignment.revisionId &&
      attempt.origin == MovementOrigin.teacherCreated &&
      attempt.assessmentMode == AssessmentMode.teacherReviewed &&
      attempt.attemptKind == AssignmentAttemptKind.teacherReviewSubmission &&
      attempt.supersedesAttemptId == null &&
      attempt.status != AssignmentAttemptStatus.draft &&
      attempt.status != AssignmentAttemptStatus.approved &&
      attempt.status != AssignmentAttemptStatus.needsRetry;
}

bool isTeacherAssignmentSubmissionOpen({
  required GroupAssignment assignment,
  DateTime? now,
}) {
  if (!assignment.isActive) return false;
  final dueAt = assignment.dueAt;
  return dueAt == null ||
      !(now ?? DateTime.now().toUtc()).toUtc().isAfter(dueAt.toUtc());
}

void ensureCanSupersedeNeedsRetry({
  required AssignmentAttempt previous,
  required String traineeId,
  required GroupAssignment assignment,
}) {
  if (previous.attemptKind != AssignmentAttemptKind.teacherReviewSubmission ||
      previous.status != AssignmentAttemptStatus.needsRetry ||
      previous.reviewVerdict != AssignmentReviewVerdict.needsRetry ||
      previous.traineeId != traineeId ||
      previous.teacherId != assignment.teacherId ||
      previous.groupId != assignment.groupId ||
      previous.assignmentId != assignment.id ||
      previous.movementId != assignment.movementId ||
      previous.revisionId != assignment.revisionId) {
    throw const ClassroomException(ClassroomError.invalidState);
  }
}

bool canMarkTeacherReviewSubmissionAbandoned({
  required AssignmentAttempt attempt,
  required String traineeId,
}) {
  return attempt.traineeId == traineeId &&
      attempt.attemptKind == AssignmentAttemptKind.teacherReviewSubmission &&
      attempt.status == AssignmentAttemptStatus.draft &&
      attempt.abandonedAt == null &&
      attempt.awardsGlobalXp == false &&
      attempt.sourceSessionId == null &&
      attempt.submittedAt == null &&
      attempt.videoExpiresAt == null &&
      attempt.videoStoragePath == null &&
      attempt.videoContentType == null &&
      attempt.videoSizeBytes == null &&
      attempt.videoDurationMs == null &&
      attempt.videoDeletedAt == null &&
      attempt.reviewVerdict == null &&
      attempt.reviewFeedback == null &&
      attempt.reviewedAt == null &&
      attempt.deletionFailed == false;
}
