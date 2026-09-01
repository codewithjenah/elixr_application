import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/coach_code.dart';
import '../models/classroom_teacher_access_context.dart';
import '../models/elixr_group.dart';
import '../models/group_exception.dart';
import '../models/group_invite.dart';
import '../models/group_membership.dart';
import 'group_repository.dart';

typedef GroupCodeGenerator = String Function();

class InMemoryGroupRepository implements GroupRepository {
  InMemoryGroupRepository({
    GroupCodeGenerator? generateNormalizedCode,
    DateTime Function()? now,
    String Function()? generateGroupId,
    this.maxCodeAttempts = 8,
  }) : generateNormalizedCode =
           generateNormalizedCode ?? CoachCode.generateNormalized,
       _now = now,
       _generateGroupId = generateGroupId ?? _defaultGroupId;

  final GroupCodeGenerator generateNormalizedCode;
  final DateTime Function()? _now;
  final String Function() _generateGroupId;
  final int maxCodeAttempts;

  final Map<String, ElixrGroup> groups = {};
  final Map<String, GroupInvite> invites = {};
  final Map<String, String> activeInviteByGroup = {};
  final Map<String, GroupMembership> memberships = {};
  final Map<String, ClassroomTeacherAccessContext> classroomAccessContexts = {};

  /// Legacy `teacher_invites` codes reserved for cross-namespace collision tests.
  @visibleForTesting
  Set<String> legacyTeacherInviteCodes = {};

  final _teacherGroupControllers =
      <String, StreamController<List<ElixrGroup>>>{};
  final _groupMembershipControllers =
      <String, StreamController<List<GroupMembership>>>{};
  final _teacherMembershipControllers =
      <String, StreamController<List<GroupMembership>>>{};
  final _traineeMembershipControllers =
      <String, StreamController<List<GroupMembership>>>{};
  final _approvedMemberControllers =
      <String, StreamController<List<GroupMembership>>>{};

  static String _defaultGroupId() =>
      'group-${DateTime.now().microsecondsSinceEpoch}';

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  @visibleForTesting
  void seedGroup(ElixrGroup group) {
    groups[group.id] = group;
    _emitGroups();
  }

  @visibleForTesting
  void seedInvite(GroupInvite invite) {
    invites[invite.normalizedCode] = invite;
    activeInviteByGroup[invite.groupId] = invite.normalizedCode;
    final group = groups[invite.groupId];
    if (group != null) {
      groups[invite.groupId] = group.copyWith(
        inviteCode: invite.normalizedCode,
      );
    }
    _emitGroups();
  }

  @visibleForTesting
  void seedMembership(GroupMembership membership) {
    memberships[membership.id] = membership;
    _emitMemberships();
  }

  @override
  Future<void> prepareClassroomAccessContext({
    required String teacherId,
    required String traineeId,
    required String groupId,
  }) async {
    final membership =
        memberships[GroupMembership.documentId(
          groupId: groupId,
          traineeId: traineeId,
        )];
    final group = groups[groupId];
    if (membership == null ||
        !membership.isApproved ||
        membership.teacherId != teacherId ||
        membership.traineeId != traineeId ||
        membership.groupId != groupId ||
        group == null ||
        group.teacherId != teacherId) {
      throw const GroupException(GroupError.notFound);
    }
    classroomAccessContexts[ClassroomTeacherAccessContext.documentId(
      teacherId: teacherId,
      traineeId: traineeId,
    )] = ClassroomTeacherAccessContext(
      teacherId: teacherId,
      traineeId: traineeId,
      groupId: groupId,
      updatedAt: now,
    );
  }

  void dispose() {
    for (final controller in _teacherGroupControllers.values) {
      controller.close();
    }
    for (final controller in _groupMembershipControllers.values) {
      controller.close();
    }
    for (final controller in _teacherMembershipControllers.values) {
      controller.close();
    }
    for (final controller in _traineeMembershipControllers.values) {
      controller.close();
    }
    for (final controller in _approvedMemberControllers.values) {
      controller.close();
    }
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
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const GroupException(
        GroupError.forbidden,
        'Group name is required.',
      );
    }
    final timestamp = now;
    final id = _generateGroupId();
    final group = ElixrGroup(
      id: id,
      teacherId: teacherId,
      name: trimmed,
      status: ElixrGroupStatus.active,
      section: _normalizeOptional(section, ElixrGroup.maxSectionLength),
      schedule: _normalizeOptional(schedule, ElixrGroup.maxScheduleLength),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    groups[id] = group;
    try {
      await createOrRotateGroupInvite(
        groupId: id,
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
      );
    } catch (e) {
      groups.remove(id);
      rethrow;
    }
    _emitGroups();
    return groups[id]!;
  }

