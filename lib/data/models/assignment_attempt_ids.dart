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
/// Phase 6 may create later replacement attempts with new IDs and
/// `supersedes_attempt_id` without rewriting this document's identity.
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
