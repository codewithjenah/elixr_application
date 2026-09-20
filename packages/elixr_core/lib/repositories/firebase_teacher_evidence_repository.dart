import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'teacher_evidence_repository.dart';

typedef TeacherEvidenceDownload =
    Future<Uint8List?> Function(String path, int maximumBytes);
typedef TeacherEvidenceAuthRefresh = Future<void> Function();

class FirebaseTeacherEvidenceRepository implements TeacherEvidenceRepository {
  FirebaseTeacherEvidenceRepository({
    FirebaseStorage? storage,
    FirebaseAuth? auth,
    TeacherEvidenceDownload? downloadData,
    TeacherEvidenceAuthRefresh? forceRefreshIdToken,
  }) : _storageOverride = storage,
       _authOverride = auth,
       _downloadData = downloadData,
       _forceRefreshIdToken = forceRefreshIdToken;

  final FirebaseStorage? _storageOverride;
  final FirebaseAuth? _authOverride;
  final TeacherEvidenceDownload? _downloadData;
  final TeacherEvidenceAuthRefresh? _forceRefreshIdToken;

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static String pathFor({
    required String traineeId,
    required String sessionId,
  }) => 'users/$traineeId/session_evidence/$sessionId.jpg';

  @override
  Future<Uint8List?> downloadEvidence({
    required String traineeId,
    required String sessionId,
  }) async {
    final path = pathFor(traineeId: traineeId, sessionId: sessionId);
    try {
      return await _download(path);
    } on FirebaseException catch (error) {
      // A stale/legacy projection is allowed to be uncertain. A missing
      // deterministic object is an expected no-image state, while denied and
      // transient Storage failures must remain visible and retryable.
      if (isObjectNotFound(error)) return null;
      if (!isAuthRetryable(error)) rethrow;

      final injectedRefresh = _forceRefreshIdToken;
      if (injectedRefresh != null) {
        await injectedRefresh();
      } else {
        final user = _auth.currentUser;
        if (user == null) rethrow;
        await user.getIdToken(true);
      }
      debugPrint(
        '[TeacherEvidence] retrying_after_auth_refresh '
        'error_code=${error.code}',
      );

      // Firebase Storage on Windows can briefly retain an older ID token.
      // Retry exactly once after a forced refresh so current Teacher claims
      // are applied without hiding a persistent rules or network failure.
      try {
        return await _download(path);
      } on FirebaseException catch (retryError) {
        if (isObjectNotFound(retryError)) return null;
        debugPrint(
          '[TeacherEvidence] download_failed_after_auth_refresh '
          'error_code=${retryError.code}',
        );
        rethrow;
      }
    }
  }

  Future<Uint8List?> _download(String path) {
    final injected = _downloadData;
    if (injected != null) {
      return injected(path, TeacherEvidenceRepository.maximumBytes);
    }
    return _storage.ref(path).getData(TeacherEvidenceRepository.maximumBytes);
  }

  static bool isObjectNotFound(Object error) =>
      error is FirebaseException && error.code == 'object-not-found';

  static bool isAuthRetryable(Object error) =>
      error is FirebaseException &&
      (error.code == 'unauthorized' ||
          error.code == 'unauthenticated' ||
          error.code == 'permission-denied' ||
          error.code == 'retry-limit-exceeded');
}
