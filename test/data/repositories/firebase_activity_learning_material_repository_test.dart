import 'package:elixr_application/data/repositories/firebase_activity_learning_material_repository.dart';
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
}
