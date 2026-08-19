import 'coach_code.dart';
import 'teacher_roster_invite.dart';

/// Per-group bearer invite stored at `group_invites/{normalizedCode}`.
class GroupInvite {
  const GroupInvite({
    required this.normalizedCode,
    required this.groupId,
    required this.teacherId,
    required this.teacherDisplayName,
    this.createdAt,
  });

  final String normalizedCode;
  final String groupId;
  final String teacherId;
  final String teacherDisplayName;
  final DateTime? createdAt;

  String get displayCode => CoachCode.format(normalizedCode);
  Uri get joinUri => Uri(
    scheme: 'elixr',
    host: 'join',
    queryParameters: {'code': normalizedCode},
  );

  static GroupInvite? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final normalized = CoachCode.tryNormalize(id);
    final groupId = _readString(map['group_id']);
    final teacherId = _readString(map['teacher_id']);
    final teacherDisplayName = _readString(map['teacher_display_name']);
    if (normalized == null ||
        groupId == null ||
        teacherId == null ||
        teacherDisplayName == null) {
      return null;
    }
    return GroupInvite(
      normalizedCode: normalized,
      groupId: groupId,
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
    );
  }

  static String? _readString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
