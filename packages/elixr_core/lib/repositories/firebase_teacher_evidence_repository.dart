import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import 'teacher_evidence_repository.dart';

class FirebaseTeacherEvidenceRepository implements TeacherEvidenceRepository {
  FirebaseTeacherEvidenceRepository({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  static String pathFor({
    required String traineeId,
    required String sessionId,
  }) => 'users/$traineeId/session_evidence/$sessionId.jpg';

  @override
  Future<Uint8List?> downloadEvidence({
    required String traineeId,
    required String sessionId,
  }) async {
    try {
      return await _storage
          .ref(pathFor(traineeId: traineeId, sessionId: sessionId))
          .getData(TeacherEvidenceRepository.maximumBytes);
    } on FirebaseException catch (error) {
      // A stale/legacy projection is allowed to be uncertain. A missing
      // deterministic object is an expected no-image state, while denied and
      // transient Storage failures must remain visible and retryable.
      if (isObjectNotFound(error)) return null;
      rethrow;
    }
  }

  static bool isObjectNotFound(Object error) =>
      error is FirebaseException && error.code == 'object-not-found';
}
