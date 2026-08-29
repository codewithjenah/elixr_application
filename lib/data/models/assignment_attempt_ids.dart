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
/// The old Phase 5 start anchor is retained for compatibility. New recorded
/// submissions use [assignmentAttemptIdForCanonicalTeacherReviewSubmission].
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

final _canonicalReviewSubmissionPartPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// Deterministic submission identity for one trainee on one assignment.
///
/// This document is reused across the full `in_progress -> submitted ->
/// checked` lifecycle. It deliberately contains only stable document IDs,
/// never email addresses or display names.
String assignmentAttemptIdForCanonicalTeacherReviewSubmission({
  required String assignmentId,
  required String traineeId,
}) {
  final assignment = assignmentId.trim();
  final trainee = traineeId.trim();
  if (assignment.isEmpty ||
      trainee.isEmpty ||
      !_canonicalReviewSubmissionPartPattern.hasMatch(assignment) ||
      !_canonicalReviewSubmissionPartPattern.hasMatch(trainee)) {
    throw ArgumentError(
      'assignmentId and traineeId must be valid document IDs',
    );
  }
  final id = 'review_sub_${assignment}_$trainee';
  if (id.length > 128) {
    throw ArgumentError('The canonical submission ID is too long');
  }
  return id;
}

/// Readable aliases for callers that describe the identity as a submission
/// rather than an attempt.
String canonicalTeacherReviewSubmissionAttemptId({
  required String assignmentId,
  required String traineeId,
}) => assignmentAttemptIdForCanonicalTeacherReviewSubmission(
  assignmentId: assignmentId,
  traineeId: traineeId,
);

String assignmentAttemptIdForTeacherCreatedSubmission({
  required String assignmentId,
  required String traineeId,
}) => assignmentAttemptIdForCanonicalTeacherReviewSubmission(
  assignmentId: assignmentId,
  traineeId: traineeId,
);

bool isCanonicalTeacherReviewSubmissionId({
  required String id,
  required String assignmentId,
  required String traineeId,
}) {
  try {
    return id.trim() ==
        assignmentAttemptIdForCanonicalTeacherReviewSubmission(
          assignmentId: assignmentId,
          traineeId: traineeId,
        );
  } on ArgumentError {
    return false;
  }
}

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

String _defaultEntropy() {
  final mix =
      '${DateTime.now().toUtc().microsecondsSinceEpoch}'
      '${identityHashCode(Object())}';
  return mix
      .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
      .padRight(16, '0')
      .substring(0, 16);
}
