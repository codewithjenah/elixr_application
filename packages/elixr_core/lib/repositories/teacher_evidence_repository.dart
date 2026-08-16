import 'dart:typed_data';

abstract class TeacherEvidenceRepository {
  static const maximumBytes = 256 * 1024;

  Future<Uint8List?> downloadEvidence({
    required String traineeId,
    required String sessionId,
  });
}
