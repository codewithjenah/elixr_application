import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../data/models/leaderboard_entry.dart';
import '../../../data/models/leaderboard_period.dart';
import '../../leaderboard/leaderboard_list_controller.dart';
import 'teacher_leaderboard_models.dart';

typedef TeacherScopedLeaderboardFetcher =
    Future<Map<String, LeaderboardEntry>> Function(List<String> userIds);

class TeacherLeaderboardController extends ChangeNotifier {
  TeacherLeaderboardController({
    required this.groupRepository,
    required this.teacherId,
    required TeacherScopedLeaderboardFetcher fetchEntriesByUserIds,
    required LeaderboardPeriodPageFetcher fetchGlobalPage,
    LeaderboardListController? globalListController,
    DateTime Function()? nowUtc,
  }) : _fetchEntriesByUserIds = fetchEntriesByUserIds,
       _nowUtc = nowUtc ?? DateTime.now,
       globalList =
           globalListController ??
           LeaderboardListController(fetchPageForPeriod: fetchGlobalPage);

  final GroupRepository groupRepository;
  final String teacherId;
  final TeacherScopedLeaderboardFetcher _fetchEntriesByUserIds;
  final DateTime Function() _nowUtc;
  final LeaderboardListController globalList;

  TeacherLeaderboardScope scope = TeacherLeaderboardScope.global;
  LeaderboardPeriod period = LeaderboardPeriod.allTime;
  bool loading = true;
  bool scopedLoading = false;
  String? errorMessage;
  String? scopedErrorMessage;
  String? selectedGroupId;

  List<ElixrGroup> groups = const [];
  List<GroupMembership> memberships = const [];
  List<LeaderboardEntry> scopedEntries = const [];
  Map<String, LeaderboardEntry> _scopedFetched = const {};

  StreamSubscription<List<ElixrGroup>>? _groupsSub;
  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  int _scopedGeneration = 0;
  bool _disposed = false;
  bool _globalStarted = false;

  List<ElixrGroup> get activeGroups =>
      TeacherLeaderboardModels.activeGroups(groups);

  bool get isGlobal => scope == TeacherLeaderboardScope.global;

  bool get showGroupPicker => scope == TeacherLeaderboardScope.group;