  @override
  Stream<List<ElixrGroup>> watchTeacherGroups({required String teacherId}) =>
      _watchGroups(teacherId);

  @override
  Future<ElixrGroup?> getGroup({required String groupId}) async =>
      groups[groupId];

  @override
  Future<void> renameGroup({
    required String groupId,
    required String teacherId,
    required String name,
  }) async {
    final group = groups[groupId];
    if (group == null || group.teacherId != teacherId) {
      throw const GroupException(GroupError.notFound);
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const GroupException(
        GroupError.forbidden,
        'Group name is required.',
      );
    }
    await updateGroupDetails(
      groupId: groupId,
      teacherId: teacherId,
      name: trimmed,
      section: group.section,
      schedule: group.schedule,
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
    final group = groups[groupId];
    if (group == null || group.teacherId != teacherId) {
      throw const GroupException(GroupError.notFound);
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const GroupException(
        GroupError.forbidden,
        'Group name is required.',
      );
    }
    groups[groupId] = group.copyWith(
      name: trimmed,
      section: _normalizeOptional(section, ElixrGroup.maxSectionLength),
      schedule: _normalizeOptional(schedule, ElixrGroup.maxScheduleLength),
      clearSection: section == null || section.trim().isEmpty,
      clearSchedule: schedule == null || schedule.trim().isEmpty,
      updatedAt: now,
    );
    _emitGroups();
  }

  static String? _normalizeOptional(String? value, int maxLength) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.length > maxLength) {
      throw const GroupException(
        GroupError.forbidden,
        'Class detail is too long.',
      );
    }
    return trimmed;
  }

  @override
  Future<void> archiveGroup({
    required String groupId,
    required String teacherId,
  }) async {
    final group = groups[groupId];
    if (group == null || group.teacherId != teacherId) {
      throw const GroupException(GroupError.notFound);
    }
    groups[groupId] = group.copyWith(
      status: ElixrGroupStatus.archived,
      updatedAt: now,
    );
    _emitGroups();
  }

  @override
  Future<void> unarchiveGroup({
    required String groupId,
    required String teacherId,
  }) async {
    final group = groups[groupId];
    if (group == null || group.teacherId != teacherId) {
      throw const GroupException(GroupError.notFound);
    }
    groups[groupId] = group.copyWith(
      status: ElixrGroupStatus.active,
      updatedAt: now,
    );
    _emitGroups();
  }

  @override
  Future<GroupInvite> createOrRotateGroupInvite({
    required String groupId,
    required String teacherId,
    required String teacherDisplayName,
  }) async {
    final group = groups[groupId];
    if (group == null || group.teacherId != teacherId) {
      throw const GroupException(GroupError.notFound);
    }
    if (!group.isActive) {
      throw const GroupException(
        GroupError.groupInactive,
        'Cannot rotate invite for an archived group.',
      );
    }
    final previous = activeInviteByGroup[groupId];
    for (var attempt = 0; attempt < maxCodeAttempts; attempt++) {
      final normalized = generateNormalizedCode();
      if (!CoachCode.isNormalized(normalized) ||
          legacyTeacherInviteCodes.contains(normalized) ||
          (invites.containsKey(normalized) && previous != normalized)) {
        continue;
      }
      if (previous != null && previous != normalized) {
        invites.remove(previous);
      }
      final invite = GroupInvite(
        normalizedCode: normalized,
        groupId: groupId,
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        createdAt: now,
      );
      invites[normalized] = invite;
      activeInviteByGroup[groupId] = normalized;
      groups[groupId] = group.copyWith(inviteCode: normalized, updatedAt: now);
      _emitGroups();
      return invite;
    }
    throw const GroupException(
      GroupError.collisionExhausted,
      'Could not allocate a unique group invite code.',
    );
  }

  @override
  Future<GroupInvite?> getActiveGroupInvite({required String groupId}) async {
    final code = activeInviteByGroup[groupId];
    return code == null ? null : invites[code];
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
    final invite = invites[normalized];
    if (invite == null) {
      throw const GroupException(
        GroupError.inviteNotFound,
        'No group is using that invite code.',
      );
    }
    return invite;
  }

  String _membershipWatchKey(
    String teacherId,
    String groupId,
    GroupMembershipStatus? status,
  ) => '$teacherId::$groupId::${status?.name ?? 'all'}';

  (String teacherId, String groupId, GroupMembershipStatus? status)
  _parseMembershipWatchKey(String key) {
    final parts = key.split('::');
    if (parts.length < 2) return (key, '', null);
    final teacherId = parts[0];
    final groupId = parts[1];
    final statusName = parts.length > 2 ? parts[2] : 'all';
    return (
      teacherId,
      groupId,
      statusName == 'all' ? null : GroupMembershipStatus.tryParse(statusName),
    );
  }

  @override
  Stream<List<GroupMembership>> watchGroupMemberships({
    required String groupId,
    required String teacherId,
    GroupMembershipStatus? status,
  }) => _watchMemberships(
    _groupMembershipControllers,
    _membershipWatchKey(teacherId, groupId, status),
    () => _membershipsForGroup(teacherId, groupId, status),
  );

  @override
  Stream<List<GroupMembership>> watchTeacherMemberships({
    required String teacherId,
  }) => _watchMemberships(
    _teacherMembershipControllers,
    teacherId,
    () => _membershipsForTeacher(teacherId),
  );

  @override
  Stream<List<GroupMembership>> watchTraineeMemberships({
    required String traineeId,
  }) => _watchMemberships(
    _traineeMembershipControllers,
    traineeId,
    () => _membershipsForTrainee(traineeId),
  );

  @override
  Stream<List<GroupMembership>> watchApprovedGroupMembers({
    required String groupId,
    required String teacherId,
  }) => _watchMemberships(
    _approvedMemberControllers,
    _approvedMemberWatchKey(teacherId, groupId),
    () => _approvedMembersForGroup(teacherId, groupId),
  );

  @override
  Future<GroupMembership> requestGroupJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  }) async {
    final invite = await resolveGroupInviteCode(code);
    final group = groups[invite.groupId];
    if (group == null) {
      throw const GroupException(GroupError.groupNotFound);
    }
    if (!group.isActive) {
      throw const GroupException(
        GroupError.groupInactive,
        'That group is no longer accepting members.',
      );
    }
    if (invite.teacherId == traineeId) {
      throw const GroupException(
        GroupError.invalidParticipant,
        'You cannot join your own group.',
      );
    }
    final id = GroupMembership.documentId(
      groupId: invite.groupId,
      traineeId: traineeId,
    );
    final existing = memberships[id];
    if (existing?.isApproved == true) {
      throw const GroupException(
        GroupError.alreadyMember,
        'You are already a member of this group.',
      );
    }
    if (existing?.isPending == true) {
      throw const GroupException(
        GroupError.alreadyPending,
        'A request is already waiting for this group.',
      );
    }
    final timestamp = now;
    final membership = GroupMembership(
      id: id,
      groupId: invite.groupId,
      teacherId: invite.teacherId,
      traineeId: traineeId,
      traineeDisplayName: traineeDisplayName,
      teacherDisplayName: invite.teacherDisplayName,
      status: GroupMembershipStatus.pending,
      inviteId: invite.normalizedCode,
      requestVersion: GroupMembership.currentRequestVersion,
      createdAt: existing?.createdAt ?? timestamp,
      updatedAt: timestamp,
    );
    memberships[id] = membership;
    _emitMemberships();
    return membership;
  }

  @override
  Future<void> approveMembership({
    required String membershipId,
    required String teacherId,
  }) async {
    final membership = memberships[membershipId];
    if (membership == null ||
        membership.teacherId != teacherId ||
        !membership.isPending) {
      throw const GroupException(GroupError.notFound);
    }
    final group = groups[membership.groupId];
    if (group == null || group.teacherId != teacherId) {
      throw const GroupException(GroupError.notFound);
    }
    memberships[membershipId] = membership.copyWith(
      status: GroupMembershipStatus.approved,
      updatedAt: now,
    );
    classroomAccessContexts[ClassroomTeacherAccessContext.documentId(
      teacherId: membership.teacherId,
      traineeId: membership.traineeId,
    )] = ClassroomTeacherAccessContext(
      teacherId: membership.teacherId,
      traineeId: membership.traineeId,
      groupId: membership.groupId,
      updatedAt: now,
    );
    _emitMemberships();
  }

  @override
  Future<void> rejectMembership({
    required String membershipId,
    required String teacherId,
  }) => _transition(
    membershipId: membershipId,
    participantId: teacherId,
    teacherOwned: true,
    from: GroupMembershipStatus.pending,
    to: GroupMembershipStatus.rejected,
  );

  @override
  Future<void> removeMembership({
    required String membershipId,
    required String teacherId,
  }) => _transition(
    membershipId: membershipId,
    participantId: teacherId,
    teacherOwned: true,
    from: GroupMembershipStatus.approved,
    to: GroupMembershipStatus.removed,
  );

  @override
  Future<void> cancelMembership({
    required String membershipId,
    required String traineeId,
  }) => _transition(
    membershipId: membershipId,
    participantId: traineeId,
    teacherOwned: false,
    from: GroupMembershipStatus.pending,
    to: GroupMembershipStatus.cancelled,
  );

  @override
  Future<void> leaveMembership({
    required String membershipId,
    required String traineeId,
  }) => _transition(
    membershipId: membershipId,
    participantId: traineeId,
    teacherOwned: false,
    from: GroupMembershipStatus.approved,
    to: GroupMembershipStatus.removed,
  );

  Future<void> _transition({
    required String membershipId,
    required String participantId,
    required bool teacherOwned,
    required GroupMembershipStatus from,
    required GroupMembershipStatus to,
  }) async {
    final membership = memberships[membershipId];
    final matches = teacherOwned
        ? membership?.teacherId == participantId
        : membership?.traineeId == participantId;
    if (membership == null || !matches || membership.status != from) {
      throw const GroupException(GroupError.notFound);
    }
    memberships[membershipId] = membership.copyWith(status: to, updatedAt: now);
    _emitMemberships();
  }

  Stream<List<ElixrGroup>> _watchGroups(String teacherId) {
    final existing = _teacherGroupControllers[teacherId];
    if (existing != null && !existing.isClosed) return existing.stream;
    late final StreamController<List<ElixrGroup>> controller;
    controller = StreamController<List<ElixrGroup>>.broadcast(
      onListen: () => controller.add(_groupsForTeacher(teacherId)),
    );
    _teacherGroupControllers[teacherId] = controller;
    return controller.stream;
  }

  Stream<List<GroupMembership>> _watchMemberships(
    Map<String, StreamController<List<GroupMembership>>> controllers,
    String key,
    List<GroupMembership> Function() current,
  ) {
    final existing = controllers[key];
    if (existing != null && !existing.isClosed) return existing.stream;
    late final StreamController<List<GroupMembership>> controller;
    controller = StreamController<List<GroupMembership>>.broadcast(
      onListen: () => controller.add(current()),
    );
    controllers[key] = controller;
    return controller.stream;
  }

  List<ElixrGroup> _groupsForTeacher(String teacherId) {
    final result = groups.values
        .where((group) => group.teacherId == teacherId)
        .toList();
    result.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return result;
  }

  List<GroupMembership> _membershipsForGroup(
    String teacherId,
    String groupId,
    GroupMembershipStatus? status,
  ) {
    final result = memberships.values.where((membership) {
      if (membership.teacherId != teacherId) return false;
      if (membership.groupId != groupId) return false;
      if (status != null && membership.status != status) return false;
      return true;
    }).toList();
    result.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return result;
  }

  List<GroupMembership> _membershipsForTeacher(String teacherId) {
    final result = memberships.values
        .where((membership) => membership.teacherId == teacherId)
        .toList();
    result.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return result;
  }

  List<GroupMembership> _membershipsForTrainee(String traineeId) {
    final result = memberships.values
        .where((membership) => membership.traineeId == traineeId)
        .toList();
    result.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return result;
  }

  String _approvedMemberWatchKey(String teacherId, String groupId) =>
      '$teacherId::$groupId';

  (String teacherId, String groupId) _parseApprovedMemberWatchKey(String key) {
    final separator = key.indexOf('::');
    if (separator <= 0) return (key, '');
    return (key.substring(0, separator), key.substring(separator + 2));
  }

  List<GroupMembership> _approvedMembersForGroup(
    String teacherId,
    String groupId,
  ) {
    final result = memberships.values
        .where(
          (membership) =>
              membership.teacherId == teacherId &&
              membership.groupId == groupId &&
              membership.isApproved,
        )
        .toList();
    result.sort(
      (a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)),
    );
    return result;
  }

  void _emitGroups() {
    for (final entry in _teacherGroupControllers.entries) {
      if (!entry.value.isClosed) {
        entry.value.add(_groupsForTeacher(entry.key));
      }
    }
  }

  void _emitMemberships() {
    for (final entry in _groupMembershipControllers.entries) {
      if (!entry.value.isClosed) {
        final (teacherId, groupId, status) = _parseMembershipWatchKey(
          entry.key,
        );
        entry.value.add(_membershipsForGroup(teacherId, groupId, status));
      }
    }
    for (final entry in _teacherMembershipControllers.entries) {
      if (!entry.value.isClosed) {
        entry.value.add(_membershipsForTeacher(entry.key));
      }
    }
    for (final entry in _traineeMembershipControllers.entries) {
      if (!entry.value.isClosed) {
        entry.value.add(_membershipsForTrainee(entry.key));
      }
    }
    for (final entry in _approvedMemberControllers.entries) {
      if (!entry.value.isClosed) {
        final (teacherId, groupId) = _parseApprovedMemberWatchKey(entry.key);
        entry.value.add(_approvedMembersForGroup(teacherId, groupId));
      }
    }
  }
}
