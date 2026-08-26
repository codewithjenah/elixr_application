import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_exception.dart';
import 'package:elixr_core/models/group_invite.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/teacher_relationship_exception.dart';
import 'package:elixr_core/models/teacher_roster_invite.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/public_profile.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../../services/join_code_resolver.dart';

enum JoinTeacherStep { enterCode, confirm }

class TeacherAccessController extends ChangeNotifier {
  TeacherAccessController({
    required this.relationshipRepository,
    required this.groupRepository,
    required this.joinCodeResolver,
    required this.traineeId,
    required this.traineeDisplayName,
    this.privateImageSavingEnabled = false,
    this.reconcileEvidenceAvailability,
    this.publicProfileRepository,
    this.onJoinCompleted,
  });

  final TeacherRelationshipRepository relationshipRepository;
  final GroupRepository groupRepository;
  final JoinCodeResolver joinCodeResolver;
  final String traineeId;
  final String traineeDisplayName;
  final bool privateImageSavingEnabled;
  final Future<void> Function(String traineeId)? reconcileEvidenceAvailability;
  final PublicProfileRepository? publicProfileRepository;
  final VoidCallback? onJoinCompleted;

  List<TeacherStudentLink> pending = const [];
  List<TeacherStudentLink> approved = const [];
  List<GroupMembership> pendingGroupMemberships = const [];
  List<GroupMembership> approvedGroupMemberships = const [];
  final Map<String, ElixrGroup> groupNamesById = {};
  bool loading = false;
  bool busy = false;
  String? errorMessage;
  String codeInput = '';
  JoinTeacherStep joinStep = JoinTeacherStep.enterCode;
  JoinCodeKind? resolvedKind;
  TeacherRosterInvite? resolvedTeacherInvite;
  GroupInvite? resolvedGroupInvite;
  String? resolvedGroupName;
  String? joinError;
  StreamSubscription<List<TeacherStudentLink>>? _linksSub;
  StreamSubscription<List<GroupMembership>>? _groupMembershipsSub;
  final Map<String, StreamSubscription<List<GroupMembership>>> _classmateSubs =
      {};
  final Map<String, List<GroupMembership>> membersByGroupId = {};
  final Map<String, StreamSubscription<PublicProfile?>> _profileSubs = {};
  final Map<String, String> _profilePictureUrls = {};
  bool _disposed = false;

