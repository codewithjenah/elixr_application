import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/public_profile.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../data/repositories/public_profile_repository.dart';
import '../assigned_movements/assigned_movements_controller.dart';

enum TraineeClassDetailTab { classwork, announcements, people }

class TraineeClassDetailController extends ChangeNotifier {
  TraineeClassDetailController({
    required this.groupId,
    required this.traineeId,
    required this.groupRepository,
    required this.assignmentRepository,
    this.submissionRepository,
    this.publicProfileRepository,
  });

  final String groupId;
  final String traineeId;
  final GroupRepository groupRepository;
  final ClassroomAssignmentRepository assignmentRepository;
  final AssignmentSubmissionRepository? submissionRepository;
  final PublicProfileRepository? publicProfileRepository;

  bool loading = false;
  bool unauthorized = false;
  String? errorMessage;
  ElixrGroup? group;
  GroupMembership? membership;
  List<GroupMembership> classmates = const [];
  bool classmatesLoading = false;
  TraineeClassDetailTab tab = TraineeClassDetailTab.classwork;
  AssignedMovementsController? assignments;

  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  StreamSubscription<List<GroupMembership>>? _classmatesSub;
  final Map<String, StreamSubscription<PublicProfile?>> _profileSubs = {};
  final Map<String, String> _profilePictureUrls = {};
  bool _disposed = false;
  Future<void>? _assignmentsStart;

  String get className => group?.name ?? 'Class';

  String get teacherDisplayName => membership?.teacherDisplayName ?? 'Teacher';

  String? profilePictureUrlFor(String userId) {
    final url = _profilePictureUrls[userId]?.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  void setTab(TraineeClassDetailTab value) {
    if (tab == value) return;
    tab = value;
    notifyListeners();
  }

  Future<void> start() async {
    loading = true;
    unauthorized = false;
    errorMessage = null;
    notifyListeners();
    try {
      await _membershipsSub?.cancel();
      final first = Completer<void>();
      _membershipsSub = groupRepository
          .watchTraineeMemberships(traineeId: traineeId)
          .listen(
            (memberships) {
              _onMemberships(memberships);
              if (!first.isCompleted) first.complete();
            },
            onError: (Object error) {
              errorMessage = 'Could not load this class.';
              if (!first.isCompleted) first.completeError(error);
              _safeNotifyListeners();
            },
          );
      await first.future;
      await _refreshGroup();
      if (!unauthorized) {
        await _ensureAssignments();
      }
    } catch (_) {
      errorMessage = 'Could not load this class.';
    } finally {
      loading = false;
      _safeNotifyListeners();
    }
  }

  void _onMemberships(List<GroupMembership> memberships) {
    GroupMembership? match;
    for (final item in memberships) {
      if (item.groupId == groupId && item.hasClassroomAuthorization) {
        match = item;
        break;
      }
    }
    membership = match;
    if (match == null) {
      unauthorized = true;
      classmates = const [];
      classmatesLoading = false;
      unawaited(_classmatesSub?.cancel());
      _classmatesSub = null;
      _cancelProfileWatches();
      _safeNotifyListeners();
      return;
    }

    unauthorized = false;
    unawaited(_refreshGroup());
    _ensureClassmateWatch(match);
    unawaited(_ensureAssignments());
    _safeNotifyListeners();
  }

  Future<void> _refreshGroup() async {
    try {
      final loaded = await groupRepository.getGroup(groupId: groupId);
      if (_disposed) return;
      if (loaded != null) {
        group = loaded;
        _safeNotifyListeners();
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[TraineeClassDetail] getGroup failed: $error\n$stackTrace');
      }
    }
  }

  void _ensureClassmateWatch(GroupMembership approved) {
    if (_classmatesSub != null) return;
    classmatesLoading = true;
    _classmatesSub = groupRepository
        .watchApprovedGroupMembers(
          groupId: groupId,
          teacherId: approved.teacherId,
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
            classmates = sorted;
            classmatesLoading = false;
            _syncProfileWatches();
            _safeNotifyListeners();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (kDebugMode) {
              debugPrint(
                '[TraineeClassDetail] classmates stream failed: '
                '$error\n$stackTrace',
              );
            }
            classmates = const [];
            classmatesLoading = false;
            errorMessage = 'Could not load classmates.';
            _safeNotifyListeners();
          },
        );
  }

  Future<void> _ensureAssignments() {
    final inFlight = _assignmentsStart;
    if (inFlight != null) return inFlight;
    final future = _startAssignments();
    _assignmentsStart = future;
    return future;
  }

  Future<void> _startAssignments() async {
    if (_disposed) return;
    final controller = AssignedMovementsController(
      traineeId: traineeId,
      groupRepository: groupRepository,
      assignmentRepository: assignmentRepository,
      submissionRepository: submissionRepository,
      filterGroupId: groupId,
    );
    assignments = controller;
    controller.addListener(_onAssignmentsTick);
    await controller.start();
  }

  void _onAssignmentsTick() {
    _safeNotifyListeners();
  }

  void _syncProfileWatches() {
    final ids = {for (final member in classmates) member.traineeId};
    final repository = publicProfileRepository;
    if (repository == null) {
      _cancelProfileWatches();
      return;
    }

    final staleIds = _profileSubs.keys
        .where((id) => !ids.contains(id))
        .toList(growable: false);
    for (final id in staleIds) {
      unawaited(_profileSubs.remove(id)?.cancel());
      _profilePictureUrls.remove(id);
    }

    for (final id in ids) {
      if (_profileSubs.containsKey(id)) continue;
      _profileSubs[id] = repository
          .watchProfileRoot(id)
          .listen(
            (profile) {
              if (_disposed) return;
              final trimmed = profile?.profilePictureUrl?.trim();
              final next = (trimmed == null || trimmed.isEmpty)
                  ? null
                  : trimmed;
              final previous = _profilePictureUrls[id];
              if (previous == next) return;
              if (next == null) {
                _profilePictureUrls.remove(id);
              } else {
                _profilePictureUrls[id] = next;
              }
              _safeNotifyListeners();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!kDebugMode) return;
              debugPrint(
                '[TraineeClassDetail] profile watch failed for $id: '
                '$error\n$stackTrace',
              );
            },
          );
    }
  }

  void _cancelProfileWatches() {
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
    unawaited(_membershipsSub?.cancel());
    unawaited(_classmatesSub?.cancel());
    _cancelProfileWatches();
    assignments?.removeListener(_onAssignmentsTick);
    assignments?.dispose();
    assignments = null;
    super.dispose();
  }
}
