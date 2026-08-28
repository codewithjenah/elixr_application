import 'package:elixr_core/models/coach_code.dart';
import 'package:elixr_core/models/group_exception.dart';
import 'package:elixr_core/models/group_invite.dart';
import 'package:elixr_core/repositories/group_repository.dart';

/// Resolves Trainee join codes against classroom invites.
///
/// Historical Teacher-level roster invites are intentionally not resolved by
/// the current Teacher Access client. Its visible roster is derived only from
/// classroom memberships, so accepting a legacy invite would create a
/// relationship that is not attached to any class.
class JoinCodeResolver {
  const JoinCodeResolver({required GroupRepository groupRepository})
    : _groupRepository = groupRepository;

  final GroupRepository _groupRepository;

  Future<GroupInvite> resolve(String input) async {
    final normalized = CoachCode.tryNormalize(input);
    if (normalized == null) {
      throw const GroupException(
        GroupError.malformedCode,
        'That code is not valid.',
      );
    }

    return _groupRepository.resolveGroupInviteCode(normalized);
  }
}
