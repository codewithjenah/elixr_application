/// Canonical document IDs for [assignment_attempts].
///
/// Official practice pointers are derived from the source session ID so the
/// Firestore rules can require that exact document in the same atomic write.
/// Do not reconstruct these strings in UI or ad-hoc repository code.
String assignmentAttemptIdForOfficialSession(String sessionId) {
  final trimmed = sessionId.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('sessionId is required');
  }
  return 'official_ptr_$trimmed';
}

/// First Teacher-created attempt for one trainee on one assignment.
///
/// Video submissions use [assignmentAttemptIdForTeacherReviewSubmission]
/// and may set `supersedes_attempt_id` without rewriting this document.
String assignmentAttemptIdForTeacherCreatedDraft({
  required String assignmentId,
  required String traineeId,
}) {
  final assignment = assignmentId.trim();
  final trainee = traineeId.trim();
  if (assignment.isEmpty || trainee.isEmpty) {
    throw ArgumentError('assignmentId and traineeId are required');
  }
  return 'tc_draft_${assignment}_$trainee';
}

final _reviewSubmissionIdPattern = RegExp(r'^[A-Za-z0-9]+$');

/// Canonical ID for one Teacher-reviewed video submission attempt.
///
/// Do not put email or display names in [uniquePart].
String assignmentAttemptIdForTeacherReviewSubmission(String uniquePart) {
  final token = uniquePart.trim();
  if (token.isEmpty || token.length > 64) {
    throw ArgumentError('uniquePart is required');
  }
  if (!_reviewSubmissionIdPattern.hasMatch(token)) {
    throw ArgumentError('uniquePart must be alphanumeric');
  }
  return 'review_sub_$token';
}

String newTeacherReviewSubmissionAttemptId({String Function()? entropy}) {
  final raw = entropy?.call() ?? _defaultEntropy();
  return assignmentAttemptIdForTeacherReviewSubmission(raw);
}

final _templateScoreIdPattern = RegExp(r'^[A-Za-z0-9]+$');

/// Collision-resistant ID for one completed template-scored attempt.
///
/// Repeated classroom runs must create new documents. Do not derive this
/// from assignment+trainee alone.
String assignmentAttemptIdForTemplateScore(String uniquePart) {
  final token = uniquePart.trim();
  if (token.isEmpty || token.length > 64) {
    throw ArgumentError('uniquePart is required');
  }
  if (!_templateScoreIdPattern.hasMatch(token)) {
    throw ArgumentError('uniquePart must be alphanumeric');
  }
  return 'template_score_$token';
}

String newTemplateScoreAttemptId({String Function()? entropy}) {
  final raw = entropy?.call() ?? _defaultEntropy();
  return assignmentAttemptIdForTemplateScore(raw);
}

String _defaultEntropy() {
  final mix =
      '${DateTime.now().toUtc().microsecondsSinceEpoch}'
      '${identityHashCode(Object())}';
  return mix
      .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
      .padRight(16, '0')
      .substring(0, 16);
}