  String? profilePictureUrlFor(String userId) {
    final url = _profilePictureUrls[userId]?.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  Set<String> get classroomTeacherIds => {
    for (final membership in approvedGroupMemberships) membership.teacherId,
  };

  /// Approved legacy relationships that are not already covered by an
  /// approved classroom membership. These retain the explicit legacy sharing
  /// controls for backward compatibility.
  List<TeacherStudentLink> get legacyOnlyApproved => [
    for (final link in approved)
      if (!classroomTeacherIds.contains(link.teacherId)) link,
  ];

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _linksSub?.cancel();
      await _groupMembershipsSub?.cancel();
      final firstLinks = Completer<void>();
      final firstGroups = Completer<void>();
      _linksSub = relationshipRepository
          .watchTraineeLinks(traineeId: traineeId)
          .listen(
            (links) {
              pending = [
                for (final link in links)
                  if (link.isPending && link.isV2Request) link,
              ];
              approved = [
                for (final link in links)
                  if (link.isApproved) link,
              ];
              if (!firstLinks.isCompleted) firstLinks.complete();
              notifyListeners();
            },
            onError: (Object error) {
              errorMessage = 'Could not load Teacher Access.';
              if (!firstLinks.isCompleted) firstLinks.completeError(error);
              notifyListeners();
            },
          );
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
              if (!firstGroups.isCompleted) firstGroups.complete();
              _syncClassmateWatches();
              _safeNotifyListeners();
              unawaited(_refreshGroupNames(memberships));
            },
            onError: (Object error) {
              errorMessage = 'Could not load group memberships.';
              if (!firstGroups.isCompleted) firstGroups.completeError(error);
              notifyListeners();
            },
          );
      await Future.wait([firstLinks.future, firstGroups.future]);
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
    resolvedKind = null;
    resolvedTeacherInvite = null;
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
    resolvedKind = null;
    resolvedTeacherInvite = null;
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
      final resolved = await joinCodeResolver.resolve(codeInput);
      resolvedKind = resolved.kind;
      switch (resolved) {
        case ResolvedGroupJoinCode(:final invite):
          resolvedGroupInvite = invite;
          resolvedTeacherInvite = null;
          final group = await groupRepository.getGroup(groupId: invite.groupId);
          resolvedGroupName = group?.name;
        case ResolvedTeacherRosterJoinCode(:final invite):
          resolvedTeacherInvite = invite;
          resolvedGroupInvite = null;
          resolvedGroupName = null;
      }
      joinStep = JoinTeacherStep.confirm;
    } on GroupException catch (error) {
      joinError = switch (error.code) {
        GroupError.malformedCode => 'That code is not valid.',
        GroupError.inviteNotFound =>
          'No group or Teacher roster is using that code.',
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
      switch (resolvedKind) {
        case JoinCodeKind.groupInvite:
          final invite = resolvedGroupInvite;
          if (invite == null) return false;
          final membership = await groupRepository.requestGroupJoin(
            traineeId: traineeId,
            traineeDisplayName: traineeDisplayName,
            code: invite.normalizedCode,
          );
          pendingGroupMemberships = [
            membership,
            ...pendingGroupMemberships.where(
              (item) => item.id != membership.id,
            ),
          ];
        case JoinCodeKind.teacherRosterInvite:
          final invite = resolvedTeacherInvite;
          if (invite == null) return false;
          final link = await relationshipRepository.requestTeacherJoin(
            traineeId: traineeId,
            traineeDisplayName: traineeDisplayName,
            code: invite.normalizedCode,
          );
          pending = [link, ...pending.where((item) => item.id != link.id)];
        case null:
          return false;
      }
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
    } on TeacherRelationshipException catch (error) {
      joinError = switch (error.code) {
        TeacherRelationshipError.alreadyPending =>
          'A request is already waiting for this Teacher.',
        TeacherRelationshipError.alreadyLinked =>
          'This Teacher is already linked.',
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

  Future<void> cancelPending(TeacherStudentLink link) => _run(() async {
    await relationshipRepository.cancelJoin(
      linkId: link.id,
      traineeId: traineeId,
    );
    pending = pending.where((item) => item.id != link.id).toList();
  }, 'Could not cancel that request.');

  Future<void> cancelPendingGroup(GroupMembership membership) => _run(() async {
    await groupRepository.cancelMembership(
      membershipId: membership.id,
      traineeId: traineeId,
    );
    pendingGroupMemberships = pendingGroupMemberships
        .where((item) => item.id != membership.id)
        .toList();
  }, 'Could not cancel that group request.');

  Future<void> revokeTeacher(TeacherStudentLink link) => _run(
    () => relationshipRepository.revokeLink(
      linkId: link.id,
      traineeId: traineeId,
    ),
    'Could not revoke that Teacher.',
  );

  Future<void> shareProgress(TeacherStudentLink link) => _run(
    () => relationshipRepository.grantProgressAccess(
      linkId: link.id,
      traineeId: traineeId,
    ),
    'Could not enable progress sharing. Check your connection and try again.',
  );

  Future<void> stopSharingProgress(TeacherStudentLink link) => _run(
    () => relationshipRepository.removeProgressAccess(
      linkId: link.id,
      traineeId: traineeId,
    ),
    'Could not stop progress sharing. Check your connection and try again.',
  );

  Future<void> shareEvidence(TeacherStudentLink link) => _run(
    () async {
      if (!privateImageSavingEnabled) {
        throw StateError('Private image saving is disabled');
      }
      await reconcileEvidenceAvailability?.call(traineeId);
      await relationshipRepository.grantEvidenceAccess(
        linkId: link.id,
        traineeId: traineeId,
      );
    },
    'Could not enable saved-image sharing. Check your connection and try again.',
  );

  Future<void> stopSharingEvidence(TeacherStudentLink link) => _run(
    () => relationshipRepository.removeEvidenceAccess(
      linkId: link.id,
      traineeId: traineeId,
    ),
    'Could not stop saved-image sharing.',
  );

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

  List<GroupMembership> membersForGroup(String groupId) {
    return membersByGroupId[groupId] ?? const [];
  }

  bool isLoadingGroupMembers(String groupId) {
    return !membersByGroupId.containsKey(groupId);
  }

  void _syncClassmateWatches() {
    final approvedIds = {
      for (final membership in approvedGroupMemberships) membership.groupId,
    };
    final staleIds = _classmateSubs.keys
        .where((id) => !approvedIds.contains(id))
        .toList(growable: false);
    for (final groupId in staleIds) {
      unawaited(_classmateSubs.remove(groupId)?.cancel());
      membersByGroupId.remove(groupId);
    }
    _syncClassmateProfileWatches();
    for (final membership in approvedGroupMemberships) {
      final groupId = membership.groupId;
      if (_classmateSubs.containsKey(groupId)) continue;
      _classmateSubs[groupId] = groupRepository
          .watchApprovedGroupMembers(
            groupId: groupId,
            teacherId: membership.teacherId,
          )
          .listen(
            (members) {
              if (_disposed) return;
              final sorted = [...members]
                ..sort(
                  (a, b) => a.traineeDisplayName.toLowerCase().compareTo(
                    b.traineeDisplayName.toLowerCase(),
                  ),
                );
              membersByGroupId[groupId] = sorted;
              _syncClassmateProfileWatches();
              _safeNotifyListeners();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (kDebugMode) {
                debugPrint(
                  '[TeacherAccess] classmates stream failed for $groupId: '
                  '$error\n$stackTrace',
                );
              }
              membersByGroupId[groupId] = const [];
              errorMessage = 'Could not load classmates.';
              _safeNotifyListeners();
            },
          );
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

  void _syncClassmateProfileWatches() {
    final ids = <String>{
      for (final members in membersByGroupId.values)
        for (final member in members) member.traineeId,
    };
    final repository = publicProfileRepository;
    if (repository == null) {
      _cancelClassmateProfileWatches();
      return;
    }

    final staleIds = _profileSubs.keys
        .where((id) => !ids.contains(id))
        .toList(growable: false);
    for (final id in staleIds) {
      unawaited(_profileSubs.remove(id)?.cancel());
      _profilePictureUrls.remove(id);
    }

    for (final traineeId in ids) {
      if (_profileSubs.containsKey(traineeId)) continue;
      _profileSubs[traineeId] = repository
          .watchProfileRoot(traineeId)
          .listen(
            (profile) {
              if (_disposed) return;
              final trimmed = profile?.profilePictureUrl?.trim();
              final next = (trimmed == null || trimmed.isEmpty)
                  ? null
                  : trimmed;
              final previous = _profilePictureUrls[traineeId];
              if (previous == next) return;
              if (next == null) {
                _profilePictureUrls.remove(traineeId);
              } else {
                _profilePictureUrls[traineeId] = next;
              }
              _safeNotifyListeners();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!kDebugMode) return;
              debugPrint(
                '[TeacherAccess] profile watch failed for $traineeId: '
                '$error\n$stackTrace',
              );
            },
          );
    }
  }

  void _cancelClassmateProfileWatches() {
    for (final subscription in _profileSubs.values) {
      unawaited(subscription.cancel());
    }
    _profileSubs.clear();
    _profilePictureUrls.clear();
  }

  void _safeNotifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_linksSub?.cancel());
    unawaited(_groupMembershipsSub?.cancel());
    for (final subscription in _classmateSubs.values) {
      unawaited(subscription.cancel());
    }
    _classmateSubs.clear();
    _cancelClassmateProfileWatches();
    super.dispose();
  }
}
