import 'dart:io';
import 'dart:typed_data';

import '../models/assignment_attempt.dart';
import '../models/assignment_submission_limits.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/phase6_submission_diagnostics.dart';
import '../models/ws_protocol.dart';
import 'classroom_assignment_repository.dart';

export '../models/classroom_exceptions.dart' show AssignmentSubmissionException;

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

  Future<SubmissionPlaybackFile?> openLocalPlayback(AssignmentAttempt attempt);

  Future<void> releaseLocalPlayback(SubmissionPlaybackFile? playback);

  Future<void> reconcileExpiredVideos({
    required String actorId,
    required List<AssignmentAttempt> attempts,
    DateTime? now,
  });
}

/// Local file handle for in-app review playback. Never a download URL.
class SubmissionPlaybackFile {
  const SubmissionPlaybackFile({required this.localPath});

  final String localPath;

  Uri get uri => Uri.file(localPath);
}

/// Authenticated Storage download that writes directly to [destination].
///
/// [maxSize] is part of the contract so callers cannot accidentally omit the
/// playback size limit when they switch download implementations.
typedef SubmissionDownloadFile =
    Future<void> Function(
      String path, {
      required File destination,
      required int maxSize,
    });

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

Future<void> releaseSubmissionPlaybackFile(
  SubmissionPlaybackFile? playback,
) async {
  final path = playback?.localPath;
  if (path == null || path.isEmpty) return;
  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } on FileSystemException {
    // Windows may still hold the file until the player releases it.
  }
}

/// Downloads an authenticated clip into an ELIXR review cache file.
///
/// [downloadBytes] must use the signed-in Storage SDK. It must not mint a
/// shareable download URL.
Future<SubmissionPlaybackFile> materializeAuthenticatedSubmissionClip({
  required AssignmentAttempt attempt,
  required Future<Uint8List> Function(String path, {required int maxSize})
  downloadBytes,
  required Directory cacheDirectory,
}) async {
  return materializeAuthenticatedSubmissionClipToFile(
    attempt: attempt,
    cacheDirectory: cacheDirectory,
    downloadFile: (path, {required destination, required maxSize}) async {
      final bytes = await downloadBytes(path, maxSize: maxSize);
      if (bytes.isEmpty || bytes.length > maxSize) {
        throw const AssignmentSubmissionException(
          'The submission clip is empty or larger than the download limit.',
        );
      }
      await destination.writeAsBytes(bytes, flush: true);
    },
  );
}

/// Downloads an authenticated clip straight into an ELIXR review cache file.
///
/// The Firebase Storage Windows SDK has a native file-download path. Using
/// that path avoids allocating a full playback buffer in Dart and gives the
/// native player a completed file only after the download has finished.
Future<SubmissionPlaybackFile> materializeAuthenticatedSubmissionClipToFile({
  required AssignmentAttempt attempt,
  required SubmissionDownloadFile downloadFile,
  required Directory cacheDirectory,
}) async {
  if (!attempt.hasPlayableVideo || attempt.videoExpired) {
    throw const AssignmentSubmissionException(
      'This clip is no longer available.',
    );
  }
  final storagePath = attempt.videoStoragePath;
  if (storagePath == null || storagePath.isEmpty) {
    throw const AssignmentSubmissionException(
      'This clip is no longer available.',
    );
  }
  final local = File(
    '${cacheDirectory.path}${Platform.pathSeparator}review_${attempt.id}.mp4',
  );
  try {
    await cacheDirectory.create(recursive: true);
    await downloadFile(
      storagePath,
      destination: local,
      maxSize: AssignmentSubmissionLimits.maxPlaybackDownloadBytes,
    );
    final size = await local.length();
    if (size <= 0 ||
        size > AssignmentSubmissionLimits.maxPlaybackDownloadBytes) {
      throw const AssignmentSubmissionException(
        'The submission clip is empty or larger than the download limit.',
      );
    }
    return SubmissionPlaybackFile(localPath: local.path);
  } catch (error) {
    try {
      if (await local.exists()) {
        await local.delete();
      }
    } on FileSystemException {
      // Partial cache must not linger after a failed download.
    }
    if (error is AssignmentSubmissionException || error is ClassroomException) {
      rethrow;
    }
    throw const AssignmentSubmissionException(
      'The submission clip could not be downloaded.',
    );
  }
}

