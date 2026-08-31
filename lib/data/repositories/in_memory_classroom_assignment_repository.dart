import 'dart:async';

import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/repositories/group_repository.dart';

import '../models/assessment_mode.dart';
import '../models/assignment_attempt.dart';
import '../models/assignment_attempt_ids.dart';
import '../models/assignment_submission_limits.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/teacher_movement.dart';
import '../models/teacher_activity_assessment.dart';
import 'classroom_assignment_repository.dart';

class InMemoryClassroomAssignmentRepository
    implements ClassroomAssignmentRepository {
  InMemoryClassroomAssignmentRepository({
    DateTime Function()? now,
    String Function()? generateId,
    GroupRepository? groupRepository,
  }) : _now = now,
       _generateId = generateId ?? _defaultId,
       _groupRepository = groupRepository;

  final DateTime Function()? _now;
  final String Function() _generateId;
  final GroupRepository? _groupRepository;

  final Map<String, GroupAssignment> assignments = {};
  final Map<String, AssignmentAttempt> attempts = {};
  final Set<String> consumedTeacherActivityAttemptIds = {};
  bool failNextSubmitTransition = false;

  final _teacherControllers =
      <String, StreamController<List<GroupAssignment>>>{};
  final _assignmentAttemptControllers =
      <String, StreamController<List<AssignmentAttempt>>>{};
  final _traineeAttemptControllers =
      <String, StreamController<List<AssignmentAttempt>>>{};
  final _teacherAttemptControllers =
      <String, StreamController<List<AssignmentAttempt>>>{};

  static String _defaultId() => 'asg-${DateTime.now().microsecondsSinceEpoch}';

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  void dispose() {
    for (final controller in _teacherControllers.values) {
      controller.close();
    }
    for (final controller in _assignmentAttemptControllers.values) {
      controller.close();
    }
    for (final controller in _traineeAttemptControllers.values) {
      controller.close();
    }
    for (final controller in _teacherAttemptControllers.values) {
      controller.close();
    }
  }

  @override
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    String? displayInstructions,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) => createOfficialAssignmentWithTopic(
    teacherId: teacherId,
    teacherDisplayName: teacherDisplayName,
    group: group,
    officialMovementName: officialMovementName,
    dueAt: dueAt,
    displayInstructions: displayInstructions,
    audience: audience,
  );

  @override
  Future<GroupAssignment> createOfficialAssignmentWithTopic({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    String? displayInstructions,
    String? topic,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    if (!audience.isEntireClass) {
      await _ensureAudienceTargetsAreApprovedMembers(
        teacherId: teacherId,
        group: group,
        audience: audience,
      );
    }
    final id = _generateId();
    final created = now;
    final payload = officialAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      officialMovementName: officialMovementName,
      displayInstructions: displayInstructions ?? '',
      dueAt: dueAt,
      topic: topic,
      audience: audience,
      createdAt: created,
      updatedAt: created,
    );
    final parsed = GroupAssignment.tryFromMap(payload, id: id);
    if (parsed == null) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    final assignment = parsed.copyWith(
      // In-memory storage models the private recipient projection by keeping
      // the authorized IDs alongside the canonical value. Firestore uses the
      // nested projection instead and hydrates it at read time.
      audience: parsed.audience.withRecipientIds(audience.targetTraineeIds),
    );
    assignments[id] = assignment;
    _emitTeacher(teacherId);
    return assignment;
  }

  @override
  Future<GroupAssignment> createTeacherCreatedAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    int maxScore = 100,
    TeacherActivityAssessmentConfig? activityAssessment,
    String? displayTitle,
    String? displayInstructions,
    String? displaySafetyGuidance,
    DateTime? dueAt,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) => createTeacherCreatedAssignmentWithTopic(
    teacherId: teacherId,
    teacherDisplayName: teacherDisplayName,
    group: group,
    movement: movement,
    revision: revision,
    maxScore: maxScore,
    activityAssessment: activityAssessment,
    displayTitle: displayTitle,
    displayInstructions: displayInstructions,
    displaySafetyGuidance: displaySafetyGuidance,
    dueAt: dueAt,
    audience: audience,
  );

  @override
  Future<GroupAssignment> createTeacherCreatedAssignmentWithTopic({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    int maxScore = 100,
    TeacherActivityAssessmentConfig? activityAssessment,
    String? displayTitle,
    String? displayInstructions,
    String? displaySafetyGuidance,
    DateTime? dueAt,
    String? topic,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    if (!audience.isEntireClass) {
      await _ensureAudienceTargetsAreApprovedMembers(
        teacherId: teacherId,
        group: group,
        audience: audience,
      );
    }
    final id = _generateId();
    final created = now;
    final payload = teacherCreatedAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      maxScore: maxScore,
      activityAssessment: activityAssessment,
      displayTitle: displayTitle,
      displayInstructions: displayInstructions,
      displaySafetyGuidance: displaySafetyGuidance,
      dueAt: dueAt,
      topic: topic,
      audience: audience,
      createdAt: created,
      updatedAt: created,
    );
    final parsed = GroupAssignment.tryFromMap(payload, id: id);
    if (parsed == null) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    final assignment = parsed.copyWith(
      audience: parsed.audience.withRecipientIds(audience.targetTraineeIds),
    );
    assignments[id] = assignment;
    _emitTeacher(teacherId);
    return assignment;
  }

  @override
  Future<void> archiveAssignment({
    required String teacherId,
    required String assignmentId,
  }) async {
    final existing = assignments[assignmentId];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (existing.isRetiredTemplate) {
      throw const ClassroomException(
        ClassroomError.identityMismatch,
        'Retired template-scored assignments are read-only.',
      );
    }
    assignments[assignmentId] = GroupAssignment(
      id: existing.id,
      teacherId: existing.teacherId,
      groupId: existing.groupId,
      movementId: existing.movementId,
      revisionId: existing.revisionId,
      origin: existing.origin,
      assessmentMode: existing.assessmentMode,
      status: GroupAssignmentStatus.archived,
      displayTitle: existing.displayTitle,
      teacherDisplayName: existing.teacherDisplayName,
      groupName: existing.groupName,
      topic: existing.topic,
      officialMovementName: existing.officialMovementName,
      displayInstructions: existing.displayInstructions,
      displaySafetyGuidance: existing.displaySafetyGuidance,
      allowedProp: existing.allowedProp,
      assessmentSpec: existing.assessmentSpec,
      maxScore: existing.maxScore,
      gradingLocked: existing.gradingLocked,
      gradingLockedAt: existing.gradingLockedAt,
      dueAt: existing.dueAt,
      createdAt: existing.createdAt,
      updatedAt: now,
      audience: existing.audience,
    );
    _emitTeacher(teacherId);
  }

  @override
  Future<GroupAssignment> updateAssignmentSettings({
    required String teacherId,
    required String assignmentId,
    DateTime? dueAt,
    int? maxScore,
    String? topic,
  }) async {
    if (maxScore != null) ensureTeacherAssignmentMaxScore(maxScore);
    final existing = assignments[assignmentId];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (!existing.isActive || existing.isRetiredTemplate) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (maxScore != null) {
      if (!existing.isTeacherCreated || existing.gradingLocked) {
        throw const ClassroomException(ClassroomError.invalidState);
      }
      if (attempts.values.any(
        (attempt) => attempt.assignmentId == assignmentId && attempt.isChecked,
      )) {
        throw const ClassroomException(ClassroomError.invalidState);
      }
    }
    final updated = existing.copyWith(
      dueAt: dueAt,
      clearDueAt: dueAt == null,
      maxScore: maxScore,
      topic: topic,
      clearTopic: topic == null || topic.trim().isEmpty,
      gradingLocked: maxScore == null ? null : false,
      clearGradingLockedAt: maxScore != null,
    );
    assignments[assignmentId] = updated;
    _emitTeacher(teacherId);
    return updated;
  }

  @override
  Future<GroupAssignment> updateTeacherActivityAssignment({
    required String teacherId,
    required String assignmentId,
    required int expectedConfigurationRevision,
    required String displayTitle,
    required String instructions,
    String? safetyGuidance,
    String? topic,
    DateTime? dueAt,
    required AssignmentAudience audience,
    required TeacherActivityAssessmentConfig activityAssessment,
  }) async {
    final existing = assignments[assignmentId];
    if (existing == null ||
        existing.teacherId != teacherId ||
        existing.configurationRevision != expectedConfigurationRevision ||
        !activityAssessment.isValid) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final consumedByTrainee = <String, int>{};
    for (final attempt in attempts.values) {
      if (attempt.assignmentId == assignmentId &&
          consumedTeacherActivityAttemptIds.contains(attempt.id)) {
        consumedByTrainee.update(
          attempt.traineeId,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final maximum = activityAssessment.attemptPolicy.maximumAttempts;
    if (maximum != null &&
        consumedByTrainee.values.any((count) => count > maximum)) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final updated = GroupAssignment(
      id: existing.id,
      teacherId: existing.teacherId,
      groupId: existing.groupId,
      movementId: existing.movementId,
      revisionId: existing.revisionId,
      origin: existing.origin,
      assessmentMode: existing.assessmentMode,
      status: existing.status,
      displayTitle: displayTitle.trim(),
      teacherDisplayName: existing.teacherDisplayName,
      groupName: existing.groupName,
      topic: topic?.trim().isEmpty == true ? null : topic?.trim(),
      displayInstructions: instructions.trim(),
      displaySafetyGuidance: safetyGuidance?.trim().isEmpty == true
          ? null
          : safetyGuidance?.trim(),
      allowedProp: existing.allowedProp,
      maxScore: activityAssessment.rubric.maximumScore,
      gradingLocked: existing.gradingLocked,
      gradingLockedAt: existing.gradingLockedAt,
      dueAt: dueAt,
      createdAt: existing.createdAt,
      updatedAt: now,
      audience: audience,
      configurationRevision: existing.configurationRevision + 1,
      activityAssessment: activityAssessment,
    );
    assignments[assignmentId] = updated;
    _emitTeacher(teacherId);
    return updated;
  }

  @override
  Future<GroupAssignment?> getAssignment({required String assignmentId}) async {
    return assignments[assignmentId];
  }

  @override
  Future<bool> hasTeacherAssignmentForMovement({
    required String teacherId,
    required String movementId,
  }) async {
    return assignments.values.any(
      (assignment) =>
          assignment.teacherId == teacherId &&
          assignment.movementId == movementId,
    );
  }

  @override
  Stream<List<GroupAssignment>> watchTeacherAssignments({
    required String teacherId,
  }) {
    return _watch(
      _teacherControllers,
      teacherId,
      () => _emitTeacher(teacherId),
    );
  }

  @override
  Future<List<GroupAssignment>> fetchAssignmentsForGroup({
    required String groupId,
  }) async {
    final items = assignments.values
        .where((assignment) => assignment.groupId == groupId)
        .toList();
    _sortAssignments(items);
    return items;
  }

  @override
  Future<List<GroupAssignment>> fetchAssignmentsForTrainee({
    required String traineeId,
    String? groupId,
  }) async {
    var items = assignments.values
        .where(
          (assignment) =>
              assignment.isAvailableToTrainee(traineeId) &&
              (groupId == null || assignment.groupId == groupId),
        )
        .toList();
    final groupRepository = _groupRepository;
    if (groupRepository != null && items.isNotEmpty) {
      final approvedClasses = <(String, String)>{};
      final classes = <(String, String)>{
        for (final assignment in items)
          (assignment.groupId, assignment.teacherId),
      };
      for (final classroom in classes) {
        final memberships = await groupRepository
            .watchGroupMemberships(
              groupId: classroom.$1,
              teacherId: classroom.$2,
              status: GroupMembershipStatus.approved,
            )
            .first;
        if (memberships.any(
          (membership) =>
              membership.traineeId == traineeId &&
              membership.groupId == classroom.$1 &&
              membership.teacherId == classroom.$2 &&
              membership.hasClassroomAuthorization,
        )) {
          approvedClasses.add(classroom);
        }
      }
      items = [
        for (final assignment in items)
          if (approvedClasses.contains((
            assignment.groupId,
            assignment.teacherId,
          )))
            assignment,
      ];
    }
    _sortAssignments(items);
    return items;
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForAssignment({
    required String teacherId,
    required String assignmentId,
  }) {
    return _watch(
      _assignmentAttemptControllers,
      '$teacherId|$assignmentId',
      () => _emitAssignmentAttempts(teacherId, assignmentId),
    );
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  }) {
    return _watch(
      _traineeAttemptControllers,
      traineeId,
      () => _emitTraineeAttempts(traineeId),
    );
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTeacher({
    required String teacherId,
  }) {
    return _watch(
      _teacherAttemptControllers,
      teacherId,
      () => _emitTeacherAttempts(teacherId),
    );
  }

  @override
  Future<AssignmentAttempt?> getAttempt({required String attemptId}) async {
    return attempts[attemptId];
  }

  @override
  Future<AssignmentAttempt> reserveTeacherActivityAttempt({
    required String traineeId,
    required GroupAssignment assignment,
    required String requestId,
  }) async {
    final config = assignment.activityAssessment;
    if (config == null ||
        !isTeacherAssignmentSubmissionOpen(assignment: assignment, now: now)) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final active = attempts.values.where(
      (attempt) =>
          attempt.assignmentId == assignment.id &&
          attempt.traineeId == traineeId &&
          attempt.activityAssessmentSnapshot != null &&
          attempt.status == AssignmentAttemptStatus.inProgress,
    );
    if (active.isNotEmpty) return active.first;
    final consumed = attempts.values
        .where(
          (attempt) =>
              attempt.assignmentId == assignment.id &&
              attempt.traineeId == traineeId &&
              consumedTeacherActivityAttemptIds.contains(attempt.id),
        )
        .length;
    final maximum = config.attemptPolicy.maximumAttempts;
    if (maximum != null && consumed >= maximum) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final id = 'activity_${assignment.id}_${traineeId}_${consumed + 1}';
    final attempt = teacherReviewSubmissionDraftAttempt(
      traineeId: traineeId,
      assignment: assignment,
      attemptId: id,
      createdAt: now,
    ).copyWith(status: AssignmentAttemptStatus.inProgress);
    attempts[id] = attempt;
    _emitAssignmentAttempts(assignment.teacherId, assignment.id);
    _emitTraineeAttempts(traineeId);
    _emitTeacherAttempts(assignment.teacherId);
    return attempt;
  }

  @override
  Future<void> consumeTeacherActivityAttempt({
    required String traineeId,
    required AssignmentAttempt attempt,
  }) async {
    if (attempt.traineeId != traineeId ||
        attempt.activityAssessmentSnapshot == null ||
        attempts[attempt.id]?.status != AssignmentAttemptStatus.inProgress) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    consumedTeacherActivityAttemptIds.add(attempt.id);
    attempts[attempt.id] = attempts[attempt.id]!.copyWith(
      recordingStartedAt: now,
    );
    _emitAssignmentAttempts(attempt.teacherId, attempt.assignmentId);
    _emitTraineeAttempts(traineeId);
    _emitTeacherAttempts(attempt.teacherId);
  }

  @override
  Future<void> abandonTeacherActivityAttempt({
    required String traineeId,
    required AssignmentAttempt attempt,
  }) async {
    final stored = attempts[attempt.id];
    if (attempt.traineeId != traineeId ||
        attempt.activityAssessmentSnapshot == null ||
        stored?.status != AssignmentAttemptStatus.inProgress) {
      return;
    }
    attempts[attempt.id] = stored!.copyWith(
      status: AssignmentAttemptStatus.draft,
      abandonedAt: now,
    );
    _emitAssignmentAttempts(attempt.teacherId, attempt.assignmentId);
    _emitTraineeAttempts(traineeId);
    _emitTeacherAttempts(attempt.teacherId);
  }

  @override
  Future<void> permanentlyDeleteAssignment({
    required String teacherId,
    required String assignmentId,
    required String confirmation,
  }) async {
    if (confirmation != 'DELETE ASSIGNMENT' ||
        assignments[assignmentId]?.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    assignments.remove(assignmentId);
    attempts.removeWhere((_, attempt) => attempt.assignmentId == assignmentId);
    consumedTeacherActivityAttemptIds.removeWhere(
      (id) => !attempts.containsKey(id),
    );
    _emitTeacher(teacherId);
  }

  @override
  Future<void> permanentlyDeleteClassroom({
    required String teacherId,
    required String groupId,
    required String confirmation,
  }) async {
    if (confirmation != 'DELETE CLASSROOM') {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final ids = assignments.values
        .where((item) => item.teacherId == teacherId && item.groupId == groupId)
        .map((item) => item.id)
        .toList();
    for (final id in ids) {
      await permanentlyDeleteAssignment(
        teacherId: teacherId,
        assignmentId: id,
        confirmation: 'DELETE ASSIGNMENT',
      );
    }
  }

  @override
  Future<AssignmentAttempt> startTeacherCreatedAttempt({
    required String traineeId,
    required GroupAssignment assignment,
  }) {
    return startTeacherCreatedAttemptWorkflow(
      traineeId: traineeId,
      assignment: assignment,
      create: (draft) async {
        if (attempts.containsKey(draft.id)) {
          throw const ClassroomException(ClassroomError.forbidden);
        }
        attempts[draft.id] = AssignmentAttempt(
          id: draft.id,
          traineeId: draft.traineeId,
          teacherId: draft.teacherId,
          groupId: draft.groupId,
          assignmentId: draft.assignmentId,
          movementId: draft.movementId,
          revisionId: draft.revisionId,
          origin: draft.origin,
          assessmentMode: draft.assessmentMode,
          attemptKind: draft.attemptKind,
          status: draft.status,
          createdAt: draft.createdAt ?? now,
        );
        _emitAssignmentAttempts(assignment.teacherId, assignment.id);
        _emitTraineeAttempts(traineeId);
        _emitTeacherAttempts(assignment.teacherId);
      },
      readExisting: (attemptId) async => attempts[attemptId],
      promoteDraftToInProgress: (existing) async {
        final promoted = teacherCreatedAttemptWithStatus(
          attempt: existing,
          status: AssignmentAttemptStatus.inProgress,
        );
        attempts[existing.id] = promoted;
        _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
        _emitTraineeAttempts(existing.traineeId);
        _emitTeacherAttempts(existing.teacherId);
        return promoted;
      },
      isPermissionDenied: (error) =>
          error is ClassroomException && error.code == ClassroomError.forbidden,
    );
  }

  @override
  Future<AssignmentAttempt> createTeacherReviewSubmissionDraft({
    required String traineeId,
    required GroupAssignment assignment,
    String? supersedesAttemptId,
    String? attemptId,
  }) async {
    if (supersedesAttemptId != null) {
      final previous = attempts[supersedesAttemptId];
      if (previous == null) {
        throw const ClassroomException(ClassroomError.notFound);
      }
      ensureCanSupersedeNeedsRetry(
        previous: previous,
        traineeId: traineeId,
        assignment: assignment,
      );
    }
    final id = attemptId ?? newTeacherReviewSubmissionAttemptId();
    final draft = teacherReviewSubmissionDraftAttempt(
      traineeId: traineeId,
      assignment: assignment,
      attemptId: id,
      supersedesAttemptId: supersedesAttemptId,
      createdAt: now,
    );
    if (attempts.containsKey(draft.id)) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    attempts[draft.id] = draft;
    _emitAssignmentAttempts(assignment.teacherId, assignment.id);
    _emitTraineeAttempts(traineeId);
    _emitTeacherAttempts(assignment.teacherId);
    return draft;
  }

  @override
  Future<AssignmentAttempt> getOrCreateTeacherReviewSubmission({
    required String traineeId,
    required GroupAssignment assignment,
  }) async {
    if (!isTeacherAssignmentSubmissionOpen(assignment: assignment, now: now)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    final canonical = canonicalTeacherReviewSubmissionAttempt(
      traineeId: traineeId,
      assignment: assignment,
      createdAt: now,
    );
    final existing = attempts[canonical.id];
    if (existing == null) {
      attempts[canonical.id] = canonical;
      _emitAssignmentAttempts(assignment.teacherId, assignment.id);
      _emitTraineeAttempts(traineeId);
      _emitTeacherAttempts(assignment.teacherId);
      return canonical;
    }
    if (!_sameCanonicalSubmissionIdentity(existing, canonical)) {
      throw const ClassroomException(ClassroomError.identityMismatch);
    }
    if (existing.status == AssignmentAttemptStatus.draft &&
        existing.abandonedAt == null &&
        existing.videoStoragePath == null &&
        existing.videoContentType == null &&
        existing.videoSizeBytes == null &&
        existing.videoDurationMs == null &&
        existing.submittedAt == null &&
        existing.videoExpiresAt == null &&
        existing.videoDeletedAt == null &&
        existing.reviewVerdict == null &&
        existing.reviewFeedback == null &&
        existing.reviewedAt == null &&
        existing.gradeScore == null &&
        existing.gradeMaxScore == null &&
        existing.checkedAt == null &&
        existing.reviewUpdatedAt == null &&
        existing.reviewRevision == null &&
        existing.resultSentRevision == null &&
        existing.resultSentAt == null &&
        existing.resultMessageId == null &&
        existing.deletionFailed == false &&
        existing.deletionFailedAt == null) {
      return _storeAttempt(
        existing.copyWith(status: AssignmentAttemptStatus.inProgress),
      );
    }
    if (!isReusableCanonicalTeacherReviewSubmission(
      attempt: existing,
      traineeId: traineeId,
      assignment: assignment,
    )) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return existing;
  }

  @override
  Future<void> markTeacherReviewSubmissionAbandoned({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? abandonedAt,
    DateTime? videoDeletedAt,
    bool deletionFailed = false,
    DateTime? deletionFailedAt,
  }) async {
    if (!canMarkTeacherReviewSubmissionAbandoned(
      attempt: attempt,
      traineeId: traineeId,
    )) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (deletionFailed && videoDeletedAt != null) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final existing = attempts[attempt.id];
    if (existing == null) return;
    final marked = existing.copyWith(
      abandonedAt: abandonedAt ?? now,
      videoDeletedAt: videoDeletedAt,
      deletionFailed: deletionFailed,
      deletionFailedAt: deletionFailedAt,
    );
    attempts[existing.id] = marked;
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
  }

  @override
  Future<AssignmentAttempt> markTeacherReviewSubmitted({
    required String traineeId,
    required AssignmentAttempt attempt,
    required String videoStoragePath,
    required String videoContentType,
    required int videoSizeBytes,
    required int videoDurationMs,
    required DateTime submittedAt,
    required DateTime videoExpiresAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.traineeId != traineeId ||
        existing.attemptKind != AssignmentAttemptKind.teacherReviewSubmission) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (existing.abandonedAt != null) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (existing.status != AssignmentAttemptStatus.draft &&
        existing.status != AssignmentAttemptStatus.inProgress) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    ensureTeacherReviewSubmissionVideo(
      attempt: existing,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
    );
    final assignment = assignments[existing.assignmentId];
    if (assignment == null ||
        !isTeacherAssignmentSubmissionOpen(assignment: assignment, now: now)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    if (failNextSubmitTransition) {
      failNextSubmitTransition = false;
      throw const ClassroomException(
        ClassroomError.uploadFailed,
        'Could not finalize the submission metadata.',
      );
    }
    final submitted = existing.copyWith(
      status: AssignmentAttemptStatus.submitted,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
    );
    attempts[existing.id] = submitted;
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
    return submitted;
  }

  @override
  Future<AssignmentAttempt> saveTeacherReviewDraftClip({
    required String traineeId,
    required AssignmentAttempt attempt,
    required String videoStoragePath,
    required String videoContentType,
    required int videoSizeBytes,
    required int videoDurationMs,
    required DateTime savedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null ||
        existing.traineeId != traineeId ||
        !existing.isCanonicalTeacherReviewSubmission ||
        existing.status != AssignmentAttemptStatus.inProgress ||
        existing.hasAttachedDraftClip) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    ensureLocalTeacherReviewDraftVideo(
      attempt: existing,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
    );
    final saved = existing.copyWith(
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      draftSavedAt: savedAt,
    );
    attempts[existing.id] = saved;
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
    return saved;
  }

  @override
  Future<AssignmentAttempt> turnInTeacherReviewSubmission({
    required String traineeId,
    required AssignmentAttempt attempt,
    required DateTime submittedAt,
    required DateTime videoExpiresAt,
  }) async {
    final existing = attempts[attempt.id];
    final assignment = existing == null
        ? null
        : assignments[existing.assignmentId];
    if (existing == null ||
        existing.traineeId != traineeId ||
        !existing.hasAttachedDraftClip) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (assignment == null ||
        !isTeacherAssignmentSubmissionOpen(assignment: assignment, now: now)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    final submitted = existing.copyWith(
      status: AssignmentAttemptStatus.submitted,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
      clearDraftSavedAt: true,
    );
    attempts[existing.id] = submitted;
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
    return submitted;
  }

  @override
  Future<AssignmentAttempt> beginTeacherReviewDraftClipRemoval({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? startedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null ||
        existing.traineeId != traineeId ||
        !existing.hasAttachedDraftClip) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final pending = existing.copyWith(draftCleanupStartedAt: startedAt ?? now);
    attempts[existing.id] = pending;
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
    return pending;
  }

  @override
  Future<AssignmentAttempt> completeTeacherReviewDraftClipRemoval({
    required String traineeId,
    required AssignmentAttempt attempt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null ||
        existing.traineeId != traineeId ||
        !existing.isDraftClipRemovalPending) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final cleared = existing.copyWith(clearVideoMetadata: true);
    attempts[existing.id] = cleared;
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
    return cleared;
  }

  @override
  Future<AssignmentAttempt> beginTeacherReviewUnsubmit({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? startedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    final assignment = assignments[existing.assignmentId];
    if (existing.traineeId != traineeId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (!existing.isCanonicalTeacherReviewSubmission) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (existing.status == AssignmentAttemptStatus.unsubmitting) {
      return existing;
    }
    if (assignment == null ||
        !isTeacherAssignmentSubmissionOpen(assignment: assignment, now: now)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    if (existing.status != AssignmentAttemptStatus.submitted ||
        !existing.hasPlayableVideo) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _storeAttempt(
      existing.copyWith(
        status: AssignmentAttemptStatus.unsubmitting,
        deletionFailed: false,
        clearDeletionFailedAt: true,
      ),
    );
  }

  @override
  Future<AssignmentAttempt> completeTeacherReviewUnsubmit({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? completedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.traineeId != traineeId ||
        !existing.isCanonicalTeacherReviewSubmission ||
        existing.status != AssignmentAttemptStatus.unsubmitting) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    return _storeAttempt(
      existing.copyWith(
        status: AssignmentAttemptStatus.inProgress,
        clearVideoMetadata: true,
        clearVideoDeletedAt: true,
        deletionFailed: false,
        clearDeletionFailedAt: true,
      ),
    );
  }

  @override
  Future<AssignmentAttempt> saveTeacherReview({
    required String teacherId,
    required AssignmentAttempt attempt,
    required GroupAssignment assignment,
    required int gradeScore,
    String? feedback,
    DateTime? reviewedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId ||
        existing.assignmentId != assignment.id ||
        existing.attemptKind != AssignmentAttemptKind.teacherReviewSubmission ||
        !assignment.isTeacherCreated ||
        assignment.assessmentMode != AssessmentMode.teacherReviewed ||
        existing.groupId != assignment.groupId ||
        existing.movementId != assignment.movementId ||
        existing.revisionId != assignment.revisionId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final storedAssignment = assignments[assignment.id];
    if (storedAssignment == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (storedAssignment.teacherId != teacherId ||
        !storedAssignment.isTeacherCreated ||
        storedAssignment.assessmentMode != AssessmentMode.teacherReviewed ||
        storedAssignment.groupId != existing.groupId ||
        storedAssignment.movementId != existing.movementId ||
        storedAssignment.revisionId != existing.revisionId) {
      throw const ClassroomException(ClassroomError.identityMismatch);
    }
    if (existing.status != AssignmentAttemptStatus.submitted &&
        existing.status != AssignmentAttemptStatus.checked &&
        existing.status != AssignmentAttemptStatus.approved &&
        existing.status != AssignmentAttemptStatus.needsRetry) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final maxScore = existing.gradeMaxScore ?? storedAssignment.maxScore ?? 100;
    ensureTeacherReviewGrade(gradeScore: gradeScore, maxScore: maxScore);
    final at = (reviewedAt ?? now).toUtc();
    final feedbackValue = feedback?.trim();
    if (feedbackValue != null &&
        feedbackValue.length >
            AssignmentSubmissionLimits.reviewFeedbackMaxLength) {
      throw const ClassroomException(
        ClassroomError.invalidGrade,
        'Feedback is too long.',
      );
    }
    final checked = existing.copyWith(
      status: AssignmentAttemptStatus.checked,
      gradeScore: gradeScore,
      gradeMaxScore: maxScore,
      checkedAt: existing.checkedAt ?? at,
      reviewUpdatedAt: at,
      reviewRevision: (existing.reviewRevision ?? 0) + 1,
      reviewFeedback: feedbackValue == null || feedbackValue.isEmpty
          ? null
          : feedbackValue,
      videoExpiresAt: reviewedVideoExpiresAt(at),
      clearLegacyReview: true,
      clearReviewFeedback: feedbackValue == null || feedbackValue.isEmpty,
      clearResultSent: true,
    );
    attempts[existing.id] = checked;
    if (!storedAssignment.gradingLocked) {
      assignments[assignment.id] = storedAssignment.copyWith(
        gradingLocked: true,
        gradingLockedAt: at,
      );
      _emitTeacher(teacherId);
    }
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
    return checked;
  }

  @override
  Future<AssignmentAttempt> saveTeacherActivityRubricReview({
    required String teacherId,
    required AssignmentAttempt attempt,
    required Map<String, int> criterionScores,
    String? feedback,
  }) async {
    final snapshot = attempt.activityAssessmentSnapshot;
    if (snapshot == null || attempt.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    var total = 0;
    for (final criterion in snapshot.rubric.criteria) {
      final value = criterionScores[criterion.id];
      if (value == null || value < 0 || value > criterion.maximumPoints) {
        throw const ClassroomException(ClassroomError.invalidGrade);
      }
      total += value;
    }
    if (criterionScores.length != snapshot.rubric.criteria.length) {
      throw const ClassroomException(ClassroomError.invalidGrade);
    }
    final reviewed = attempt.copyWith(
      status: AssignmentAttemptStatus.checked,
      gradeScore: total,
      gradeMaxScore: snapshot.rubric.maximumScore,
      criterionScores: criterionScores,
      reviewFeedback: feedback,
      checkedAt: now,
      reviewUpdatedAt: now,
      reviewRevision: (attempt.reviewRevision ?? 0) + 1,
    );
    return _storeAttempt(reviewed);
  }

  @override
  Future<GroupAssignment> updateTeacherAssignmentMaxScore({
    required String teacherId,
    required String assignmentId,
    required int maxScore,
  }) async {
    final existing = assignments[assignmentId];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    return updateAssignmentSettings(
      teacherId: teacherId,
      assignmentId: assignmentId,
      dueAt: existing.dueAt,
      maxScore: maxScore,
      topic: existing.topic,
    );
  }

  @override
  Future<AssignmentAttempt> markTeacherReviewResultSent({
    required String teacherId,
    required AssignmentAttempt attempt,
    required String messageId,
    DateTime? sentAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId ||
        !existing.isChecked ||
        existing.reviewRevision == null ||
        messageId.trim().isEmpty ||
        messageId.trim().length > 256) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (existing.resultSentForCurrentRevision) return existing;
    return _storeAttempt(
      existing.copyWith(
        resultSentRevision: existing.reviewRevision,
        resultSentAt: (sentAt ?? now).toUtc(),
        resultMessageId: messageId.trim(),
      ),
    );
  }

  @override
  Future<AssignmentAttempt> reviewTeacherSubmission({
    required String teacherId,
    required AssignmentAttempt attempt,
    required AssignmentReviewVerdict verdict,
    String? feedback,
    required DateTime reviewedAt,
    required DateTime videoExpiresAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (existing.isCanonicalTeacherReviewSubmission) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (existing.attemptKind != AssignmentAttemptKind.teacherReviewSubmission ||
        existing.status != AssignmentAttemptStatus.submitted) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final status = verdict == AssignmentReviewVerdict.approved
        ? AssignmentAttemptStatus.approved
        : AssignmentAttemptStatus.needsRetry;
    final reviewed = existing.copyWith(
      status: status,
      reviewVerdict: verdict,
      reviewFeedback: feedback,
      reviewedAt: reviewedAt,
      videoExpiresAt: videoExpiresAt,
    );
    attempts[existing.id] = reviewed;
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
    return reviewed;
  }

  @override
  Future<void> markSubmissionVideoDeleted({
    required String actorId,
    required AssignmentAttempt attempt,
    required DateTime deletedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.traineeId != actorId && existing.teacherId != actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (existing.isCanonicalTeacherReviewSubmission &&
        existing.traineeId == actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    attempts[existing.id] = existing.copyWith(
      clearVideoStoragePath: true,
      videoDeletedAt: deletedAt,
      deletionFailed: false,
      clearDeletionFailedAt: true,
    );
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
  }

  @override
  Future<void> markSubmissionDeletionFailed({
    required String actorId,
    required AssignmentAttempt attempt,
    required DateTime failedAt,
  }) async {
    final existing = attempts[attempt.id];
    if (existing == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (existing.traineeId != actorId && existing.teacherId != actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (existing.isCanonicalTeacherReviewSubmission &&
        (existing.traineeId != actorId ||
            existing.status != AssignmentAttemptStatus.unsubmitting)) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    attempts[existing.id] = existing.copyWith(
      deletionFailed: true,
      deletionFailedAt: failedAt,
    );
    _emitAssignmentAttempts(existing.teacherId, existing.assignmentId);
    _emitTraineeAttempts(existing.traineeId);
    _emitTeacherAttempts(existing.teacherId);
  }

  bool _sameCanonicalSubmissionIdentity(
    AssignmentAttempt existing,
    AssignmentAttempt canonical,
  ) {
    return existing.isCanonicalTeacherReviewSubmission &&
        existing.traineeId == canonical.traineeId &&
        existing.teacherId == canonical.teacherId &&
        existing.groupId == canonical.groupId &&
        existing.assignmentId == canonical.assignmentId &&
        existing.movementId == canonical.movementId &&
        existing.revisionId == canonical.revisionId &&
        existing.origin == canonical.origin &&
        existing.assessmentMode == canonical.assessmentMode &&
        existing.attemptKind == canonical.attemptKind &&
        existing.supersedesAttemptId == null;
  }

  AssignmentAttempt _storeAttempt(AssignmentAttempt value) {
    attempts[value.id] = value;
    _emitAssignmentAttempts(value.teacherId, value.assignmentId);
    _emitTraineeAttempts(value.traineeId);
    _emitTeacherAttempts(value.teacherId);
    return value;
  }

  void seedAssignment(GroupAssignment assignment) {
    assignments[assignment.id] = assignment;
    _emitTeacher(assignment.teacherId);
  }

  void seedAttempt(AssignmentAttempt attempt) {
    attempts[attempt.id] = attempt;
    _emitAssignmentAttempts(attempt.teacherId, attempt.assignmentId);
    _emitTraineeAttempts(attempt.traineeId);
    _emitTeacherAttempts(attempt.teacherId);
  }

  Future<void> _ensureAudienceTargetsAreApprovedMembers({
    required String teacherId,
    required ElixrGroup group,
    required AssignmentAudience audience,
  }) async {
    if (audience.isEntireClass) return;
    final repository = _groupRepository;
    if (repository == null) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final memberships = await repository
        .watchGroupMemberships(
          groupId: group.id,
          teacherId: teacherId,
          status: GroupMembershipStatus.approved,
        )
        .first;
    ensureAssignmentAudienceMatchesRoster(
      audience: audience,
      group: group,
      memberships: memberships,
    );
  }

  void _emitTeacher(String teacherId) {
    final controller = _teacherControllers[teacherId];
    if (controller == null || controller.isClosed) return;
    final items = assignments.values
        .where((assignment) => assignment.teacherId == teacherId)
        .toList();
    _sortAssignments(items);
    controller.add(items);
  }

  void _emitAssignmentAttempts(String teacherId, String assignmentId) {
    final controller =
        _assignmentAttemptControllers['$teacherId|$assignmentId'];
    if (controller == null || controller.isClosed) return;
    final items = attempts.values
        .where(
          (attempt) =>
              attempt.teacherId == teacherId &&
              attempt.assignmentId == assignmentId,
        )
        .toList();
    controller.add(items);
  }

  void _emitTraineeAttempts(String traineeId) {
    final controller = _traineeAttemptControllers[traineeId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      attempts.values
          .where((attempt) => attempt.traineeId == traineeId)
          .toList(),
    );
  }

  void _emitTeacherAttempts(String teacherId) {
    final controller = _teacherAttemptControllers[teacherId];
    if (controller == null || controller.isClosed) return;
    controller.add(
      attempts.values
          .where((attempt) => attempt.teacherId == teacherId)
          .toList(),
    );
  }

  Stream<List<T>> _watch<T>(
    Map<String, StreamController<List<T>>> controllers,
    String key,
    void Function() emit,
  ) {
    final existing = controllers[key];
    if (existing != null && !existing.isClosed) return existing.stream;
    late final StreamController<List<T>> controller;
    controller = StreamController<List<T>>.broadcast(onListen: emit);
    controllers[key] = controller;
    return controller.stream;
  }

  static void _sortAssignments(List<GroupAssignment> items) {
    items.sort((a, b) {
      final aDue = a.dueAt;
      final bDue = b.dueAt;
      if (aDue != null && bDue != null) return aDue.compareTo(bDue);
      if (aDue != null) return -1;
      if (bDue != null) return 1;
      final aAt = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
  }
}
