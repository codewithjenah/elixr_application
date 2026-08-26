import 'teacher_roster_invite.dart';

/// Lifecycle of one Trainee membership in a Teacher-owned group.
enum GroupMembershipStatus {
  pending,
  approved,
  rejected,
  cancelled,
  removed;

  static GroupMembershipStatus? tryParse(String? value) {
    if (value == null) return null;
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// Membership at `group_memberships/{groupId}_{traineeId}`.
///
/// Approved membership is **Classroom Authorization**. It automatically
/// enables the separate, read-only classroom progress/evidence context while
/// it remains approved; assignment submission authorization is separate.
class GroupMembership {
  static const currentRequestVersion = 1;

  const GroupMembership({
    required this.id,
    required this.groupId,
    required this.teacherId,
    required this.traineeId,
    required this.traineeDisplayName,
    required this.teacherDisplayName,
    required this.status,
    this.inviteId,
    this.createdAt,
    this.updatedAt,
    this.requestVersion,
  });

  final String id;
  final String groupId;
  final String teacherId;
  final String traineeId;
  final String traineeDisplayName;
  final String teacherDisplayName;
  final GroupMembershipStatus status;
  final String? inviteId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? requestVersion;

  bool get isPending => status == GroupMembershipStatus.pending;
  bool get isApproved => status == GroupMembershipStatus.approved;

  /// Classroom Authorization exists only for approved membership.
  bool get hasClassroomAuthorization => isApproved;

  GroupMembership copyWith({
    GroupMembershipStatus? status,
    String? inviteId,
    DateTime? updatedAt,
    int? requestVersion,
  }) => GroupMembership(
    id: id,
    groupId: groupId,
    teacherId: teacherId,
    traineeId: traineeId,
    traineeDisplayName: traineeDisplayName,
    teacherDisplayName: teacherDisplayName,
    status: status ?? this.status,
    inviteId: inviteId ?? this.inviteId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    requestVersion: requestVersion ?? this.requestVersion,
  );

  static String documentId({
    required String groupId,
    required String traineeId,
  }) => '${groupId}_$traineeId';

  static GroupMembership? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
  }) {
    final groupId = _readString(map['group_id']);
    final teacherId = _readString(map['teacher_id']);
    final traineeId = _readString(map['trainee_id']);
    final traineeDisplayName = _readString(map['trainee_display_name']);
    final teacherDisplayName = _readString(map['teacher_display_name']);
    final status = GroupMembershipStatus.tryParse(
      map['status'] is String ? map['status'] as String : null,
    );
    if (groupId == null ||
        teacherId == null ||
        traineeId == null ||
        traineeDisplayName == null ||
        teacherDisplayName == null ||
        status == null) {
      return null;
    }

    return GroupMembership(
      id: id,
      groupId: groupId,
      teacherId: teacherId,
      traineeId: traineeId,
      traineeDisplayName: traineeDisplayName,
      teacherDisplayName: teacherDisplayName,
      status: status,
      inviteId: _readString(map['invite_id']),
      createdAt: TeacherRosterInvite.readDateTime(map['created_at']),
      updatedAt: TeacherRosterInvite.readDateTime(map['updated_at']),
      requestVersion: _readInt(map['request_version']),
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
