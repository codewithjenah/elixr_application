/// Delivery policy for one classroom assignment.
///
/// This deliberately lives outside a reusable Teacher Activity: a template can
/// be used in different classrooms with different submission allowances.
class AssignmentAttemptPolicy {
  const AssignmentAttemptPolicy.finite(int maximumAttempts)
    : maximumAttempts = maximumAttempts,
      assert(maximumAttempts >= 1 && maximumAttempts <= 3);

  const AssignmentAttemptPolicy.unlimited() : maximumAttempts = null;

  /// Existing assignments predate this field and historically had no limit.
  static const legacyDefault = AssignmentAttemptPolicy.unlimited();

  /// Existing Activity v2 templates used three attempts by default.
  static const teacherActivityDefault = AssignmentAttemptPolicy.finite(3);

  final int? maximumAttempts;

  bool get isUnlimited => maximumAttempts == null;
  String get displayLabel => isUnlimited ? 'Unlimited' : '$maximumAttempts';

  Map<String, dynamic> toMap() => {
    'type': isUnlimited ? 'unlimited' : 'finite',
    if (!isUnlimited) 'maximum_attempts': maximumAttempts,
  };

  static AssignmentAttemptPolicy? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    if (map['type'] == 'unlimited' && map.length == 1) {
      return const AssignmentAttemptPolicy.unlimited();
    }
    final maximum = map['maximum_attempts'];
    if (map['type'] == 'finite' &&
        map.length == 2 &&
        maximum is int &&
        maximum >= 1 &&
        maximum <= 3) {
      return AssignmentAttemptPolicy.finite(maximum);
    }
    return null;
  }
}
