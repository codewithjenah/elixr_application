import 'dart:async';

import 'package:supabase/supabase.dart';

import '../database/supabase_support.dart';
import '../models/coach_code.dart';
import '../models/elixr_group.dart';
import '../models/group_exception.dart';
import '../models/group_invite.dart';
import '../models/group_membership.dart';
import 'group_repository.dart';

class SupabaseGroupRepository implements GroupRepository {
  SupabaseGroupRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  static GroupException? exceptionFor(Object error) {
    return switch (backendErrorCode(error)) {
      'malformed_code' => const GroupException(
        GroupError.malformedCode,
        'That group code is not valid.',
      ),
      'invite_not_found' => const GroupException(
        GroupError.inviteNotFound,
        'No group is using that invite code.',
      ),
      'group_not_found' => const GroupException(GroupError.groupNotFound),
      'group_inactive' => const GroupException(
        GroupError.groupInactive,
        'That group is no longer accepting members.',
      ),
      'already_member' => const GroupException(
        GroupError.alreadyMember,
        'You are already a member of this group.',
      ),
      'already_pending' => const GroupException(
        GroupError.alreadyPending,
        'A request is already waiting for this group.',
      ),
      'invalid_participant' => const GroupException(
        GroupError.invalidParticipant,
        'You cannot join your own group.',
      ),
      'collision_exhausted' => const GroupException(
        GroupError.collisionExhausted,
        'Could not allocate a unique group invite code.',
      ),
      'invalid_name' => const GroupException(
        GroupError.forbidden,
        'Group name is required.',
      ),
      'detail_too_long' => const GroupException(
        GroupError.forbidden,
        'Class detail is too long.',
      ),
      'not_found' => const GroupException(GroupError.notFound),
      'forbidden' => const GroupException(GroupError.forbidden),
      _ => null,
    };
  }

