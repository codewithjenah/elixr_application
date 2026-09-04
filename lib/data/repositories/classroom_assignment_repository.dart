import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';

import '../models/assessment_mode.dart';
import '../models/assignment_attempt_policy.dart';
import '../models/assignment_attempt.dart';
import '../models/assignment_attempt_ids.dart';
import '../models/assignment_submission_limits.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/movement_origin.dart';
import '../models/teacher_movement.dart';
import '../models/teacher_activity_assessment.dart';
import '../models/teacher_reviewed_movement_spec.dart';
import '../models/training_prop.dart';

abstract class ClassroomAssignmentRepository {
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    String? displayInstructions,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.legacyDefault,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  });

  Future<GroupAssignment> createTeacherCreatedAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    int maxScore = 100,
    TeacherActivityAssessmentConfig? activityAssessment,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.teacherActivityDefault,
    String? displayTitle,
    String? displayInstructions,
    String? displaySafetyGuidance,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  });

  Future<void> archiveAssignment({
    required String teacherId,
    required String assignmentId,
  });

  Future<void> restoreAssignment({
    required String teacherId,
    required String assignmentId,
  });

  Future<void> publishAssignmentNow({
    required String teacherId,
    required String assignmentId,
  });

  Future<void> scheduleAssignmentPublication({
    required String teacherId,
    required String assignmentId,
    required DateTime publishAt,
  });

  /// Updates the fields a teacher may safely change after publishing.
  ///
  /// Teacher-created assignments can also change their maximum score until a
  /// submission has been checked. Passing a null [dueAt] clears the deadline.
  Future<GroupAssignment> updateAssignmentSettings({
    required String teacherId,
    required String assignmentId,
    DateTime? dueAt,
    int? maxScore,
    String? topic,
  });

  Future<GroupAssignment> updateTeacherActivityAssignment({
    required String teacherId,
    required String assignmentId,
    required int expectedConfigurationRevision,
    required String displayTitle,
    required String instructions,
    String? safetyGuidance,
    String? topic,
    DateTime? dueAt,
    required AssignmentAudience audience,
    required TeacherActivityAssessmentConfig activityAssessment,
    required AssignmentAttemptPolicy attemptPolicy,
    required TrainingProp requiredProp,
  });

  Future<GroupAssignment> createOfficialAssignmentWithTopic({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    String? displayInstructions,
    String? topic,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.legacyDefault,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) => createOfficialAssignment(
    teacherId: teacherId,
    teacherDisplayName: teacherDisplayName,
    group: group,
    officialMovementName: officialMovementName,
    dueAt: dueAt,
    status: status,
    publishAt: publishAt,
    displayInstructions: displayInstructions,
    attemptPolicy: attemptPolicy,
    audience: audience,
  );

  Future<GroupAssignment> createTeacherCreatedAssignmentWithTopic({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    int maxScore = 100,
    TeacherActivityAssessmentConfig? activityAssessment,
    AssignmentAttemptPolicy attemptPolicy =
        AssignmentAttemptPolicy.teacherActivityDefault,
    String? displayTitle,
    String? displayInstructions,
    String? displaySafetyGuidance,
    DateTime? dueAt,
    GroupAssignmentStatus status = GroupAssignmentStatus.active,
    DateTime? publishAt,
    String? topic,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) => createTeacherCreatedAssignment(
    teacherId: teacherId,
    teacherDisplayName: teacherDisplayName,
    group: group,
    movement: movement,
    revision: revision,
    maxScore: maxScore,
    activityAssessment: activityAssessment,
    attemptPolicy: attemptPolicy,
    displayTitle: displayTitle,
    displayInstructions: displayInstructions,
    displaySafetyGuidance: displaySafetyGuidance,
    dueAt: dueAt,
    status: status,
    publishAt: publishAt,
    audience: audience,
  );

  Future<GroupAssignment?> getAssignment({required String assignmentId});

  Future<bool> hasTeacherAssignmentForMovement({
    required String teacherId,
    required String movementId,
  });

  Stream<List<GroupAssignment>> watchTeacherAssignments({
    required String teacherId,
  });

  Future<List<GroupAssignment>> fetchAssignmentsForGroup({
    required String groupId,
  });

  /// Returns only assignments this authenticated Trainee may access.
  Future<List<GroupAssignment>> fetchAssignmentsForTrainee({
    required String traineeId,
    String? groupId,
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

  /// Server-authoritative v2 reservation. A reservation does not consume a
  /// finite attempt until [consumeTeacherActivityAttempt] succeeds.
  Future<AssignmentAttempt> reserveTeacherActivityAttempt({
    required String traineeId,
    required GroupAssignment assignment,
    required String requestId,
  });

  Future<void> consumeTeacherActivityAttempt({
    required String traineeId,
    required AssignmentAttempt attempt,
  });

  /// Releases the active reservation after cancellation, navigation, or a
  /// recorder failure. A consumed attempt remains counted and is retained as
  /// abandoned evidence metadata; an unconsumed reservation costs no attempt.
  Future<void> abandonTeacherActivityAttempt({
    required String traineeId,
    required AssignmentAttempt attempt,
  });

  Future<void> permanentlyDeleteAssignment({
    required String teacherId,
    required String assignmentId,
    required String confirmation,
  });

  Future<void> permanentlyDeleteClassroom({
    required String teacherId,
    required String groupId,
    required String confirmation,
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

  /// Stores an uploaded clip as private trainee work. Teachers cannot see this
  /// state; the trainee must call [turnInTeacherReviewSubmission] explicitly.
  Future<AssignmentAttempt> saveTeacherReviewDraftClip({
    required String traineeId,
    required AssignmentAttempt attempt,
    required String videoStoragePath,
    required String videoContentType,
    required int videoSizeBytes,
    required int videoDurationMs,
    required DateTime savedAt,
  });

  /// Makes an already-uploaded draft visible to the assigning teacher.
  Future<AssignmentAttempt> turnInTeacherReviewSubmission({
    required String traineeId,
    required AssignmentAttempt attempt,
    required DateTime submittedAt,
    required DateTime videoExpiresAt,
  });

  Future<AssignmentAttempt> beginTeacherReviewDraftClipRemoval({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? startedAt,
  });

  Future<AssignmentAttempt> completeTeacherReviewDraftClipRemoval({
    required String traineeId,
    required AssignmentAttempt attempt,
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

  Future<AssignmentAttempt> saveTeacherActivityRubricReview({
    required String teacherId,
    required AssignmentAttempt attempt,
    required Map<String, int> criterionScores,
    String? feedback,
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

/// Verifies that every targeted Trainee is currently an approved member of
/// [group]. Callers must obtain [memberships] from the current roster source
/// immediately before writing a targeted assignment.
void ensureAssignmentAudienceMatchesRoster({
  required AssignmentAudience audience,
  required ElixrGroup group,
  required Iterable<GroupMembership> memberships,
}) {
  if (!group.isActive) {
    throw const ClassroomException(ClassroomError.inactive);
  }
  if (audience.isEntireClass) return;
  final approvedIds = <String>{
    for (final membership in memberships)
      if (membership.isApproved &&
          membership.groupId == group.id &&
          membership.teacherId == group.teacherId)
        membership.traineeId,
  };
  if (!approvedIds.containsAll(audience.targetTraineeIds)) {
    throw const ClassroomException(ClassroomError.forbidden);
  }
}

Map<String, dynamic> officialAssignmentPayload({
  required String teacherId,
  required String teacherDisplayName,
  required ElixrGroup group,
  required String officialMovementName,
  required String displayInstructions,
  DateTime? dueAt,
  GroupAssignmentStatus status = GroupAssignmentStatus.active,
  DateTime? publishAt,
  String? topic,
  AssignmentAttemptPolicy attemptPolicy = AssignmentAttemptPolicy.legacyDefault,
  AssignmentAudience audience = const AssignmentAudience.entireClass(),
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
    'status': status.name,
    'official_movement_name': identity.catalogName,
    'display_title': identity.catalogName,
    'teacher_display_name': teacherDisplayName.trim(),
    'group_name': group.name,
    ...audience.toMap(),
    'attempt_policy': attemptPolicy.toMap(),
    'created_at': createdAt,
    'updated_at': updatedAt,
    if (displayInstructions.trim().isNotEmpty)
      'display_instructions': displayInstructions.trim(),
    'due_at': ?dueAt,
    'publish_at': ?_validatedPublication(status: status, publishAt: publishAt),
    if (_normalizeTopic(topic) != null) 'topic': _normalizeTopic(topic),
  };
}

DateTime? _validatedPublication({
  required GroupAssignmentStatus status,
  required DateTime? publishAt,
}) {
  if (status == GroupAssignmentStatus.scheduled) {
    if (publishAt == null) {
      throw ArgumentError('Scheduled assignments require a publication time.');
    }
    return publishAt.toUtc();
  }
  if (publishAt != null ||
      !{
        GroupAssignmentStatus.active,
        GroupAssignmentStatus.draft,
      }.contains(status)) {
    throw ArgumentError(
      'This assignment lifecycle cannot have a publication time.',
    );
  }
  return null;
}

Map<String, dynamic> teacherCreatedAssignmentPayload({
  required String teacherId,
  required String teacherDisplayName,
  required ElixrGroup group,
  required TeacherMovement movement,
  required TeacherMovementRevision revision,
  int maxScore = 100,
  TeacherActivityAssessmentConfig? activityAssessment,
  AssignmentAttemptPolicy attemptPolicy =
      AssignmentAttemptPolicy.teacherActivityDefault,
  String? displayTitle,
  String? displayInstructions,
  String? displaySafetyGuidance,
  DateTime? dueAt,
  GroupAssignmentStatus status = GroupAssignmentStatus.active,
  DateTime? publishAt,
  String? topic,
  AssignmentAudience audience = const AssignmentAudience.entireClass(),
  required Object createdAt,
  required Object updatedAt,
  bool includeGradingFields = true,
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

  final spec = revision.spec as TeacherReviewedMovementSpec;
  var resolvedAssessment = activityAssessment ?? spec.effectiveAssessment;
  if (resolvedAssessment.rubric.maximumScore != maxScore) {
    if (resolvedAssessment.rubric.template ==
        TeacherActivityRubricTemplate.custom) {
      throw const ClassroomException(
        ClassroomError.invalidGrade,
        'Custom rubric points must total the Assignment maximum.',
      );
    }
    resolvedAssessment = TeacherActivityAssessmentConfig(
      readiness: resolvedAssessment.readiness,
      rubric: TeacherActivityRubric.builtIn(
        resolvedAssessment.rubric.template,
        maxScore,
      ),
      recordingDurationSeconds: resolvedAssessment.recordingDurationSeconds,
      demonstrationVideo: resolvedAssessment.demonstrationVideo,
    );
  }

  final payload = <String, dynamic>{
    'teacher_id': teacherId,
    'group_id': group.id,
    'movement_id': movement.id,
    'revision_id': revision.id,
    'origin': MovementOrigin.teacherCreated.wireValue,
    'assessment_mode': AssessmentMode.teacherReviewed.wireValue,
    'status': status.name,
    'display_title': (displayTitle ?? movement.title).trim(),
    'display_instructions': (displayInstructions ?? revision.spec.instructions)
        .trim(),
    'display_safety_guidance': ?(() {
      final value = displaySafetyGuidance ?? revision.spec.safetyGuidance;
      return value?.trim().isEmpty == true ? null : value?.trim();
    })(),
    'allowed_prop': revision.spec.requiredProp.protocolValue,
    'teacher_display_name': teacherDisplayName.trim(),
    'group_name': group.name,
    ...audience.toMap(),
    'attempt_policy': attemptPolicy.toMap(),
    if (includeGradingFields) ...{
      'max_score': maxScore,
      'configuration_revision': 1,
      'activity_assessment': resolvedAssessment.toMap(),
      'grading_locked': false,
    },
    'created_at': createdAt,
    'updated_at': updatedAt,
    'due_at': ?dueAt,
    'publish_at': ?_validatedPublication(status: status, publishAt: publishAt),
    if (_normalizeTopic(topic) != null) 'topic': _normalizeTopic(topic),
  };

  return payload;
}

String? _normalizeTopic(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.length > GroupAssignment.maxTopicLength) {
    throw const ClassroomException(
      ClassroomError.invalidState,
      'Topic must be 80 characters or fewer.',
    );
  }
  return trimmed;
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

void ensureLocalTeacherReviewDraftVideo({
  required AssignmentAttempt attempt,
  required String videoStoragePath,
  required String videoContentType,
  required int videoSizeBytes,
  required int videoDurationMs,
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
      videoDurationMs > AssignmentSubmissionLimits.maxDurationMs) {
    throw const ClassroomException(ClassroomError.invalidState);
  }
}

AssignmentAttempt teacherCreatedDraftAttempt({
  required String traineeId,
  required GroupAssignment assignment,
  DateTime? createdAt,
}) {
  ensureAssignmentAvailableToTrainee(
    traineeId: traineeId,
    assignment: assignment,
  );
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
    assignmentConfigurationRevision: assignment.activityAssessment == null
        ? null
        : assignment.configurationRevision,
    activityAssessmentSnapshot: assignment.activityAssessment,
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

/// Creates the deterministic canonical submission before attempting to read
/// it. A missing document cannot pass the resource-based Firestore read rule,
/// so the read is only safe after a Firebase write failure that may mean a
/// concurrent client already created the same deterministic ID.
Future<AssignmentAttempt> getOrCreateCanonicalTeacherReviewSubmissionWorkflow({
  required String traineeId,
  required GroupAssignment assignment,
  required Future<void> Function(AssignmentAttempt canonical) create,
  required Future<AssignmentAttempt?> Function(String attemptId) readExisting,
  required Future<AssignmentAttempt> Function(AssignmentAttempt existing)
  promoteLegacyDraft,
  required bool Function(Object error) shouldReadAfterCreateFailure,
  required bool Function(Object error) isFallbackReadFailure,
}) async {
  final canonical = canonicalTeacherReviewSubmissionAttempt(
    traineeId: traineeId,
    assignment: assignment,
  );
  try {
    await create(canonical);
    return canonical;
  } catch (error, stackTrace) {
    if (!shouldReadAfterCreateFailure(error)) rethrow;
    AssignmentAttempt? existing;
    try {
      existing = await readExisting(canonical.id);
    } catch (readError) {
      if (isFallbackReadFailure(readError)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      rethrow;
    }
    if (existing == null) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    return resolveCanonicalTeacherReviewSubmission(
      existing: existing,
      canonical: canonical,
      traineeId: traineeId,
      assignment: assignment,
      promoteLegacyDraft: promoteLegacyDraft,
    );
  }
}

Future<AssignmentAttempt> resolveCanonicalTeacherReviewSubmission({
  required AssignmentAttempt existing,
  required AssignmentAttempt canonical,
  required String traineeId,
  required GroupAssignment assignment,
  required Future<AssignmentAttempt> Function(AssignmentAttempt existing)
  promoteLegacyDraft,
}) async {
  if (!sameCanonicalTeacherReviewSubmissionIdentity(existing, canonical)) {
    throw const ClassroomException(ClassroomError.identityMismatch);
  }
  if (isPromotableCanonicalTeacherReviewSubmissionDraft(existing)) {
    return promoteLegacyDraft(existing);
  }
  if (!isReusableCanonicalTeacherReviewSubmission(
    attempt: existing,
    traineeId: traineeId,
    assignment: assignment,
  )) {
    throw const ClassroomException(ClassroomError.invalidState);
  }
  return existing;
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
  ensureAssignmentAvailableToTrainee(
    traineeId: traineeId,
    assignment: assignment,
  );
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
    assignmentConfigurationRevision: assignment.activityAssessment == null
        ? null
        : assignment.configurationRevision,
    activityAssessmentSnapshot: assignment.activityAssessment,
  );
}

AssignmentAttempt canonicalTeacherReviewSubmissionAttempt({
  required String traineeId,
  required GroupAssignment assignment,
  DateTime? createdAt,
}) {
  ensureAssignmentAvailableToTrainee(
    traineeId: traineeId,
    assignment: assignment,
  );
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
    assignmentConfigurationRevision: assignment.activityAssessment == null
        ? null
        : assignment.configurationRevision,
    activityAssessmentSnapshot: assignment.activityAssessment,
  );
}

void ensureAssignmentAvailableToTrainee({
  required String traineeId,
  required GroupAssignment assignment,
}) {
  if (!assignment.isAvailableToTrainee(traineeId)) {
    throw const ClassroomException(ClassroomError.forbidden);
  }
}

bool sameCanonicalTeacherReviewSubmissionIdentity(
  AssignmentAttempt existing,
  AssignmentAttempt canonical,
) {
  return existing.isCanonicalTeacherReviewSubmission &&
      existing.traineeId == canonical.traineeId &&
      existing.teacherId == canonical.teacherId &&
      existing.groupId == canonical.groupId &&
      existing.assignmentId == canonical.assignmentId &&
      existing.movementId == canonical.movementId &&
      existing.revisionId == canonical.revisionId &&
      existing.origin == canonical.origin &&
      existing.assessmentMode == canonical.assessmentMode &&
      existing.attemptKind == canonical.attemptKind &&
      existing.supersedesAttemptId == null;
}

bool isPromotableCanonicalTeacherReviewSubmissionDraft(
  AssignmentAttempt attempt,
) {
  return attempt.status == AssignmentAttemptStatus.draft &&
      hasPristineCanonicalTeacherReviewSubmissionPayload(attempt);
}

bool hasPristineCanonicalTeacherReviewSubmissionPayload(
  AssignmentAttempt attempt,
) {
  return attempt.abandonedAt == null &&
      attempt.videoStoragePath == null &&
      attempt.videoContentType == null &&
      attempt.videoSizeBytes == null &&
      attempt.videoDurationMs == null &&
      attempt.submittedAt == null &&
      attempt.videoExpiresAt == null &&
      attempt.videoDeletedAt == null &&
      attempt.reviewVerdict == null &&
      attempt.reviewFeedback == null &&
      attempt.reviewedAt == null &&
      attempt.gradeScore == null &&
      attempt.gradeMaxScore == null &&
      attempt.checkedAt == null &&
      attempt.reviewUpdatedAt == null &&
      attempt.reviewRevision == null &&
      attempt.resultSentRevision == null &&
      attempt.resultSentAt == null &&
      attempt.resultMessageId == null &&
      attempt.deletionFailed == false &&
      attempt.deletionFailedAt == null;
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
      attempt.status == AssignmentAttemptStatus.inProgress &&
      hasPristineCanonicalTeacherReviewSubmissionPayload(attempt);
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
