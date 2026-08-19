import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../students/teacher_student_models.dart';

class TeacherDashboardController extends ChangeNotifier {
  TeacherDashboardController({
    required this.repository,
    required this.teacherId,
  });

  final GroupRepository repository;
  final String teacherId;

  bool loading = true;
  String? errorMessage;
  Object? groupsStreamError;
  Object? membershipsStreamError;
  bool groupsHasFirstSuccess = false;
  bool membershipsHasFirstSuccess = false;
  Object? _startFailure;
  List<ElixrGroup> groups = const [];
  List<GroupMembership> memberships = const [];
  List<TeacherGroupSummary> groupSummaries = const [];
  List<GroupMembership> pendingQueue = const [];
  int activeGroupCount = 0;
  int approvedStudentCount = 0;
  int pendingRequestCount = 0;

  StreamSubscription<List<ElixrGroup>>? _groupsSub;
  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  Completer<void>? _groupsReady;
  Completer<void>? _membershipsReady;
  int _listenGeneration = 0;
  bool _disposed = false;

  Future<void> start() async {
    final generation = ++_listenGeneration;
    _completeReady(_groupsReady);
    _completeReady(_membershipsReady);
    loading = true;
    errorMessage = null;
    groupsStreamError = null;
    membershipsStreamError = null;
    groupsHasFirstSuccess = false;
    membershipsHasFirstSuccess = false;
    _startFailure = null;
    _publish();
    await _groupsSub?.cancel();
    await _membershipsSub?.cancel();
    if (_isStale(generation)) return;
    try {
      final groupsReady = Completer<void>();
      final membershipsReady = Completer<void>();
      _groupsReady = groupsReady;
      _membershipsReady = membershipsReady;
      _groupsSub = repository
          .watchTeacherGroups(teacherId: teacherId)
          .listen(
            (value) => _onGroupsEvent(generation, groupsReady, value),
            onError: (Object error, StackTrace stackTrace) =>
                _onGroupsError(generation, groupsReady, error, stackTrace),
          );
      _membershipsSub = repository
          .watchTeacherMemberships(teacherId: teacherId)
          .listen(
            (value) => _onMembershipsEvent(generation, membershipsReady, value),
            onError: (Object error, StackTrace stackTrace) =>
                _onMembershipsError(
                  generation,
                  membershipsReady,
                  error,
                  stackTrace,
                ),
          );
      await Future.wait([groupsReady.future, membershipsReady.future]);
    } catch (error, stackTrace) {
      if (_isStale(generation)) return;
      _logDashboardFailure('start failed', error, stackTrace);
      _startFailure = error;
    } finally {
      if (!_isStale(generation)) {
        loading = false;
        _publish();
      }
    }
  }

  Future<void> retry() => start();

  void _onGroupsEvent(
    int generation,
    Completer<void> ready,
    List<ElixrGroup> value,
  ) {
    if (_isStale(generation)) return;
    groups = value;
    groupsHasFirstSuccess = true;
    groupsStreamError = null;
    _completeReady(ready);
    _publish();
  }

  void _onMembershipsEvent(
    int generation,
    Completer<void> ready,
    List<GroupMembership> value,
  ) {
    if (_isStale(generation)) return;
    memberships = value;
    membershipsHasFirstSuccess = true;
    membershipsStreamError = null;
    _completeReady(ready);
    _publish();
  }

  void _onGroupsError(
    int generation,
    Completer<void> ready,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_isStale(generation)) return;
    _logDashboardFailure('groups stream failed', error, stackTrace);
    groupsStreamError = error;
    _completeReady(ready);
    _publish();
  }

  void _onMembershipsError(
    int generation,
    Completer<void> ready,
    Object error,
    StackTrace stackTrace,
  ) {
    if (_isStale(generation)) return;
    _logDashboardFailure('memberships stream failed', error, stackTrace);
    membershipsStreamError = error;
    _completeReady(ready);
    _publish();
  }

  void _publish() {
    _recomputeMetrics();
    errorMessage = _blockingErrorMessage();
    if (_disposed) return;
    notifyListeners();
  }

  String? _blockingErrorMessage() {
    if (groupsStreamError == null &&
        membershipsStreamError == null &&
        _startFailure == null) {
      return null;
    }
    return 'Could not load dashboard data.';
  }

  void _recomputeMetrics() {
    activeGroupCount = groups.where((g) => g.isActive).length;
    groupSummaries = buildGroupSummaries(
      groups: groups,
      memberships: memberships,
    );
    pendingQueue = memberships
        .where((m) => m.status == GroupMembershipStatus.pending)
        .toList();
    pendingRequestCount = pendingQueue.length;
    final approvedTrainees = memberships
        .where((m) => m.isApproved)
        .map((m) => m.traineeId)
        .toSet();
    approvedStudentCount = approvedTrainees.length;
  }

  void _completeReady(Completer<void>? ready) {
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  bool _isStale(int generation) => _disposed || generation != _listenGeneration;

  void _logDashboardFailure(String label, Object error, StackTrace stackTrace) {
    if (!kDebugMode) return;
    final buffer = StringBuffer(
      '[TeacherDashboard] $label: ${error.runtimeType}: $error',
    );
    if (error is FirebaseException) {
      buffer
        ..writeln()
        ..write('plugin=${error.plugin} code=${error.code}');
      final message = error.message;
      if (message != null && message.isNotEmpty) {
        buffer.write(' message=$message');
      }
    }
    debugPrint('$buffer\n$stackTrace');
  }

  @override
  void dispose() {
    _disposed = true;
    _listenGeneration++;
    _completeReady(_groupsReady);
    _completeReady(_membershipsReady);
    unawaited(_groupsSub?.cancel());
    unawaited(_membershipsSub?.cancel());
    super.dispose();
  }
}
