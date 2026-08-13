import 'coach_code.dart';

/// Snapshot stored at `teacher_invites/{normalizedCode}`.
class TeacherInvite {
  const TeacherInvite({
    required this.normalizedCode,
    required this.traineeId,
    required this.traineeDisplayName,
    this.createdAt,
    this.expiresAt,
  });

  final String normalizedCode;
  final String traineeId;
  final String traineeDisplayName;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  String get displayCode => CoachCode.format(normalizedCode);

  bool isExpiredAt(DateTime now) {
    final expiresAt = this.expiresAt;
    if (expiresAt == null) return true;
    return !expiresAt.isAfter(now);
  }

  bool get isExpired => isExpiredAt(DateTime.now().toUtc());

  static TeacherInvite? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final traineeId = _readString(map['trainee_id']);
    final traineeDisplayName = _readString(map['trainee_display_name']);
    if (traineeId == null ||
        traineeId.isEmpty ||
        traineeDisplayName == null ||
        traineeDisplayName.isEmpty) {
      return null;
    }
    final normalized = CoachCode.tryNormalize(id);
    if (normalized == null) return null;

    return TeacherInvite(
      normalizedCode: normalized,
      traineeId: traineeId,
      traineeDisplayName: traineeDisplayName,
      createdAt: readDateTime(map['created_at']),
      expiresAt: readDateTime(map['expires_at']),
    );
  }

  static String? _readString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }

  static DateTime? readDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    try {
      final toDate = (value as dynamic).toDate;
      if (toDate is Function) {
        final date = toDate() as DateTime?;
        return date?.toUtc();
      }
    } catch (_) {}
    return null;
  }
}
