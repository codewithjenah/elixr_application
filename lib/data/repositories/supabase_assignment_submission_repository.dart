import 'dart:io';

import 'package:elixr_core/database/supabase_support.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, StorageException, SupabaseClient;

import '../models/assignment_attempt.dart';
import '../models/assignment_submission_limits.dart';
import '../models/classroom_exceptions.dart';
import '../models/group_assignment.dart';
import '../models/phase6_submission_diagnostics.dart';
import '../models/ws_protocol.dart';
import 'assignment_submission_repository.dart';
import 'classroom_assignment_repository.dart';

class SupabaseAssignmentSubmissionRepository
    implements AssignmentSubmissionRepository {
  SupabaseAssignmentSubmissionRepository({
    required ClassroomAssignmentRepository classroom,
    SupabaseClient? client,
    Directory? reviewCacheDirectory,
    Future<Uint8List> Function(String path, {required int maxSize})?
    downloadBytes,
    SubmissionDownloadFile? downloadFile,
    Phase6StorageAuthProbe Function()? debugAuthProbe,
    void Function(String line)? diagnosticLog,
  }) : _classroom = classroom,
       _clientOverride = client,
       _reviewCacheDirectory = reviewCacheDirectory,
       _downloadBytes = downloadBytes,
       _downloadFile = downloadFile,
       _debugAuthProbe = debugAuthProbe,
       _diagnosticLog = diagnosticLog;

  static const _bucket = 'assignment-submissions';

  final ClassroomAssignmentRepository _classroom;
  final SupabaseClient? _clientOverride;
  final Directory? _reviewCacheDirectory;
  final Future<Uint8List> Function(String path, {required int maxSize})?
  _downloadBytes;
  final SubmissionDownloadFile? _downloadFile;
  final Phase6StorageAuthProbe Function()? _debugAuthProbe;
  final void Function(String line)? _diagnosticLog;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  Future<int> _putClip({
    required File file,
    required String storagePath,
    required int size,
    required Map<String, String> customMetadata,
  }) async {
    await _client.storage
        .from(_bucket)
        .upload(
          storagePath,
          file,
          fileOptions: FileOptions(
            contentType: AssignmentSubmissionLimits.contentType,
            metadata: customMetadata,
          ),
        );
    return size;
  }

  Future<void> Function({
    required AssignmentAttempt draft,
    required String storagePath,
  })
  _uploader(File file, int size) {
    return ({required draft, required storagePath}) async {
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
          return _putClip(
            file: file,
            storagePath: storagePath,
            size: size,
            customMetadata: customMetadata,
          );
        },
      );
    };
  }

  File _requireUnchangedClip(SubmissionRecordResult clip) {
    ensureLocalClipWithinLimits(clip);
    final file = File(clip.localPath);
    if (!file.existsSync()) {
      throw const AssignmentSubmissionException(
        'The local submission clip is no longer available.',
      );
    }
    if (file.lengthSync() != clip.sizeBytes) {
      throw const AssignmentSubmissionException(
        'The local submission clip changed before upload.',
      );
    }
    return file;
  }

  Future<void> Function() _localDeleter(File file) => () async {
    try {
      await file.delete();
    } on FileSystemException {
      // Backend cancel also deletes the temp clip.
    }
  };

  @override
  Future<AssignmentAttempt> submitLocalClip({
    required String traineeId,
    required GroupAssignment assignment,
    required SubmissionRecordResult clip,
    String? supersedesAttemptId,
  }) async {
    final file = _requireUnchangedClip(clip);
    return submitLocalClipWithDraftCompensation(
      traineeId: traineeId,
      assignment: assignment,
      clip: clip,
      supersedesAttemptId: supersedesAttemptId,
      classroom: _classroom,
      now: DateTime.now().toUtc(),
      diagnosticLog: _diagnosticLog,
      uploadObject: _uploader(file, clip.sizeBytes),
      deleteObject: deleteSubmissionObject,
      isObjectNotFound: isStorageObjectNotFound,
      deleteLocalFile: _localDeleter(file),
    );
  }

  @override
  Future<AssignmentAttempt> submitCanonicalLocalClip({
    required String traineeId,
    required GroupAssignment assignment,
    required SubmissionRecordResult clip,
  }) async {
    final file = _requireUnchangedClip(clip);
    return submitCanonicalLocalClipWithCleanup(
      traineeId: traineeId,
      assignment: assignment,
      clip: clip,
      classroom: _classroom,
      now: DateTime.now().toUtc(),
      diagnosticLog: _diagnosticLog,
      uploadObject: _uploader(file, clip.sizeBytes),
      deleteObject: deleteSubmissionObject,
      isObjectNotFound: isStorageObjectNotFound,
      deleteLocalFile: _localDeleter(file),
    );
  }

  @override
  Future<AssignmentAttempt> saveCanonicalLocalClipDraft({
    required String traineeId,
    required GroupAssignment assignment,
    required SubmissionRecordResult clip,
  }) async {
    final file = _requireUnchangedClip(clip);
    return saveCanonicalLocalClipDraftWithCleanup(
      traineeId: traineeId,
      assignment: assignment,
      clip: clip,
      classroom: _classroom,
      now: DateTime.now().toUtc(),
      uploadObject: _uploader(file, clip.sizeBytes),
      deleteObject: deleteSubmissionObject,
      isObjectNotFound: isStorageObjectNotFound,
      deleteLocalFile: _localDeleter(file),
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
    try {
      await _putClip(
        file: file,
        storagePath: storagePath,
        size: clip.sizeBytes,
        customMetadata: metadata,
      );
    } on StorageException catch (error) {
      // A retry after an ambiguous failure finds the deterministic object
      // already present; the server finalize verifies its size and type.
      if (error.statusCode != '409') rethrow;
    }
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
    } catch (error) {
      final terminalServerCode = error is ClassroomException
          ? error.serverCode
          : null;
      if ({
        'attempt_conflict',
        'deadline_passed',
        'forbidden',
        'upload_mismatch',
        'upload_missing',
      }.contains(terminalServerCode)) {
        try {
          await _client.storage.from(_bucket).remove([storagePath]);
        } on StorageException {
          // Never replace the server's deliberate error code with a
          // best-effort client cleanup failure.
        }
      }
      // Ambiguous failures keep the deterministic object and attempt identity
      // so retry can safely finish the same server transition.
      rethrow;
    }
  }

  @override
  Future<void> deleteSubmissionObject(String storagePath) async {
    // Storage removal of an absent object succeeds with an empty result.
    try {
      await _client.storage.from(_bucket).remove([storagePath]);
    } on StorageException catch (error) {
      if (!isStorageObjectNotFound(error)) rethrow;
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
      isObjectNotFound: isStorageObjectNotFound,
      now: now,
    );
  }

  Future<void> _downloadAuthenticatedFile(
    String storagePath, {
    required File destination,
    required int maxSize,
  }) async {
    final bytes = await _client.storage.from(_bucket).download(storagePath);
    if (bytes.isEmpty || bytes.length > maxSize) {
      throw const AssignmentSubmissionException(
        'The submission clip is empty or larger than the download limit.',
      );
    }
    await destination.writeAsBytes(bytes, flush: true);
  }

  Directory _defaultReviewCacheDirectory() {
    return Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      '${AssignmentSubmissionLimits.reviewCacheDirname}',
    );
  }

  Future<void> _emitDebugStorageUploadIntent({
    required AssignmentAttempt draft,
    required String storagePath,
    required int fileSizeBytes,
    required Map<String, String> customMetadata,
  }) async {
    if (!kDebugMode) return;
    final auth = _captureDebugAuthProbe();
    await runPhase6DebugPreUploadProbes(
      request: Phase6StorageRequestSnapshot(
        authUid: auth.uid,
        projectId: null,
        bucket: _bucket,
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
      final auth = _client.auth;
      final user = auth.currentUser;
      return Phase6StorageAuthProbe(
        uid: user?.id,
        forceRefreshIdToken: user == null
            ? null
            : () async {
                await auth.refreshSession();
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
