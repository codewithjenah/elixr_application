import '../models/assignment_attempt.dart';
import '../models/assignment_submission_limits.dart';
import '../models/group_assignment.dart';
import '../models/ws_protocol.dart';
import 'classroom_assignment_repository.dart';

/// Classroom video submissions. Separate from session-evidence JPEGs.
///
/// Never writes `sessions`, leaderboard markers, or XP.
abstract class AssignmentSubmissionRepository {
  Future<AssignmentAttempt> submitLocalClip({
    required String traineeId,
    required GroupAssignment assignment,
    required SubmissionRecordResult clip,
    String? supersedesAttemptId,
  });

  Future<void> deleteSubmissionObject(String storagePath);

  Future<Uri?> playableUri(AssignmentAttempt attempt);

  Future<void> reconcileExpiredVideos({
    required String actorId,
    required List<AssignmentAttempt> attempts,
    DateTime? now,
  });
}

class AssignmentSubmissionException implements Exception {
  const AssignmentSubmissionException(this.message);

  final String message;

  @override
  String toString() => message;
}

void ensureLocalClipWithinLimits(SubmissionRecordResult clip) {
  if (clip.contentType != AssignmentSubmissionLimits.contentType) {
    throw const AssignmentSubmissionException(
      'Only MP4 submission clips can be uploaded.',
    );
  }
  if (clip.sizeBytes <= 0 ||
      clip.sizeBytes > AssignmentSubmissionLimits.maxSizeBytes) {
    throw const AssignmentSubmissionException(
      'The submission clip is empty or larger than the 15 MiB limit.',
    );
  }
  if (clip.durationMs <= 0 ||
      clip.durationMs > AssignmentSubmissionLimits.maxDurationMs) {
    throw const AssignmentSubmissionException(
      'The submission clip is empty or longer than 20 seconds.',
    );
  }
  if (clip.localPath.trim().isEmpty) {
    throw const AssignmentSubmissionException(
      'The local submission clip is missing.',
    );
  }
}

bool submissionVideoIsDueForDeletion({
  required AssignmentAttempt attempt,
  required DateTime now,
}) {
  if (!attempt.isTeacherReviewSubmission) return false;
  final path = attempt.videoStoragePath;
  if (path == null || path.isEmpty) return false;
  final expires = attempt.videoExpiresAt;
  if (expires == null) return false;
  if (now.toUtc().isBefore(expires.toUtc())) return false;
  if (attempt.deletionFailed && attempt.deletionFailedAt != null) {
    final elapsed = now.toUtc().difference(attempt.deletionFailedAt!.toUtc());
    if (elapsed < AssignmentSubmissionLimits.deletionRetryCooldown) {
      return false;
    }
  }
  return true;
}

Future<void> reconcileExpiredSubmissionVideos({
  required String actorId,
  required List<AssignmentAttempt> attempts,
  required ClassroomAssignmentRepository classroom,
  required Future<void> Function(String path) deleteObject,
  required bool Function(Object error) isObjectNotFound,
  DateTime? now,
}) async {
  final clock = (now ?? DateTime.now()).toUtc();
  for (final attempt in attempts) {
    if (!submissionVideoIsDueForDeletion(attempt: attempt, now: clock)) {
      continue;
    }
    final path = attempt.videoStoragePath!;
    try {
      await deleteObject(path);
      await classroom.markSubmissionVideoDeleted(
        actorId: actorId,
        attempt: attempt,
        deletedAt: clock,
      );
    } catch (error) {
      if (isObjectNotFound(error)) {
        await classroom.markSubmissionVideoDeleted(
          actorId: actorId,
          attempt: attempt,
          deletedAt: clock,
        );
        continue;
      }
      try {
        await classroom.markSubmissionDeletionFailed(
          actorId: actorId,
          attempt: attempt,
          failedAt: clock,
        );
      } catch (_) {
        // Keep the review queue usable if metadata marking also fails.
      }
    }
  }
}

Future<void> deleteSupersededSubmissionVideo({
  required String actorId,
  required String? supersedesAttemptId,
  required ClassroomAssignmentRepository classroom,
  required Future<void> Function(String path) deleteObject,
  required bool Function(Object error) isObjectNotFound,
  DateTime? now,
}) async {
  final previousId = supersedesAttemptId?.trim();
  if (previousId == null || previousId.isEmpty) return;
  final previous = await classroom.getAttempt(attemptId: previousId);
  if (previous == null) return;
  final path = previous.videoStoragePath;
  if (path == null || path.isEmpty) return;
  final clock = (now ?? DateTime.now()).toUtc();
  try {
    await deleteObject(path);
    await classroom.markSubmissionVideoDeleted(
      actorId: actorId,
      attempt: previous,
      deletedAt: clock,
    );
  } catch (error) {
    if (isObjectNotFound(error)) {
      await classroom.markSubmissionVideoDeleted(
        actorId: actorId,
        attempt: previous,
        deletedAt: clock,
      );
      return;
    }
    await classroom.markSubmissionDeletionFailed(
      actorId: actorId,
      attempt: previous,
      failedAt: clock,
    );
  }
}
