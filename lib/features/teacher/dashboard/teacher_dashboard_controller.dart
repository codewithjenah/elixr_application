import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
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
  List<ElixrGroup> groups = const [];
  List<GroupMembership> memberships = const [];
  List<TeacherGroupSummary> groupSummaries = const [];
  List<GroupMembership> pendingQueue = const [];
  int activeGroupCount = 0;
  int approvedStudentCount = 0;
  int pendingRequestCount = 0;

  StreamSubscription<List<ElixrGroup>>? _groupsSub;
  StreamSubscription<List<GroupMembership>>? _membershipsSub;

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    await _groupsSub?.cancel();
    await _membershipsSub?.cancel();
    try {
      final groupsReady = Completer<void>();
      final membershipsReady = Completer<void>();
      _groupsSub = repository
          .watchTeacherGroups(teacherId: teacherId)
          .listen(
            (value) {
              groups = value;
              _recompute();
              if (!groupsReady.isCompleted) groupsReady.complete();
              notifyListeners();
            },
            onError: (_) {
              errorMessage = 'Could not load dashboard data.';
              if (!groupsReady.isCompleted) groupsReady.complete();
              notifyListeners();
            },
          );
      _membershipsSub = repository
          .watchTeacherMemberships(teacherId: teacherId)
          .listen(
            (value) {
              memberships = value;
              _recompute();
              if (!membershipsReady.isCompleted) membershipsReady.complete();
              notifyListeners();
            },
            onError: (_) {
              errorMessage = 'Could not load dashboard data.';
              if (!membershipsReady.isCompleted) membershipsReady.complete();
              notifyListeners();
            },
          );
      await Future.wait([groupsReady.future, membershipsReady.future]);
    } catch (_) {
      errorMessage = 'Could not load dashboard data.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> retry() => start();

  void _recompute() {
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

  @override
  void dispose() {
    unawaited(_groupsSub?.cancel());
    unawaited(_membershipsSub?.cancel());
    super.dispose();
  }
}
