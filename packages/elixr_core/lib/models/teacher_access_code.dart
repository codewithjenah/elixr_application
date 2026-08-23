import 'coach_code.dart';
import 'teacher_roster_invite.dart';

/// One-time Teacher registration grant stored at
/// `teacher_access_codes/{normalizedCode}`.
///
/// TODO: Role trust should move to a Firebase Auth custom claim set by a
/// Cloud Function after code redemption. This document plus Firestore rules
/// is an interim control; a client can still write `users.role` if rules
/// are misconfigured.
class TeacherAccessCode {
  const TeacherAccessCode({
    required this.normalizedCode,
    required this.consumed,
    this.createdAt,
    this.note,
    this.createdBy,
    this.consumedBy,
    this.consumedAt,
  });

  final String normalizedCode;
  final bool consumed;
  final DateTime? createdAt;
  final String? note;
  final String? createdBy;
  final String? consumedBy;
  final DateTime? consumedAt;

  String get displayCode => CoachCode.format(normalizedCode);

  static TeacherAccessCode? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final normalized = CoachCode.tryNormalize(id);
    final consumed = map['consumed'];
    if (normalized == null || consumed is! bool) return null;
    return TeacherAccessCode(
      normalizedCode: normalized,
      consumed: consumed,
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
      note: _readString(map['note']),
      createdBy: _readString(map['created_by']),
      consumedBy: _readString(map['consumed_by']),
      consumedAt: TeacherRosterInvite.readDateTime(map['consumed_at']),
    );
  }

  static String? _readString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
