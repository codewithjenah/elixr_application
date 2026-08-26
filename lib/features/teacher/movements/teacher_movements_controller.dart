import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/movements.dart';
import '../../../data/models/assessment_mode.dart';
import '../../../data/models/assignment_attempt.dart';
import '../../../data/models/assignment_submission_limits.dart';
import '../../../data/models/classroom_exceptions.dart';
import '../../../data/models/group_assignment.dart';
import '../../../data/models/movement.dart';
import '../../../data/models/teacher_movement.dart';
import '../../../data/models/training_prop.dart';
import '../../../data/repositories/assignment_submission_repository.dart';
import '../../../data/repositories/classroom_assignment_repository.dart';
import '../../../data/repositories/teacher_movement_repository.dart';

enum TeacherMovementsTab { official, mine, assignments, reviews }

class TeacherMovementsController extends ChangeNotifier {
  TeacherMovementsController({
    required this.teacherId,
    required this.teacherDisplayName,
    required this.groupRepository,
    required this.movementRepository,
    required this.assignmentRepository,
    this.submissionRepository,
  });

  final String teacherId;
  final String teacherDisplayName;
  final GroupRepository groupRepository;
  final TeacherMovementRepository movementRepository;
  final ClassroomAssignmentRepository assignmentRepository;
  final AssignmentSubmissionRepository? submissionRepository;

  TeacherMovementsTab tab = TeacherMovementsTab.official;
  List<ElixrGroup> groups = const [];
  List<TeacherMovement> myMovements = const [];
  Map<String, TeacherMovementRevision> currentRevisions = const {};
  List<GroupAssignment> assignments = const [];
  List<AssignmentAttempt> attempts = const [];
  List<GroupMembership> memberships = const [];
  AssignmentAttempt? selectedReview;
  String? reviewFeedbackDraft;
  bool loading = false;
  bool busy = false;
  String? errorMessage;
  SubmissionPlaybackFile? _playbackCache;

  StreamSubscription<List<ElixrGroup>>? _groupsSub;
  StreamSubscription<List<TeacherMovement>>? _movementsSub;
  StreamSubscription<List<GroupAssignment>>? _assignmentsSub;
  StreamSubscription<List<AssignmentAttempt>>? _attemptsSub;
  StreamSubscription<List<GroupMembership>>? _membershipsSub;

  List<Movement> get officialCatalog =>
      movementCatalog.where((movement) => movement.enabled).toList();

  List<ElixrGroup> get activeGroups =>
      groups.where((group) => group.isActive).toList();

  List<TeacherMovement> get activeMyMovements =>
      myMovements.where(canManageMovement).toList();

  TeacherMovementRevision? revisionFor(TeacherMovement movement) {
    final cached = currentRevisions[movement.id];
    if (cached != null && cached.id == movement.currentRevisionId) {
      return cached;
    }
    return null;
  }

  bool isRetiredTemplate(TeacherMovement movement) {
    return revisionFor(movement)?.isRetiredTemplate == true;
  }

  bool canManageMovement(TeacherMovement movement) {
    return movement.isActive &&
        revisionFor(movement)?.assessmentMode == AssessmentMode.teacherReviewed;
  }

  String movementModeLabel(TeacherMovement movement) {
    final revision = revisionFor(movement);
    if (revision?.isRetiredTemplate == true) {
      return 'Retired template scoring · Historical read-only';
    }
    if (!movement.isActive) {
      return 'Archived · Historical assignments stay pinned';
    }
    if (revision?.assessmentMode == AssessmentMode.teacherReviewed) {
      return 'Teacher reviewed · No automatic ELIXR score';
    }
    return 'Teacher-created movement';
  }

  List<AssignmentAttempt> attemptsFor(String assignmentId) {
    return attempts
        .where((attempt) => attempt.assignmentId == assignmentId)
        .toList();
  }