Future<AssignmentAttempt> submitLocalClipWithDraftCompensation({
  required String traineeId,
  required GroupAssignment assignment,
  required SubmissionRecordResult clip,
  String? supersedesAttemptId,
  required ClassroomAssignmentRepository classroom,
  required Future<void> Function({
    required AssignmentAttempt draft,
    required String storagePath,
  })
  uploadObject,
  required Future<void> Function(String path) deleteObject,
  required bool Function(Object error) isObjectNotFound,
  required DateTime now,
  Future<void> Function()? deleteLocalFile,
  void Function(String line)? diagnosticLog,
}) async {
  ensureLocalClipWithinLimits(clip);
  late final AssignmentAttempt draft;
  try {
    draft = await classroom.createTeacherReviewSubmissionDraft(
      traineeId: traineeId,
      assignment: assignment,
      supersedesAttemptId: supersedesAttemptId,
    );
  } catch (error) {
    emitPhase6SubmissionDiagnostic(
      stage: Phase6SubmissionStage.createDraft,
      error: error,
      log: diagnosticLog,
    );
    if (error is ClassroomException || error is AssignmentSubmissionException) {
      rethrow;
    }
    throw const ClassroomException(
      ClassroomError.uploadFailed,
      'The submission clip could not be uploaded. Try again.',
    );
  }
  await emitPhase6DurableDraftAnchor(
    draft: draft,
    readAttempt: ({required attemptId}) =>
        classroom.getAttempt(attemptId: attemptId),
    diagnosticLog: diagnosticLog,
  );
  final path = assignmentSubmissionStoragePath(
    teacherId: draft.teacherId,
    groupId: draft.groupId,
    assignmentId: draft.assignmentId,
    traineeId: draft.traineeId,
    attemptId: draft.id,
  );
  var stage = Phase6SubmissionStage.storageUpload;
  try {
    await uploadObject(draft: draft, storagePath: path);
    stage = Phase6SubmissionStage.firestoreSubmit;
    final submitted = await classroom.markTeacherReviewSubmitted(
      traineeId: traineeId,
      attempt: draft,
      videoStoragePath: path,
      videoContentType: AssignmentSubmissionLimits.contentType,
      videoSizeBytes: clip.sizeBytes,
      videoDurationMs: clip.durationMs,
      submittedAt: now,
      videoExpiresAt: unreviewedVideoExpiresAt(now),
    );
    stage = Phase6SubmissionStage.supersededCleanup;
    await deleteSupersededSubmissionVideo(
      actorId: traineeId,
      supersedesAttemptId: supersedesAttemptId,
      classroom: classroom,
      deleteObject: deleteObject,
      isObjectNotFound: isObjectNotFound,
      now: now,
    );
    stage = Phase6SubmissionStage.localCleanup;
    try {
      await deleteLocalFile?.call();
    } catch (error) {
      emitPhase6SubmissionDiagnostic(
        stage: Phase6SubmissionStage.localCleanup,
        error: error,
        log: diagnosticLog,
      );
    }
    return submitted;
  } catch (error) {
    emitPhase6SubmissionDiagnostic(
      stage: stage,
      error: error,
      log: diagnosticLog,
    );
    // Firebase C++ desktop can CREATE the object and still complete the
    // caller Future with unauthorized after the metadata PATCH. Always
    // attempt exactly one canonical-path delete before abandoning.
    await _abandonDraftAfterFailedUpload(
      classroom: classroom,
      traineeId: traineeId,
      draft: draft,
      storagePath: path,
      deleteObject: deleteObject,
      isObjectNotFound: isObjectNotFound,
      now: now,
      diagnosticLog: diagnosticLog,
    );
    if (error is ClassroomException || error is AssignmentSubmissionException) {
      rethrow;
    }
    throw const ClassroomException(
      ClassroomError.uploadFailed,
      'The submission clip could not be uploaded. Try again.',
    );
  }
}

Future<void> _abandonDraftAfterFailedUpload({
  required ClassroomAssignmentRepository classroom,
  required String traineeId,
  required AssignmentAttempt draft,
  required String storagePath,
  required Future<void> Function(String path) deleteObject,
  required bool Function(Object error) isObjectNotFound,
  required DateTime now,
  void Function(String line)? diagnosticLog,
}) async {
  var objectGone = false;
  try {
    await deleteObject(storagePath);
    objectGone = true;
  } catch (deleteError) {
    if (isObjectNotFound(deleteError)) {
      objectGone = true;
    }
  }
  if (objectGone) {
    await _markAbandonedDraftQuietly(
      classroom: classroom,
      traineeId: traineeId,
      draft: draft,
      videoDeletedAt: now,
      diagnosticLog: diagnosticLog,
    );
  } else {
    await _markAbandonedDraftQuietly(
      classroom: classroom,
      traineeId: traineeId,
      draft: draft,
      deletionFailed: true,
      deletionFailedAt: now,
      diagnosticLog: diagnosticLog,
    );
  }
}

Future<void> _markAbandonedDraftQuietly({
  required ClassroomAssignmentRepository classroom,
  required String traineeId,
  required AssignmentAttempt draft,
  DateTime? videoDeletedAt,
  bool deletionFailed = false,
  DateTime? deletionFailedAt,
  void Function(String line)? diagnosticLog,
}) async {
  try {
    await classroom.markTeacherReviewSubmissionAbandoned(
      traineeId: traineeId,
      attempt: draft,
      videoDeletedAt: videoDeletedAt,
      deletionFailed: deletionFailed,
      deletionFailedAt: deletionFailedAt,
    );
  } catch (error) {
    emitPhase6SubmissionDiagnostic(
      stage: Phase6SubmissionStage.abandonCompensation,
      error: error,
      log: diagnosticLog,
    );
    // Leftover draft remains an authorization anchor. Never report submitted.
  }
}

bool abandonedSubmissionNeedsObjectCleanup({
  required AssignmentAttempt attempt,
  required DateTime now,
}) {
  if (!attempt.isAbandonedTeacherReviewDraft) return false;
  if (attempt.videoDeletedAt != null && !attempt.deletionFailed) return false;
  if (attempt.deletionFailed && attempt.deletionFailedAt != null) {
    final elapsed = now.toUtc().difference(attempt.deletionFailedAt!.toUtc());
    if (elapsed < AssignmentSubmissionLimits.deletionRetryCooldown) {
      return false;
    }
  }
  return true;
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
    if (abandonedSubmissionNeedsObjectCleanup(attempt: attempt, now: clock)) {
      final path = assignmentSubmissionStoragePath(
        teacherId: attempt.teacherId,
        groupId: attempt.groupId,
        assignmentId: attempt.assignmentId,
        traineeId: attempt.traineeId,
        attemptId: attempt.id,
      );
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
          // Keep Assigned Movements / Teacher Reviews usable.
        }
      }
      continue;
    }
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
