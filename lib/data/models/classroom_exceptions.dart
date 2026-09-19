class ClassroomException implements Exception {
  const ClassroomException(this.code, [this.message])
    : httpStatus = null,
      serverCode = null,
      activeAttemptId = null;

  const ClassroomException.fromFunction(
    this.code, {
    this.message,
    required this.httpStatus,
    required this.serverCode,
    this.activeAttemptId,
  });

  final ClassroomError code;
  final String? message;
  final int? httpStatus;
  final String? serverCode;
  final String? activeAttemptId;

  @override
  String toString() => message ?? code.name;
}

class AssignmentSubmissionException implements Exception {
  const AssignmentSubmissionException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum ClassroomError {
  notFound,
  forbidden,
  malformed,
  inactive,
  archived,
  unofficial,
  identityMismatch,
  invalidState,
  deadlinePassed,
  invalidGrade,
  uploadFailed,
  conflict,
  attemptLimitConflict,
  invalidRecipient,

  /// A Function endpoint returned a response that was not part of ELIXR's
  /// authenticated JSON contract. This is diagnostic-only; callers must not
  /// surface the response body.
  endpointUnavailable,
}
