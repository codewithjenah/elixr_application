import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/assignment_attempt.dart';
import '../models/assignment_submission_limits.dart';
import '../models/group_assignment.dart';
import '../models/phase6_submission_diagnostics.dart';
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
    SubmissionDownloadFile? downloadFile,
    Phase6StorageAuthProbe Function()? debugAuthProbe,
    void Function(String line)? diagnosticLog,
  }) : _classroom = classroom,
       _storage = storage ?? FirebaseStorage.instance,
       _reviewCacheDirectory = reviewCacheDirectory,
       _downloadBytes = downloadBytes,
       _downloadFile = downloadFile,
       _debugAuthProbe = debugAuthProbe,
       _diagnosticLog = diagnosticLog;

  final ClassroomAssignmentRepository _classroom;
  final FirebaseStorage _storage;
  final Directory? _reviewCacheDirectory;
  final Future<Uint8List> Function(String path, {required int maxSize})?
  _downloadBytes;
  final SubmissionDownloadFile? _downloadFile;
  final Phase6StorageAuthProbe Function()? _debugAuthProbe;
  final void Function(String line)? _diagnosticLog;

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
      diagnosticLog: _diagnosticLog,
      uploadObject: ({required draft, required storagePath}) async {
        await runPhase6StorageUpload(
          log: _diagnosticLog,
          upload: () async {
            final customMetadata = assignmentSubmissionCustomMetadata(
              teacherId: draft.teacherId,
              groupId: draft.groupId,
              assignmentId: draft.assignmentId,
              traineeId: draft.traineeId,
              attemptId: draft.id,
              movementId: draft.movementId,
              revisionId: draft.revisionId,
            );
            await _emitDebugStorageUploadIntent(
              draft: draft,
              storagePath: storagePath,
              fileSizeBytes: size,
              customMetadata: customMetadata,
            );
            final snapshot = await _storage
                .ref(storagePath)
                .putFile(
                  file,
                  SettableMetadata(
                    contentType: AssignmentSubmissionLimits.contentType,
                    customMetadata: customMetadata,
                  ),
                );
            return snapshot.totalBytes;
          },
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
  Future<AssignmentAttempt> submitCanonicalLocalClip({
    required String traineeId,
    required GroupAssignment assignment,
    required SubmissionRecordResult clip,
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

    return submitCanonicalLocalClipWithCleanup(
      traineeId: traineeId,
      assignment: assignment,
      clip: clip,
      classroom: _classroom,
      now: DateTime.now().toUtc(),
      diagnosticLog: _diagnosticLog,
      uploadObject: ({required draft, required storagePath}) async {
        await runPhase6StorageUpload(
          log: _diagnosticLog,
          upload: () async {
            final customMetadata = assignmentSubmissionCustomMetadata(
              teacherId: draft.teacherId,
              groupId: draft.groupId,
              assignmentId: draft.assignmentId,
              traineeId: draft.traineeId,
              attemptId: draft.id,
              movementId: draft.movementId,
              revisionId: draft.revisionId,
            );
            await _emitDebugStorageUploadIntent(
              draft: draft,
              storagePath: storagePath,
              fileSizeBytes: size,
              customMetadata: customMetadata,
            );
            final snapshot = await _storage
                .ref(storagePath)
                .putFile(
                  file,
                  SettableMetadata(
                    contentType: AssignmentSubmissionLimits.contentType,
                    customMetadata: customMetadata,
                  ),
                );
            return snapshot.totalBytes;
          },
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
  Future<AssignmentAttempt> saveCanonicalLocalClipDraft({
    required String traineeId,
    required GroupAssignment assignment,
    required SubmissionRecordResult clip,
  }) async {
    ensureLocalClipWithinLimits(clip);
    final file = File(clip.localPath);
    if (!file.existsSync() || file.lengthSync() != clip.sizeBytes) {
      throw const AssignmentSubmissionException(
        'The local submission clip is no longer available.',
      );
    }
    final size = file.lengthSync();
    return saveCanonicalLocalClipDraftWithCleanup(
      traineeId: traineeId,
      assignment: assignment,
      clip: clip,
      classroom: _classroom,
      now: DateTime.now().toUtc(),
      uploadObject: ({required draft, required storagePath}) async {
        final metadata = assignmentSubmissionCustomMetadata(
          teacherId: draft.teacherId,
          groupId: draft.groupId,
          assignmentId: draft.assignmentId,
          traineeId: draft.traineeId,
          attemptId: draft.id,
          movementId: draft.movementId,
          revisionId: draft.revisionId,
        );
        await runPhase6StorageUpload(
          log: _diagnosticLog,
          upload: () async {
            await _emitDebugStorageUploadIntent(
              draft: draft,
              storagePath: storagePath,
              fileSizeBytes: size,
              customMetadata: metadata,
            );
            final snapshot = await _storage
                .ref(storagePath)
                .putFile(
                  file,
                  SettableMetadata(
                    contentType: AssignmentSubmissionLimits.contentType,
                    customMetadata: metadata,
                  ),
                );
            return snapshot.totalBytes;
          },
        );
      },
      deleteObject: deleteSubmissionObject,
      isObjectNotFound: _isObjectNotFound,
      deleteLocalFile: () async {
        try {
          await file.delete();
        } on FileSystemException {
          // Backend cancel also removes this temporary file.
        }
      },
    );
  }

  @override
  Future<AssignmentAttempt> submitTeacherActivityAttemptClip({
    required String traineeId,
    required GroupAssignment assignment,
    required AssignmentAttempt attempt,
    required SubmissionRecordResult clip,
  }) async {
    ensureLocalClipWithinLimits(clip);
    if (attempt.traineeId != traineeId ||
        attempt.assignmentId != assignment.id ||
        attempt.activityAssessmentSnapshot == null ||
        attempt.status != AssignmentAttemptStatus.inProgress) {
      throw const AssignmentSubmissionException(
        'This Teacher Activity attempt is no longer available.',
      );
    }
    final file = File(clip.localPath);
    if (!file.existsSync() || file.lengthSync() != clip.sizeBytes) {
      throw const AssignmentSubmissionException(
        'The local submission clip is no longer available.',
      );
    }
    final storagePath = assignmentSubmissionStoragePath(
      teacherId: attempt.teacherId,
      groupId: attempt.groupId,
      assignmentId: attempt.assignmentId,
      traineeId: attempt.traineeId,
      attemptId: attempt.id,
    );
    final metadata = assignmentSubmissionCustomMetadata(
      teacherId: attempt.teacherId,
      groupId: attempt.groupId,
      assignmentId: attempt.assignmentId,
      traineeId: attempt.traineeId,
      attemptId: attempt.id,
      movementId: attempt.movementId,
      revisionId: attempt.revisionId,
    );
    await _storage
        .ref(storagePath)
        .putFile(
          file,
          SettableMetadata(
            contentType: AssignmentSubmissionLimits.contentType,
            customMetadata: metadata,
          ),
        );
    final submittedAt = DateTime.now().toUtc();
    try {
      final submitted = await _classroom.markTeacherReviewSubmitted(
        traineeId: traineeId,
        attempt: attempt,
        videoStoragePath: storagePath,
        videoContentType: clip.contentType,
        videoSizeBytes: clip.sizeBytes,
        videoDurationMs: clip.durationMs,
        submittedAt: submittedAt,
        videoExpiresAt: unreviewedVideoExpiresAt(submittedAt),
      );
      try {
        await file.delete();
      } on FileSystemException {
        // Backend orphan cleanup remains the deterministic fallback.
      }
      return submitted;
    } catch (_) {
      // Keep the uploaded object and the same attempt identity. A retry is
      // idempotent at the path and can complete the Firestore transition.
      rethrow;
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
  Future<SubmissionPlaybackFile?> openLocalPlayback(
    AssignmentAttempt attempt,
  ) async {
    if (!attempt.hasPlayableVideo ||
        attempt.videoExpired ||
        attempt.isUnsubmitting) {
      return null;
    }
    final path = attempt.videoStoragePath;
    if (path == null || path.isEmpty) return null;
    final cacheDirectory =
        _reviewCacheDirectory ?? _defaultReviewCacheDirectory();
    final downloadBytes = _downloadBytes;
    if (downloadBytes != null) {
      return materializeAuthenticatedSubmissionClip(
        attempt: attempt,
        downloadBytes: downloadBytes,
        cacheDirectory: cacheDirectory,
      );
    }
    return materializeAuthenticatedSubmissionClipToFile(
      attempt: attempt,
      downloadFile: _downloadFile ?? _downloadAuthenticatedFile,
      cacheDirectory: cacheDirectory,
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

  Future<void> _downloadAuthenticatedFile(
    String storagePath, {
    required File destination,
    required int maxSize,
  }) async {
    try {
      await _storage.ref(storagePath).writeToFile(destination);
    } on FirebaseException catch (error) {
      if (!_canRetryAfterAuthRefresh(error)) rethrow;
      final refreshToken = _captureDebugAuthProbe().forceRefreshIdToken;
      if (refreshToken == null) rethrow;
      (_diagnosticLog ?? phase6SubmissionDefaultLog)(
        '[Phase6StoragePlayback] retrying_after_auth_refresh '
        'error_code=${error.code}',
      );
      await refreshToken();
      await _storage.ref(storagePath).writeToFile(destination);
    }
    if (await destination.length() > maxSize) {
      throw const AssignmentSubmissionException(
        'The submission clip is empty or larger than the download limit.',
      );
    }
  }

  bool _canRetryAfterAuthRefresh(FirebaseException error) {
    return error.code == 'unauthorized' ||
        error.code == 'unauthenticated' ||
        error.code == 'retry-limit-exceeded';
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

  Future<void> _emitDebugStorageUploadIntent({
    required AssignmentAttempt draft,
    required String storagePath,
    required int fileSizeBytes,
    required Map<String, String> customMetadata,
  }) async {
    if (!kDebugMode) return;
    String? projectId;
    String? bucket;
    try {
      projectId = _storage.app.options.projectId;
      bucket = _storage.bucket;
    } catch (error) {
      (_diagnosticLog ?? phase6SubmissionDefaultLog)(
        '[Phase6StorageRequest] context_capture_failed '
        'error_type=${error.runtimeType}',
      );
    }
    final auth = _captureDebugAuthProbe();
    await runPhase6DebugPreUploadProbes(
      request: Phase6StorageRequestSnapshot(
        authUid: auth.uid,
        projectId: projectId,
        bucket: bucket,
        attemptId: draft.id,
        teacherId: draft.teacherId,
        groupId: draft.groupId,
        assignmentId: draft.assignmentId,
        traineeId: draft.traineeId,
        movementId: draft.movementId,
        revisionId: draft.revisionId,
        storagePath: storagePath,
        fileSizeBytes: fileSizeBytes,
        contentType: AssignmentSubmissionLimits.contentType,
        metadataKeys: customMetadata.keys.toList(),
      ),
      auth: auth,
      log: _diagnosticLog,
    );
  }

  Phase6StorageAuthProbe _captureDebugAuthProbe() {
    final injected = _debugAuthProbe;
    if (injected != null) return injected();
    try {
      final user = FirebaseAuth.instance.currentUser;
      return Phase6StorageAuthProbe(
        uid: user?.uid,
        forceRefreshIdToken: user == null
            ? null
            : () async {
                await user.getIdToken(true);
              },
      );
    } catch (error) {
      (_diagnosticLog ?? phase6SubmissionDefaultLog)(
        '[Phase6StorageAuth] uid=null capture_failed '
        'error_type=${error.runtimeType}',
      );
      return const Phase6StorageAuthProbe(uid: null);
    }
  }
}
