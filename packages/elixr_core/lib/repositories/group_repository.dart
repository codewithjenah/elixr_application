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

  Stream<List<GroupMembership>> watchTraineeMemberships({
    required String traineeId,
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
