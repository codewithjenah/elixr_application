import 'coach_code.dart';

/// Durable Teacher-owned roster code stored at
/// `teacher_invites/{normalizedCode}`.
class TeacherRosterInvite {
  const TeacherRosterInvite({
    required this.normalizedCode,
    required this.teacherId,
    required this.teacherDisplayName,
    this.createdAt,
  });

  final String normalizedCode;
  final String teacherId;
  final String teacherDisplayName;
  final DateTime? createdAt;

  String get displayCode => CoachCode.format(normalizedCode);
  Uri get joinUri => Uri(
    scheme: 'elixr',
    host: 'join',
    queryParameters: {'code': normalizedCode},
  );

  static TeacherRosterInvite? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final normalized = CoachCode.tryNormalize(id);
    final teacherId = _readString(map['teacher_id']);
    final teacherDisplayName = _readString(map['teacher_display_name']);
    if (normalized == null || teacherId == null || teacherDisplayName == null) {
      return null;
    }
    return TeacherRosterInvite(
      normalizedCode: normalized,
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      createdAt: readDateTime(map['created_at']),
    );
  }

  static String? _readString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? readDateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    try {
      final toDate = (value as dynamic).toDate;
      if (toDate is Function) return (toDate() as DateTime?)?.toUtc();
    } catch (_) {}
    return null;
  }
}
