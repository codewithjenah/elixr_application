enum TeacherProgressError { accessWithdrawn, unavailable }

class TeacherProgressException implements Exception {
  const TeacherProgressException(this.code, [this.message]);
  final TeacherProgressError code;
  final String? message;
}
