import 'dart:io';

import '../models/activity_learning_material.dart';

abstract class ActivityLearningMaterialRepository {
  Future<ActivityMaterialUpload> beginUpload({
    required String assignmentId,
    required String requestId,
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

  /// Reads the server-owned lifecycle state once. Polling cadence belongs to a
  /// future Teacher UI, not this repository.
  Future<ActivityMaterialUploadStatus> getUploadStatus({
    required String uploadId,
  });

  Future<ActivityLearningMaterial> addLink({
    required String assignmentId,
    required String displayName,
    required Uri url,
    required String requestId,
  });

  Future<void> remove({
    required String assignmentId,
    required String materialId,
  });

  /// Returns only materials the authenticated caller can access. File paths
  /// are consumed through authenticated Firebase Storage, never public URLs.
  Future<List<ActivityLearningMaterial>> list({required String assignmentId});

  /// Returns ready materials across assignments currently visible to the
  /// authenticated Trainee. The server derives the Trainee identity from the
  /// Firebase token and enforces classroom and assignment audience access.
  Future<List<ActivityLearningMaterial>> listForTrainee();

  /// Downloads an authorized file material into ELIXR-managed cache storage.
  /// Callers must never turn [ActivityLearningMaterial.storagePath] into a URL
  /// or a local filename themselves.
  Future<File> openFile(ActivityLearningMaterial material);
}
