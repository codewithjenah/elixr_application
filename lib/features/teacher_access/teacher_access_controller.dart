import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_exception.dart';
import 'package:elixr_core/models/group_invite.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/group_assignment.dart';
import '../../data/models/public_profile.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/join_code_resolver.dart';

enum JoinTeacherStep { enterCode, confirm }

class TeacherAccessController extends ChangeNotifier {
  TeacherAccessController({
    required this.groupRepository,
    required this.joinCodeResolver,
    required this.traineeId,
    required this.traineeDisplayName,
    this.onJoinCompleted,
    this.assignmentRepository,
    this.publicProfileRepository,
  });

  final GroupRepository groupRepository;
  final JoinCodeResolver joinCodeResolver;
  final String traineeId;
  final String traineeDisplayName;
  final VoidCallback? onJoinCompleted;
  final ClassroomAssignmentRepository? assignmentRepository;
  final PublicProfileRepository? publicProfileRepository;

  List<GroupMembership> pendingGroupMemberships = const [];
  List<GroupMembership> approvedGroupMemberships = const [];
  final Map<String, ElixrGroup> groupNamesById = {};
  Map<String, List<GroupAssignment>> assignmentsByGroupId = const {};
  final Map<String, String> _teacherProfilePictureUrls = {};
  final Map<String, String> _teacherDisplayNames = {};
  final Map<String, StreamSubscription<PublicProfile?>> _teacherProfileSubs =
      {};
  final Map<String, StreamSubscription<ElixrGroup?>> _activeGroupSubs = {};
  int _assignmentLoadGen = 0;
  bool loading = false;
  bool busy = false;
  String? errorMessage;
  String codeInput = '';
  JoinTeacherStep joinStep = JoinTeacherStep.enterCode;
  GroupInvite? resolvedGroupInvite;
  String? resolvedGroupName;
  String? joinError;
  StreamSubscription<List<GroupMembership>>? _groupMembershipsSub;
  bool _disposed = false;

  List<GroupAssignment> assignmentsFor(String groupId) {
    return assignmentsByGroupId[groupId] ?? const [];
  }

