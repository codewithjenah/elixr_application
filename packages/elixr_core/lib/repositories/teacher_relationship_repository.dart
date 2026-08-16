import '../models/teacher_roster_invite.dart';
import '../models/teacher_student_link.dart';

/// Shared persistence for Teacher-owned roster codes and relationships.
abstract class TeacherRelationshipRepository {
  Future<TeacherRosterInvite> createOrRotateRosterInvite({
    required String teacherId,
    required String teacherDisplayName,
  });

  Future<TeacherRosterInvite?> getActiveRosterInvite({
    required String teacherId,
  });

  Future<void> revokeRosterInvite({required String teacherId});

  Future<TeacherRosterInvite> resolveRosterCode(String code);

  Stream<List<TeacherStudentLink>> watchTraineeLinks({
    required String traineeId,
  });

  Stream<List<TeacherStudentLink>> watchTeacherLinks({
    required String teacherId,
  });

  Stream<TeacherStudentLinkSnapshot> watchLink({
    required String teacherId,
    required String traineeId,
  });

  /// Creates or supersedes a deterministic non-approved link as a V2 request.
  Future<TeacherStudentLink> requestTeacherJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  });

  Future<void> approveJoin({required String linkId, required String teacherId});
  Future<void> rejectJoin({required String linkId, required String teacherId});
  Future<void> cancelJoin({required String linkId, required String traineeId});

  Future<void> revokeLink({required String linkId, required String traineeId});

  Future<void> grantProgressAccess({
    required String linkId,
    required String traineeId,
  });

  Future<void> removeProgressAccess({
    required String linkId,
    required String traineeId,
  });

  Future<void> grantEvidenceAccess({
    required String linkId,
    required String traineeId,
  });

  Future<void> removeEvidenceAccess({
    required String linkId,
    required String traineeId,
  });

  Future<void> revokeAllEvidenceAccess({required String traineeId});
}

class TeacherStudentLinkSnapshot {
  const TeacherStudentLinkSnapshot({
    required this.link,
    required this.isServerVerified,
  });

  final TeacherStudentLink? link;
  final bool isServerVerified;
}
