/// Errors from Teacher access-code validation, minting, or consumption.
class TeacherAccessCodeException implements Exception {
  const TeacherAccessCodeException(this.code, [this.message]);

  final TeacherAccessCodeError code;
  final String? message;

  @override
  String toString() => message ?? code.name;
}

enum TeacherAccessCodeError {
  malformedCode,
  notFound,
  alreadyConsumed,
  collisionExhausted,
  forbidden,
}
