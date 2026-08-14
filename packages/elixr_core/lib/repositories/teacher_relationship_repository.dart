import '../models/teacher_invite.dart';
import '../models/teacher_student_link.dart';

/// Shared persistence for coach invites and Teacher↔Trainee relationships.
///
/// Does not enumerate users or invite codes. Callers pass an exact code or
/// the authenticated participant uid.
abstract class TeacherRelationshipRepository {
  Future<TeacherInvite> createOrRotateInvite({
    required String traineeId,
    required String traineeDisplayName,
  });

  Future<void> revokeInvite({required String traineeId});

  Future<TeacherInvite?> getActiveInvite({required String traineeId});

  Stream<List<TeacherStudentLink>> watchTraineeLinks({
    required String traineeId,
  });

  Stream<List<TeacherStudentLink>> watchTeacherLinks({
    required String teacherId,
  });

  /// Watches one deterministic link and reports whether it came from server.
  Stream<TeacherStudentLinkSnapshot> watchLink({
    required String teacherId,
    required String traineeId,
  });

  Future<TeacherInvite> resolveCoachCode(String code);

  Future<TeacherStudentLink> requestLink({
    required String teacherId,
    required String teacherDisplayName,
    required String code,
  });

  Future<void> approveLink({required String linkId, required String traineeId});

  Future<void> rejectLink({required String linkId, required String traineeId});

  Future<void> revokeLink({required String linkId, required String traineeId});

  Future<void> grantProgressAccess({
    required String linkId,
    required String traineeId,
  });

  Future<void> removeProgressAccess({
    required String linkId,
    required String traineeId,
  });

  Future<void> cancelLink({required String linkId, required String teacherId});
}

class TeacherStudentLinkSnapshot {
  const TeacherStudentLinkSnapshot({
    required this.link,
    required this.isServerVerified,
  });

  final TeacherStudentLink? link;
  final bool isServerVerified;
}
