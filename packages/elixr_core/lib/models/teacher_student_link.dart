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

/// Explicit, versioned consent for a Teacher to read sanitized progress.
enum TeacherProgressAccess {
  none,
  granted;

  static TeacherProgressAccess fromFirestore(Object? value) {
    return value == 'granted'
        ? TeacherProgressAccess.granted
        : TeacherProgressAccess.none;
  }
}

/// Authoritative relationship at `teacher_student_links/{teacherId}_{traineeId}`.
class TeacherStudentLink {
  static const supportedProgressAccessVersion = 1;
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
    this.progressAccess = TeacherProgressAccess.none,
    this.progressAccessVersion,
    this.progressAccessGrantedAt,
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
  final TeacherProgressAccess progressAccess;
  final int? progressAccessVersion;
  final DateTime? progressAccessGrantedAt;

  bool get isPending => status == TeacherStudentLinkStatus.pending;
  bool get isApproved => status == TeacherStudentLinkStatus.approved;
  bool get hasEffectiveProgressAccess =>
      isApproved &&
      progressAccess == TeacherProgressAccess.granted &&
      progressAccessVersion == supportedProgressAccessVersion &&
      progressAccessGrantedAt != null;

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
      progressAccess: TeacherProgressAccess.fromFirestore(
        map['progress_access'],
      ),
      progressAccessVersion: _readInt(map['progress_access_version']),
      progressAccessGrantedAt: TeacherInvite.readDateTime(
        map['progress_access_granted_at'],
      ),
    );
  }

  static String? _readString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) return value;
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
