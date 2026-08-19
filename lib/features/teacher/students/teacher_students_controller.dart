import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import 'teacher_student_models.dart';

class TeacherStudentsController extends ChangeNotifier {
  TeacherStudentsController({
    required this.repository,
    required this.teacherId,
  });

  final GroupRepository repository;
  final String teacherId;

  bool loading = true;
  String? errorMessage;
  List<ElixrGroup> groups = const [];
  List<GroupMembership> memberships = const [];
  List<TeacherStudentEntry> allEntries = const [];
  List<TeacherStudentEntry> visibleEntries = const [];

  String searchQuery = '';
  String? selectedGroupId;
  TeacherStudentStatusFilter statusFilter = TeacherStudentStatusFilter.approved;

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
  }

  void _applyFilters() {
    visibleEntries = filterTeacherStudents(
      entries: allEntries,
      searchQuery: searchQuery,
      groupId: selectedGroupId,
      statusFilter: statusFilter,
    );
  }

  @override
  void dispose() {
    unawaited(_groupsSub?.cancel());
    unawaited(_membershipsSub?.cancel());
    super.dispose();
  }
}
