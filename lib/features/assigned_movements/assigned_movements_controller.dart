import 'dart:async';

import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/models/public_profile.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/public_profile_repository.dart';

class AssignedMovementItem {
  const AssignedMovementItem({
    required this.assignment,
    required this.attempt,
    this.latestSubmission,
    this.activityAttempts = const [],
    this.teacherProfilePictureUrl,
  });

  final GroupAssignment assignment;
  final AssignmentAttempt? attempt;
  final AssignmentAttempt? latestSubmission;

  /// All known attempts for this assignment. Teacher Activity eligibility
  /// needs the complete set because finite policies count recordings that
  /// started, including an interrupted reservation that was later abandoned.
  final List<AssignmentAttempt> activityAttempts;

  /// Best-effort public profile picture for [assignment.teacherId].
  ///
  /// Null until a public profile snapshot arrives, and whenever the teacher
  /// has no photo. Assignment loading must not wait on this field.
  final String? teacherProfilePictureUrl;
}

class AssignedMovementsController extends ChangeNotifier {
  AssignedMovementsController({
    required this.traineeId,
    required this.groupRepository,
    required this.assignmentRepository,
    this.submissionRepository,
    this.publicProfileRepository,
    this.filterGroupId,
  });

  final String traineeId;
  final GroupRepository groupRepository;
  final ClassroomAssignmentRepository assignmentRepository;
  final AssignmentSubmissionRepository? submissionRepository;
  final PublicProfileRepository? publicProfileRepository;

  /// When set, only assignments for this approved class are loaded.
  final String? filterGroupId;

  bool loading = false;
  String? errorMessage;
  List<AssignedMovementItem> items = const [];

  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  StreamSubscription<List<AssignmentAttempt>>? _attemptsSub;
  List<AssignmentAttempt> _attempts = const [];
  Set<String> _approvedGroupIds = const {};
  final Map<String, String> _teacherProfilePictureUrls = {};
  final Map<String, StreamSubscription<PublicProfile?>> _teacherProfileSubs =
      {};
  bool _disposed = false;

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      if (filterGroupId == null) {
        final membershipsFirst = Completer<void>();
        await _membershipsSub?.cancel();
        _membershipsSub = groupRepository
            .watchTraineeMemberships(traineeId: traineeId)
            .listen(
              (memberships) {
                _approvedGroupIds = {
                  for (final membership in memberships)
                    if (membership.isApproved) membership.groupId,
                };
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
      }

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
    try {
      final loaded = await assignmentRepository.fetchAssignmentsForTrainee(
        traineeId: traineeId,
        groupId: filterGroupId,
      );
      if (_disposed) return;
      _assignments = filterGroupId == null
          ? [
              for (final assignment in loaded)
                if (_approvedGroupIds.contains(assignment.groupId)) assignment,
            ]
          : loaded;
      _syncTeacherProfileWatches();
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
    final canonicalByAssignment = <String, AssignmentAttempt>{};
    final latestActivityByAssignment = <String, AssignmentAttempt>{};
    final activityAttemptsByAssignment = <String, List<AssignmentAttempt>>{};
    for (final attempt in _attempts) {
      if (attempt.activityAssessmentSnapshot != null) {
        (activityAttemptsByAssignment[attempt.assignmentId] ??= []).add(
          attempt,
        );
      }
      if (attempt.isAbandonedTeacherReviewDraft) continue;
      final existing = latestByAssignment[attempt.assignmentId];
      if (existing == null ||
          (attempt.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).isAfter(
            existing.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          )) {
        latestByAssignment[attempt.assignmentId] = attempt;
      }
      if (attempt.activityAssessmentSnapshot != null) {
        final current = latestActivityByAssignment[attempt.assignmentId];
        if (current == null ||
            (attempt.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                .isAfter(
                  current.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
                )) {
          latestActivityByAssignment[attempt.assignmentId] = attempt;
        }
      }
      if (attempt.isTeacherReviewSubmission) {
        if (attempt.isCanonicalTeacherReviewSubmission) {
          canonicalByAssignment[attempt.assignmentId] = attempt;
          continue;
        }
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
          attempt: assignment.activityAssessment != null
              ? latestActivityByAssignment[assignment.id]
              : canonicalByAssignment[assignment.id] ??
                    submissionsByAssignment[assignment.id] ??
                    latestByAssignment[assignment.id],
          latestSubmission: assignment.activityAssessment != null
              ? latestActivityByAssignment[assignment.id]
              : canonicalByAssignment[assignment.id] ??
                    submissionsByAssignment[assignment.id],
          activityAttempts: List.unmodifiable(
            activityAttemptsByAssignment[assignment.id] ?? const [],
          ),
          teacherProfilePictureUrl:
              _teacherProfilePictureUrls[assignment.teacherId.trim()],
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

  void _syncTeacherProfileWatches() {
    final repository = publicProfileRepository;
    final teacherIds = {
      for (final assignment in _assignments)
        if (assignment.teacherId.trim().isNotEmpty) assignment.teacherId.trim(),
    };
    if (repository == null) {
      _cancelTeacherProfileWatches();
      return;
    }

    final staleIds = _teacherProfileSubs.keys
        .where((id) => !teacherIds.contains(id))
        .toList(growable: false);
    for (final id in staleIds) {
      unawaited(_teacherProfileSubs.remove(id)?.cancel());
      _teacherProfilePictureUrls.remove(id);
    }

    for (final teacherId in teacherIds) {
      if (_teacherProfileSubs.containsKey(teacherId)) continue;
      _teacherProfileSubs[teacherId] = repository
          .watchProfileRoot(teacherId)
          .listen(
            (profile) {
              if (_disposed) return;
              final trimmed = profile?.profilePictureUrl?.trim();
              final next = (trimmed == null || trimmed.isEmpty)
                  ? null
                  : trimmed;
              final previous = _teacherProfilePictureUrls[teacherId];
              if (previous == next) return;
              if (next == null) {
                _teacherProfilePictureUrls.remove(teacherId);
              } else {
                _teacherProfilePictureUrls[teacherId] = next;
              }
              _rebuildItems();
              if (!_disposed) notifyListeners();
            },
            onError: (Object error, StackTrace stackTrace) {
              // Public identity is best-effort and must not fail classwork.
              if (!kDebugMode) return;
              debugPrint(
                '[AssignedMovements] teacher profile watch failed for '
                '$teacherId: $error\n$stackTrace',
              );
            },
          );
    }
  }

  void _cancelTeacherProfileWatches() {
    for (final subscription in _teacherProfileSubs.values) {
      unawaited(subscription.cancel());
    }
    _teacherProfileSubs.clear();
    _teacherProfilePictureUrls.clear();
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
    _disposed = true;
    _membershipsSub?.cancel();
    _attemptsSub?.cancel();
    _cancelTeacherProfileWatches();
    super.dispose();
  }
}
