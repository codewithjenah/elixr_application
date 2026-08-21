import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../models/assignment_attempt.dart';
import '../models/assignment_submission_limits.dart';
import '../models/group_assignment.dart';
import '../models/ws_protocol.dart';
import 'assignment_submission_repository.dart';
import 'classroom_assignment_repository.dart';

class FirebaseAssignmentSubmissionRepository
    implements AssignmentSubmissionRepository {
  FirebaseAssignmentSubmissionRepository({
    required ClassroomAssignmentRepository classroom,
    FirebaseStorage? storage,
    Directory? reviewCacheDirectory,
    Future<Uint8List> Function(String path, {required int maxSize})?
    downloadBytes,
  }) : _classroom = classroom,
       _storage = storage ?? FirebaseStorage.instance,
       _reviewCacheDirectory = reviewCacheDirectory,
       _downloadBytes = downloadBytes;

  final ClassroomAssignmentRepository _classroom;
  final FirebaseStorage _storage;
  final Directory? _reviewCacheDirectory;
  final Future<Uint8List> Function(String path, {required int maxSize})?
  _downloadBytes;

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

    return submitLocalClipWithDraftCompensation(
      traineeId: traineeId,
      assignment: assignment,
      clip: clip,
      supersedesAttemptId: supersedesAttemptId,
      classroom: _classroom,
      now: DateTime.now().toUtc(),
      uploadObject: ({required draft, required storagePath}) async {
        await _storage
            .ref(storagePath)
            .putFile(
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
      },
      deleteObject: deleteSubmissionObject,
      isObjectNotFound: _isObjectNotFound,
      deleteLocalFile: () async {
        try {
          await file.delete();
        } on FileSystemException {
          // Backend cancel also deletes the temp clip.
        }
      },
    );
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
  Future<SubmissionPlaybackFile?> openLocalPlayback(
    AssignmentAttempt attempt,
  ) async {
    if (!attempt.hasPlayableVideo || attempt.videoExpired) return null;
    final path = attempt.videoStoragePath;
    if (path == null || path.isEmpty) return null;
    return materializeAuthenticatedSubmissionClip(
      attempt: attempt,
      downloadBytes: _downloadBytes ?? _getAuthenticatedBytes,
      cacheDirectory: _reviewCacheDirectory ?? _defaultReviewCacheDirectory(),
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
      isObjectNotFound: _isObjectNotFound,
      now: now,
    );
  }

  Future<Uint8List> _getAuthenticatedBytes(
    String storagePath, {
    required int maxSize,
  }) async {
    final data = await _storage.ref(storagePath).getData(maxSize);
    if (data == null || data.isEmpty) {
      throw const AssignmentSubmissionException(
        'The submission clip could not be downloaded.',
      );
    }
    return data;
  }

  Directory _defaultReviewCacheDirectory() {
    return Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      '${AssignmentSubmissionLimits.reviewCacheDirname}',
    );
  }

  bool _isObjectNotFound(Object error) {
    return error is FirebaseException && error.code == 'object-not-found';
  }
}
