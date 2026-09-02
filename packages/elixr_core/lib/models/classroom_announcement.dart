import 'teacher_roster_invite.dart';

/// A Teacher-authored broadcast visible to the current approved members of a
/// classroom group.
class ClassroomAnnouncement {
  static const currentSchemaVersion = 1;
  static const maxTitleLength = 120;
  static const maxBodyLength = 2000;

  const ClassroomAnnouncement({
    required this.id,
    required this.groupId,
    required this.teacherId,
    required this.title,
    required this.body,
    this.createdAt,
    this.editedAt,
    this.isPinned = false,
    this.pinnedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  final String id;
  final String groupId;
  final String teacherId;
  final String title;
  final String body;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final bool isPinned;
  final DateTime? pinnedAt;
  final int schemaVersion;

  bool get isEdited => editedAt != null;

  ClassroomAnnouncement copyWith({
    String? title,
    String? body,
    DateTime? editedAt,
    bool? isPinned,
    DateTime? pinnedAt,
    bool clearPinnedAt = false,
  }) => ClassroomAnnouncement(
    id: id,
    groupId: groupId,
    teacherId: teacherId,
    title: title ?? this.title,
    body: body ?? this.body,
    createdAt: createdAt,
    editedAt: editedAt ?? this.editedAt,
    isPinned: isPinned ?? this.isPinned,
    pinnedAt: clearPinnedAt ? null : pinnedAt ?? this.pinnedAt,
    schemaVersion: schemaVersion,
  );

  static String? validateTitle(String value) =>
      _validate(value, fieldName: 'Title', maxLength: maxTitleLength);

  static String? validateBody(String value) =>
      _validate(value, fieldName: 'Announcement', maxLength: maxBodyLength);

  static String? _validate(
    String value, {
    required String fieldName,
    required int maxLength,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '$fieldName is required.';
    if (trimmed.length > maxLength) {
      return '$fieldName must be $maxLength characters or fewer.';
    }
    return null;
  }

  static ClassroomAnnouncement? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final groupId = _readString(map['group_id']);
    final teacherId = _readString(map['teacher_id']);
    final title = _readString(map['title']);
    final body = _readString(map['body']);
    if (id.trim().isEmpty ||
        groupId == null ||
        teacherId == null ||
        title == null ||
        body == null ||
        validateTitle(title) != null ||
        validateBody(body) != null) {
      return null;
    }
    return ClassroomAnnouncement(
      id: id,
      groupId: groupId,
      teacherId: teacherId,
      title: title,
      body: body,
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
      editedAt: TeacherRosterInvite.readDateTime(map['edited_at']),
      schemaVersion: _readInt(map['schema_version']) ?? currentSchemaVersion,
    );
  }

  static String? _readString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }
}
