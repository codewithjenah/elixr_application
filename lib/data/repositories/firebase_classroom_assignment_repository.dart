import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';
import 'package:elixr_core/models/elixr_group.dart';

import '../models/assignment_attempt.dart';
import '../models/assignment_attempt_ids.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
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
    DateTime? dueAt,
  }) async {
    ensureTeacherOwnsActiveGroup(teacherId: teacherId, group: group);
    final payload = teacherCreatedAssignmentPayload(
      teacherId: teacherId,
      teacherDisplayName: teacherDisplayName,
      group: group,
      movement: movement,
      revision: revision,
      dueAt: dueAt,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    );
    final ref = _assignments.doc();
    await ref.set(payload);
    return GroupAssignment.tryFromMap({
          ...payload,
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
    await ref.update({
      'status': GroupAssignmentStatus.archived.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<GroupAssignment?> getAssignment({required String assignmentId}) async {
    final snap = await _assignments.doc(assignmentId).get();
    if (!snap.exists || snap.data() == null) return null;
    return GroupAssignment.tryFromMap(snap.data()!, id: snap.id);
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
    await _attempts.doc(attempt.id).update({
      'status': AssignmentAttemptStatus.submitted.wireValue,
      'video_storage_path': videoStoragePath,
      'video_content_type': videoContentType,
      'video_size_bytes': videoSizeBytes,
      'video_duration_ms': videoDurationMs,
      'submitted_at': FieldValue.serverTimestamp(),
      'video_expires_at': Timestamp.fromDate(videoExpiresAt.toUtc()),
    });
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
    await _attempts.doc(attempt.id).update({
      'deletion_failed': true,
      'deletion_failed_at': FieldValue.serverTimestamp(),
    });
  }

  static bool _isFirestorePermissionDenied(Object error) {
    return error is FirebaseException && error.code == 'permission-denied';
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
