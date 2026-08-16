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
  }) => _storage
      .ref(pathFor(traineeId: traineeId, sessionId: sessionId))
      .getData(TeacherEvidenceRepository.maximumBytes);
}
