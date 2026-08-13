/// Errors from coach-code resolution or Teacher↔Trainee relationship writes.
class TeacherRelationshipException implements Exception {
  const TeacherRelationshipException(this.code, [this.message]);

  final TeacherRelationshipError code;
  final String? message;

  @override
  String toString() => message ?? code.name;
}

enum TeacherRelationshipError {
  malformedCode,
  inviteNotFound,
  inviteExpired,
  alreadyLinked,
  alreadyPending,
  notFound,
  collisionExhausted,
  invalidParticipant,
}
