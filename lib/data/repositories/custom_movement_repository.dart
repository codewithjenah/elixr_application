import 'dart:typed_data';

import '../models/custom_movement.dart';
import '../models/movement_template.dart';
import '../models/training_prop.dart';

enum CustomMovementSaveStage {
  validation,
  referenceImageUpload,
  firestoreCommit,
  teardown,
  unknown,
}

extension CustomMovementSaveStageDetails on CustomMovementSaveStage {
  String get wireValue => switch (this) {
    CustomMovementSaveStage.validation => 'validation',
    CustomMovementSaveStage.referenceImageUpload => 'reference_image_upload',
    CustomMovementSaveStage.firestoreCommit => 'firestore_commit',
    CustomMovementSaveStage.teardown => 'teardown',
    CustomMovementSaveStage.unknown => 'unknown',
  };

  String get userMessage => switch (this) {
    CustomMovementSaveStage.validation =>
      'Movement details failed validation. Review the name, description, difficulty, and examples.',
    CustomMovementSaveStage.referenceImageUpload =>
      'The reference image upload failed. Check your connection and Storage access, then retry.',
    CustomMovementSaveStage.firestoreCommit =>
      'The movement data could not be committed to Firestore. Check your connection and account access, then retry.',
    CustomMovementSaveStage.teardown =>
      'The movement was saved, but the recording session did not close cleanly. Check My Movements before trying again.',
    CustomMovementSaveStage.unknown =>
      'The movement save failed before completion. Please retry; diagnostic details were logged.',
  };
}

/// Preserves the failing save stage while keeping backend exception details
/// available for debug diagnostics without exposing them in the UI.
class CustomMovementSaveException implements Exception {
  const CustomMovementSaveException({
    required this.stage,
    required this.cause,
    required this.stackTrace,
  });

  final CustomMovementSaveStage stage;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() => 'CustomMovementSaveException(${stage.wireValue})';
}

abstract class CustomMovementRepository {
  String allocateSessionId();

  Stream<List<CustomMovement>> watchOwnedMovements({required String ownerUid});

  /// Watches append-only personal assessments for the signed-in movement owner.
  Stream<List<CustomMovementResult>> watchPersonalResults({
    required String ownerUid,
  });

  Future<CustomMovement?> getOwnedMovement({
    required String movementId,
    required String ownerUid,
  });

  Future<CustomMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  });

  Future<CustomMovement> createMovement({
    required String ownerUid,
    required CustomMovementOwnerRole ownerRole,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
    Uint8List? referenceImageJpegBytes,
  });

  /// Publishes a new immutable revision. Existing revisions are never updated.
  Future<CustomMovement> publishRevision({
    required CustomMovement current,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
    Uint8List? referenceImageJpegBytes,
  });

  Future<void> archiveMovement({
    required String movementId,
    required String ownerUid,
  });

  /// Removes a custom movement from its owner's active library.
  ///
  /// This deliberately archives the root rather than deleting it: immutable
  /// revisions and result records may still be needed by personal history or
  /// assignment snapshots.
  Future<void> deleteOwnedMovement({
    required String movementId,
    required String ownerUid,
  });

  Future<void> savePersonalResult({
    required String ownerUid,
    required String movementId,
    required String revisionId,
    required double totalScore,
    required Map<String, double> componentScores,
    required List<String> feedback,
    required String sessionId,
    required String movementName,
    required String difficulty,
    required TrainingProp propType,
    required int durationSeconds,
    String? referenceImageStoragePath,
  });
}

void validateCustomMovementWrite({
  required String ownerUid,
  required MovementTemplate template,
  required String name,
  required String description,
  required String difficulty,
  required TrainingProp propType,
}) {
  if (ownerUid.trim().isEmpty || ownerUid.trim().length > 128) {
    throw ArgumentError.value(ownerUid, 'ownerUid');
  }
  final error = CustomMovement.validateMetadata(
    name: name,
    description: description,
    difficulty: difficulty,
  );
  if (error != null) throw ArgumentError(error);
  if (!CustomMovement.supportedProps.contains(propType)) {
    throw ArgumentError(
      'Custom movements currently support one bottle or one shaker.',
    );
  }
  if (!template.isReady) {
    throw ArgumentError(
      'At least two valid reference demonstrations are required.',
    );
  }
  if (template.encodedBytes > MovementTemplate.maximumEncodedBytes) {
    throw ArgumentError('Movement template is too large to save safely.');
  }
}
