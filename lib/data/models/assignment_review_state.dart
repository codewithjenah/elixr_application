import 'assignment_attempt.dart';
import 'group_assignment.dart';

/// Teacher-facing review state for one intended assignment recipient.
///
/// This is derived from the canonical attempt contract and is never persisted.
enum AssignmentReviewState { toReview, checked, missing }

/// Deadline presentation is deliberately separate from review state.
enum AssignmentDeadlineState {
  noDeadline,
  missing,
  overdue,
  submittedOnTime,
  submittedLate,
}

abstract final class AssignmentReviewSemantics {
  static AssignmentReviewState reviewState(AssignmentAttempt? attempt) {
    if (!AssignmentAttemptSemantics.isTurnedIn(attempt)) {
      return AssignmentReviewState.missing;
    }
    if (attempt!.isTeacherReviewSubmission &&
        attempt.status == AssignmentAttemptStatus.submitted) {
      return AssignmentReviewState.toReview;
    }
    return AssignmentReviewState.checked;
  }

  /// A pending item that can be opened and acted on by a teacher now.
  ///
  /// Global queues and Save & Next require either the canonical legacy
  /// assignment/student document or a versioned Teacher Activity attempt with
  /// its immutable assessment snapshot, plus an available submitted clip.
  /// Other legacy submissions remain readable through classroom history.
  static bool isActionablePending(
    AssignmentAttempt? attempt, {
    required DateTime now,
  }) {
    if (attempt == null ||
        (!attempt.isCanonicalTeacherReviewSubmission &&
            (attempt.activityAssessmentSnapshot == null ||
                attempt.assignmentConfigurationRevision == null)) ||
        attempt.status != AssignmentAttemptStatus.submitted ||
        attempt.submittedAt == null ||
        !attempt.isReviewFacingSubmission ||
        !attempt.hasPlayableVideo) {
      return false;
    }
    final expiresAt = attempt.videoExpiresAt;
    return expiresAt == null || now.toUtc().isBefore(expiresAt.toUtc());
  }

  static AssignmentDeadlineState deadlineState({
    required DateTime? dueAt,
    required DateTime? submittedAt,
    required DateTime now,
  }) {
    if (submittedAt != null) {
      if (dueAt == null) return AssignmentDeadlineState.noDeadline;
      return submittedAt.toUtc().isAfter(dueAt.toUtc())
          ? AssignmentDeadlineState.submittedLate
          : AssignmentDeadlineState.submittedOnTime;
    }
    if (dueAt == null) return AssignmentDeadlineState.missing;
    return now.toUtc().isAfter(dueAt.toUtc())
        ? AssignmentDeadlineState.overdue
        : AssignmentDeadlineState.missing;
  }

  static AssignmentDeadlineState deadlineStateFor({
    required GroupAssignment assignment,
    required AssignmentAttempt? attempt,
    required DateTime now,
  }) {
    final submittedAt = AssignmentAttemptSemantics.isTurnedIn(attempt)
        ? attempt?.submittedAt
        : null;
    return deadlineState(
      dueAt: !assignment.isActive && submittedAt == null
          ? null
          : assignment.dueAt,
      submittedAt: submittedAt,
      now: now,
    );
  }
}
