class ClassroomException implements Exception {
  const ClassroomException(this.code, [this.message])
    : httpStatus = null,
      serverCode = null;

  const ClassroomException.fromFunction(
    this.code, {
    this.message,
    required this.httpStatus,
    required this.serverCode,
  });

  final ClassroomError code;
  final String? message;
  final int? httpStatus;
  final String? serverCode;

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
}
