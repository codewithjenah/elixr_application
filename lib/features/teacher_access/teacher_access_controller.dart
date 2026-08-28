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
  final Map<String, StreamSubscription<PublicProfile?>> _teacherProfileSubs =
      {};
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

  int get pendingJoinCount => pendingGroupMemberships.length;

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _groupMembershipsSub?.cancel();
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
              _syncTeacherProfileWatches();
              if (!firstGroups.isCompleted) firstGroups.complete();
              _safeNotifyListeners();
              unawaited(_refreshGroupNames(memberships));
              unawaited(_refreshAssignments());
            },
            onError: (Object error) {
              errorMessage = 'Could not load group memberships.';
              if (!firstGroups.isCompleted) firstGroups.completeError(error);
              notifyListeners();
            },
          );
      await firstGroups.future;
    } catch (_) {
      errorMessage = 'Could not load Teacher Access.';
    } finally {
      loading = false;
      notifyListeners();
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

  Future<void> _refreshGroupNames(List<GroupMembership> memberships) async {
    for (final membership in memberships) {
      if (_disposed) return;
      final group = await groupRepository.getGroup(groupId: membership.groupId);
      if (group != null) {
        groupNamesById[membership.groupId] = group;
      }
    }
    _safeNotifyListeners();
  }

  Future<void> _refreshAssignments() async {
    final repo = assignmentRepository;
    if (repo == null) {
      assignmentsByGroupId = const {};
      return;
    }
    final gen = ++_assignmentLoadGen;
    final groupIds = [
      for (final membership in approvedGroupMemberships) membership.groupId,
    ];
    try {
      final next = <String, List<GroupAssignment>>{};
      for (final groupId in groupIds) {
        if (_disposed || gen != _assignmentLoadGen) return;
        next[groupId] = await repo.fetchAssignmentsForGroup(groupId: groupId);
      }
      if (_disposed || gen != _assignmentLoadGen) return;
      assignmentsByGroupId = next;
      _safeNotifyListeners();
    } catch (error, stackTrace) {
      if (!kDebugMode) return;
      debugPrint(
        '[TeacherAccess] assignment preview load failed: $error\n$stackTrace',
      );
    }
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
              final previous = _teacherProfilePictureUrls[teacherId];
              if (previous == next) return;
              if (next == null) {
                _teacherProfilePictureUrls.remove(teacherId);
              } else {
                _teacherProfilePictureUrls[teacherId] = next;
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
  }

  void _safeNotifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _assignmentLoadGen++;
    unawaited(_groupMembershipsSub?.cancel());
    _cancelTeacherProfileWatches();
    super.dispose();
  }
}
