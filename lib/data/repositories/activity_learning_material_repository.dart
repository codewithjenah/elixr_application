import 'dart:io';

import '../models/activity_learning_material.dart';

abstract class ActivityLearningMaterialRepository {
  Future<ActivityMaterialUpload> beginUpload({
    required String assignmentId,
    required ActivityLearningMaterialType type,
    required String displayName,
    required String declaredContentType,
    required int sizeBytes,
  });

  /// Uploads only to the exact short-lived staging path returned by
  /// [beginUpload]. Availability remains asynchronous until server validation.
  Future<void> uploadStagedFile({
    required ActivityMaterialUpload upload,
    required File file,
  });

  Future<ActivityLearningMaterial> addLink({
    required String assignmentId,
    required String displayName,
    required Uri url,
  });

  Future<void> remove({
    required String assignmentId,
    required String materialId,
  });

  /// Returns only materials the authenticated caller can access. File paths
  /// are consumed through authenticated Firebase Storage, never public URLs.
  Future<List<ActivityLearningMaterial>> list({required String assignmentId});
}
