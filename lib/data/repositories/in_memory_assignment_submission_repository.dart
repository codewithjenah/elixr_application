import '../models/assignment_attempt.dart';
import '../models/assignment_submission_limits.dart';
import '../models/group_assignment.dart';
import '../models/ws_protocol.dart';
import 'assignment_submission_repository.dart';
import 'classroom_assignment_repository.dart';

class InMemoryAssignmentSubmissionRepository
    implements AssignmentSubmissionRepository {
  InMemoryAssignmentSubmissionRepository({
    required ClassroomAssignmentRepository classroom,
    DateTime Function()? now,
    this.deletedPaths,
    this.failNextDelete = false,
    this.missingPaths = const {},
  }) : _classroom = classroom,
       _now = now;

  final ClassroomAssignmentRepository _classroom;
  final DateTime Function()? _now;
  final Set<String>? deletedPaths;
  bool failNextDelete;
  final Set<String> missingPaths;

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  @override
  Future<AssignmentAttempt> submitLocalClip({
    required String traineeId,
    required GroupAssignment assignment,
    required SubmissionRecordResult clip,
    String? supersedesAttemptId,
  }) async {
    ensureLocalClipWithinLimits(clip);
    final submittedAt = now;
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
    final submitted = await _classroom.markTeacherReviewSubmitted(
      traineeId: traineeId,
      attempt: draft,
      videoStoragePath: path,
      videoContentType: AssignmentSubmissionLimits.contentType,
      videoSizeBytes: clip.sizeBytes,
      videoDurationMs: clip.durationMs,
      submittedAt: submittedAt,
      videoExpiresAt: unreviewedVideoExpiresAt(submittedAt),
    );
    await deleteSupersededSubmissionVideo(
      actorId: traineeId,
      supersedesAttemptId: supersedesAttemptId,
      classroom: _classroom,
      deleteObject: deleteSubmissionObject,
      isObjectNotFound: _isMissing,
      now: submittedAt,
    );
    return submitted;
  }

  @override
  Future<void> deleteSubmissionObject(String storagePath) async {
    if (failNextDelete) {
      failNextDelete = false;
      throw const AssignmentSubmissionException('storage delete failed');
    }
    if (missingPaths.contains(storagePath)) {
      throw const AssignmentSubmissionException('object-not-found');
    }
    deletedPaths?.add(storagePath);
  }

  @override
  Future<Uri?> playableUri(AssignmentAttempt attempt) async {
    if (!attempt.hasPlayableVideo || attempt.videoExpired) return null;
    final path = attempt.videoStoragePath;
    if (path == null) return null;
    return Uri.parse('memory://$path');
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
      isObjectNotFound: _isMissing,
      now: now ?? this.now,
    );
  }

  bool _isMissing(Object error) {
    return error is AssignmentSubmissionException &&
        error.message == 'object-not-found';
  }
}
