/// Phase 6 Teacher-reviewed clip bounds.
///
/// These are initial engineering defaults, not experimentally validated
/// camera or storage measurements.
abstract final class AssignmentSubmissionLimits {
  static const maxDurationSeconds = 60;
  static const maxDurationMs = 60000;
  static const maxSizeBytes = 50 * 1024 * 1024;
  static const maxPlaybackDownloadBytes = maxSizeBytes + (256 * 1024);
  static const reviewCacheDirname = 'elixr_review_cache';
  static const contentType = 'video/mp4';
  static const reviewFeedbackMaxLength = 1000;
  static const unreviewedRetention = Duration(days: 30);
  static const reviewedRetention = Duration(days: 14);
  static const deletionRetryCooldown = Duration(minutes: 15);
  static const storagePrefix = 'assignment_submissions';
}

/// Canonical Firebase Storage object path for one submission clip.
String assignmentSubmissionStoragePath({
  required String teacherId,
  required String groupId,
  required String assignmentId,
  required String traineeId,
  required String attemptId,
}) {
  return '${AssignmentSubmissionLimits.storagePrefix}/'
      '$teacherId/$groupId/$assignmentId/$traineeId/$attemptId.mp4';
}

Map<String, String> assignmentSubmissionCustomMetadata({
  required String teacherId,
  required String groupId,
  required String assignmentId,
  required String traineeId,
  required String attemptId,
  required String movementId,
  required String revisionId,
}) {
  return {
    'teacher_id': teacherId,
    'group_id': groupId,
    'assignment_id': assignmentId,
    'trainee_id': traineeId,
    'attempt_id': attemptId,
    'movement_id': movementId,
    'revision_id': revisionId,
  };
}

DateTime unreviewedVideoExpiresAt(DateTime submittedAt) {
  return submittedAt.toUtc().add(
    AssignmentSubmissionLimits.unreviewedRetention,
  );
}

DateTime reviewedVideoExpiresAt(DateTime reviewedAt) {
  return reviewedAt.toUtc().add(AssignmentSubmissionLimits.reviewedRetention);
}

/// Converts the civil date selected in the UI into the inclusive end of that
/// date in Asia/Manila (UTC+08:00). Date-only deadlines must not depend on the
/// Windows machine's local timezone.
DateTime manilaEndOfDayUtc(DateTime civilDate) {
  return DateTime.utc(
    civilDate.year,
    civilDate.month,
    civilDate.day,
    15,
    59,
    59,
    999,
  );
}