  String? teacherProfilePictureUrlFor(String teacherId) {
    final url = _teacherProfilePictureUrls[teacherId]?.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  /// Prefer the teacher's current profile name over the display name captured
  /// when the trainee joined the class. The membership value remains the
  /// offline/backward-compatible fallback.
  String teacherDisplayNameFor(GroupMembership membership) {
    final profileName = _teacherDisplayNames[membership.teacherId]?.trim();
    return profileName == null || profileName.isEmpty
        ? membership.teacherDisplayName
        : profileName;
  }

  int get pendingJoinCount => pendingGroupMemberships.length;

  List<GroupMembership> get activeApprovedGroupMemberships => [
    for (final membership in approvedGroupMemberships)
      if (groupNamesById[membership.groupId]?.isActive == true) membership,
  ];

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _groupMembershipsSub?.cancel();
      _groupMembershipsSub = null;
      await _cancelActiveGroupWatches();
      groupNamesById.clear();
      assignmentsByGroupId = const {};
      final firstGroups = Completer<void>();
      _groupMembershipsSub = groupRepository
          .watchTraineeMemberships(traineeId: traineeId)
          .listen(
            (memberships) {
              pendingGroupMemberships = [
                for (final membership in memberships)
                  if (membership.isPending) membership,
              ];
              approvedGroupMemberships = [
                for (final membership in memberships)
                  if (membership.isApproved) membership,
              ];
              _syncActiveGroupWatches();
              _syncTeacherProfileWatches();
              if (!firstGroups.isCompleted) firstGroups.complete();
              _safeNotifyListeners();
              unawaited(_refreshPendingGroupNames(memberships));
              unawaited(_refreshAssignments());
            },
            onError: (Object error) {
              errorMessage = 'Could not load your classes.';
              if (!firstGroups.isCompleted) firstGroups.completeError(error);
              _safeNotifyListeners();
            },
          );
      await firstGroups.future;
    } catch (_) {
      errorMessage = 'Could not load your classes.';
    } finally {
      loading = false;
      _safeNotifyListeners();
    }
  }

  void prefillCode(String code) {
    codeInput = code;
    joinStep = JoinTeacherStep.enterCode;
    resolvedGroupInvite = null;
    resolvedGroupName = null;
    joinError = null;
    notifyListeners();
  }

  void setCodeInput(String value) {
    codeInput = value;
    joinError = null;
    notifyListeners();
  }

  void resetJoin() {
    codeInput = '';
    joinStep = JoinTeacherStep.enterCode;
    resolvedGroupInvite = null;
    resolvedGroupName = null;
    joinError = null;
    notifyListeners();
  }

  Future<void> resolveCode() async {
    if (busy) return;
    busy = true;
    joinError = null;
    notifyListeners();
    try {
      final invite = await joinCodeResolver.resolve(codeInput);
      resolvedGroupInvite = invite;
      final group = await groupRepository.getGroup(groupId: invite.groupId);
      resolvedGroupName = group?.name;
      joinStep = JoinTeacherStep.confirm;
    } on GroupException catch (error) {
      joinError = switch (error.code) {
        GroupError.malformedCode => 'That code is not valid.',
        GroupError.inviteNotFound => 'No class is using that code.',
        _ => error.message ?? 'Could not look up that code.',
      };
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[TeacherAccess] resolveCode failed: $error\n$stackTrace');
      }
      joinError = 'Could not look up that code.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> confirmJoin() async {
    if (busy) return false;
    busy = true;
    joinError = null;
    notifyListeners();
    try {
      final invite = resolvedGroupInvite;
      if (invite == null) return false;
      final membership = await groupRepository.requestGroupJoin(
        traineeId: traineeId,
        traineeDisplayName: traineeDisplayName,
        code: invite.normalizedCode,
      );
      pendingGroupMemberships = [
        membership,
        ...pendingGroupMemberships.where((item) => item.id != membership.id),
      ];
      resetJoin();
      onJoinCompleted?.call();
      return true;
    } on GroupException catch (error) {
      joinError = switch (error.code) {
        GroupError.alreadyPending =>
          'A request is already waiting for this group.',
        GroupError.alreadyMember => 'You are already a member of this group.',
        GroupError.groupInactive =>
          'That group is no longer accepting members.',
        _ => error.message ?? 'Could not send that request.',
      };
      return false;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[TeacherAccess] confirmJoin failed: $error\n$stackTrace');
      }
      joinError = 'Could not send that request.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> cancelPendingGroup(GroupMembership membership) => _run(() async {
    await groupRepository.cancelMembership(
      membershipId: membership.id,
      traineeId: traineeId,
    );
    pendingGroupMemberships = pendingGroupMemberships
        .where((item) => item.id != membership.id)
        .toList();
  }, 'Could not cancel that group request.');

  Future<void> leaveApprovedGroup(GroupMembership membership) => _run(() async {
    await groupRepository.leaveMembership(
      membershipId: membership.id,
      traineeId: traineeId,
    );
    approvedGroupMemberships = approvedGroupMemberships
        .where((item) => item.id != membership.id)
        .toList();
    _syncActiveGroupWatches();
    _syncTeacherProfileWatches();
    groupNamesById.remove(membership.groupId);
    assignmentsByGroupId = {...assignmentsByGroupId}
      ..remove(membership.groupId);
  }, 'Could not leave this class.');

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (_) {
      errorMessage = failure;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _refreshAssignments() async {
    final repo = assignmentRepository;
    if (repo == null) {
      assignmentsByGroupId = const {};
      return;
    }
    final gen = ++_assignmentLoadGen;
    final groupIds = [
      for (final membership in activeApprovedGroupMemberships)
        membership.groupId,
    ];
    try {
      final visible = await repo.fetchAssignmentsForTrainee(
        traineeId: traineeId,
      );
      if (_disposed || gen != _assignmentLoadGen) return;
      final next = {
        for (final groupId in groupIds)
          groupId: [
            for (final assignment in visible)
              if (assignment.groupId == groupId) assignment,
          ],
      };
      assignmentsByGroupId = next;
      _safeNotifyListeners();
    } catch (error, stackTrace) {
      if (!kDebugMode) return;
      debugPrint(
        '[TeacherAccess] assignment preview load failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> _refreshPendingGroupNames(
    List<GroupMembership> memberships,
  ) async {
    final pending = [
      for (final membership in memberships)
        if (membership.isPending) membership,
    ];
    final visibleGroupIds = {
      for (final membership in pending) membership.groupId,
      for (final membership in approvedGroupMemberships) membership.groupId,
    };
    groupNamesById.removeWhere(
      (groupId, _) => !visibleGroupIds.contains(groupId),
    );
    for (final membership in pending) {
      if (_disposed) return;
      try {
        final group = await groupRepository.getGroup(
          groupId: membership.groupId,
        );
        if (group != null &&
            approvedGroupMemberships.every(
              (item) => item.groupId != membership.groupId,
            ) &&
            pendingGroupMemberships.any((item) => item.id == membership.id)) {
          groupNamesById[membership.groupId] = group;
        }
      } catch (_) {
        // A pending class that is no longer readable stays out of the cache.
      }
    }
    _safeNotifyListeners();
  }

  void _syncActiveGroupWatches() {
    final approvedGroupIds = {
      for (final membership in approvedGroupMemberships) membership.groupId,
    };
    final staleIds = _activeGroupSubs.keys
        .where((groupId) => !approvedGroupIds.contains(groupId))
        .toList(growable: false);
    for (final groupId in staleIds) {
      unawaited(_activeGroupSubs.remove(groupId)?.cancel());
      groupNamesById.remove(groupId);
    }

    for (final groupId in approvedGroupIds) {
      if (_activeGroupSubs.containsKey(groupId)) continue;
      _activeGroupSubs[groupId] = groupRepository
          .watchActiveGroupForTrainee(groupId: groupId, traineeId: traineeId)
          .listen(
            (group) {
              if (_disposed) return;
              final membership = _approvedMembershipForGroup(groupId);
              if (group == null ||
                  membership == null ||
                  group.teacherId != membership.teacherId) {
                groupNamesById.remove(groupId);
              } else {
                groupNamesById[groupId] = group;
              }
              _safeNotifyListeners();
              unawaited(_refreshAssignments());
            },
            onError: (Object error, StackTrace stackTrace) {
              if (_disposed) return;
              groupNamesById.remove(groupId);
              if (kDebugMode) {
                debugPrint(
                  '[TeacherAccess] active class watch failed for '
                  '$groupId: $error\n$stackTrace',
                );
              }
              _safeNotifyListeners();
              unawaited(_refreshAssignments());
            },
          );
    }
  }

  GroupMembership? _approvedMembershipForGroup(String groupId) {
    for (final membership in approvedGroupMemberships) {
      if (membership.groupId == groupId) return membership;
    }
    return null;
  }

  Future<void> _cancelActiveGroupWatches() async {
    final subscriptions = _activeGroupSubs.values.toList(growable: false);
    _activeGroupSubs.clear();
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  }

  void _syncTeacherProfileWatches() {
    final repository = publicProfileRepository;
    final teacherIds = {
      for (final membership in approvedGroupMemberships) membership.teacherId,
    };
    if (repository == null) {
      _cancelTeacherProfileWatches();
      return;
    }

    final staleIds = _teacherProfileSubs.keys
        .where((id) => !teacherIds.contains(id))
        .toList(growable: false);
    for (final id in staleIds) {
      unawaited(_teacherProfileSubs.remove(id)?.cancel());
      _teacherProfilePictureUrls.remove(id);
      _teacherDisplayNames.remove(id);
    }

    for (final teacherId in teacherIds) {
      if (_teacherProfileSubs.containsKey(teacherId)) continue;
      _teacherProfileSubs[teacherId] = repository
          .watchProfileRoot(teacherId)
          .listen(
            (profile) {
              if (_disposed) return;
              final trimmed = profile?.profilePictureUrl?.trim();
              final next = (trimmed == null || trimmed.isEmpty)
                  ? null
                  : trimmed;
              final name = profile?.displayName.trim();
              final nextName = name == null || name.isEmpty ? null : name;
              final previousImage = _teacherProfilePictureUrls[teacherId];
              final previousName = _teacherDisplayNames[teacherId];
              if (previousImage == next && previousName == nextName) return;
              if (next == null) {
                _teacherProfilePictureUrls.remove(teacherId);
              } else {
                _teacherProfilePictureUrls[teacherId] = next;
              }
              if (nextName == null) {
                _teacherDisplayNames.remove(teacherId);
              } else {
                _teacherDisplayNames[teacherId] = nextName;
              }
              _safeNotifyListeners();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!kDebugMode) return;
              debugPrint(
                '[TeacherAccess] teacher profile watch failed for '
                '$teacherId: $error\n$stackTrace',
              );
            },
          );
    }
  }

  void _cancelTeacherProfileWatches() {
    for (final subscription in _teacherProfileSubs.values) {
      unawaited(subscription.cancel());
    }
    _teacherProfileSubs.clear();
    _teacherProfilePictureUrls.clear();
    _teacherDisplayNames.clear();
  }

  void _safeNotifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _assignmentLoadGen++;
    unawaited(_groupMembershipsSub?.cancel());
    unawaited(_cancelActiveGroupWatches());
    _cancelTeacherProfileWatches();
    super.dispose();
  }
}