  Future<T> _mapped<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw exceptionFor(error) ?? error;
    }
  }

  static List<GroupMembership> _memberships(
    List<Map<String, dynamic>> rows, {
    bool Function(GroupMembership membership)? where,
  }) {
    final items = [
      for (final row in rows)
        ?GroupMembership.tryFromMap(compactRow(row), id: row['id'] as String),
    ].where((membership) => where?.call(membership) ?? true).toList();
    items.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return items;
  }

  static GroupInvite _invite(Map<String, dynamic> row) {
    final parsed = GroupInvite.tryFromMap(row, id: row['code'] as String);
    if (parsed == null) throw const FormatException('Malformed group invite.');
    return parsed;
  }

  @override
  Future<ElixrGroup> createGroup({
    required String teacherId,
    required String teacherDisplayName,
    required String name,
  }) => createGroupWithDetails(
    teacherId: teacherId,
    teacherDisplayName: teacherDisplayName,
    name: name,
  );

  @override
  Future<ElixrGroup> createGroupWithDetails({
    required String teacherId,
    required String teacherDisplayName,
    required String name,
    String? section,
    String? schedule,
  }) async {
    if (name.trim().isEmpty) {
      throw const GroupException(
        GroupError.forbidden,
        'Group name is required.',
      );
    }
    final row = await _mapped(
      () => rpcMap(_client, 'create_group', {
        'p_name': name.trim(),
        'p_section': section,
        'p_schedule': schedule,
      }),
    );
    final group = ElixrGroup.tryFromMap(row, id: row['id'] as String);
    if (group == null) throw const FormatException('Malformed classroom.');
    return group;
  }

  @override
  Stream<List<ElixrGroup>> watchTeacherGroups({required String teacherId}) {
    return _client
        .from('groups')
        .stream(primaryKey: ['id'])
        .eq('teacher_id', teacherId)
        .order('created_at') // newest first
        .map(
          (rows) => [
            for (final row in rows)
              ?ElixrGroup.tryFromMap(compactRow(row), id: row['id'] as String),
          ],
        );
  }

  @override
  Stream<ElixrGroup?> watchActiveGroupForTrainee({
    required String groupId,
    required String traineeId,
  }) {
    // The lifecycle projection is readable by approved members even after the
    // classroom is archived; archived metadata itself stays hidden.
    return _client
        .from('group_lifecycle')
        .stream(primaryKey: ['group_id'])
        .eq('group_id', groupId)
        .asyncMap((rows) async {
          if (rows.isEmpty || rows.first['status'] != 'active') return null;
          return _readActiveGroup(groupId);
        });
  }

  Future<ElixrGroup?> _readActiveGroup(String groupId) async {
    final group = await getGroup(groupId: groupId);
    return group?.isActive == true ? group : null;
  }

  @override
  Future<ElixrGroup?> getGroup({required String groupId}) async {
    final row = await _client
        .from('groups')
        .select()
        .eq('id', groupId)
        .maybeSingle();
    if (row == null) return null;
    return ElixrGroup.tryFromMap(compactRow(row), id: groupId);
  }

  @override
  Future<void> renameGroup({
    required String groupId,
    required String teacherId,
    required String name,
  }) async {
    final group = await getGroup(groupId: groupId);
    await updateGroupDetails(
      groupId: groupId,
      teacherId: teacherId,
      name: name,
      section: group?.section,
      schedule: group?.schedule,
    );
  }

  @override
  Future<void> updateGroupDetails({
    required String groupId,
    required String teacherId,
    required String name,
    String? section,
    String? schedule,
  }) async {
    if (name.trim().isEmpty) {
      throw const GroupException(
        GroupError.forbidden,
        'Group name is required.',
      );
    }
    await _mapped(
      () => _client.rpc<dynamic>(
        'update_group_details',
        params: {
          'p_group_id': groupId,
          'p_name': name.trim(),
          'p_section': section,
          'p_schedule': schedule,
        },
      ),
    );
  }

  @override
  Future<void> archiveGroup({
    required String groupId,
    required String teacherId,
  }) => _setStatus(groupId, ElixrGroupStatus.archived);

  @override
  Future<void> unarchiveGroup({
    required String groupId,
    required String teacherId,
  }) => _setStatus(groupId, ElixrGroupStatus.active);

  Future<void> _setStatus(String groupId, ElixrGroupStatus status) => _mapped(
    () => _client.rpc<dynamic>(
      'set_group_status',
      params: {'p_group_id': groupId, 'p_status': status.name},
    ),
  );

  @override
  Future<GroupInvite> createOrRotateGroupInvite({
    required String groupId,
    required String teacherId,
    required String teacherDisplayName,
  }) async {
    final row = await _mapped(
      () => rpcMap(_client, 'rotate_group_invite', {'p_group_id': groupId}),
    );
    return _invite(row);
  }

  @override
  Future<GroupInvite?> getActiveGroupInvite({required String groupId}) async {
    final result = await _mapped(
      () => _client.rpc<dynamic>(
        'get_active_group_invite',
        params: {'p_group_id': groupId},
      ),
    );
    if (result == null) return null;
    final invite = _invite(asRowMap(result));
    return invite.groupId == groupId ? invite : null;
  }

  @override
  Future<GroupInvite> resolveGroupInviteCode(String code) async {
    final normalized = CoachCode.tryNormalize(code);
    if (normalized == null) {
      throw const GroupException(
        GroupError.malformedCode,
        'That group code is not valid.',
      );
    }
    final row = await _mapped(
      () => rpcMap(_client, 'resolve_group_invite', {'p_code': normalized}),
    );
    return _invite(row);
  }

  @override
  Stream<List<GroupMembership>> watchGroupMemberships({
    required String groupId,
    required String teacherId,
    GroupMembershipStatus? status,
  }) {
    return _client
        .from('group_memberships')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .map(
          (rows) => _memberships(
            rows,
            where: (membership) =>
                membership.teacherId == teacherId &&
                (status == null || membership.status == status),
          ),
        );
  }

  @override
  Stream<List<GroupMembership>> watchTeacherMemberships({
    required String teacherId,
  }) {
    return _client
        .from('group_memberships')
        .stream(primaryKey: ['id'])
        .eq('teacher_id', teacherId)
        .map(_memberships);
  }

  @override
  Stream<List<GroupMembership>> watchTraineeMemberships({
    required String traineeId,
  }) {
    return _client
        .from('group_memberships')
        .stream(primaryKey: ['id'])
        .eq('trainee_id', traineeId)
        .map(_memberships);
  }

  @override
  Stream<List<GroupMembership>> watchApprovedGroupMembers({
    required String groupId,
    required String teacherId,
  }) {
    return _client
        .from('group_memberships')
        .stream(primaryKey: ['id'])
        .eq('group_id', groupId)
        .map(
          (rows) => _memberships(
            rows,
            where: (membership) =>
                membership.teacherId == teacherId && membership.isApproved,
          ),
        );
  }

  @override
  Future<void> prepareClassroomAccessContext({
    required String teacherId,
    required String traineeId,
    required String groupId,
  }) => _mapped(
    () => _client.rpc<dynamic>(
      'prepare_classroom_access_context',
      params: {'p_trainee_id': traineeId, 'p_group_id': groupId},
    ),
  );

  @override
  Future<GroupMembership> requestGroupJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  }) async {
    final normalized = CoachCode.tryNormalize(code);
    if (normalized == null) {
      throw const GroupException(
        GroupError.malformedCode,
        'That group code is not valid.',
      );
    }
    final row = await _mapped(
      () => rpcMap(_client, 'request_group_join', {'p_code': normalized}),
    );
    final membership = GroupMembership.tryFromMap(row, id: row['id'] as String);
    if (membership == null) {
      throw const FormatException('Malformed membership.');
    }
    return membership;
  }

  Future<void> _transition(String membershipId, String action) => _mapped(
    () => _client.rpc<dynamic>(
      'transition_group_membership',
      params: {'p_membership_id': membershipId, 'p_action': action},
    ),
  );

  @override
  Future<void> approveMembership({
    required String membershipId,
    required String teacherId,
  }) => _transition(membershipId, 'approve');

  @override
  Future<void> rejectMembership({
    required String membershipId,
    required String teacherId,
  }) => _transition(membershipId, 'reject');

  @override
  Future<void> removeMembership({
    required String membershipId,
    required String teacherId,
  }) => _transition(membershipId, 'remove');

  @override
  Future<void> cancelMembership({
    required String membershipId,
    required String traineeId,
  }) => _transition(membershipId, 'cancel');

  @override
  Future<void> leaveMembership({
    required String membershipId,
    required String traineeId,
  }) => _transition(membershipId, 'leave');
}
