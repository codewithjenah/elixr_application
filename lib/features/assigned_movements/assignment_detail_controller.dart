import 'dart:async';

import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/assignment_attempt.dart';
import '../../data/models/group_assignment.dart';
import '../../data/repositories/assignment_submission_repository.dart';
import '../../data/repositories/classroom_assignment_repository.dart';

/// Read-only trainee view of one assignment and the trainee's own attempts.
class AssignmentDetailController extends ChangeNotifier {
  AssignmentDetailController({
    required this.assignmentId,
    required this.traineeId,
    required this.groupRepository,
    required this.assignmentRepository,
    this.submissionRepository,
  });

  final String assignmentId;
  final String traineeId;
  final GroupRepository groupRepository;
  final ClassroomAssignmentRepository assignmentRepository;
  final AssignmentSubmissionRepository? submissionRepository;

  GroupAssignment? assignment;
  List<AssignmentAttempt> attempts = const [];
  bool loading = false;
  String? errorMessage;
  bool authorized = false;

  StreamSubscription<List<GroupMembership>>? _membershipsSub;
  StreamSubscription<List<AssignmentAttempt>>? _attemptsSub;
  List<GroupMembership> _memberships = const [];
  List<AssignmentAttempt> _allAttempts = const [];
  SubmissionPlaybackFile? _playbackCache;
  bool _disposed = false;

  AssignmentAttempt? get latestAttempt =>
      attempts.isEmpty ? null : attempts.first;

  List<AssignmentAttempt> get earlierAttempts =>
      attempts.length <= 1 ? const [] : attempts.sublist(1);

  /// Newest clip the trainee actually turned in, so Your work can replay it
  /// even if a later draft exists.
  AssignmentAttempt? get latestClipSubmission {
    for (final attempt in attempts) {
      if (attempt.isReviewFacingSubmission) return attempt;
    }
    return null;
  }

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    authorized = false;
    assignment = null;
    attempts = const [];
    _notify();
    try {
      final id = assignmentId.trim();
      if (id.isEmpty) {
        errorMessage = 'This assignment link is not valid.';
        return;
      }
      final loaded = await assignmentRepository.getAssignment(assignmentId: id);
      if (_disposed) return;
      assignment = loaded;
      if (loaded == null) {
        errorMessage = 'This assignment is not available.';
        return;
      }

      final membershipsFirst = Completer<void>();
      await _membershipsSub?.cancel();
      _membershipsSub = groupRepository
          .watchTraineeMemberships(traineeId: traineeId)
          .listen(
            (value) {
              _memberships = value;
              _applyAuthorization();
              if (!membershipsFirst.isCompleted) membershipsFirst.complete();
              if (authorized) {
                unawaited(_ensureAttemptsWatch());
              } else {
                unawaited(_stopAttemptsWatch());
                attempts = const [];
              }
              _notify();
            },
            onError: (Object error) {
              errorMessage = 'Could not load this assignment.';
              if (!membershipsFirst.isCompleted) {
                membershipsFirst.completeError(error);
              }
              _notify();
            },
          );
      await membershipsFirst.future;
      if (_disposed) return;
      if (authorized) {
        await _ensureAttemptsWatch();
      }
    } catch (_) {
      errorMessage = 'Could not load this assignment.';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> retry() => start();

  Future<SubmissionPlaybackFile?> openLocalPlayback(
    AssignmentAttempt attempt,
  ) async {
    await releaseLocalPlayback();
    final playback = await submissionRepository?.openLocalPlayback(attempt);
    _playbackCache = playback;
    return playback;
  }

  Future<void> releaseLocalPlayback() async {
    final playback = _playbackCache;
    _playbackCache = null;
    final repo = submissionRepository;
    if (repo == null || playback == null) return;
    await repo.releaseLocalPlayback(playback);
  }

  void _applyAuthorization() {
    final current = assignment;
    if (current == null) {
      authorized = false;
      return;
    }
    authorized = _memberships.any(
      (membership) =>
          membership.groupId == current.groupId &&
          membership.teacherId == current.teacherId &&
          membership.traineeId == traineeId &&
          membership.hasClassroomAuthorization,
    );
  }

  Future<void> _ensureAttemptsWatch() async {
    if (_attemptsSub != null || _disposed) return;
    final attemptsFirst = Completer<void>();
    _attemptsSub = assignmentRepository
        .watchAttemptsForTrainee(traineeId: traineeId)
        .listen(
          (value) {
            _allAttempts = value;
            _rebuildAttempts();
            if (!attemptsFirst.isCompleted) attemptsFirst.complete();
            _notify();
          },
          onError: (Object error) {
            errorMessage = 'Could not load this assignment.';
            if (!attemptsFirst.isCompleted) {
              attemptsFirst.completeError(error);
            }
            _notify();
          },
        );
    await attemptsFirst.future;
  }

  Future<void> _stopAttemptsWatch() async {
    await _attemptsSub?.cancel();
    _attemptsSub = null;
    _allAttempts = const [];
  }

  void _rebuildAttempts() {
    final id = assignmentId.trim();
    final filtered = [
      for (final attempt in _allAttempts)
        if (attempt.assignmentId == id &&
            !attempt.isAbandonedTeacherReviewDraft)
          attempt,
    ];
    filtered.sort((a, b) {
      final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    attempts = filtered;
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _membershipsSub?.cancel();
    _attemptsSub?.cancel();
    unawaited(releaseLocalPlayback());
    super.dispose();
  }
}
