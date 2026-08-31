import 'teacher_roster_invite.dart';

/// Lifecycle of a Teacher-owned classroom group document.
enum ElixrGroupStatus {
  active,
  archived;

  static ElixrGroupStatus? tryParse(String? value) {
    if (value == null) return null;
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// Teacher-owned group at `groups/{groupId}`.
class ElixrGroup {
  static const currentSchemaVersion = 2;
  static const maxSectionLength = 80;
  static const maxScheduleLength = 120;

  const ElixrGroup({
    required this.id,
    required this.teacherId,
    required this.name,
    required this.status,
    this.section,
    this.schedule,
    this.inviteCode,
    this.createdAt,
    this.updatedAt,
    this.schemaVersion = currentSchemaVersion,
  });

  final String id;
  final String teacherId;
  final String name;
  final ElixrGroupStatus status;
  final String? section;
  final String? schedule;
  final String? inviteCode;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int schemaVersion;

  bool get isActive => status == ElixrGroupStatus.active;

  ElixrGroup copyWith({
    String? name,
    String? section,
    String? schedule,
    bool clearSection = false,
    bool clearSchedule = false,
    ElixrGroupStatus? status,
    String? inviteCode,
    bool clearInviteCode = false,
    DateTime? updatedAt,
  }) => ElixrGroup(
    id: id,
    teacherId: teacherId,
    name: name ?? this.name,
    status: status ?? this.status,
    section: clearSection ? null : section ?? this.section,
    schedule: clearSchedule ? null : schedule ?? this.schedule,
    inviteCode: clearInviteCode ? null : inviteCode ?? this.inviteCode,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    schemaVersion: schemaVersion,
  );

  static ElixrGroup? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final teacherId = _readString(map['teacher_id']);
    final name = _readString(map['name']);
    final status = ElixrGroupStatus.tryParse(
      map['status'] is String ? map['status'] as String : null,
    );
    if (teacherId == null || name == null || status == null) return null;

    return ElixrGroup(
      id: id,
      teacherId: teacherId,
      name: name,
      status: status,
      section: _readOptionalText(map['section'], maxLength: maxSectionLength),
      schedule: _readOptionalText(
        map['schedule'],
        maxLength: maxScheduleLength,
      ),
      inviteCode: _readString(map['invite_code']),
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
      updatedAt: TeacherRosterInvite.readDateTime(map['updated_at']),
      schemaVersion: _readInt(map['schema_version']) ?? currentSchemaVersion,
    );
  }

  static String? _readString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  static String? _readOptionalText(dynamic value, {required int maxLength}) {
    if (value == null) return null;
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    return trimmed;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }
}
