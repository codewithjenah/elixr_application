import 'teacher_invite.dart';

/// Lifecycle of one Teacher↔Trainee relationship document.
enum TeacherStudentLinkStatus {
  pending,
  approved,
  rejected,
  cancelled,
  revoked;

  static TeacherStudentLinkStatus? tryParse(String? value) {
    if (value == null) return null;
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// Authoritative relationship at `teacher_student_links/{teacherId}_{traineeId}`.
class TeacherStudentLink {
  const TeacherStudentLink({
    required this.id,
    required this.teacherId,
    required this.traineeId,
    required this.teacherDisplayName,
    required this.traineeDisplayName,
    required this.status,
    this.inviteId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String teacherId;
  final String traineeId;
  final String teacherDisplayName;
  final String traineeDisplayName;
  final TeacherStudentLinkStatus status;
  final String? inviteId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPending => status == TeacherStudentLinkStatus.pending;
  bool get isApproved => status == TeacherStudentLinkStatus.approved;

  static String documentId({
    required String teacherId,
    required String traineeId,
  }) {
    return '${teacherId}_$traineeId';
  }

  static TeacherStudentLink? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final teacherId = _readString(map['teacher_id']);
    final traineeId = _readString(map['trainee_id']);
    final teacherDisplayName = _readString(map['teacher_display_name']);
    final traineeDisplayName = _readString(map['trainee_display_name']);
    final status = TeacherStudentLinkStatus.tryParse(
      map['status'] is String ? map['status'] as String : null,
    );
    if (teacherId == null ||
        traineeId == null ||
        teacherDisplayName == null ||
        traineeDisplayName == null ||
        status == null) {
      return null;
    }

    return TeacherStudentLink(
      id: id,
      teacherId: teacherId,
      traineeId: traineeId,
      teacherDisplayName: teacherDisplayName,
      traineeDisplayName: traineeDisplayName,
      status: status,
      inviteId: _readString(map['invite_id']),
      createdAt: TeacherInvite.readDateTime(map['created_at']),
      updatedAt: TeacherInvite.readDateTime(map['updated_at']),
    );
  }

  static String? _readString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value;
    return null;
  }
}
