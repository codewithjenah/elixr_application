import 'teacher_roster_invite.dart';

/// Server-maintained pointer that connects one Teacher/Trainee pair to an
/// approved classroom group.
///
/// The document is an authorization cache, not the source of truth. Firestore
/// and Storage rules must re-check the pointed-to group and membership before
/// allowing protected reads.
class ClassroomTeacherAccessContext {
  static const currentSchemaVersion = 1;

  const ClassroomTeacherAccessContext({
    required this.teacherId,
    required this.traineeId,
    required this.groupId,
    this.schemaVersion = currentSchemaVersion,
    this.updatedAt,
  });

  final String teacherId;
  final String traineeId;
  final String groupId;
  final int schemaVersion;
  final DateTime? updatedAt;

  static String documentId({
    required String teacherId,
    required String traineeId,
  }) => '${teacherId}_$traineeId';

  String get id => documentId(teacherId: teacherId, traineeId: traineeId);

  /// Fields written by the Firebase repository. [updatedAt] is normally
  /// `FieldValue.serverTimestamp()` so rules can require request-time writes.
  static Map<String, Object?> firestoreFields({
    required String teacherId,
    required String traineeId,
    required String groupId,
    required Object updatedAt,
  }) => {
    'teacher_id': teacherId,
    'trainee_id': traineeId,
    'group_id': groupId,
    'schema_version': currentSchemaVersion,
    'updated_at': updatedAt,
  };

  static ClassroomTeacherAccessContext? tryFromMap(
    Map<String, dynamic> map, {
    String? id,
  }) {
    final teacherId = _readString(map['teacher_id']);
    final traineeId = _readString(map['trainee_id']);
    final groupId = _readString(map['group_id']);
    final schemaVersion = _readInt(map['schema_version']);
    if (teacherId == null ||
        traineeId == null ||
        groupId == null ||
        teacherId == traineeId ||
        schemaVersion != currentSchemaVersion ||
        (id != null &&
            id != documentId(teacherId: teacherId, traineeId: traineeId))) {
      return null;
    }
    return ClassroomTeacherAccessContext(
      teacherId: teacherId,
      traineeId: traineeId,
      groupId: groupId,
      schemaVersion: schemaVersion!,
      updatedAt: TeacherRosterInvite.readDateTime(map['updated_at']),
    );
  }

  static String? _readString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }
}
