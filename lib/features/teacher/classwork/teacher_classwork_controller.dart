import 'dart:async';

import 'package:elixr_core/models/chat_user.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/chat_repository.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/assignment_review_state.dart';
import '../../../data/models/assignment_submission_limits.dart';
import '../../../data/models/classroom_exceptions.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/models/teacher_activity_assessment.dart';
import '../../../data/models/assignment_attempt_policy.dart';
import '../../../data/models/training_prop.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';

const _attemptStatusLoadError =
    'Some classwork status could not be loaded. Try again.';

class TeacherAssignmentRosterCounts {
  const TeacherAssignmentRosterCounts({
    required this.turnedIn,
    required this.awaitingCheck,
    required this.checked,
    required this.notTurnedIn,
  });

  const TeacherAssignmentRosterCounts.empty()
    : turnedIn = 0,
      awaitingCheck = 0,
      checked = 0,
      notTurnedIn = 0;

  final int turnedIn;
  final int awaitingCheck;
  final int checked;
  final int notTurnedIn;
}

class TeacherAssignmentRosterEntry {
  const TeacherAssignmentRosterEntry({
    required this.membership,
    required this.attempt,
    required this.reviewState,
    required this.deadlineState,
  });

  final GroupMembership membership;
  final AssignmentAttempt? attempt;
  final AssignmentReviewState reviewState;
  final AssignmentDeadlineState deadlineState;
}

/// Classroom-scoped source of truth for assignment roster and review state.
///
/// Assignment attempts are watched per assignment. This keeps a classroom
/// workspace from subscribing to every attempt owned by the Teacher while
/// preserving live counts for every assignment in the opened class.
class TeacherClassworkController extends ChangeNotifier {
  TeacherClassworkController({
    required this.teacherId,
    required this.teacherDisplayName,
    required this.groupId,
    required this.groupRepository,
    required this.assignmentRepository,
    this.submissionRepository,
    this.chatRepository,
    this.fixedTraineeId,
    this.initialAssignmentId,
    this.initialTraineeId,
    this.approvedMembershipsProvider,
    this.approvedMembershipsListenable,
    this.approvedMembershipsReady,
    DateTime Function()? now,
  }) : selectedAssignmentId = initialAssignmentId,
       selectedTraineeId = fixedTraineeId ?? initialTraineeId,
       _now = now ?? DateTime.now,
       assert(
         (approvedMembershipsProvider == null) ==
             (approvedMembershipsListenable == null),
         'Provide both approved-membership inputs or neither.',
       );

  final String teacherId;
  final String teacherDisplayName;
  final String groupId;
  final GroupRepository groupRepository;
  final ClassroomAssignmentRepository assignmentRepository;
  final AssignmentSubmissionRepository? submissionRepository;
  final ChatRepository? chatRepository;
  final String? fixedTraineeId;
  final String? initialAssignmentId;
  final String? initialTraineeId;
  final List<GroupMembership> Function()? approvedMembershipsProvider;
  final Listenable? approvedMembershipsListenable;
  final bool Function()? approvedMembershipsReady;
  final DateTime Function() _now;

  ElixrGroup? group;
  List<GroupAssignment> assignments = const [];
  List<GroupMembership> approvedMemberships = const [];
  String? selectedAssignmentId;
  String? selectedTraineeId;
  bool loading = false;
  bool busy = false;
  bool unauthorized = false;
  String? errorMessage;

  final Map<String, List<AssignmentAttempt>> _attemptsByAssignment = {};
  final Set<String> _attemptLoadErrors = {};
  final Map<String, StreamSubscription<List<AssignmentAttempt>>>
  _attemptSubscriptions = {};
  StreamSubscription<List<GroupAssignment>>? _assignmentsSubscription;
  StreamSubscription<List<GroupMembership>>? _membershipsSubscription;
  SubmissionPlaybackFile? _playbackCache;
  int _playbackGeneration = 0;
  bool _disposed = false;

  GroupAssignment? get selectedAssignment {
    final id = selectedAssignmentId;
    if (id == null) return null;
    return assignmentById(id);
  }

