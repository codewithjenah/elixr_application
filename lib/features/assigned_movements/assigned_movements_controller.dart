import 'dart:async';

import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';

class AssignedMovementItem {
  const AssignedMovementItem({
    required this.assignment,
    required this.attempt,
    this.latestSubmission,
  });

  final GroupAssignment assignment;
  final AssignmentAttempt? attempt;
  final AssignmentAttempt? latestSubmission;
}

class AssignedMovementsController extends ChangeNotifier {
  AssignedMovementsController({
    required this.traineeId,
    required this.groupRepository,
    required this.assignmentRepository,
    this.submissionRepository,
  });

  final String traineeId;
  final GroupRepository groupRepository;
  final ClassroomAssignmentRepository assignmentRepository;
  final AssignmentSubmissionRepository? submissionRepository;

  bool loading = false;
  String? errorMessage;
  List<AssignedMovementItem> items = const [];

  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  StreamSubscription<List<AssignmentAttempt>>? _attemptsSub;
  List<GroupMembership> _memberships = const [];
  List<AssignmentAttempt> _attempts = const [];

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final membershipsFirst = Completer<void>();
      await _membershipsSub?.cancel();
      _membershipsSub = groupRepository
          .watchTraineeMemberships(traineeId: traineeId)
          .listen(
            (value) {
              _memberships = value;
              if (!membershipsFirst.isCompleted) membershipsFirst.complete();
              unawaited(_reloadAssignments());
            },
            onError: (Object error) {
              errorMessage = 'Could not load assigned movements.';
              if (!membershipsFirst.isCompleted) {
                membershipsFirst.completeError(error);
              }
              notifyListeners();
            },
          );
      await membershipsFirst.future;

      final attemptsFirst = Completer<void>();
      await _attemptsSub?.cancel();
      _attemptsSub = assignmentRepository
          .watchAttemptsForTrainee(traineeId: traineeId)
          .listen(
            (value) {
              _attempts = value;
              _rebuildItems();
              if (!attemptsFirst.isCompleted) attemptsFirst.complete();
              notifyListeners();
            },
            onError: (Object error) {
              errorMessage = 'Could not load assigned movements.';
              if (!attemptsFirst.isCompleted) {
                attemptsFirst.completeError(error);
              }
              notifyListeners();
            },
          );
      await attemptsFirst.future;
      await _reloadAssignments();
      await _reconcileExpired();
    } catch (_) {
      errorMessage = 'Could not load assigned movements.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> retry() => start();

  Future<void> _reloadAssignments() async {
    final approved = _memberships
        .where((membership) => membership.hasClassroomAuthorization)
        .toList();
    try {
      final loaded = <GroupAssignment>[];
      for (final membership in approved) {
        loaded.addAll(
          await assignmentRepository.fetchAssignmentsForGroup(
            groupId: membership.groupId,
          ),
        );
      }
      _assignments = loaded;
      _rebuildItems();
      errorMessage = null;
      notifyListeners();
    } catch (_) {
      errorMessage = 'Could not load assigned movements.';
      notifyListeners();
    }
  }

  List<GroupAssignment> _assignments = const [];

  void _rebuildItems() {
    final latestByAssignment = <String, AssignmentAttempt>{};
    final submissionsByAssignment = <String, AssignmentAttempt>{};
    for (final attempt in _attempts) {
      if (attempt.isAbandonedTeacherReviewDraft) continue;
      final existing = latestByAssignment[attempt.assignmentId];
      if (existing == null ||
          (attempt.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(
            existing.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          )) {
        latestByAssignment[attempt.assignmentId] = attempt;
      }
      if (attempt.isTeacherReviewSubmission) {
        final current = submissionsByAssignment[attempt.assignmentId];
        if (current == null ||
            (attempt.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .isAfter(
                  current.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                )) {
          submissionsByAssignment[attempt.assignmentId] = attempt;
        }
      }
    }
    final next = [
      for (final assignment in _assignments)
        AssignedMovementItem(
          assignment: assignment,
          attempt:
              submissionsByAssignment[assignment.id] ??
              latestByAssignment[assignment.id],
          latestSubmission: submissionsByAssignment[assignment.id],
        ),
    ];
    next.sort(_compareItems);
    items = next;
  }

  Future<void> _reconcileExpired() async {
    final repo = submissionRepository;
    if (repo == null) return;
    try {
      await repo.reconcileExpiredVideos(
        actorId: traineeId,
        attempts: _attempts,
      );
    } catch (_) {
      // Retention is best-effort and must not crash Assigned Movements.
    }
  }

  static int _compareItems(AssignedMovementItem a, AssignedMovementItem b) {
    final aActive = a.assignment.isActive;
    final bActive = b.assignment.isActive;
    if (aActive != bActive) return aActive ? -1 : 1;
    final aDue = a.assignment.dueAt;
    final bDue = b.assignment.dueAt;
    if (aDue != null && bDue != null) return aDue.compareTo(bDue);
    if (aDue != null) return -1;
    if (bDue != null) return 1;
    final aAt =
        a.assignment.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bAt =
        b.assignment.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bAt.compareTo(aAt);
  }

  @override
  void dispose() {
    _membershipsSub?.cancel();
    _attemptsSub?.cancel();
    super.dispose();
  }
}
