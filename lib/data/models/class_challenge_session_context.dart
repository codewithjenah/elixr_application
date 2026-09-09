class ClassChallengeSessionContext {
  const ClassChallengeSessionContext({
    required this.challengeId,
    required this.groupId,
    required this.teacherId,
    required this.attemptId,
  });

  final String challengeId;
  final String groupId;
  final String teacherId;
  final String attemptId;

  Map<String, dynamic> toMap() => {
    'challenge_id': challengeId,
    'group_id': groupId,
    'teacher_id': teacherId,
    'attempt_id': attemptId,
  };

  static ClassChallengeSessionContext? tryFrom(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    if (map['challenge_id'] is! String ||
        map['group_id'] is! String ||
        map['teacher_id'] is! String ||
        map['attempt_id'] is! String) {
      return null;
    }
    return ClassChallengeSessionContext(
      challengeId: map['challenge_id'] as String,
      groupId: map['group_id'] as String,
      teacherId: map['teacher_id'] as String,
      attemptId: map['attempt_id'] as String,
    );
  }
}
