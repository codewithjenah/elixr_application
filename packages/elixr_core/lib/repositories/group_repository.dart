import '../models/elixr_group.dart';
import '../models/group_invite.dart';
import '../models/group_membership.dart';

/// Persistence for Teacher-owned groups, per-group invites, and memberships.
///
/// Legacy roster compatibility inventory (Phase 2 — documentation only):
/// - `teacher_invites/{code}`: one active Teacher-level roster code per Teacher.
/// - `teacher_student_links/{teacherId}_{traineeId}`: consent + roster lifecycle.
/// - Link statuses: pending, approved, rejected, cancelled, revoked.
/// - Consent fields: progress_access, evidence_access (+ versions/timestamps).
/// - Trainees may hold multiple approved Teacher links (no single-coach rule).
/// - Group membership does not write or modify teacher_student_links.
abstract class GroupRepository {
  Future<ElixrGroup> createGroup({
    required String teacherId,
    required String teacherDisplayName,
    required String name,
  });

  Stream<List<ElixrGroup>> watchTeacherGroups({required String teacherId});

  Future<ElixrGroup?> getGroup({required String groupId});

  Future<void> renameGroup({
    required String groupId,
    required String teacherId,
    required String name,
  });

  Future<void> archiveGroup({
    required String groupId,
    required String teacherId,
  });

  Future<GroupInvite> createOrRotateGroupInvite({
    required String groupId,
    required String teacherId,
    required String teacherDisplayName,
  });

  Future<GroupInvite?> getActiveGroupInvite({required String groupId});

  Future<GroupInvite> resolveGroupInviteCode(String code);

  Stream<List<GroupMembership>> watchGroupMemberships({
    required String groupId,
    required String teacherId,
    GroupMembershipStatus? status,
  });

  /// Teacher-wide membership stream ordered newest first.
  Stream<List<GroupMembership>> watchTeacherMemberships({
    required String teacherId,
  });

  Stream<List<GroupMembership>> watchTraineeMemberships({
    required String traineeId,
  });

  /// Approved members of one group, newest first.
  ///
  /// Firestore allows this query for the group's Teacher or an approved
  /// classmate. Callers must pass `groupId` and `teacherId` together with the
  /// approved-status filter — pending rows are not returned. Omitting
  /// `teacher_id` from the query makes the classmate list rule unprovable and
  /// Cloud Firestore denies the whole snapshot.
  Stream<List<GroupMembership>> watchApprovedGroupMembers({
    required String groupId,
    required String teacherId,
  });

  /// Idempotently prepares the protected-read pointer for an approved
  /// Teacher/Trainee classroom relationship. Implementations must validate the
  /// current membership before writing the pointer.
  Future<void> prepareClassroomAccessContext({
    required String teacherId,
    required String traineeId,
    required String groupId,
  });

  Future<GroupMembership> requestGroupJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  });

  Future<void> approveMembership({
    required String membershipId,
    required String teacherId,
  });

  Future<void> rejectMembership({
    required String membershipId,
    required String teacherId,
  });

  Future<void> removeMembership({
    required String membershipId,
    required String teacherId,
  });

  Future<void> cancelMembership({
    required String membershipId,
    required String traineeId,
  });
}
