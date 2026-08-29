import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../data/models/public_profile.dart';
import '../../../data/repositories/public_profile_repository.dart';
import 'teacher_student_models.dart';

class TeacherStudentsController extends ChangeNotifier {
  TeacherStudentsController({
    required this.repository,
    required this.teacherId,
    this.publicProfileRepository,
  });

  final GroupRepository repository;
  final String teacherId;
  final PublicProfileRepository? publicProfileRepository;

  bool loading = true;
  String? errorMessage;
  List<ElixrGroup> groups = const [];
  List<GroupMembership> memberships = const [];
  List<TeacherStudentEntry> allEntries = const [];
  List<TeacherStudentEntry> visibleEntries = const [];
  List<TeacherGroupRoster> visibleGroupRosters = const [];

  String searchQuery = '';
  String? selectedGroupId;
  TeacherStudentStatusFilter statusFilter = TeacherStudentStatusFilter.approved;

  StreamSubscription<List<ElixrGroup>>? _groupsSub;
  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  final Map<String, StreamSubscription<PublicProfile?>> _profileSubs = {};
  final Map<String, String> _profilePictureUrls = {};
  bool _disposed = false;

  String? profilePictureUrlFor(String traineeId) {
    final url = _profilePictureUrls[traineeId]?.trim();
    if (url == null || url.isEmpty) return null;
    return url;
  }

  Future<void> start() async {
    if (_disposed) return;
    loading = true;
    errorMessage = null;
    notifyListeners();
    await _groupsSub?.cancel();
    await _membershipsSub?.cancel();
    _cancelProfileWatches();
    try {
      final groupsReady = Completer<void>();
      final membershipsReady = Completer<void>();
      _groupsSub = repository
          .watchTeacherGroups(teacherId: teacherId)
          .listen(
            (value) {
              groups = value;
              _recomputeEntries();
              if (!groupsReady.isCompleted) groupsReady.complete();
              notifyListeners();
            },
            onError: (_) {
              errorMessage = 'Could not load students.';
              if (!groupsReady.isCompleted) groupsReady.complete();
              notifyListeners();
            },
          );
      _membershipsSub = repository
          .watchTeacherMemberships(teacherId: teacherId)
          .listen(
            (value) {
              memberships = value;
              _recomputeEntries();
              if (!membershipsReady.isCompleted) membershipsReady.complete();
              notifyListeners();
            },
            onError: (_) {
              errorMessage = 'Could not load students.';
              if (!membershipsReady.isCompleted) membershipsReady.complete();
              notifyListeners();
            },
          );
      await Future.wait([groupsReady.future, membershipsReady.future]);
    } catch (_) {
      errorMessage = 'Could not load students.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> retry() => start();

  void setSearchQuery(String value) {
    searchQuery = value;
    _applyFilters();
    notifyListeners();
  }

  void setGroupFilter(String? groupId) {
    selectedGroupId = groupId;
    _applyFilters();
    notifyListeners();
  }

  void setStatusFilter(TeacherStudentStatusFilter filter) {
    statusFilter = filter;
    _applyFilters();
    notifyListeners();
  }

  void _recomputeEntries() {
    allEntries = aggregateTeacherStudents(memberships);
    _applyFilters();
    _syncProfileWatches();
  }

  void _syncProfileWatches() {
    final repository = publicProfileRepository;
    if (repository == null) {
      _cancelProfileWatches();
      return;
    }

    final traineeIds = {
      for (final membership in memberships) membership.traineeId,
    };
    final staleIds = _profileSubs.keys
        .where((id) => !traineeIds.contains(id))
        .toList(growable: false);
    for (final id in staleIds) {
      unawaited(_profileSubs.remove(id)?.cancel());
      _profilePictureUrls.remove(id);
    }

    for (final traineeId in traineeIds) {
      if (_profileSubs.containsKey(traineeId)) continue;
      _profileSubs[traineeId] = repository
          .watchProfileRoot(traineeId)
          .listen(
            (profile) {
              if (_disposed) return;
              final trimmed = profile?.profilePictureUrl?.trim();
              final next = trimmed == null || trimmed.isEmpty ? null : trimmed;
              final previous = _profilePictureUrls[traineeId];
              if (previous == next) return;
              if (next == null) {
                _profilePictureUrls.remove(traineeId);
              } else {
                _profilePictureUrls[traineeId] = next;
              }
              if (hasListeners) notifyListeners();
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!kDebugMode) return;
              debugPrint(
                '[TeacherStudents] profile watch failed for $traineeId: '
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

  void _applyFilters() {
    visibleEntries = filterTeacherStudents(
      entries: allEntries,
      searchQuery: searchQuery,
      groupId: selectedGroupId,
      statusFilter: statusFilter,
    );
    visibleGroupRosters = buildTeacherGroupRosters(
      groups: groups,
      memberships: memberships,
      searchQuery: searchQuery,
      groupId: selectedGroupId,
      statusFilter: statusFilter,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_groupsSub?.cancel());
    unawaited(_membershipsSub?.cancel());
    _cancelProfileWatches();
    super.dispose();
  }
}
