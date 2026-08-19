import 'package:elixr_core/models/coach_code.dart';
import 'package:elixr_core/models/group_exception.dart';
import 'package:elixr_core/models/group_invite.dart';
import 'package:elixr_core/models/teacher_relationship_exception.dart';
import 'package:elixr_core/models/teacher_roster_invite.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';

/// Typed resolution for Trainee join codes.
enum JoinCodeKind { groupInvite, teacherRosterInvite }

sealed class ResolvedJoinCode {
  const ResolvedJoinCode(this.kind);

  final JoinCodeKind kind;
}

final class ResolvedGroupJoinCode extends ResolvedJoinCode {
  const ResolvedGroupJoinCode(this.invite) : super(JoinCodeKind.groupInvite);

  final GroupInvite invite;
}

final class ResolvedTeacherRosterJoinCode extends ResolvedJoinCode {
  const ResolvedTeacherRosterJoinCode(this.invite)
    : super(JoinCodeKind.teacherRosterInvite);

  final TeacherRosterInvite invite;
}

/// Resolves a normalized coach code against group invites first, then legacy
/// Teacher roster invites.
class JoinCodeResolver {
  const JoinCodeResolver({
    required GroupRepository groupRepository,
    required TeacherRelationshipRepository relationshipRepository,
  }) : _groupRepository = groupRepository,
       _relationshipRepository = relationshipRepository;

  final GroupRepository _groupRepository;
  final TeacherRelationshipRepository _relationshipRepository;

  Future<ResolvedJoinCode> resolve(String input) async {
    final normalized = CoachCode.tryNormalize(input);
    if (normalized == null) {
      throw const GroupException(
        GroupError.malformedCode,
        'That code is not valid.',
      );
    }

    try {
      final groupInvite = await _groupRepository.resolveGroupInviteCode(
        normalized,
      );
      return ResolvedGroupJoinCode(groupInvite);
    } on GroupException catch (error) {
      if (error.code != GroupError.inviteNotFound &&
          error.code != GroupError.malformedCode) {
        rethrow;
      }
    }

    try {
      final rosterInvite = await _relationshipRepository.resolveRosterCode(
        normalized,
      );
      return ResolvedTeacherRosterJoinCode(rosterInvite);
    } on TeacherRelationshipException catch (error) {
      if (error.code == TeacherRelationshipError.inviteNotFound) {
        throw const GroupException(
          GroupError.inviteNotFound,
          'No group or Teacher roster is using that code.',
        );
      }
      if (error.code == TeacherRelationshipError.malformedCode) {
        throw const GroupException(
          GroupError.malformedCode,
          'That code is not valid.',
        );
      }
      rethrow;
    }
  }
}
