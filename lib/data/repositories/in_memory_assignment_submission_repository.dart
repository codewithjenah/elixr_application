import 'dart:io';
import 'dart:typed_data';

import '../models/assignment_attempt.dart';
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
    this.failNextUpload = false,
    this.missingPaths = const {},
    this.reviewCacheDirectory,
    this.downloadedPaths,
    this.diagnosticLog,
    this.uploadException,
    Uint8List? playbackBytes,
  }) : _classroom = classroom,
       _now = now,
       _playbackBytes = playbackBytes;

  final ClassroomAssignmentRepository _classroom;
  final DateTime Function()? _now;
  final Set<String>? deletedPaths;
  bool failNextDelete;
  bool failNextUpload;
  final Set<String> missingPaths;
  final Directory? reviewCacheDirectory;
  final Set<String>? downloadedPaths;
  final void Function(String line)? diagnosticLog;
  Object? uploadException;
  final Uint8List? _playbackBytes;

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  @override
  Future<AssignmentAttempt> submitLocalClip({
    required String traineeId,
    required GroupAssignment assignment,
    required SubmissionRecordResult clip,
    String? supersedesAttemptId,
  }) {
    return submitLocalClipWithDraftCompensation(
      traineeId: traineeId,
      assignment: assignment,
      clip: clip,
      supersedesAttemptId: supersedesAttemptId,
      classroom: _classroom,
      now: now,
      diagnosticLog: diagnosticLog,
      uploadObject: ({required draft, required storagePath}) async {
        if (uploadException != null) {
          final error = uploadException!;
          uploadException = null;
          throw error;
        }
        if (failNextUpload) {
          failNextUpload = false;
          throw const AssignmentSubmissionException('storage upload failed');
        }
      },
      deleteObject: deleteSubmissionObject,
      isObjectNotFound: _isMissing,
    );
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
  Future<SubmissionPlaybackFile?> openLocalPlayback(
    AssignmentAttempt attempt,
  ) async {
    if (!attempt.hasPlayableVideo || attempt.videoExpired) return null;
    final path = attempt.videoStoragePath;
    if (path == null || path.isEmpty) return null;
    downloadedPaths?.add(path);
    final cache =
        reviewCacheDirectory ??
        Directory.systemTemp.createTempSync('elixr_review_cache');
    return materializeAuthenticatedSubmissionClip(
      attempt: attempt,
      cacheDirectory: cache,
      downloadBytes: (storagePath, {required maxSize}) async {
        if (storagePath.contains('://')) {
          throw const AssignmentSubmissionException(
            'Playback must not use a download URL.',
          );
        }
        return _playbackBytes ?? Uint8List.fromList(const [0, 0, 0, 1]);
      },
    );
  }

  @override
  Future<void> releaseLocalPlayback(SubmissionPlaybackFile? playback) {
    return releaseSubmissionPlaybackFile(playback);
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
