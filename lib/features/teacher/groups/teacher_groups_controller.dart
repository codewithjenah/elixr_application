import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_exception.dart';
import 'package:elixr_core/models/group_invite.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../core/auth/teacher_auth_messages.dart';
import '../../../data/models/public_profile.dart';
import '../../../data/repositories/public_profile_repository.dart';

class TeacherGroupsController extends ChangeNotifier {
  TeacherGroupsController({
    required this.repository,
    required this.teacherId,
    required this.teacherDisplayName,
    this.ensureTeacherAuthorization,
    this.publicProfileRepository,
  });

  final GroupRepository repository;
  final String teacherId;
  final String teacherDisplayName;
  final Future<bool> Function()? ensureTeacherAuthorization;
  final PublicProfileRepository? publicProfileRepository;

  List<ElixrGroup> groups = const [];
  ElixrGroup? selectedGroup;
  List<GroupMembership> pendingMemberships = const [];
  List<GroupMembership> approvedMemberships = const [];
  GroupInvite? activeInvite;
  bool loading = false;
  bool busy = false;
  String? errorMessage;
  String? actionMessage;

  StreamSubscription<List<ElixrGroup>>? _groupsSub;
  StreamSubscription<List<GroupMembership>>? _pendingSub;
  StreamSubscription<List<GroupMembership>>? _approvedSub;
  final Map<String, StreamSubscription<PublicProfile?>> _profileSubs = {};
  final Map<String, String> _profilePictureUrls = {};

  String? profilePictureUrlFor(String traineeId) {
    final url = _profilePictureUrls[traineeId]?.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _groupsSub?.cancel();
      final first = Completer<void>();
      _groupsSub = repository
          .watchTeacherGroups(teacherId: teacherId)
          .listen(
            (value) {
              groups = value;
              if (selectedGroup != null) {
                final selectedId = selectedGroup!.id;
                ElixrGroup? refreshed;
                for (final group in value) {
                  if (group.id == selectedId) {
                    refreshed = group;
                    break;
                  }
                }
                if (refreshed == null) {
                  clearSelection();
                } else {
                  selectedGroup = refreshed;
                }
              }
              if (!first.isCompleted) first.complete();
              notifyListeners();
            },
            onError: (Object error) {
              errorMessage = 'Could not load groups.';
              if (!first.isCompleted) first.completeError(error);
              notifyListeners();
            },
          );
      await first.future;
    } catch (_) {
      errorMessage = 'Could not load groups.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectGroup(ElixrGroup group) async {
    selectedGroup = group;
    actionMessage = null;
    notifyListeners();
    await _watchSelectedGroup(group.id);
  }

  void clearSelection() {
    selectedGroup = null;
    pendingMemberships = const [];
    approvedMemberships = const [];
    activeInvite = null;
    unawaited(_pendingSub?.cancel());
    unawaited(_approvedSub?.cancel());
    _syncMemberProfileWatches();
    notifyListeners();
  }

  Future<void> createGroup(String name) {
    return _runTeacherAction(
      operation: 'createGroup',
      failureMessage: 'Could not create that group.',
      action: () async {
        final group = await repository.createGroup(
          teacherId: teacherId,
          teacherDisplayName: teacherDisplayName,
          name: name,
        );
        actionMessage = 'Created ${group.name}.';
        await selectGroup(group);
      },
    );
  }

  Future<void> renameSelectedGroup(String name) {
    final group = selectedGroup;
    if (group == null) return Future.value();
    return _runTeacherAction(
      operation: 'renameGroup',
      failureMessage: 'Could not rename that group.',
      action: () async {
        await repository.renameGroup(
          groupId: group.id,
          teacherId: teacherId,
          name: name,
        );
        actionMessage = 'Renamed group.';
      },
    );
  }

  Future<void> archiveSelectedGroup() {
    final group = selectedGroup;
    if (group == null) return Future.value();
    return _runTeacherAction(
      operation: 'archiveGroup',
      failureMessage: 'Could not archive that group.',
      action: () async {
        await repository.archiveGroup(groupId: group.id, teacherId: teacherId);
        actionMessage = 'Archived ${group.name}.';
        clearSelection();
      },
    );
  }

  Future<void> rotateInvite() {
    final group = selectedGroup;
    if (group == null) return Future.value();
    return _runTeacherAction(
      operation: 'rotateInvite',
      failureMessage: 'Could not make a new class code.',
      action: () async {
        activeInvite = await repository.createOrRotateGroupInvite(
          groupId: group.id,
          teacherId: teacherId,
          teacherDisplayName: teacherDisplayName,
        );
        actionMessage = 'New class code is ready.';
      },
    );
  }

