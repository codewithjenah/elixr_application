import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:elixr_core/database/firestore_collections.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/models/group_membership.dart';
import 'package:elixr_core/models/teacher_roster_invite.dart';

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
  FirebaseClassroomAssignmentRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Uri? apiBaseUri,
    HttpClient Function()? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       apiBaseUri = apiBaseUri ?? Uri.parse(_configuredApiBaseUrl),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'ELIXR_ASSIGNMENTS_API_BASE_URL',
    defaultValue: 'https://asia-southeast1-elixr-app-2026.cloudfunctions.net/',
  );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Uri apiBaseUri;
  final HttpClient Function() _httpClientFactory;
  final Duration requestTimeout;

  CollectionReference<Map<String, dynamic>> get _assignments =>
      _firestore.collection(FirestoreCollections.groupAssignments);

  CollectionReference<Map<String, dynamic>> get _attempts =>
      _firestore.collection(FirestoreCollections.assignmentAttempts);

  CollectionReference<Map<String, dynamic>> get _memberships =>
      _firestore.collection(FirestoreCollections.groupMemberships);

  @override
  Future<GroupAssignment> createOfficialAssignment({
    required String teacherId,
    required String teacherDisplayName,
    required ElixrGroup group,
    required String officialMovementName,
    DateTime? dueAt,
    String? displayInstructions,
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    await _ensureAudienceTargetsAreApprovedMembers(
      teacherId: teacherId,
      group: group,
      audience: audience,
    );
    final payload = officialAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      officialMovementName: officialMovementName,
      displayInstructions: displayInstructions ?? '',
      dueAt: dueAt,
      audience: audience,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    return _createThroughFunction(payload: payload, audience: audience);
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
    AssignmentAudience audience = const AssignmentAudience.entireClass(),
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    await _ensureAudienceTargetsAreApprovedMembers(
      teacherId: teacherId,
      group: group,
      audience: audience,
    );
    final persistedPayload = teacherCreatedAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      maxScore: maxScore,
      dueAt: dueAt,
      audience: audience,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    return _createThroughFunction(
      payload: persistedPayload,
      audience: audience,
    );
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
    final assignment = GroupAssignment.tryFromMap(snap.data()!, id: snap.id);
    if (assignment == null || assignment.audience.isEntireClass) {
      return assignment;
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    if (uid == assignment.teacherId) {
      return _hydrateTeacherAssignments([
        assignment,
      ], uid).then((items) => items.isEmpty ? null : items.single);
    }
    final recipient = await _assignments
        .doc(assignmentId)
        .collection(FirestoreCollections.assignmentRecipients)
        .doc(uid)
        .get();
    return _validRecipient(recipient.data(), assignment, uid)
        ? assignment.copyWith(
            audience: assignment.audience.withRecipientIds([uid]),
          )
        : null;
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
        .asyncMap((snapshot) async {
          final items = snapshot.docs
              .map((doc) => GroupAssignment.tryFromMap(doc.data(), id: doc.id))
              .whereType<GroupAssignment>()
              .toList();
          final hydrated = await _hydrateTeacherAssignments(items, teacherId);
          _sortAssignments(hydrated);
          return hydrated;
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
  Future<List<GroupAssignment>> fetchAssignmentsForTrainee({
    required String traineeId,
    String? groupId,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != traineeId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final endpoint = apiBaseUri
        .resolve('listTraineeAssignments')
        .replace(queryParameters: {'group_id': ?groupId});
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(endpoint).timeout(requestTimeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(requestTimeout);
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(requestTimeout);
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const ClassroomException(ClassroomError.forbidden);
      }
      if (response.statusCode != HttpStatus.ok) {
        throw const ClassroomException(ClassroomError.invalidState);
      }
      final decoded = jsonDecode(body);
      final values = decoded is Map<String, dynamic>
          ? decoded['assignments']
          : null;
      if (values is! List) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      final items = <GroupAssignment>[];
      for (final value in values) {
        if (value is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(value);
        final id = map['id'];
        if (id is! String || id.trim().isEmpty || id.trim().length > 128) {
          continue;
        }
        final assignment = GroupAssignment.tryFromMap(map, id: id.trim());
        if (assignment != null &&
            (groupId == null || assignment.groupId == groupId)) {
          // The Function has already authorized this authenticated recipient;
          // it deliberately does not serialize any recipient UID list.
          items.add(
            assignment.copyWith(
              audience: assignment.audience.withRecipientIds([traineeId]),
            ),
          );
        }
      }
      _sortAssignments(items);
      return items;
    } on ClassroomException {
      rethrow;
    } on TimeoutException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on SocketException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on FormatException {
      throw const ClassroomException(ClassroomError.malformed);
    } finally {
      client.close(force: true);
    }
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

  /// Re-read the approved roster immediately before a targeted assignment is
  /// written. This is intentionally one constrained membership query, not one
  /// read per target.
  Future<void> _ensureAudienceTargetsAreApprovedMembers({
    required String teacherId,
    required ElixrGroup group,
    required AssignmentAudience audience,
  }) async {
    if (audience.isEntireClass) return;
    final snapshot = await _memberships
        .where('teacher_id', isEqualTo: teacherId)
        .where('group_id', isEqualTo: group.id)
        .where('status', isEqualTo: GroupMembershipStatus.approved.name)
        .get();
    ensureAssignmentAudienceMatchesRoster(
      audience: audience,
      group: group,
      memberships: [
        for (final doc in snapshot.docs)
          ?GroupMembership.tryFromMap(doc.data(), id: doc.id),
      ],
    );
  }

  /// Targeted canonical and recipient rows are one server-side transaction.
  /// The Function derives the teacher from the verified token; local fields
  /// are retained only as a defensive preflight and are never trusted there.
  Future<GroupAssignment> _createThroughFunction({
    required Map<String, dynamic> payload,
    required AssignmentAudience audience,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.uid != payload['teacher_id']) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final requestPayload =
        <String, dynamic>{
            ...payload,
            'recipient_ids': audience.isEntireClass
                ? const <String>[]
                : audience.targetTraineeIds,
          }
          ..remove('teacher_id')
          ..remove('teacher_display_name')
          ..remove('group_name')
          ..remove('created_at')
          ..remove('updated_at');
    final dueAt = requestPayload['due_at'];
    if (dueAt is DateTime) {
      requestPayload['due_at'] = dueAt.toUtc().toIso8601String();
    }
    final client = _httpClientFactory();
    try {
      final request = await client
          .postUrl(apiBaseUri.resolve('createClassroomAssignment'))
          .timeout(requestTimeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(requestPayload));
      final response = await request.close().timeout(requestTimeout);
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(requestTimeout);
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const ClassroomException(ClassroomError.forbidden);
      }
      if (response.statusCode != HttpStatus.ok) {
        throw const ClassroomException(ClassroomError.invalidState);
      }
      final decoded = jsonDecode(body);
      final map = decoded is Map<String, dynamic>
          ? decoded['assignment']
          : null;
      if (map is! Map) throw const ClassroomException(ClassroomError.malformed);
      final assignmentMap = Map<String, dynamic>.from(map);
      final id = assignmentMap.remove('id');
      if (id is! String || id.trim().isEmpty) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      final parsed = GroupAssignment.tryFromMap(assignmentMap, id: id.trim());
      if (parsed == null) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      final responseRecipients = decoded is Map
          ? decoded['recipient_ids']
          : null;
      if (responseRecipients is! List ||
          responseRecipients.length != audience.targetTraineeIds.length ||
          responseRecipients.whereType<String>().toSet().length !=
              responseRecipients.length ||
          !responseRecipients.every(
            (value) =>
                value is String &&
                audience.targetTraineeIds.contains(value.trim()),
          ) ||
          parsed.audience.type != audience.type) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      return parsed.copyWith(
        audience: parsed.audience.withRecipientIds(
          responseRecipients.cast<String>().map((value) => value.trim()),
        ),
      );
    } on ClassroomException {
      rethrow;
    } on TimeoutException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on SocketException {
      throw const ClassroomException(ClassroomError.invalidState);
    } on FormatException {
      throw const ClassroomException(ClassroomError.malformed);
    } finally {
      client.close(force: true);
    }
  }

  Future<List<GroupAssignment>> _hydrateTeacherAssignments(
    List<GroupAssignment> assignments,
    String teacherId,
  ) async {
    final byId = {
      for (final assignment in assignments) assignment.id: assignment,
    };
    final recipientsByAssignment = <String, Set<String>>{};
    final snapshot = await _firestore
        .collectionGroup(FirestoreCollections.assignmentRecipients)
        .where('teacher_id', isEqualTo: teacherId)
        .get();
    for (final doc in snapshot.docs) {
      final path = doc.reference.path.split('/');
      if (path.length != 4 ||
          path[0] != FirestoreCollections.groupAssignments ||
          path[2] != FirestoreCollections.assignmentRecipients ||
          path[3] != doc.id) {
        continue;
      }
      final id = doc.reference.parent.parent?.id;
      if (id == null) continue;
      final assignment = byId[id];
      final data = doc.data();
      if (assignment != null &&
          _validRecipient(data, assignment, doc.id) &&
          doc.id == data['trainee_id']) {
        recipientsByAssignment.putIfAbsent(id, () => <String>{}).add(doc.id);
      }
    }
    return [
      for (final assignment in assignments)
        if (assignment.audience.isEntireClass)
          assignment
        else if (recipientsByAssignment.containsKey(assignment.id) &&
            (assignment.audience.type !=
                    AssignmentAudienceType.individualStudent ||
                recipientsByAssignment[assignment.id]!.length == 1))
          assignment.copyWith(
            audience: assignment.audience.withRecipientIds(
              recipientsByAssignment[assignment.id]!,
            ),
          ),
    ];
  }

  static bool _validRecipient(
    Map<String, dynamic>? data,
    GroupAssignment assignment,
    String traineeId,
  ) {
    if (data == null || assignment.audience.isEntireClass) return false;
    const keys = {
      'assignment_id',
      'group_id',
      'teacher_id',
      'trainee_id',
      'audience_type',
      'schema_version',
      'created_at',
    };
    return data.length == keys.length &&
        data.keys.toSet().containsAll(keys) &&
        data['assignment_id'] == assignment.id &&
        data['group_id'] == assignment.groupId &&
        data['teacher_id'] == assignment.teacherId &&
        data['trainee_id'] == traineeId &&
        data['audience_type'] == assignment.audience.type.wireValue &&
        data['schema_version'] == 1 &&
        TeacherRosterInvite.readDateTime(data['created_at']) != null;
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
