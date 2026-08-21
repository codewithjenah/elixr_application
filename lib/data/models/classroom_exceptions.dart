class ClassroomException implements Exception {
  const ClassroomException(this.code, [this.message]);

  final ClassroomError code;
  final String? message;

  @override
  String toString() => message ?? code.name;
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
  uploadFailed,
}