  Future<void> approveMembership(GroupMembership membership) =>
      _runTeacherAction(
        operation: 'approveMembership',
        failureMessage: 'Could not approve that request.',
        action: () => repository.approveMembership(
          membershipId: membership.id,
          teacherId: teacherId,
        ),
      );

  Future<void> rejectMembership(GroupMembership membership) =>
      _runTeacherAction(
        operation: 'rejectMembership',
        failureMessage: 'Could not reject that request.',
        action: () => repository.rejectMembership(
          membershipId: membership.id,
          teacherId: teacherId,
        ),
      );

  Future<void> removeMembership(GroupMembership membership) =>
      _runTeacherAction(
        operation: 'removeMembership',
        failureMessage: 'Could not remove that member.',
        action: () => repository.removeMembership(
          membershipId: membership.id,
          teacherId: teacherId,
        ),
      );

  Future<void> _watchSelectedGroup(String groupId) async {
    await _pendingSub?.cancel();
    await _approvedSub?.cancel();
    activeInvite = await repository.getActiveGroupInvite(groupId: groupId);
    final pendingFirst = Completer<void>();
    final approvedFirst = Completer<void>();
    _pendingSub = repository
        .watchGroupMemberships(
          groupId: groupId,
          teacherId: teacherId,
          status: GroupMembershipStatus.pending,
        )
        .listen(
          (value) {
            pendingMemberships = value;
            _syncMemberProfileWatches();
            if (!pendingFirst.isCompleted) pendingFirst.complete();
            notifyListeners();
          },
          onError: (Object error, StackTrace stackTrace) {
            _logMembershipStreamFailure('pending', error, stackTrace);
            errorMessage = 'Could not load pending requests.';
            if (!pendingFirst.isCompleted) pendingFirst.complete();
            notifyListeners();
          },
        );
    _approvedSub = repository
        .watchGroupMemberships(
          groupId: groupId,
          teacherId: teacherId,
          status: GroupMembershipStatus.approved,
        )
        .listen(
          (value) {
            approvedMemberships = value;
            _syncMemberProfileWatches();
            if (!approvedFirst.isCompleted) approvedFirst.complete();
            notifyListeners();
          },
          onError: (Object error, StackTrace stackTrace) {
            _logMembershipStreamFailure('approved', error, stackTrace);
            errorMessage = 'Could not load members.';
            if (!approvedFirst.isCompleted) approvedFirst.complete();
            notifyListeners();
          },
        );
    await Future.wait([pendingFirst.future, approvedFirst.future]);
    notifyListeners();
  }

  Future<void> _runTeacherAction({
    required String operation,
    required Future<void> Function() action,
    required String failureMessage,
  }) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final authorized = await _ensureAuthorizationFresh(operation);
      if (!authorized) {
        errorMessage = TeacherAuthMessages.teacherAuthorizationRefreshRequired;
        return;
      }
      await action();
    } on GroupException catch (error, stackTrace) {
      _logTeacherActionFailure(operation, error, stackTrace);
      errorMessage = error.message ?? failureMessage;
    } catch (error, stackTrace) {
      _logTeacherActionFailure(operation, error, stackTrace);
      errorMessage = failureMessage;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> _ensureAuthorizationFresh(String operation) async {
    final callback = ensureTeacherAuthorization;
    if (callback == null) return false;
    try {
      return await callback();
    } catch (error, stackTrace) {
      _logTeacherActionFailure(operation, error, stackTrace);
      return false;
    }
  }

  void _logTeacherActionFailure(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    debugPrint('[TeacherGroups] $operation failed: $error\n$stackTrace');
  }

  void _logMembershipStreamFailure(
    String stream,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    debugPrint(
      '[TeacherGroups] $stream memberships stream failed: $error\n$stackTrace',
    );
  }

  void _syncMemberProfileWatches() {
    final ids = <String>{
      for (final membership in pendingMemberships) membership.traineeId,
      for (final membership in approvedMemberships) membership.traineeId,
    };
    final repository = publicProfileRepository;
    if (repository == null) {
      _cancelMemberProfileWatches();
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
              if (!hasListeners) return;
              notifyListeners();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!kDebugMode) return;
              debugPrint(
                '[TeacherGroups] profile watch failed for $traineeId: '
                '$error\n$stackTrace',
              );
            },
          );
    }
  }

  void _cancelMemberProfileWatches() {
    for (final subscription in _profileSubs.values) {
      unawaited(subscription.cancel());
    }
    _profileSubs.clear();
    _profilePictureUrls.clear();
  }

  @override
  void dispose() {
    unawaited(_groupsSub?.cancel());
    unawaited(_pendingSub?.cancel());
    unawaited(_approvedSub?.cancel());
    _cancelMemberProfileWatches();
    super.dispose();
  }
}
