/// Classroom identity attached to an official guided session launched from
/// a specific group assignment. Absent on ordinary (non-assignment) practice.
class SessionAssignmentContext {
  const SessionAssignmentContext({
    required this.assignmentId,
    required this.groupId,
    required this.teacherId,
    required this.movementId,
    required this.revisionId,
  });

  final String assignmentId;
  final String groupId;
  final String teacherId;
  final String movementId;
  final String revisionId;

  Map<String, dynamic> toMap() => {
    'assignment_id': assignmentId,
    'group_id': groupId,
    'teacher_id': teacherId,
    'movement_id': movementId,
    'revision_id': revisionId,
  };

  static SessionAssignmentContext? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final assignmentId = _readId(map['assignment_id']);
    final groupId = _readId(map['group_id']);
    final teacherId = _readId(map['teacher_id']);
    final movementId = _readId(map['movement_id']);
    final revisionId = _readId(map['revision_id']);
    if (assignmentId == null ||
        groupId == null ||
        teacherId == null ||
        movementId == null ||
        revisionId == null) {
      return null;
    }
    return SessionAssignmentContext(
      assignmentId: assignmentId,
      groupId: groupId,
      teacherId: teacherId,
      movementId: movementId,
      revisionId: revisionId,
    );
  }

  static String? _readId(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 128) return null;
    return trimmed;
  }

  @override
  bool operator ==(Object other) {
    return other is SessionAssignmentContext &&
        other.assignmentId == assignmentId &&
        other.groupId == groupId &&
        other.teacherId == teacherId &&
        other.movementId == movementId &&
        other.revisionId == revisionId;
  }

  @override
  int get hashCode =>
      Object.hash(assignmentId, groupId, teacherId, movementId, revisionId);
}
