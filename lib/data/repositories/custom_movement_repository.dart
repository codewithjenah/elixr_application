import '../models/custom_movement.dart';
import '../models/movement_template.dart';
import '../models/training_prop.dart';

abstract class CustomMovementRepository {
  Stream<List<CustomMovement>> watchOwnedMovements({required String ownerUid});

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
  });

  /// Publishes a new immutable revision. Existing revisions are never updated.
  Future<CustomMovement> publishRevision({
    required CustomMovement current,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
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
    throw ArgumentError('Three valid reference demonstrations are required.');
  }
  if (template.encodedBytes > MovementTemplate.maximumEncodedBytes) {
    throw ArgumentError('Movement template is too large to save safely.');
  }
}