  AssignmentAttempt? get selectedAttempt {
    final assignmentId = selectedAssignmentId;
    final traineeId = selectedTraineeId;
    if (assignmentId == null || traineeId == null) return null;
    return latestVisibleAttemptFor(
      assignmentId: assignmentId,
      traineeId: traineeId,
    );
  }

  bool get fixedStudentAuthorized {
    final traineeId = fixedTraineeId;
    return traineeId == null ||
        approvedMemberships.any((member) => member.traineeId == traineeId);
  }

  Future<void> start() async {
    loading = true;
    unauthorized = false;
    errorMessage = null;
    notifyListeners();
    try {
      final candidate = await groupRepository.getGroup(groupId: groupId);
      if (candidate == null || candidate.teacherId != teacherId) {
        unauthorized = true;
        errorMessage = 'This class is not available.';
        return;
      }
      group = candidate;
      if (fixedTraineeId != null) {
        // A class-scoped student route must prove approved membership before
        // subscribing to assignments or submission attempts for the class.
        await _listenToMembers();
        if (!fixedStudentAuthorized) {
          unauthorized = true;
          errorMessage =
              'This student is not an approved member of this class.';
          return;
        }
        await _listenToAssignments();
      } else {
        await Future.wait([_listenToAssignments(), _listenToMembers()]);
      }
    } catch (error, stackTrace) {
      _logFailure('start', error, stackTrace);
      errorMessage = 'Classwork could not be loaded.';
    } finally {
      if (!_disposed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _listenToAssignments() async {
    await _assignmentsSubscription?.cancel();
    final first = Completer<void>();
    _assignmentsSubscription = assignmentRepository
        .watchTeacherAssignments(teacherId: teacherId)
        .listen(
          (items) {
            if (_disposed) return;
            assignments = [
              for (final assignment in items)
                if (assignment.groupId == groupId &&
                    assignment.teacherId == teacherId &&
                    (fixedTraineeId == null ||
                        assignment.isAvailableToTrainee(fixedTraineeId!)))
                  assignment,
            ]..sort(_compareAssignments);
            _syncAttemptSubscriptions();
            _reconcileSelection();
            if (!first.isCompleted) first.complete();
            notifyListeners();
          },
          onError: (Object error, StackTrace stackTrace) {
            _logFailure('assignments stream', error, stackTrace);
            if (!first.isCompleted) first.completeError(error, stackTrace);
          },
        );
    await first.future;
  }

  Future<void> _listenToMembers() async {
    final providedMembers = approvedMembershipsProvider;
    final providedListenable = approvedMembershipsListenable;
    if (providedMembers != null && providedListenable != null) {
      providedListenable.removeListener(_onProvidedMembershipsChanged);
      providedListenable.addListener(_onProvidedMembershipsChanged);
      _applyApprovedMemberships(providedMembers());
      return;
    }
    await _membershipsSubscription?.cancel();
    final first = Completer<void>();
    _membershipsSubscription = groupRepository
        .watchApprovedGroupMembers(groupId: groupId, teacherId: teacherId)
        .listen(
          (items) {
            if (_disposed) return;
            _applyApprovedMemberships(items);
            if (!first.isCompleted) first.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            _logFailure('memberships stream', error, stackTrace);
            if (!first.isCompleted) first.completeError(error, stackTrace);
          },
        );
    await first.future;
  }

  void _onProvidedMembershipsChanged() {
    final provider = approvedMembershipsProvider;
    if (_disposed || provider == null) return;
    _applyApprovedMemberships(provider());
  }

  void _applyApprovedMemberships(List<GroupMembership> items) {
    if (_disposed) return;
    final membershipIsReady = approvedMembershipsReady?.call() ?? true;
    approvedMemberships =
        [
          for (final member in items)
            if (member.groupId == groupId &&
                member.teacherId == teacherId &&
                member.hasClassroomAuthorization)
              member,
        ]..sort(
          (a, b) => a.traineeDisplayName.toLowerCase().compareTo(
            b.traineeDisplayName.toLowerCase(),
          ),
        );
    if (fixedTraineeId != null &&
        membershipIsReady &&
        !fixedStudentAuthorized) {
      unauthorized = true;
      selectedTraineeId = fixedTraineeId;
      errorMessage = 'This student is not an approved member of this class.';
    } else if (fixedTraineeId != null && membershipIsReady) {
      unauthorized = false;
      if (errorMessage ==
          'This student is not an approved member of this class.') {
        errorMessage = null;
      }
    }
    if (selectedTraineeId != null &&
        fixedTraineeId == null &&
        membershipIsReady &&
        !approvedMemberships.any(
          (member) => member.traineeId == selectedTraineeId,
        )) {
      unawaited(selectTrainee(null));
    }
    notifyListeners();
  }

  void _syncAttemptSubscriptions() {
    final assignmentIds = assignments.map((item) => item.id).toSet();
    final staleIds = _attemptSubscriptions.keys
        .where((id) => !assignmentIds.contains(id))
        .toList(growable: false);
    for (final id in staleIds) {
      unawaited(_attemptSubscriptions.remove(id)?.cancel());
      _attemptsByAssignment.remove(id);
      _attemptLoadErrors.remove(id);
    }
    for (final assignmentId in assignmentIds) {
      if (_attemptSubscriptions.containsKey(assignmentId)) continue;
      _attemptSubscriptions[assignmentId] = assignmentRepository
          .watchAttemptsForAssignment(
            teacherId: teacherId,
            assignmentId: assignmentId,
          )
          .listen(
            (items) {
              if (_disposed) return;
              _attemptLoadErrors.remove(assignmentId);
              if (_attemptLoadErrors.isEmpty &&
                  errorMessage == _attemptStatusLoadError) {
                errorMessage = null;
              }
              _attemptsByAssignment[assignmentId] = [
                for (final attempt in items)
                  if (attempt.teacherId == teacherId &&
                      attempt.groupId == groupId &&
                      attempt.assignmentId == assignmentId)
                    attempt,
              ];
              unawaited(
                _reconcileExpired(_attemptsByAssignment[assignmentId]!),
              );
              notifyListeners();
            },
            onError: (Object error, StackTrace stackTrace) {
              _logFailure('attempts stream', error, stackTrace);
              if (_disposed) return;
              _attemptLoadErrors.add(assignmentId);
              _attemptsByAssignment.remove(assignmentId);
              errorMessage = _attemptStatusLoadError;
              notifyListeners();
            },
          );
    }
  }

  void _reconcileSelection() {
    final selectedId = selectedAssignmentId;
    if (selectedId == null) return;
    if (assignments.any((assignment) => assignment.id == selectedId)) return;
    selectedAssignmentId = null;
    if (fixedTraineeId == null) selectedTraineeId = null;
    unawaited(releaseLocalPlayback());
  }

  GroupAssignment? assignmentById(String assignmentId) {
    for (final assignment in assignments) {
      if (assignment.id == assignmentId) return assignment;
    }
    return null;
  }

  List<AssignmentAttempt> attemptsFor(String assignmentId) {
    return _attemptsByAssignment[assignmentId] ?? const [];
  }

  /// Whether the first attempt snapshot for [assignmentId] has arrived.
  /// An empty snapshot is authoritative; an absent entry is still loading.
  bool hasAttemptSnapshot(String assignmentId) =>
      _attemptsByAssignment.containsKey(assignmentId);

  bool hasAttemptLoadError(String assignmentId) {
    return _attemptLoadErrors.contains(assignmentId);
  }

  /// One reference instant for a single gradebook derivation pass.
  DateTime get gradebookReferenceNow => _now().toUtc();

  AssignmentAttempt? latestVisibleAttemptFor({
    required String assignmentId,
    required String traineeId,
  }) {
    return AssignmentAttemptSemantics.latestVisible(
      attempts: attemptsFor(assignmentId),
      assignmentId: assignmentId,
      traineeId: traineeId,
    );
  }

  TeacherAssignmentRosterCounts rosterCountsFor(String assignmentId) {
    var turnedIn = 0;
    var awaitingCheck = 0;
    var checked = 0;
    var notTurnedIn = 0;
    for (final entry in rosterEntriesFor(assignmentId)) {
      switch (entry.reviewState) {
        case AssignmentReviewState.toReview:
          turnedIn++;
          awaitingCheck++;
        case AssignmentReviewState.checked:
          turnedIn++;
          checked++;
        case AssignmentReviewState.missing:
          notTurnedIn++;
      }
    }
    return TeacherAssignmentRosterCounts(
      turnedIn: turnedIn,
      awaitingCheck: awaitingCheck,
      checked: checked,
      notTurnedIn: notTurnedIn,
    );
  }

  List<TeacherAssignmentRosterEntry> rosterEntriesFor(String assignmentId) {
    final assignment = assignmentById(assignmentId);
    if (assignment == null) return const [];
    final now = _now().toUtc();
    return [
      for (final member in approvedMemberships)
        if (assignment.isAvailableToTrainee(member.traineeId))
          _rosterEntry(assignment, member, now),
    ];
  }

  TeacherAssignmentRosterEntry _rosterEntry(
    GroupAssignment assignment,
    GroupMembership member,
    DateTime now,
  ) {
    final attempt = latestVisibleAttemptFor(
      assignmentId: assignment.id,
      traineeId: member.traineeId,
    );
    return TeacherAssignmentRosterEntry(
      membership: member,
      attempt: attempt,
      reviewState: AssignmentReviewSemantics.reviewState(attempt),
      deadlineState: AssignmentReviewSemantics.deadlineStateFor(
        assignment: assignment,
        attempt: attempt,
        now: now,
      ),
    );
  }

  List<AssignmentAttempt> pendingReviewAttemptsFor(String assignmentId) {
    final assignment = assignmentById(assignmentId);
    if (assignment == null) return const [];
    final now = _now().toUtc();
    final pending = <AssignmentAttempt>[
      for (final entry in rosterEntriesFor(assignmentId))
        if (AssignmentReviewSemantics.isActionablePending(
          entry.attempt,
          now: now,
        ))
          entry.attempt!,
    ];
    pending.sort((a, b) {
      final byTime = a.submittedAt!.compareTo(b.submittedAt!);
      if (byTime != 0) return byTime;
      final byTrainee = a.traineeId.compareTo(b.traineeId);
      return byTrainee != 0 ? byTrainee : a.id.compareTo(b.id);
    });
    return pending;
  }

  bool hasAnotherPendingReview({
    required String assignmentId,
    required String currentAttemptId,
  }) => pendingReviewAttemptsFor(
    assignmentId,
  ).any((attempt) => attempt.id != currentAttemptId);

  String traineeName(String traineeId) {
    for (final member in approvedMemberships) {
      if (member.traineeId == traineeId &&
          member.traineeDisplayName.trim().isNotEmpty) {
        return member.traineeDisplayName;
      }
    }
    return 'Student';
  }

  String audienceLabel(GroupAssignment assignment) {
    switch (assignment.audience.type) {
      case AssignmentAudienceType.entireClass:
        return 'Entire class';
      case AssignmentAudienceType.selectedStudents:
        final count = assignment.audience.targetTraineeIds.length;
        return count == 0
            ? 'Selected students (unavailable)'
            : count == 1
            ? '1 student'
            : '$count students';
      case AssignmentAudienceType.individualStudent:
        final targets = assignment.audience.targetTraineeIds;
        return targets.length == 1
            ? 'Individual: ${traineeName(targets.single)}'
            : 'Individual student (unavailable)';
    }
  }

  Future<void> selectAssignment(String? assignmentId) async {
    if (selectedAssignmentId == assignmentId) return;
    await releaseLocalPlayback();
    selectedAssignmentId = assignmentId;
    selectedTraineeId = fixedTraineeId;
    notifyListeners();
  }

  Future<void> selectTrainee(String? traineeId) async {
    if (fixedTraineeId != null && traineeId != fixedTraineeId) return;
    if (selectedTraineeId == traineeId) return;
    await releaseLocalPlayback();
    selectedTraineeId = traineeId;
    notifyListeners();
  }

  Future<SubmissionPlaybackFile?> openLocalPlayback(
    AssignmentAttempt attempt,
  ) async {
    final repository = submissionRepository;
    if (repository == null) return null;
    final generation = ++_playbackGeneration;
    await _releasePlaybackCache();
    final playback = await repository.openLocalPlayback(attempt);
    if (_disposed || generation != _playbackGeneration) {
      await repository.releaseLocalPlayback(playback);
      return null;
    }
    _playbackCache = playback;
    return playback;
  }

  Future<void> releaseLocalPlayback() async {
    _playbackGeneration++;
    await _releasePlaybackCache();
  }

  Future<void> _releasePlaybackCache() async {
    final playback = _playbackCache;
    _playbackCache = null;
    if (playback != null) {
      await submissionRepository?.releaseLocalPlayback(playback);
    }
  }

  Future<bool> saveReview({
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
    required int gradeScore,
    String? feedback,
  }) async {
    final saved = await _runWriteWithResult(() async {
      final updated = await assignmentRepository.saveTeacherReview(
        teacherId: teacherId,
        attempt: attempt,
        assignment: assignment,
        gradeScore: gradeScore,
        feedback: feedback,
        reviewedAt: DateTime.now().toUtc(),
      );
      _replaceAttempt(updated);
    });
    if (!saved) return false;
    final checked = latestVisibleAttemptFor(
      assignmentId: assignment.id,
      traineeId: attempt.traineeId,
    );
    if (checked?.isChecked == true &&
        checked!.resultSentForCurrentRevision == false) {
      await sendReviewResult(attempt: checked, assignment: assignment);
    }
    return true;
  }

  Future<bool> saveReviewAndNext({
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
    required int gradeScore,
    String? feedback,
  }) async {
    final saved = await saveReview(
      attempt: attempt,
      assignment: assignment,
      gradeScore: gradeScore,
      feedback: feedback,
    );
    if (!saved) return false;
    final pending = pendingReviewAttemptsFor(assignment.id);
    if (pending.isNotEmpty) {
      await selectTrainee(pending.first.traineeId);
    }
    return true;
  }

  /// Saves a v2 Teacher Activity rubric review.  The immutable configuration
  /// snapshot on [attempt] is deliberately used by the repository, so an
  /// assignment edit can never change how an already-recorded clip is graded.
  Future<bool> saveTeacherActivityRubricReview({
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
    required Map<String, int> criterionScores,
    String? feedback,
  }) async {
    final saved = await _runWriteWithResult(() async {
      final updated = await assignmentRepository
          .saveTeacherActivityRubricReview(
            teacherId: teacherId,
            attempt: attempt,
            criterionScores: criterionScores,
            feedback: feedback,
          );
      _replaceAttempt(updated);
    });
    if (!saved) return false;
    final checked = latestVisibleAttemptFor(
      assignmentId: assignment.id,
      traineeId: attempt.traineeId,
    );
    if (checked?.isChecked == true &&
        checked!.resultSentForCurrentRevision == false) {
      await sendReviewResult(attempt: checked, assignment: assignment);
    }
    return true;
  }

  Future<bool> saveTeacherActivityRubricReviewAndNext({
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
    required Map<String, int> criterionScores,
    String? feedback,
  }) async {
    final saved = await saveTeacherActivityRubricReview(
      attempt: attempt,
      assignment: assignment,
      criterionScores: criterionScores,
      feedback: feedback,
    );
    if (!saved) return false;
    final pending = pendingReviewAttemptsFor(assignment.id);
    if (pending.isNotEmpty) {
      await selectTrainee(pending.first.traineeId);
    }
    return true;
  }

  Future<void> reviewLegacy({
    required AssignmentAttempt attempt,
    required AssignmentReviewVerdict verdict,
    String? feedback,
  }) {
    return _runWrite(() async {
      final reviewedAt = DateTime.now().toUtc();
      final updated = await assignmentRepository.reviewTeacherSubmission(
        teacherId: teacherId,
        attempt: attempt,
        verdict: verdict,
        feedback: feedback,
        reviewedAt: reviewedAt,
        videoExpiresAt: reviewedVideoExpiresAt(reviewedAt),
      );
      _replaceAttempt(updated);
    });
  }

  Future<void> sendReviewResult({
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
  }) async {
    final chat = chatRepository;
    if (chat == null) {
      errorMessage = 'Messaging is unavailable. The saved review is kept.';
      notifyListeners();
      return;
    }
    if (!attempt.isChecked || attempt.resultSentForCurrentRevision) return;
    final earnedScore = attempt.gradeScore;
    final maxScore = attempt.gradeMaxScore;
    final reviewRevision = attempt.reviewRevision;
    if (earnedScore == null || maxScore == null || reviewRevision == null) {
      return;
    }
    await _runWrite(() async {
      final message = await chat.sendAssignmentResult(
        sender: ChatUser(
          id: teacherId,
          displayName: teacherDisplayName,
          role: 'Teacher',
        ),
        recipient: ChatUser(
          id: attempt.traineeId,
          displayName: traineeName(attempt.traineeId),
          role: 'Trainee',
        ),
        movementTitle: assignment.displayTitle,
        earnedScore: earnedScore,
        maxScore: maxScore,
        feedback: attempt.reviewFeedback,
        submissionId: attempt.id,
        reviewRevision: reviewRevision,
      );
      final updated = await assignmentRepository.markTeacherReviewResultSent(
        teacherId: teacherId,
        attempt: attempt,
        messageId: message.id,
        sentAt: DateTime.now().toUtc(),
      );
      _replaceAttempt(updated);
    });
  }

  Future<bool> updateAssignmentSettings(
    GroupAssignment assignment, {
    required DateTime? dueAt,
    int? maxScore,
    String? topic,
  }) {
    return _runWriteWithResult(
      () async => _replaceAssignment(
        await assignmentRepository.updateAssignmentSettings(
          teacherId: teacherId,
          assignmentId: assignment.id,
          dueAt: dueAt,
          maxScore: maxScore,
          topic: topic ?? assignment.topic,
        ),
      ),
    );
  }

  Future<void> updateMaximumScore({
    required String assignmentId,
    required int maxScore,
  }) {
    return _runWrite(
      () => assignmentRepository.updateTeacherAssignmentMaxScore(
        teacherId: teacherId,
        assignmentId: assignmentId,
        maxScore: maxScore,
      ),
    );
  }

  Future<bool> updateTeacherActivityAssignment({
    required GroupAssignment assignment,
    required String displayTitle,
    required String instructions,
    String? safetyGuidance,
    String? topic,
    DateTime? dueAt,
    required AssignmentAudience audience,
    required TeacherActivityAssessmentConfig activityAssessment,
    required AssignmentAttemptPolicy attemptPolicy,
    required TrainingProp requiredProp,
  }) {
    return _runWriteWithResult(
      () async => _replaceAssignment(
        await assignmentRepository.updateTeacherActivityAssignment(
          teacherId: teacherId,
          assignmentId: assignment.id,
          expectedConfigurationRevision: assignment.configurationRevision,
          displayTitle: displayTitle,
          instructions: instructions,
          safetyGuidance: safetyGuidance,
          topic: topic,
          dueAt: dueAt,
          audience: audience,
          activityAssessment: activityAssessment,
          attemptPolicy: attemptPolicy,
          requiredProp: requiredProp,
        ),
      ),
    );
  }

  Future<void> archiveAssignment(GroupAssignment assignment) {
    return _runWrite(
      () => assignmentRepository.archiveAssignment(
        teacherId: teacherId,
        assignmentId: assignment.id,
      ),
    );
  }

  Future<void> permanentlyDeleteAssignment(GroupAssignment assignment) {
    return _runWrite(
      () => assignmentRepository.permanentlyDeleteAssignment(
        teacherId: teacherId,
        assignmentId: assignment.id,
        confirmation: 'DELETE ASSIGNMENT',
      ),
    );
  }

  void _replaceAttempt(AssignmentAttempt updated) {
    final attempts = [...attemptsFor(updated.assignmentId)];
    final index = attempts.indexWhere((attempt) => attempt.id == updated.id);
    if (index == -1) {
      attempts.add(updated);
    } else {
      attempts[index] = updated;
    }
    _attemptsByAssignment[updated.assignmentId] = attempts;
  }

  void _replaceAssignment(GroupAssignment updated) {
    final index = assignments.indexWhere((item) => item.id == updated.id);
    if (index == -1) {
      assignments = [...assignments, updated]..sort(_compareAssignments);
    } else {
      final next = [...assignments];
      next[index] = updated;
      assignments = next..sort(_compareAssignments);
    }
  }

  Future<void> _reconcileExpired(List<AssignmentAttempt> attempts) async {
    try {
      await submissionRepository?.reconcileExpiredVideos(
        actorId: teacherId,
        attempts: attempts,
      );
    } catch (error, stackTrace) {
      _logFailure('video retention reconciliation', error, stackTrace);
    }
  }

  Future<void> _runWrite(Future<void> Function() action) async {
    await _runWriteWithResult(action);
  }

  Future<bool> _runWriteWithResult(Future<void> Function() action) async {
    if (busy || unauthorized) {
      errorMessage = busy
          ? 'Another classwork action is still saving. Wait and try again.'
          : 'You no longer have permission to change this classwork.';
      if (!_disposed) notifyListeners();
      return false;
    }
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
      errorMessage = null;
      return true;
    } on ClassroomException catch (error, stackTrace) {
      _logFailure('classwork write', error, stackTrace);
      errorMessage = error.message ?? _messageForClassroomError(error.code);
      return false;
    } catch (error, stackTrace) {
      _logFailure('classwork write', error, stackTrace);
      errorMessage = 'That classwork action could not be saved.';
      return false;
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  static String _messageForClassroomError(
    ClassroomError error,
  ) => switch (error) {
    ClassroomError.conflict =>
      'This assignment changed since you opened it. Reopen the editor and try again.',
    ClassroomError.attemptLimitConflict =>
      'The attempt limit is lower than attempts already used. Choose a higher limit or Unlimited.',
    ClassroomError.invalidRecipient =>
      'One or more selected students are no longer approved in this class. Refresh the roster and try again.',
    ClassroomError.notFound => 'This assignment no longer exists.',
    ClassroomError.forbidden =>
      'You no longer have permission to change this assignment.',
    ClassroomError.malformed => 'Check the assignment settings and try again.',
    _ => 'That classwork action could not be saved.',
  };

  int _compareAssignments(GroupAssignment a, GroupAssignment b) {
    if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
    final aAt = a.updatedAt ?? a.createdAt;
    final bAt = b.updatedAt ?? b.createdAt;
    if (aAt == null && bAt != null) return 1;
    if (aAt != null && bAt == null) return -1;
    if (aAt == null || bAt == null) {
      return a.displayTitle.compareTo(b.displayTitle);
    }
    return bAt.compareTo(aAt);
  }

  void _logFailure(String operation, Object error, StackTrace stackTrace) {
    if (kDebugMode) {
      debugPrint('[TeacherClasswork] $operation failed: $error\n$stackTrace');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _playbackGeneration++;
    approvedMembershipsListenable?.removeListener(
      _onProvidedMembershipsChanged,
    );
    unawaited(_assignmentsSubscription?.cancel());
    unawaited(_membershipsSubscription?.cancel());
    for (final subscription in _attemptSubscriptions.values) {
      unawaited(subscription.cancel());
    }
    _attemptSubscriptions.clear();
    unawaited(_releasePlaybackCache());
    super.dispose();
  }
}
