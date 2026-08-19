import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_exception.dart';
import 'package:elixr_core/models/group_invite.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

class TeacherGroupsController extends ChangeNotifier {
  TeacherGroupsController({
    required this.repository,
    required this.teacherId,
    required this.teacherDisplayName,
  });

  final GroupRepository repository;
  final String teacherId;
  final String teacherDisplayName;

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
    notifyListeners();
  }

  Future<void> createGroup(String name) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final group = await repository.createGroup(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        name: name,
      );
      actionMessage = 'Created ${group.name}.';
      await selectGroup(group);
    } on GroupException catch (error) {
      errorMessage = error.message ?? 'Could not create that group.';
    } catch (_) {
      errorMessage = 'Could not create that group.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> renameSelectedGroup(String name) async {
    final group = selectedGroup;
    if (busy || group == null) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await repository.renameGroup(
        groupId: group.id,
        teacherId: teacherId,
        name: name,
      );
      actionMessage = 'Renamed group.';
    } on GroupException catch (error) {
      errorMessage = error.message ?? 'Could not rename that group.';
    } catch (_) {
      errorMessage = 'Could not rename that group.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> archiveSelectedGroup() async {
    final group = selectedGroup;
    if (busy || group == null) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await repository.archiveGroup(groupId: group.id, teacherId: teacherId);
      actionMessage = 'Archived ${group.name}.';
      clearSelection();
    } on GroupException catch (error) {
      errorMessage = error.message ?? 'Could not archive that group.';
    } catch (_) {
      errorMessage = 'Could not archive that group.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> rotateInvite() async {
    final group = selectedGroup;
    if (busy || group == null) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      activeInvite = await repository.createOrRotateGroupInvite(
        groupId: group.id,
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
      );
      actionMessage = 'Invite code rotated.';
    } on GroupException catch (error) {
      errorMessage = error.message ?? 'Could not rotate the invite code.';
    } catch (_) {
      errorMessage = 'Could not rotate the invite code.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> approveMembership(GroupMembership membership) => _run(
    () => repository.approveMembership(
      membershipId: membership.id,
      teacherId: teacherId,
    ),
    'Could not approve that request.',
  );

  Future<void> rejectMembership(GroupMembership membership) => _run(
    () => repository.rejectMembership(
      membershipId: membership.id,
      teacherId: teacherId,
    ),
    'Could not reject that request.',
  );

  Future<void> removeMembership(GroupMembership membership) => _run(
    () => repository.removeMembership(
      membershipId: membership.id,
      teacherId: teacherId,
    ),
    'Could not remove that member.',
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
          status: GroupMembershipStatus.pending,
        )
        .listen(
          (value) {
            pendingMemberships = value;
            if (!pendingFirst.isCompleted) pendingFirst.complete();
            notifyListeners();
          },
          onError: (Object error) {
            errorMessage = 'Could not load pending requests.';
            if (!pendingFirst.isCompleted) pendingFirst.completeError(error);
            notifyListeners();
          },
        );
    _approvedSub = repository
        .watchGroupMemberships(
          groupId: groupId,
          status: GroupMembershipStatus.approved,
        )
        .listen(
          (value) {
            approvedMemberships = value;
            if (!approvedFirst.isCompleted) approvedFirst.complete();
            notifyListeners();
          },
          onError: (Object error) {
            errorMessage = 'Could not load members.';
            if (!approvedFirst.isCompleted) approvedFirst.completeError(error);
            notifyListeners();
          },
        );
    await Future.wait([pendingFirst.future, approvedFirst.future]);
    notifyListeners();
  }

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

  @override
  void dispose() {
    unawaited(_groupsSub?.cancel());
    unawaited(_pendingSub?.cancel());
    unawaited(_approvedSub?.cancel());
    super.dispose();
  }
}