  bool get hasNoActiveGroups =>
      scope == TeacherLeaderboardScope.group && activeGroups.isEmpty;

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    scopedErrorMessage = null;
    _globalStarted = false;
    _emit();
    await _groupsSub?.cancel();
    await _membershipsSub?.cancel();
    try {
      final groupsReady = Completer<void>();
      final membershipsReady = Completer<void>();
      _groupsSub = groupRepository
          .watchTeacherGroups(teacherId: teacherId)
          .listen(
            (value) {
              groups = value;
              _onMembershipContextChanged();
              if (!groupsReady.isCompleted) groupsReady.complete();
              _emit();
            },
            onError: (_) {
              errorMessage = 'Could not load the Teacher leaderboard.';
              if (!groupsReady.isCompleted) groupsReady.complete();
              _emit();
            },
          );
      _membershipsSub = groupRepository
          .watchTeacherMemberships(teacherId: teacherId)
          .listen(
            (value) {
              memberships = value;
              _onMembershipContextChanged();
              if (!membershipsReady.isCompleted) membershipsReady.complete();
              _emit();
            },
            onError: (_) {
              errorMessage = 'Could not load the Teacher leaderboard.';
              if (!membershipsReady.isCompleted) membershipsReady.complete();
              _emit();
            },
          );
      await Future.wait([groupsReady.future, membershipsReady.future]);
    } catch (_) {
      errorMessage = 'Could not load the Teacher leaderboard.';
    } finally {
      loading = false;
      _emit();
    }
    if (_disposed || errorMessage != null) return;
    // Global Firestore paging has its own loading/error surface. Do not keep
    // start() blocked on it — My Students / Group can still render.
    unawaited(_ensureGlobalLoaded());
    unawaited(_reloadScopedEntries());
  }

  Future<void> retry() => start();

  Future<void> refresh() async {
    if (isGlobal) {
      errorMessage = null;
      await globalList.refresh();
    } else {
      scopedErrorMessage = null;
    }
    await _reloadScopedEntries();
    _emit();
  }

  Future<void> setScope(TeacherLeaderboardScope value) async {
    if (_disposed || scope == value) return;
    scope = value;
    _recoverSelectedGroup();
    if (isGlobal) {
      await _ensureGlobalLoaded();
    } else {
      await _reloadScopedEntries();
    }
    _emit();
  }

  Future<void> setPeriod(LeaderboardPeriod value) async {
    if (_disposed || period == value) return;
    period = value;
    final globalUpdate = globalList.setPeriod(value);
    if (!isGlobal) {
      scopedEntries = TeacherLeaderboardModels.rankScoped(
        trainees: _currentTrainees(),
        fetched: _scopedFetched,
        period: period,
        nowUtc: _nowUtc().toUtc(),
      );
    }
    await globalUpdate;
    _emit();
  }

  Future<void> setSelectedGroupId(String? groupId) async {
    if (_disposed || selectedGroupId == groupId) return;
    selectedGroupId = groupId;
    _recoverSelectedGroup();
    if (scope == TeacherLeaderboardScope.group) {
      await _reloadScopedEntries();
    }
    _emit();
  }

  bool canOpenStudentDetail(String traineeId) {
    return TeacherLeaderboardModels.hasClassroomAuthorization(
      traineeId: traineeId,
      memberships: memberships,
    );
  }

  String? drillDownGroupId(String traineeId) {
    return TeacherLeaderboardModels.drillDownGroupId(
      traineeId: traineeId,
      memberships: memberships,
      preferredGroupId: selectedGroupId,
    );
  }

  Map<String, String> groupNamesById() {
    return {for (final group in groups) group.id: group.name};
  }

  void _onMembershipContextChanged() {
    _recoverSelectedGroup();
    if (!isGlobal) {
      unawaited(_reloadScopedEntries());
    }
  }

  void _recoverSelectedGroup() {
    selectedGroupId = TeacherLeaderboardModels.recoverSelectedGroupId(
      selectedGroupId: selectedGroupId,
      activeGroups: activeGroups,
    );
  }

  Future<void> _ensureGlobalLoaded() async {
    if (_globalStarted) return;
    _globalStarted = true;
    await globalList.loadInitial();
  }

  Map<String, String> _currentTrainees() {
    final approved = TeacherLeaderboardModels.approvedMemberships(
      memberships,
      groupId: scope == TeacherLeaderboardScope.group ? selectedGroupId : null,
    );
    return TeacherLeaderboardModels.uniqueApprovedTrainees(approved);
  }

  Future<void> _reloadScopedEntries() async {
    if (isGlobal || _disposed) return;
    final generation = ++_scopedGeneration;
    final trainees = _currentTrainees();
    scopedLoading = true;
    _emit();
    try {
      final fetched = trainees.isEmpty
          ? const <String, LeaderboardEntry>{}
          : await _fetchEntriesByUserIds(trainees.keys.toList());
      if (_disposed || generation != _scopedGeneration) return;
      _scopedFetched = fetched;
      scopedErrorMessage = null;
      scopedEntries = TeacherLeaderboardModels.rankScoped(
        trainees: trainees,
        fetched: fetched,
        period: period,
        nowUtc: _nowUtc().toUtc(),
      );
    } catch (_) {
      if (_disposed || generation != _scopedGeneration) return;
      scopedErrorMessage = 'Could not load the Teacher leaderboard.';
    } finally {
      if (!_disposed && generation == _scopedGeneration) {
        scopedLoading = false;
        _emit();
      }
    }
  }

  void _emit() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _scopedGeneration++;
    unawaited(_groupsSub?.cancel());
    unawaited(_membershipsSub?.cancel());
    globalList.dispose();
    super.dispose();
  }
}
