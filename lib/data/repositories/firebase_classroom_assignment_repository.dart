import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';
import 'package:elixr_core/models/elixr_group.dart';

import '../models/assessment_mode.dart';
import '../models/assignment_attempt.dart';
import '../models/assignment_attempt_ids.dart';
import '../models/assignment_submission_limits.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/phase6_submission_diagnostics.dart';
import '../models/teacher_movement.dart';
import 'classroom_assignment_repository.dart';

class FirebaseClassroomAssignmentRepository
    implements ClassroomAssignmentRepository {
  FirebaseClassroomAssignmentRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _assignments =>
      _firestore.collection(FirestoreCollections.groupAssignments);

  CollectionReference<Map<String, dynamic>> get _attempts =>
      _firestore.collection(FirestoreCollections.assignmentAttempts);

  @override
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    String? displayInstructions,
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    final payload = officialAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      officialMovementName: officialMovementName,
      displayInstructions: displayInstructions ?? '',
      dueAt: dueAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    );
    final ref = _assignments.doc();
    await ref.set(payload);
    final parsed = Map<String, dynamic>.from(payload)
      ..['created_at'] = DateTime.now().toUtc()
      ..['updated_at'] = DateTime.now().toUtc();
    if (dueAt != null) parsed['due_at'] = dueAt;
    return GroupAssignment.tryFromMap(parsed, id: ref.id) ??
        (throw const ClassroomException(ClassroomError.malformed));
  }

  @override
  Future<GroupAssignment> createTeacherCreatedAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required TeacherMovement movement,
    required TeacherMovementRevision revision,
    int maxScore = 100,
    DateTime? dueAt,
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    var persistedPayload = teacherCreatedAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      maxScore: maxScore,
      dueAt: dueAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    );
    final ref = _assignments.doc();
    try {
      await ref.set(persistedPayload);
    } on FirebaseException catch (error) {
      // Older deployments predate the optional grading fields. A default
      // score is already the compatibility value exposed by GroupAssignment,
      // so retry only that safe default without the newer fields. Non-default
      // scores still fail loudly until the matching rules are deployed.
      if (!_isFirestorePermissionDenied(error) || maxScore != 100) rethrow;
      persistedPayload = teacherCreatedAssignmentPayload(
        teacherId: teacherId,
        teacherDisplayName: teacherDisplayName,
        group: group,
        movement: movement,
        revision: revision,
        maxScore: maxScore,
        dueAt: dueAt,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        includeGradingFields: false,
      );
      await ref.set(persistedPayload);
    }
    return GroupAssignment.tryFromMap({
          ...persistedPayload,
          'created_at': DateTime.now().toUtc(),
          'updated_at': DateTime.now().toUtc(),
          'due_at': ?dueAt,
        }, id: ref.id) ??
        (throw const ClassroomException(ClassroomError.malformed));
  }

  @override
  Future<void> archiveAssignment({
    required String teacherId,
    required String assignmentId,
  }) async {
    final ref = _assignments.doc(assignmentId);
    final snap = await ref.get();
    if (!snap.exists) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    final current = GroupAssignment.tryFromMap(
      snap.data() ?? const {},
      id: snap.id,
    );
    if (current == null) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    if (current.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (current.isRetiredTemplate) {
      throw const ClassroomException(
        ClassroomError.identityMismatch,
        'Retired template-scored assignments are read-only.',
      );
    }
    await ref.update({
      'status': GroupAssignmentStatus.archived.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<GroupAssignment> updateAssignmentSettings({
    required String teacherId,
    required String assignmentId,
    DateTime? dueAt,
    int? maxScore,
  }) async {
    if (maxScore != null) ensureTeacherAssignmentMaxScore(maxScore);
    final current = await getAssignment(assignmentId: assignmentId);
    if (current == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (current.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (!current.isActive || current.isRetiredTemplate) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (maxScore != null) {
      if (!current.isTeacherCreated || current.gradingLocked) {
        throw const ClassroomException(ClassroomError.invalidState);
      }
      final snapshot = await _attempts
          .where('assignment_id', isEqualTo: assignmentId)
          .get();
      final hasChecked = snapshot.docs.any((doc) {
        final parsed = AssignmentAttempt.tryFromMap(doc.data(), id: doc.id);
        return parsed?.isChecked == true;
      });
      if (hasChecked) {
        throw const ClassroomException(ClassroomError.invalidState);
      }
    }

    final update = <String, Object>{
      'due_at': dueAt ?? FieldValue.delete(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (maxScore != null) {
      update['max_score'] = maxScore;
      update['grading_locked'] = false;
      update['grading_locked_at'] = FieldValue.delete();
    }
    await _assignments.doc(assignmentId).update(update);
    return current.copyWith(
      dueAt: dueAt,
      clearDueAt: dueAt == null,
      maxScore: maxScore,
      gradingLocked: maxScore == null ? null : false,
      clearGradingLockedAt: maxScore != null,
    );
  }

  @override
  Future<GroupAssignment?> getAssignment({required String assignmentId}) async {
    final snap = await _assignments.doc(assignmentId).get();
    if (!snap.exists || snap.data() == null) return null;
    return GroupAssignment.tryFromMap(snap.data()!, id: snap.id);
  }

  @override
  Future<bool> hasTeacherAssignmentForMovement({
    required String teacherId,
    required String movementId,
  }) async {
    final snapshot = await _assignments
        .where('teacher_id', isEqualTo: teacherId)
        .where('movement_id', isEqualTo: movementId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  @override
  Stream<List<GroupAssignment>> watchTeacherAssignments({
    required String teacherId,
  }) {
    return _assignments
        .where('teacher_id', isEqualTo: teacherId)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map((doc) => GroupAssignment.tryFromMap(doc.data(), id: doc.id))
              .whereType<GroupAssignment>()
              .toList();
          _sortAssignments(items);
          return items;
        });
  }

  @override
  Future<List<GroupAssignment>> fetchAssignmentsForGroup({
    required String groupId,
  }) async {
    final snapshot = await _assignments
        .where('group_id', isEqualTo: groupId)
        .get();
    final items = snapshot.docs
        .map((doc) => GroupAssignment.tryFromMap(doc.data(), id: doc.id))
        .whereType<GroupAssignment>()
        .toList();
    _sortAssignments(items);
    return items;
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForAssignment({
    required String teacherId,
    required String assignmentId,
  }) {
    return _attempts
        .where('teacher_id', isEqualTo: teacherId)
        .where('assignment_id', isEqualTo: assignmentId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(
                (doc) => AssignmentAttempt.tryFromMap(doc.data(), id: doc.id),
              )
              .whereType<AssignmentAttempt>()
              .toList();
        });
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTeacher({
    required String teacherId,
  }) {
    return _attempts.where('teacher_id', isEqualTo: teacherId).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => AssignmentAttempt.tryFromMap(doc.data(), id: doc.id))
          .whereType<AssignmentAttempt>()
          .toList();
    });
  }

  @override
  Stream<List<AssignmentAttempt>> watchAttemptsForTrainee({
    required String traineeId,
  }) {
    return _attempts.where('trainee_id', isEqualTo: traineeId).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => AssignmentAttempt.tryFromMap(doc.data(), id: doc.id))
          .whereType<AssignmentAttempt>()
          .toList();
    });
  }

  @override
  Future<AssignmentAttempt?> getAttempt({required String attemptId}) async {
    final snap = await _attempts.doc(attemptId).get();
    if (!snap.exists || snap.data() == null) return null;
    return AssignmentAttempt.tryFromMap(snap.data()!, id: snap.id);
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
        await _attempts
            .doc(draft.id)
            .set(draft.toCreateMap(createdAt: FieldValue.serverTimestamp()));
      },
      readExisting: (attemptId) async {
        final snap = await _attempts.doc(attemptId).get();
        if (!snap.exists || snap.data() == null) return null;
        return AssignmentAttempt.tryFromMap(snap.data()!, id: snap.id) ??
            (throw const ClassroomException(ClassroomError.malformed));
      },
      promoteDraftToInProgress: (existing) async {
        await _attempts.doc(existing.id).update({
          'status': AssignmentAttemptStatus.inProgress.wireValue,
        });
        return teacherCreatedAttemptWithStatus(
          attempt: existing,
          status: AssignmentAttemptStatus.inProgress,
        );
      },
      isPermissionDenied: _isFirestorePermissionDenied,
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
      final previous = await getAttempt(attemptId: supersedesAttemptId);
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
    );
    await _attempts
        .doc(draft.id)
        .set(draft.toCreateMap(createdAt: FieldValue.serverTimestamp()));
    return draft.copyWith();
  }

  @override
  Future<AssignmentAttempt> getOrCreateTeacherReviewSubmission({
    required String traineeId,
    required GroupAssignment assignment,
  }) async {
    if (!isTeacherAssignmentSubmissionOpen(assignment: assignment)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    return getOrCreateCanonicalTeacherReviewSubmissionWorkflow(
      traineeId: traineeId,
      assignment: assignment,
      create: (canonical) async {
        await _attempts
            .doc(canonical.id)
            .set(
              canonical.toCreateMap(createdAt: FieldValue.serverTimestamp()),
            );
      },
      readExisting: (attemptId) async {
        final snapshot = await _attempts.doc(attemptId).get();
        if (!snapshot.exists || snapshot.data() == null) return null;
        return AssignmentAttempt.tryFromMap(
              snapshot.data()!,
              id: snapshot.id,
            ) ??
            (throw const ClassroomException(ClassroomError.malformed));
      },
      promoteLegacyDraft: (existing) async {
        await _attempts.doc(existing.id).update({
          'status': AssignmentAttemptStatus.inProgress.wireValue,
          'deletion_failed': FieldValue.delete(),
          'deletion_failed_at': FieldValue.delete(),
        });
        return existing.copyWith(status: AssignmentAttemptStatus.inProgress);
      },
      shouldReadAfterCreateFailure: _isFirebaseException,
      isFallbackReadFailure: _isFirebaseException,
    );
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
    final payload = <String, dynamic>{
      'abandoned_at': FieldValue.serverTimestamp(),
    };
    if (videoDeletedAt != null) {
      payload['video_deleted_at'] = FieldValue.serverTimestamp();
      payload['deletion_failed'] = false;
    }
    if (deletionFailed) {
      payload['deletion_failed'] = true;
      payload['deletion_failed_at'] = FieldValue.serverTimestamp();
    }
    await _attempts.doc(attempt.id).update(payload);
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
    if (attempt.traineeId != traineeId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (attempt.attemptKind != AssignmentAttemptKind.teacherReviewSubmission ||
        attempt.abandonedAt != null ||
        (attempt.status != AssignmentAttemptStatus.draft &&
            attempt.status != AssignmentAttemptStatus.inProgress)) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    ensureTeacherReviewSubmissionVideo(
      attempt: attempt,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
    );
    final assignment = await getAssignment(assignmentId: attempt.assignmentId);
    if (assignment == null ||
        !isTeacherAssignmentSubmissionOpen(assignment: assignment)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    try {
      await _attempts.doc(attempt.id).update({
        'status': AssignmentAttemptStatus.submitted.wireValue,
        'video_storage_path': videoStoragePath,
        'video_content_type': videoContentType,
        'video_size_bytes': videoSizeBytes,
        'video_duration_ms': videoDurationMs,
        'submitted_at': FieldValue.serverTimestamp(),
        'video_expires_at': Timestamp.fromDate(videoExpiresAt.toUtc()),
      });
    } on FirebaseException catch (error) {
      emitPhase6SubmissionDiagnostic(
        stage: Phase6SubmissionStage.firestoreSubmit,
        error: error,
      );
      rethrow;
    }
    return attempt.copyWith(
      status: AssignmentAttemptStatus.submitted,
      videoStoragePath: videoStoragePath,
      videoContentType: videoContentType,
      videoSizeBytes: videoSizeBytes,
      videoDurationMs: videoDurationMs,
      submittedAt: submittedAt,
      videoExpiresAt: videoExpiresAt,
    );
  }

  @override
  Future<AssignmentAttempt> beginTeacherReviewUnsubmit({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? startedAt,
  }) async {
    final current = await getAttempt(attemptId: attempt.id);
    if (current == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (current.traineeId != traineeId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (!current.isCanonicalTeacherReviewSubmission) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (current.status == AssignmentAttemptStatus.unsubmitting) return current;
    final assignment = await getAssignment(assignmentId: current.assignmentId);
    if (assignment == null ||
        !isTeacherAssignmentSubmissionOpen(assignment: assignment)) {
      throw const ClassroomException(ClassroomError.deadlinePassed);
    }
    if (current.status != AssignmentAttemptStatus.submitted ||
        !current.hasPlayableVideo) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    await _attempts.doc(current.id).update({
      'status': AssignmentAttemptStatus.unsubmitting.wireValue,
      'deletion_failed': false,
      'deletion_failed_at': FieldValue.delete(),
    });
    return current.copyWith(
      status: AssignmentAttemptStatus.unsubmitting,
      deletionFailed: false,
      clearDeletionFailedAt: true,
    );
  }

  @override
  Future<AssignmentAttempt> completeTeacherReviewUnsubmit({
    required String traineeId,
    required AssignmentAttempt attempt,
    DateTime? completedAt,
  }) async {
    final current = await getAttempt(attemptId: attempt.id);
    if (current == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (!current.isCanonicalTeacherReviewSubmission ||
        current.traineeId != traineeId ||
        current.status != AssignmentAttemptStatus.unsubmitting) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    await _attempts.doc(current.id).update({
      'status': AssignmentAttemptStatus.inProgress.wireValue,
      'video_storage_path': FieldValue.delete(),
      'video_content_type': FieldValue.delete(),
      'video_size_bytes': FieldValue.delete(),
      'video_duration_ms': FieldValue.delete(),
      'submitted_at': FieldValue.delete(),
      'video_expires_at': FieldValue.delete(),
      'video_deleted_at': FieldValue.delete(),
      'deletion_failed': false,
      'deletion_failed_at': FieldValue.delete(),
    });
    return current.copyWith(
      status: AssignmentAttemptStatus.inProgress,
      clearVideoMetadata: true,
      clearVideoDeletedAt: true,
      deletionFailed: false,
      clearDeletionFailedAt: true,
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
    final at = (reviewedAt ?? DateTime.now().toUtc()).toUtc();
    AssignmentAttempt? saved;
    await _firestore.runTransaction((transaction) async {
      final assignmentRef = _assignments.doc(assignment.id);
      final attemptRef = _attempts.doc(attempt.id);
      final assignmentSnapshot = await transaction.get(assignmentRef);
      final attemptSnapshot = await transaction.get(attemptRef);
      if (!assignmentSnapshot.exists || assignmentSnapshot.data() == null) {
        throw const ClassroomException(ClassroomError.notFound);
      }
      if (!attemptSnapshot.exists || attemptSnapshot.data() == null) {
        throw const ClassroomException(ClassroomError.notFound);
      }
      final currentAssignment = GroupAssignment.tryFromMap(
        assignmentSnapshot.data()!,
        id: assignmentSnapshot.id,
      );
      final current = AssignmentAttempt.tryFromMap(
        attemptSnapshot.data()!,
        id: attemptSnapshot.id,
      );
      if (currentAssignment == null || current == null) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      if (current.teacherId != teacherId ||
          current.assignmentId != currentAssignment.id ||
          current.attemptKind !=
              AssignmentAttemptKind.teacherReviewSubmission ||
          !currentAssignment.isTeacherCreated ||
          currentAssignment.assessmentMode != AssessmentMode.teacherReviewed ||
          current.groupId != currentAssignment.groupId ||
          current.movementId != currentAssignment.movementId ||
          current.revisionId != currentAssignment.revisionId) {
        throw const ClassroomException(ClassroomError.forbidden);
      }
      if (current.status != AssignmentAttemptStatus.submitted &&
          current.status != AssignmentAttemptStatus.checked &&
          current.status != AssignmentAttemptStatus.approved &&
          current.status != AssignmentAttemptStatus.needsRetry) {
        throw const ClassroomException(ClassroomError.invalidState);
      }
      final maxScore =
          current.gradeMaxScore ?? currentAssignment.maxScore ?? 100;
      ensureTeacherReviewGrade(gradeScore: gradeScore, maxScore: maxScore);
      final normalizedFeedback = feedback?.trim();
      if (normalizedFeedback != null &&
          normalizedFeedback.length >
              AssignmentSubmissionLimits.reviewFeedbackMaxLength) {
        throw const ClassroomException(
          ClassroomError.invalidGrade,
          'Feedback is too long.',
        );
      }
      final revision = (current.reviewRevision ?? 0) + 1;
      final checkedAt = current.checkedAt ?? at;
      final expiresAt = reviewedVideoExpiresAt(at);
      final update = <String, dynamic>{
        'status': AssignmentAttemptStatus.checked.wireValue,
        'grade_score': gradeScore,
        'grade_max_score': maxScore,
        'checked_at': current.checkedAt == null
            ? FieldValue.serverTimestamp()
            : Timestamp.fromDate(checkedAt),
        'review_updated_at': FieldValue.serverTimestamp(),
        'review_revision': revision,
        'video_expires_at': Timestamp.fromDate(expiresAt),
        'review_verdict': FieldValue.delete(),
        'reviewed_at': FieldValue.delete(),
        'result_sent_revision': FieldValue.delete(),
        'result_sent_at': FieldValue.delete(),
        'result_message_id': FieldValue.delete(),
      };
      if (normalizedFeedback == null || normalizedFeedback.isEmpty) {
        update['review_feedback'] = FieldValue.delete();
      } else {
        update['review_feedback'] = normalizedFeedback;
      }
      transaction.update(attemptRef, update);
      if (!currentAssignment.gradingLocked) {
        transaction.update(assignmentRef, {
          'max_score': maxScore,
          'grading_locked': true,
          'grading_locked_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      saved = current.copyWith(
        status: AssignmentAttemptStatus.checked,
        gradeScore: gradeScore,
        gradeMaxScore: maxScore,
        checkedAt: checkedAt,
        reviewUpdatedAt: at,
        reviewRevision: revision,
        reviewFeedback: normalizedFeedback,
        videoExpiresAt: expiresAt,
        clearLegacyReview: true,
        clearReviewFeedback:
            normalizedFeedback == null || normalizedFeedback.isEmpty,
        clearResultSent: true,
      );
    });
    return saved!;
  }

  @override
  Future<GroupAssignment> updateTeacherAssignmentMaxScore({
    required String teacherId,
    required String assignmentId,
    required int maxScore,
  }) async {
    final current = await getAssignment(assignmentId: assignmentId);
    if (current == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    return updateAssignmentSettings(
      teacherId: teacherId,
      assignmentId: assignmentId,
      dueAt: current.dueAt,
      maxScore: maxScore,
    );
  }

  @override
  Future<AssignmentAttempt> markTeacherReviewResultSent({
    required String teacherId,
    required AssignmentAttempt attempt,
    required String messageId,
    DateTime? sentAt,
  }) async {
    final current = await getAttempt(attemptId: attempt.id);
    if (current == null) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    if (current.teacherId != teacherId ||
        !current.isChecked ||
        current.reviewRevision == null ||
        messageId.trim().isEmpty) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    if (current.resultSentForCurrentRevision) return current;
    await _attempts.doc(current.id).update({
      'result_sent_revision': current.reviewRevision,
      'result_sent_at': FieldValue.serverTimestamp(),
      'result_message_id': messageId.trim(),
    });
    return current.copyWith(
      resultSentRevision: current.reviewRevision,
      resultSentAt: (sentAt ?? DateTime.now().toUtc()).toUtc(),
      resultMessageId: messageId.trim(),
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
    if (attempt.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (attempt.isCanonicalTeacherReviewSubmission) {
      throw const ClassroomException(ClassroomError.invalidState);
    }
    final status = verdict == AssignmentReviewVerdict.approved
        ? AssignmentAttemptStatus.approved
        : AssignmentAttemptStatus.needsRetry;
    final payload = <String, dynamic>{
      'status': status.wireValue,
      'review_verdict': verdict.wireValue,
      'reviewed_at': FieldValue.serverTimestamp(),
      'video_expires_at': Timestamp.fromDate(videoExpiresAt.toUtc()),
    };
    if (feedback != null && feedback.trim().isNotEmpty) {
      payload['review_feedback'] = feedback.trim();
    }
    await _attempts.doc(attempt.id).update(payload);
    return attempt.copyWith(
      status: status,
      reviewVerdict: verdict,
      reviewFeedback: feedback?.trim(),
      reviewedAt: reviewedAt,
      videoExpiresAt: videoExpiresAt,
    );
  }

  @override
  Future<void> markSubmissionVideoDeleted({
    required String actorId,
    required AssignmentAttempt attempt,
    required DateTime deletedAt,
  }) async {
    if (attempt.traineeId != actorId && attempt.teacherId != actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (attempt.isCanonicalTeacherReviewSubmission &&
        attempt.traineeId == actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await _attempts.doc(attempt.id).update({
      'video_storage_path': FieldValue.delete(),
      'video_deleted_at': FieldValue.serverTimestamp(),
      'deletion_failed': false,
      'deletion_failed_at': FieldValue.delete(),
    });
  }

  @override
  Future<void> markSubmissionDeletionFailed({
    required String actorId,
    required AssignmentAttempt attempt,
    required DateTime failedAt,
  }) async {
    if (attempt.traineeId != actorId && attempt.teacherId != actorId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    if (attempt.isCanonicalTeacherReviewSubmission &&
        (attempt.traineeId != actorId ||
            attempt.status != AssignmentAttemptStatus.unsubmitting)) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await _attempts.doc(attempt.id).update({
      'deletion_failed': true,
      'deletion_failed_at': FieldValue.serverTimestamp(),
    });
  }

  static bool _isFirestorePermissionDenied(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
  }

  static bool _isFirebaseException(Object error) => error is FirebaseException;

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
