import 'teacher_roster_invite.dart';

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
  static const supportedEvidenceAccessVersion = 1;
  static const currentRequestVersion = 2;
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
    this.requestVersion,
    this.evidenceAccess = TeacherProgressAccess.none,
    this.evidenceAccessVersion,
    this.evidenceAccessGrantedAt,
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
  final int? requestVersion;
  final TeacherProgressAccess evidenceAccess;
  final int? evidenceAccessVersion;
  final DateTime? evidenceAccessGrantedAt;

  bool get isPending => status == TeacherStudentLinkStatus.pending;
  bool get isV2Request => requestVersion == currentRequestVersion;
  bool get isApproved => status == TeacherStudentLinkStatus.approved;
  bool get hasEffectiveProgressAccess =>
      isApproved &&
      progressAccess == TeacherProgressAccess.granted &&
      progressAccessVersion == supportedProgressAccessVersion &&
      progressAccessGrantedAt != null;
  bool get hasEffectiveEvidenceAccess =>
      hasEffectiveProgressAccess &&
      evidenceAccess == TeacherProgressAccess.granted &&
      evidenceAccessVersion == supportedEvidenceAccessVersion &&
      evidenceAccessGrantedAt != null;

  TeacherStudentLink copyWith({
    TeacherStudentLinkStatus? status,
    String? inviteId,
    DateTime? updatedAt,
    TeacherProgressAccess? progressAccess,
    int? progressAccessVersion,
    bool clearProgressVersion = false,
    DateTime? progressAccessGrantedAt,
    bool clearProgressGrantedAt = false,
    int? requestVersion,
    TeacherProgressAccess? evidenceAccess,
    int? evidenceAccessVersion,
    bool clearEvidenceVersion = false,
    DateTime? evidenceAccessGrantedAt,
    bool clearEvidenceGrantedAt = false,
  }) => TeacherStudentLink(
    id: id,
    teacherId: teacherId,
    traineeId: traineeId,
    teacherDisplayName: teacherDisplayName,
    traineeDisplayName: traineeDisplayName,
    status: status ?? this.status,
    inviteId: inviteId ?? this.inviteId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    progressAccess: progressAccess ?? this.progressAccess,
    progressAccessVersion: clearProgressVersion
        ? null
        : progressAccessVersion ?? this.progressAccessVersion,
    progressAccessGrantedAt: clearProgressGrantedAt
        ? null
        : progressAccessGrantedAt ?? this.progressAccessGrantedAt,
    requestVersion: requestVersion ?? this.requestVersion,
    evidenceAccess: evidenceAccess ?? this.evidenceAccess,
    evidenceAccessVersion: clearEvidenceVersion
        ? null
        : evidenceAccessVersion ?? this.evidenceAccessVersion,
    evidenceAccessGrantedAt: clearEvidenceGrantedAt
        ? null
        : evidenceAccessGrantedAt ?? this.evidenceAccessGrantedAt,
  );

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
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
      updatedAt: TeacherRosterInvite.readDateTime(map['updated_at']),
      progressAccess: TeacherProgressAccess.fromFirestore(
        map['progress_access'],
      ),
      progressAccessVersion: _readInt(map['progress_access_version']),
      progressAccessGrantedAt: TeacherRosterInvite.readDateTime(
        map['progress_access_granted_at'],
      ),
      requestVersion: _readInt(map['request_version']),
      evidenceAccess: TeacherProgressAccess.fromFirestore(
        map['evidence_access'],
      ),
      evidenceAccessVersion: _readInt(map['evidence_access_version']),
      evidenceAccessGrantedAt: TeacherRosterInvite.readDateTime(
        map['evidence_access_granted_at'],
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
