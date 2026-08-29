import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';

import '../models/assessment_mode.dart';
import '../models/assignment_attempt.dart';
import '../models/assignment_attempt_ids.dart';
import '../models/assignment_submission_limits.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/teacher_movement.dart';
import 'classroom_assignment_repository.dart';

class InMemoryClassroomAssignmentRepository
    implements ClassroomAssignmentRepository {
  InMemoryClassroomAssignmentRepository({
    DateTime Function()? now,
    String Function()? generateId,
  }) : _now = now,
       _generateId = generateId ?? _defaultId;

  final DateTime Function()? _now;
  final String Function() _generateId;

  final Map<String, GroupAssignment> assignments = {};
  final Map<String, AssignmentAttempt> attempts = {};
  bool failNextSubmitTransition = false;

  final _teacherControllers =
      <String, StreamController<List<GroupAssignment>>>{};
  final _assignmentAttemptControllers =
      <String, StreamController<List<AssignmentAttempt>>>{};
  final _traineeAttemptControllers =
      <String, StreamController<List<AssignmentAttempt>>>{};
  final _teacherAttemptControllers =
      <String, StreamController<List<AssignmentAttempt>>>{};

  static String _defaultId() => 'asg-${DateTime.now().microsecondsSinceEpoch}';

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  void dispose() {
    for (final controller in _teacherControllers.values) {
      controller.close();
    }
    for (final controller in _assignmentAttemptControllers.values) {
      controller.close();
    }
    for (final controller in _traineeAttemptControllers.values) {
      controller.close();
    }
    for (final controller in _teacherAttemptControllers.values) {
      controller.close();
    }
  }

  @override
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    String? displayInstructions,
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    final id = _generateId();
    final created = now;
    final payload = officialAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      officialMovementName: officialMovementName,
      displayInstructions: displayInstructions ?? '',
      dueAt: dueAt,
      createdAt: created,
      updatedAt: created,
    );
    final assignment =
        GroupAssignment.tryFromMap(payload, id: id) ??
        (throw const ClassroomException(ClassroomError.malformed));
    assignments[id] = assignment;
    _emitTeacher(teacherId);
    return assignment;
  }

  @override
  Future<GroupAssignment> createTeacherCreatedAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    int maxScore = 100,
    DateTime? dueAt,
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    final id = _generateId();
    final created = now;
    final payload = teacherCreatedAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      maxScore: maxScore,
      dueAt: dueAt,
      createdAt: created,
      updatedAt: created,
    );
    final assignment =
        GroupAssignment.tryFromMap(payload, id: id) ??
        (throw const ClassroomException(ClassroomError.malformed));
    assignments[id] = assignment;
    _emitTeacher(teacherId);
    return assignment;
  }

  @override
  Future<void> archiveAssignment({
    required String teacherId,
    required String assignmentId,
  }) async {
    final existing = assignments[assignmentId];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (existing.isRetiredTemplate) {
      throw const ClassroomException(
        ClassroomError.identityMismatch,
        'Retired template-scored assignments are read-only.',
      );
    }
    assignments[assignmentId] = GroupAssignment(
      id: existing.id,
      teacherId: existing.teacherId,
      groupId: existing.groupId,
      movementId: existing.movementId,
      revisionId: existing.revisionId,
      origin: existing.origin,
      assessmentMode: existing.assessmentMode,
      status: GroupAssignmentStatus.archived,
      displayTitle: existing.displayTitle,
      teacherDisplayName: existing.teacherDisplayName,
      groupName: existing.groupName,
      officialMovementName: existing.officialMovementName,
      displayInstructions: existing.displayInstructions,
      displaySafetyGuidance: existing.displaySafetyGuidance,
      allowedProp: existing.allowedProp,
      assessmentSpec: existing.assessmentSpec,
      maxScore: existing.maxScore,
      gradingLocked: existing.gradingLocked,
      gradingLockedAt: existing.gradingLockedAt,
      dueAt: existing.dueAt,
      createdAt: existing.createdAt,
      updatedAt: now,
    );
    _emitTeacher(teacherId);
  }

  @override
  Future<GroupAssignment?> getAssignment({required String assignmentId}) async {
    return assignments[assignmentId];
  }

  @override
  Stream<List<GroupAssignment>> watchTeacherAssignments({
    required String teacherId,
  }) {
    return _watch(
      _teacherControllers,
      teacherId,
      () => _emitTeacher(teacherId),
    );
  }

  @override
  Future<List<GroupAssignment>> fetchAssignmentsForGroup({
    required String groupId,
  }) async {
    final items = assignments.values
        .where((assignment) => assignment.groupId == groupId)
        .toList();
    _sortAssignments(items);
    return items;
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForAssignment({
    required String teacherId,
    required String assignmentId,
  }) {
    return _watch(
      _assignmentAttemptControllers,
      '$teacherId|$assignmentId',
      () => _emitAssignmentAttempts(teacherId, assignmentId),
    );
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  }) {
    return _watch(
      _traineeAttemptControllers,
      traineeId,
      () => _emitTraineeAttempts(traineeId),
    );
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTeacher({
    required String teacherId,
  }) {
    return _watch(
      _teacherAttemptControllers,
      teacherId,
      () => _emitTeacherAttempts(teacherId),
    );
  }

  @override
  Future<AssignmentAttempt?> getAttempt({required String attemptId}) async {
    return attempts[attemptId];
  }

  @override
  Future<AssignmentAttempt> startTeacherCreatedAttempt({
    required String traineeId,
    required GroupAssignment assignment,
  }) {
    return startTeacherCreatedAttemptWorkflow(
      traineeId: traineeId,
      assignment: assignment,
      create: (draft) async {
        if (attempts.containsKey(draft.id)) {
          throw const ClassroomException(ClassroomError.forbidden);
        }
        attempts[draft.id] = AssignmentAttempt(
          id: draft.id,
          traineeId: draft.traineeId,
          teacherId: draft.teacherId,
          groupId: draft.groupId,
          assignmentId: draft.assignmentId,
          movementId: draft.movementId,
          revisionId: draft.revisionId,
          origin: draft.origin,
          assessmentMode: draft.assessmentMode,
          attemptKind: draft.attemptKind,
          status: draft.status,
          createdAt: draft.createdAt ?? now,
        );
        _emitAssignmentAttempts(assignment.teacherId, assignment.id);
        _emitTraineeAttempts(traineeId);
        _emitTeacherAttempts(assignment.teacherId);
      },
      readExisting: (attemptId) async => attempts[attemptId],
      promoteDraftToInProgress: (existing) async {
        final promoted = teacherCreatedAttemptWithStatus(
          attempt: existing,
          status: AssignmentAttemptStatus.inProgress,
        );
        attempts[existing.id] = promoted;
        _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
        _emitTraineeAttempts(existing.traineeId);
        _emitTeacherAttempts(existing.teacherId);
        return promoted;
      },
      isPermissionDenied: (error) =>
          error is ClassroomException && error.code == ClassroomError.forbidden,
    );
  }

  @override
  Future<AssignmentAttempt> createTeacherReviewSubmissionDraft({
    required String traineeId,
    required GroupAssignment assignment,
    String? supersedesAttemptId,
    String? attemptId,
  }) async {
    if (supersedesAttemptId != null) {
      final previous = attempts[supersedesAttemptId];
      if (previous == null) {
        throw const ClassroomException(ClassroomError.notFound);
      }
      ensureCanSupersedeNeedsRetry(
        previous: previous,
        traineeId: traineeId,
        assignment: assignment,
      );
    }
    final id = attemptId ?? newTeacherReviewSubmissionAttemptId();
    final draft = teacherReviewSubmissionDraftAttempt(
      traineeId: traineeId,
      assignment: assignment,
      attemptId: id,
      supersedesAttemptId: supersedesAttemptId,
      createdAt: now,
    );
    if (attempts.containsKey(draft.id)) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    attempts[draft.id] = draft;
    _emitAssignmentAttempts(assignment.teacherId, assignment.id);
    _emitTraineeAttempts(traineeId);
    _emitTeacherAttempts(assignment.teacherId);
    return draft;
  }

  @override
  Future<AssignmentAttempt> getOrCreateTeacherReviewSubmission({
    required String traineeId,
    required GroupAssignment assignment,
  }) async {
    if (!isTeacherAssignmentSubmissionOpen(assignment: assignment, now: now)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    final canonical = canonicalTeacherReviewSubmissionAttempt(
      traineeId: traineeId,
      assignment: assignment,
      createdAt: now,
    );
    final existing = attempts[canonical.id];
    if (existing == null) {
      attempts[canonical.id] = canonical;
      _emitAssignmentAttempts(assignment.teacherId, assignment.id);
      _emitTraineeAttempts(traineeId);
      _emitTeacherAttempts(assignment.teacherId);
      return canonical;
    }
    if (!_sameCanonicalSubmissionIdentity(existing, canonical)) {
      throw const ClassroomException(ClassroomError.identityMismatch);
    }
    if (existing.status == AssignmentAttemptStatus.draft &&
        existing.abandonedAt == null &&
        existing.videoStoragePath == null &&
        existing.videoContentType == null &&
        existing.videoSizeBytes == null &&
        existing.videoDurationMs == null &&
        existing.submittedAt == null &&
        existing.videoExpiresAt == null &&
        existing.videoDeletedAt == null &&
        existing.reviewVerdict == null &&
        existing.reviewFeedback == null &&
        existing.reviewedAt == null &&
        existing.gradeScore == null &&
        existing.gradeMaxScore == null &&
        existing.checkedAt == null &&
        existing.reviewUpdatedAt == null &&
        existing.reviewRevision == null &&
        existing.resultSentRevision == null &&
        existing.resultSentAt == null &&
        existing.resultMessageId == null &&
        existing.deletionFailed == false &&
        existing.deletionFailedAt == null) {
      return _storeAttempt(
        existing.copyWith(status: AssignmentAttemptStatus.inProgress),
      );
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

  @override
  Future<void> markTeacherReviewSubmissionAbandoned({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? abandonedAt,
    DateTime? videoDeletedAt,
    bool deletionFailed = false,
    DateTime? deletionFailedAt,
  }) async {
    if (!canMarkTeacherReviewSubmissionAbandoned(
      attempt: attempt,
      traineeId: traineeId,
    )) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (deletionFailed && videoDeletedAt != null) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final existing = attempts[attempt.id];
    if (existing == null) return;
    final marked = existing.copyWith(
      abandonedAt: abandonedAt ?? now,
      videoDeletedAt: videoDeletedAt,
      deletionFailed: deletionFailed,
      deletionFailedAt: deletionFailedAt,
    );
    attempts[existing.id] = marked;
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
  }

  @override
  Future<AssignmentAttempt> markTeacherReviewSubmitted({
    required String traineeId,
    required AssignmentAttempt attempt,
    required String videoStoragePath,
    required String videoContentType,
    required int videoSizeBytes,
    required int videoDurationMs,
    required DateTime submittedAt,
    required DateTime videoExpiresAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.traineeId != traineeId ||
        existing.attemptKind != AssignmentAttemptKind.teacherReviewSubmission) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (existing.abandonedAt != null) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (existing.status != AssignmentAttemptStatus.draft &&
        existing.status != AssignmentAttemptStatus.inProgress) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    ensureTeacherReviewSubmissionVideo(
      attempt: existing,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
    );
    final assignment = assignments[existing.assignmentId];
    if (assignment == null ||
        !isTeacherAssignmentSubmissionOpen(assignment: assignment, now: now)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    if (failNextSubmitTransition) {
      failNextSubmitTransition = false;
      throw const ClassroomException(
        ClassroomError.uploadFailed,
        'Could not finalize the submission metadata.',
      );
    }
    final submitted = existing.copyWith(
      status: AssignmentAttemptStatus.submitted,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
    );
    attempts[existing.id] = submitted;
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
    return submitted;
  }

  @override
  Future<AssignmentAttempt> beginTeacherReviewUnsubmit({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? startedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    final assignment = assignments[existing.assignmentId];
    if (existing.traineeId != traineeId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (!existing.isCanonicalTeacherReviewSubmission) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (existing.status == AssignmentAttemptStatus.unsubmitting) {
      return existing;
    }
    if (assignment == null ||
        !isTeacherAssignmentSubmissionOpen(assignment: assignment, now: now)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    if (existing.status != AssignmentAttemptStatus.submitted ||
        !existing.hasPlayableVideo) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _storeAttempt(
      existing.copyWith(
        status: AssignmentAttemptStatus.unsubmitting,
        deletionFailed: false,
        clearDeletionFailedAt: true,
      ),
    );
  }

  @override
  Future<AssignmentAttempt> completeTeacherReviewUnsubmit({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? completedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.traineeId != traineeId ||
        !existing.isCanonicalTeacherReviewSubmission ||
        existing.status != AssignmentAttemptStatus.unsubmitting) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _storeAttempt(
      existing.copyWith(
        status: AssignmentAttemptStatus.inProgress,
        clearVideoMetadata: true,
        clearVideoDeletedAt: true,
        deletionFailed: false,
        clearDeletionFailedAt: true,
      ),
    );
  }

  @override
  Future<AssignmentAttempt> saveTeacherReview({
    required String teacherId,
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
    required int gradeScore,
    String? feedback,
    DateTime? reviewedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId ||
        existing.assignmentId != assignment.id ||
        existing.attemptKind != AssignmentAttemptKind.teacherReviewSubmission ||
        !assignment.isTeacherCreated ||
        assignment.assessmentMode != AssessmentMode.teacherReviewed ||
        existing.groupId != assignment.groupId ||
        existing.movementId != assignment.movementId ||
        existing.revisionId != assignment.revisionId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final storedAssignment = assignments[assignment.id];
    if (storedAssignment == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (storedAssignment.teacherId != teacherId ||
        !storedAssignment.isTeacherCreated ||
        storedAssignment.assessmentMode != AssessmentMode.teacherReviewed ||
        storedAssignment.groupId != existing.groupId ||
        storedAssignment.movementId != existing.movementId ||
        storedAssignment.revisionId != existing.revisionId) {
      throw const ClassroomException(ClassroomError.identityMismatch);
    }
    if (existing.status != AssignmentAttemptStatus.submitted &&
        existing.status != AssignmentAttemptStatus.checked &&
        existing.status != AssignmentAttemptStatus.approved &&
        existing.status != AssignmentAttemptStatus.needsRetry) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final maxScore = existing.gradeMaxScore ?? storedAssignment.maxScore ?? 100;
    ensureTeacherReviewGrade(gradeScore: gradeScore, maxScore: maxScore);
    final at = (reviewedAt ?? now).toUtc();
    final feedbackValue = feedback?.trim();
    if (feedbackValue != null &&
        feedbackValue.length >
            AssignmentSubmissionLimits.reviewFeedbackMaxLength) {
      throw const ClassroomException(
        ClassroomError.invalidGrade,
        'Feedback is too long.',
      );
    }
    final checked = existing.copyWith(
      status: AssignmentAttemptStatus.checked,
      gradeScore: gradeScore,
      gradeMaxScore: maxScore,
      checkedAt: existing.checkedAt ?? at,
      reviewUpdatedAt: at,
      reviewRevision: (existing.reviewRevision ?? 0) + 1,
      reviewFeedback: feedbackValue == null || feedbackValue.isEmpty
          ? null
          : feedbackValue,
      videoExpiresAt: reviewedVideoExpiresAt(at),
      clearLegacyReview: true,
      clearReviewFeedback: feedbackValue == null || feedbackValue.isEmpty,
      clearResultSent: true,
    );
    attempts[existing.id] = checked;
    if (!storedAssignment.gradingLocked) {
      assignments[assignment.id] = storedAssignment.copyWith(
        gradingLocked: true,
        gradingLockedAt: at,
      );
      _emitTeacher(teacherId);
    }
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
    return checked;
  }

  @override
  Future<GroupAssignment> updateTeacherAssignmentMaxScore({
    required String teacherId,
    required String assignmentId,
    required int maxScore,
  }) async {
    ensureTeacherAssignmentMaxScore(maxScore);
    final existing = assignments[assignmentId];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (!existing.isTeacherCreated || existing.gradingLocked) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (attempts.values.any(
      (attempt) => attempt.assignmentId == assignmentId && attempt.isChecked,
    )) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final updated = existing.copyWith(maxScore: maxScore);
    assignments[assignmentId] = updated;
    _emitTeacher(teacherId);
    return updated;
  }

  @override
  Future<AssignmentAttempt> markTeacherReviewResultSent({
    required String teacherId,
    required AssignmentAttempt attempt,
    required String messageId,
    DateTime? sentAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId ||
        !existing.isChecked ||
        existing.reviewRevision == null ||
        messageId.trim().isEmpty ||
        messageId.trim().length > 256) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (existing.resultSentForCurrentRevision) return existing;
    return _storeAttempt(
      existing.copyWith(
        resultSentRevision: existing.reviewRevision,
        resultSentAt: (sentAt ?? now).toUtc(),
        resultMessageId: messageId.trim(),
      ),
    );
  }

  @override
  Future<AssignmentAttempt> reviewTeacherSubmission({
    required String teacherId,
    required AssignmentAttempt attempt,
    required AssignmentReviewVerdict verdict,
    String? feedback,
    required DateTime reviewedAt,
    required DateTime videoExpiresAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (existing.isCanonicalTeacherReviewSubmission) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (existing.attemptKind != AssignmentAttemptKind.teacherReviewSubmission ||
        existing.status != AssignmentAttemptStatus.submitted) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final status = verdict == AssignmentReviewVerdict.approved
        ? AssignmentAttemptStatus.approved
        : AssignmentAttemptStatus.needsRetry;
    final reviewed = existing.copyWith(
      status: status,
      reviewVerdict: verdict,
      reviewFeedback: feedback,
      reviewedAt: reviewedAt,
      videoExpiresAt: videoExpiresAt,
    );
    attempts[existing.id] = reviewed;
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
    return reviewed;
  }

  @override
  Future<void> markSubmissionVideoDeleted({
    required String actorId,
    required AssignmentAttempt attempt,
    required DateTime deletedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.traineeId != actorId && existing.teacherId != actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (existing.isCanonicalTeacherReviewSubmission &&
        existing.traineeId == actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    attempts[existing.id] = existing.copyWith(
      clearVideoStoragePath: true,
      videoDeletedAt: deletedAt,
      deletionFailed: false,
      clearDeletionFailedAt: true,
    );
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
  }

  @override
  Future<void> markSubmissionDeletionFailed({
    required String actorId,
    required AssignmentAttempt attempt,
    required DateTime failedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.traineeId != actorId && existing.teacherId != actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (existing.isCanonicalTeacherReviewSubmission &&
        (existing.traineeId != actorId ||
            existing.status != AssignmentAttemptStatus.unsubmitting)) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    attempts[existing.id] = existing.copyWith(
      deletionFailed: true,
      deletionFailedAt: failedAt,
    );
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
  }

  bool _sameCanonicalSubmissionIdentity(
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

  AssignmentAttempt _storeAttempt(AssignmentAttempt value) {
    attempts[value.id] = value;
    _emitAssignmentAttempts(value.teacherId, value.assignmentId);
    _emitTraineeAttempts(value.traineeId);
    _emitTeacherAttempts(value.teacherId);
    return value;
  }

  void seedAssignment(GroupAssignment assignment) {
    assignments[assignment.id] = assignment;
    _emitTeacher(assignment.teacherId);
  }

  void seedAttempt(AssignmentAttempt attempt) {
    attempts[attempt.id] = attempt;
    _emitAssignmentAttempts(attempt.teacherId, attempt.assignmentId);
    _emitTraineeAttempts(attempt.traineeId);
    _emitTeacherAttempts(attempt.teacherId);
  }

  void _emitTeacher(String teacherId) {
    final controller = _teacherControllers[teacherId];
    if (controller == null || controller.isClosed) return;
    final items = assignments.values
        .where((assignment) => assignment.teacherId == teacherId)
        .toList();
    _sortAssignments(items);
    controller.add(items);
  }

  void _emitAssignmentAttempts(String teacherId, String assignmentId) {
    final controller =
        _assignmentAttemptControllers['$teacherId|$assignmentId'];
    if (controller == null || controller.isClosed) return;
    final items = attempts.values
        .where(
          (attempt) =>
              attempt.teacherId == teacherId &&
              attempt.assignmentId == assignmentId,
        )
        .toList();
    controller.add(items);
  }

  void _emitTraineeAttempts(String traineeId) {
    final controller = _traineeAttemptControllers[traineeId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      attempts.values
          .where((attempt) => attempt.traineeId == traineeId)
          .toList(),
    );
  }

  void _emitTeacherAttempts(String teacherId) {
    final controller = _teacherAttemptControllers[teacherId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      attempts.values
          .where((attempt) => attempt.teacherId == teacherId)
          .toList(),
    );
  }

  Stream<List<T>> _watch<T>(
    Map<String, StreamController<List<T>>> controllers,
    String key,
    void Function() emit,
  ) {
    final existing = controllers[key];
    if (existing != null && !existing.isClosed) return existing.stream;
    late final StreamController<List<T>> controller;
    controller = StreamController<List<T>>.broadcast(onListen: emit);
    controllers[key] = controller;
    return controller.stream;
  }

  static void _sortAssignments(List<GroupAssignment> items) {
    items.sort((a, b) {
      final aDue = a.dueAt;
      final bDue = b.dueAt;
      if (aDue != null && bDue != null) return aDue.compareTo(bDue);
      if (aDue != null) return -1;
      if (bDue != null) return 1;
      final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
  }
}