  List<AssignmentAttempt> get reviewQueue {
    final queued = attempts
        .where((attempt) => attempt.isReviewFacingSubmission)
        .toList();
    queued.sort((a, b) {
      final aAt =
          a.submittedAt ??
          a.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bAt =
          b.submittedAt ??
          b.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    return queued;
  }

  String traineeName(String traineeId) {
    for (final membership in memberships) {
      if (membership.traineeId == traineeId &&
          membership.traineeDisplayName.trim().isNotEmpty) {
        return membership.traineeDisplayName;
      }
    }
    return 'Trainee';
  }

  GroupAssignment? assignmentFor(AssignmentAttempt attempt) {
    for (final assignment in assignments) {
      if (assignment.id == attempt.assignmentId) return assignment;
    }
    return null;
  }

  String groupName(String groupId) {
    for (final group in groups) {
      if (group.id == groupId) return group.name;
    }
    for (final assignment in assignments) {
      if (assignment.groupId == groupId) return assignment.groupName;
    }
    return 'Classroom';
  }

  Future<void> start() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await Future.wait([
        _listenOnce(
          () => _groupsSub,
          (sub) => _groupsSub = sub,
          groupRepository.watchTeacherGroups(teacherId: teacherId),
          (value) => groups = value,
        ),
        _listenOnce(
          () => _movementsSub,
          (sub) => _movementsSub = sub,
          movementRepository.watchTeacherMovements(teacherId: teacherId),
          (value) {
            myMovements = value;
            unawaited(_syncCurrentRevisions(value));
          },
        ),
        _listenOnce(
          () => _assignmentsSub,
          (sub) => _assignmentsSub = sub,
          assignmentRepository.watchTeacherAssignments(teacherId: teacherId),
          (value) => assignments = value,
        ),
        _listenOnce(
          () => _attemptsSub,
          (sub) => _attemptsSub = sub,
          assignmentRepository.watchAttemptsForTeacher(teacherId: teacherId),
          (value) => attempts = value,
        ),
        _listenOnce(
          () => _membershipsSub,
          (sub) => _membershipsSub = sub,
          groupRepository.watchTeacherMemberships(teacherId: teacherId),
          (value) => memberships = value,
        ),
      ]);
      await _syncCurrentRevisions(myMovements);
      await _reconcileExpired();
    } catch (_) {
      errorMessage = 'Could not load movements and assignments.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectReview(AssignmentAttempt? attempt) async {
    await releasePlaybackCache();
    selectedReview = attempt;
    reviewFeedbackDraft = attempt?.reviewFeedback;
    notifyListeners();
  }

  Future<SubmissionPlaybackFile?> openLocalPlayback(
    AssignmentAttempt attempt,
  ) async {
    await releasePlaybackCache();
    final playback = await submissionRepository?.openLocalPlayback(attempt);
    _playbackCache = playback;
    return playback;
  }

  Future<void> releasePlaybackCache() async {
    final playback = _playbackCache;
    _playbackCache = null;
    final repo = submissionRepository;
    if (repo == null || playback == null) return;
    await repo.releaseLocalPlayback(playback);
  }

  Future<void> reviewSelected({
    required AssignmentReviewVerdict verdict,
    String? feedback,
  }) {
    final attempt = selectedReview;
    if (attempt == null) {
      return Future.value();
    }
    return _runWrite(() async {
      final reviewedAt = DateTime.now().toUtc();
      selectedReview = await assignmentRepository.reviewTeacherSubmission(
        teacherId: teacherId,
        attempt: attempt,
        verdict: verdict,
        feedback: feedback,
        reviewedAt: reviewedAt,
        videoExpiresAt: reviewedVideoExpiresAt(reviewedAt),
      );
    });
  }

  Future<void> _reconcileExpired() async {
    final repo = submissionRepository;
    if (repo == null) return;
    try {
      await repo.reconcileExpiredVideos(actorId: teacherId, attempts: attempts);
    } catch (_) {}
  }

  Future<void> retry() => start();

  void setTab(TeacherMovementsTab value) {
    if (tab == value) return;
    tab = value;
    notifyListeners();
  }

  Future<void> createMovement({
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) {
    return _runWrite(
      () => movementRepository.createMovement(
        teacherId: teacherId,
        title: title,
        instructions: instructions,
        requiredProp: requiredProp,
        safetyGuidance: safetyGuidance,
      ),
    );
  }

  Future<void> editMovement({
    required TeacherMovement movement,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) {
    return _runWrite(
      () => movementRepository.editMovement(
        teacherId: teacherId,
        movementId: movement.id,
        title: title,
        instructions: instructions,
        requiredProp: requiredProp,
        safetyGuidance: safetyGuidance,
      ),
    );
  }

  Future<void> archiveMovement(TeacherMovement movement) {
    return _runWrite(
      () => movementRepository.archiveMovement(
        teacherId: teacherId,
        movementId: movement.id,
      ),
    );
  }

  Future<void> assignOfficial({
    required Movement movement,
    required ElixrGroup group,
    DateTime? dueAt,
  }) {
    return _runWrite(
      () => assignmentRepository.createOfficialAssignment(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        group: group,
        officialMovementName: movement.name,
        dueAt: dueAt,
        displayInstructions: movement.description,
      ),
    );
  }

  Future<void> assignTeacherCreated({
    required TeacherMovement movement,
    required ElixrGroup group,
    DateTime? dueAt,
  }) {
    return _runWrite(() async {
      final revision = await movementRepository.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      );
      if (revision == null) {
        throw const ClassroomException(ClassroomError.notFound);
      }
      await assignmentRepository.createTeacherCreatedAssignment(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        group: group,
        movement: movement,
        revision: revision,
        dueAt: dueAt,
      );
    });
  }

  Future<void> archiveAssignment(GroupAssignment assignment) {
    return _runWrite(
      () => assignmentRepository.archiveAssignment(
        teacherId: teacherId,
        assignmentId: assignment.id,
      ),
    );
  }

  Future<void> _syncCurrentRevisions(List<TeacherMovement> items) async {
    final next = <String, TeacherMovementRevision>{};
    for (final movement in items) {
      final cached = currentRevisions[movement.id];
      if (cached != null && cached.id == movement.currentRevisionId) {
        next[movement.id] = cached;
        continue;
      }
      final revision = await movementRepository.getRevision(
        movementId: movement.id,
        revisionId: movement.currentRevisionId,
      );
      if (revision != null) {
        next[movement.id] = revision;
      }
    }
    currentRevisions = next;
    notifyListeners();
  }

  Future<void> _runWrite(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
    } on ClassroomException catch (error) {
      errorMessage =
          error.message ?? 'That classroom action could not be completed.';
    } catch (_) {
      errorMessage = 'That classroom action could not be completed.';
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _listenOnce<T>(
    StreamSubscription<T>? Function() read,
    void Function(StreamSubscription<T>) write,
    Stream<T> stream,
    void Function(T value) onData,
  ) async {
    await read()?.cancel();
    final first = Completer<void>();
    write(
      stream.listen(
        (value) {
          onData(value);
          if (!first.isCompleted) first.complete();
          notifyListeners();
        },
        onError: (Object error) {
          if (!first.isCompleted) first.completeError(error);
        },
      ),
    );
    await first.future;
  }

  @override
  void dispose() {
    _groupsSub?.cancel();
    _movementsSub?.cancel();
    _assignmentsSub?.cancel();
    _attemptsSub?.cancel();
    _membershipsSub?.cancel();
    unawaited(releasePlaybackCache());
    super.dispose();
  }
}
