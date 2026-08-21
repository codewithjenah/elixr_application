import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../models/assignment_attempt.dart';
import '../models/assignment_submission_limits.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/ws_protocol.dart';
import 'assignment_submission_repository.dart';
import 'classroom_assignment_repository.dart';

class FirebaseAssignmentSubmissionRepository
    implements AssignmentSubmissionRepository {
  FirebaseAssignmentSubmissionRepository({
    required ClassroomAssignmentRepository classroom,
    FirebaseStorage? storage,
  }) : _classroom = classroom,
       _storage = storage ?? FirebaseStorage.instance;

  final ClassroomAssignmentRepository _classroom;
  final FirebaseStorage _storage;

  @override
  Future<AssignmentAttempt> submitLocalClip({
    required String traineeId,
    required GroupAssignment assignment,
    required SubmissionRecordResult clip,
    String? supersedesAttemptId,
  }) async {
    ensureLocalClipWithinLimits(clip);
    final file = File(clip.localPath);
    if (!file.existsSync()) {
      throw const AssignmentSubmissionException(
        'The local submission clip is no longer available.',
      );
    }
    final size = file.lengthSync();
    if (size != clip.sizeBytes) {
      throw const AssignmentSubmissionException(
        'The local submission clip changed before upload.',
      );
    }

    final now = DateTime.now().toUtc();
    final draft = await _classroom.createTeacherReviewSubmissionDraft(
      traineeId: traineeId,
      assignment: assignment,
      supersedesAttemptId: supersedesAttemptId,
    );
    final path = assignmentSubmissionStoragePath(
      teacherId: draft.teacherId,
      groupId: draft.groupId,
      assignmentId: draft.assignmentId,
      traineeId: draft.traineeId,
      attemptId: draft.id,
    );
    final ref = _storage.ref(path);
    var uploaded = false;
    try {
      await ref.putFile(
        file,
        SettableMetadata(
          contentType: AssignmentSubmissionLimits.contentType,
          customMetadata: assignmentSubmissionCustomMetadata(
            teacherId: draft.teacherId,
            groupId: draft.groupId,
            assignmentId: draft.assignmentId,
            traineeId: draft.traineeId,
            attemptId: draft.id,
            movementId: draft.movementId,
            revisionId: draft.revisionId,
          ),
        ),
      );
      uploaded = true;
      final submitted = await _classroom.markTeacherReviewSubmitted(
        traineeId: traineeId,
        attempt: draft,
        videoStoragePath: path,
        videoContentType: AssignmentSubmissionLimits.contentType,
        videoSizeBytes: clip.sizeBytes,
        videoDurationMs: clip.durationMs,
        submittedAt: now,
        videoExpiresAt: unreviewedVideoExpiresAt(now),
      );
      await deleteSupersededSubmissionVideo(
        actorId: traineeId,
        supersedesAttemptId: supersedesAttemptId,
        classroom: _classroom,
        deleteObject: deleteSubmissionObject,
        isObjectNotFound: _isObjectNotFound,
        now: now,
      );
      try {
        await file.delete();
      } on FileSystemException {
        // Backend cancel also deletes the temp clip.
      }
      return submitted;
    } catch (error) {
      if (uploaded) {
        try {
          await deleteSubmissionObject(path);
        } catch (_) {
          // Compensation best-effort; do not report success.
        }
      }
      if (error is ClassroomException ||
          error is AssignmentSubmissionException) {
        rethrow;
      }
      throw const ClassroomException(
        ClassroomError.uploadFailed,
        'The submission clip could not be uploaded. Try again.',
      );
    }
  }

  @override
  Future<void> deleteSubmissionObject(String storagePath) async {
    try {
      await _storage.ref(storagePath).delete();
    } on FirebaseException catch (error) {
      if (!_isObjectNotFound(error)) rethrow;
    }
  }

  @override
  Future<Uri?> playableUri(AssignmentAttempt attempt) async {
    if (!attempt.hasPlayableVideo || attempt.videoExpired) return null;
    final path = attempt.videoStoragePath;
    if (path == null || path.isEmpty) return null;
    final url = await _storage.ref(path).getDownloadURL();
    return Uri.parse(url);
  }

  @override
  Future<void> reconcileExpiredVideos({
    required String actorId,
    required List<AssignmentAttempt> attempts,
    DateTime? now,
  }) {
    return reconcileExpiredSubmissionVideos(
      actorId: actorId,
      attempts: attempts,
      classroom: _classroom,
      deleteObject: deleteSubmissionObject,
      isObjectNotFound: _isObjectNotFound,
      now: now,
    );
  }

  bool _isObjectNotFound(Object error) {
    return error is FirebaseException && error.code == 'object-not-found';
  }
}
