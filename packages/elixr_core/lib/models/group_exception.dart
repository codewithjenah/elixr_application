/// Errors from group invite resolution or membership lifecycle writes.
class GroupException implements Exception {
  const GroupException(this.code, [this.message]);

  final GroupError code;
  final String? message;

  @override
  String toString() => message ?? code.name;
}

enum GroupError {
  malformedCode,
  inviteNotFound,
  groupNotFound,
  groupInactive,
  alreadyMember,
  alreadyPending,
  notFound,
  collisionExhausted,
  invalidParticipant,
  forbidden,
}
