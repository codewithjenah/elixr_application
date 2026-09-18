import 'package:elixr_core/repositories/firebase_teacher_evidence_repository.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes only Storage object-not-found as an unavailable image', () {
    expect(
      FirebaseTeacherEvidenceRepository.isObjectNotFound(
        FirebaseException(plugin: 'firebase_storage', code: 'object-not-found'),
      ),
      isTrue,
    );
    expect(
      FirebaseTeacherEvidenceRepository.isObjectNotFound(
        FirebaseException(
          plugin: 'firebase_storage',
          code: 'permission-denied',
        ),
      ),
      isFalse,
    );
  });
}
