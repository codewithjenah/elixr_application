import 'package:elixr_application/data/repositories/firebase_activity_learning_material_repository.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'managed cache filenames cannot be influenced by paths or display names',
    () {
      final filename = activityLearningMaterialCacheFileName(
        materialId: '../teacher/safety.pdf',
        extension: 'pdf',
      );

      expect(filename, 'material____teacher_safety_pdf.pdf');
      expect(filename.contains('/'), isFalse);
      expect(filename.contains('\\'), isFalse);
    },
  );

  test('only stale managed cache entries are eligible for cleanup', () {
    final now = DateTime.utc(2026, 9, 4);

    expect(
      isManagedActivityLearningMaterialCacheFile('material_safe-id.pdf'),
      isTrue,
    );
    expect(
      isManagedActivityLearningMaterialCacheFile('user-notes.pdf'),
      isFalse,
    );
    expect(
      isStaleActivityLearningMaterialCacheEntry(
        lastModified: now.subtract(const Duration(days: 8)),
        now: now,
      ),
      isTrue,
    );
    expect(
      isStaleActivityLearningMaterialCacheEntry(
        lastModified: now.subtract(const Duration(days: 7)),
        now: now,
      ),
      isFalse,
    );
  });

  test('non-JSON Function failures retain a safe endpoint diagnostic', () {
    final error = activityLearningMaterialFunctionFailure(
      503,
      '<html>gateway detail that must not reach the UI</html>',
      receivedNonJson: true,
    );

    expect(error.code, ClassroomError.endpointUnavailable);
    expect(error.httpStatus, 503);
    expect(error.serverCode, 'non_json_function_response');
    expect(error.message, isNull);
  });

  test('structured Function failures preserve authorization and conflict', () {
    expect(
      activityLearningMaterialFunctionFailure(403, {
        'error': 'forbidden',
      }, receivedNonJson: false).code,
      ClassroomError.forbidden,
    );
    expect(
      activityLearningMaterialFunctionFailure(409, {
        'error': 'material_limit',
      }, receivedNonJson: false).code,
      ClassroomError.conflict,
    );
  });
}
