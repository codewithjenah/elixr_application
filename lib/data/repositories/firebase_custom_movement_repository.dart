import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';

import '../models/custom_movement.dart';
import '../models/movement_template.dart';
import '../models/training_prop.dart';
import 'custom_movement_repository.dart';

class FirebaseCustomMovementRepository implements CustomMovementRepository {
  FirebaseCustomMovementRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _movements =>
      _firestore.collection(FirestoreCollections.customMovements);

  @override
  Stream<List<CustomMovement>> watchOwnedMovements({
    required String ownerUid,
  }) => _movements.where('owner_uid', isEqualTo: ownerUid).snapshots().map((
    snapshot,
  ) {
    final movements = snapshot.docs
        .map((doc) => CustomMovement.tryFromMap(doc.data(), id: doc.id))
        .whereType<CustomMovement>()
        .where((movement) => movement.isActive)
        .toList(growable: false);
    movements.sort((a, b) {
      final left = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });
    return movements;
  });

  @override
  Future<CustomMovement?> getOwnedMovement({
    required String movementId,
    required String ownerUid,
  }) async {
    final doc = await _movements.doc(movementId).get();
    final movement = doc.exists
        ? CustomMovement.tryFromMap(doc.data()!, id: doc.id)
        : null;
    return movement?.isOwnedBy(ownerUid) == true ? movement : null;
  }

  @override
  Future<CustomMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  }) async {
    final doc = await _movements
        .doc(movementId)
        .collection(FirestoreCollections.customMovementRevisions)
        .doc(revisionId)
        .get();
    return doc.exists
        ? CustomMovementRevision.tryFromMap(doc.data()!, id: doc.id)
        : null;
  }

  @override
  Future<CustomMovement> createMovement({
    required String ownerUid,
    required CustomMovementOwnerRole ownerRole,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
  }) async {
    validateCustomMovementWrite(
      ownerUid: ownerUid,
      template: template,
      name: name,
      description: description,
      difficulty: difficulty,
      propType: propType,
    );
    final movementRef = _movements.doc();
    final revisionRef = movementRef
        .collection(FirestoreCollections.customMovementRevisions)
        .doc();
    final batch = _firestore.batch();
    batch.set(
      revisionRef,
      _revisionPayload(
        movementId: movementRef.id,
        ownerUid: ownerUid,
        ownerRole: ownerRole,
        template: template,
      ),
    );
    batch.set(
      movementRef,
      _rootPayload(
        ownerUid: ownerUid,
        ownerRole: ownerRole,
        name: name,
        description: description,
        difficulty: difficulty,
        propType: propType,
        revisionId: revisionRef.id,
        createdAt: FieldValue.serverTimestamp(),
      ),
    );
    await batch.commit();
    return CustomMovement(
      id: movementRef.id,
      ownerUid: ownerUid,
      ownerRole: ownerRole,
      name: name.trim(),
      description: description.trim(),
      difficulty: difficulty,
      propType: propType,
      status: CustomMovementStatus.active,
      activeRevisionId: revisionRef.id,
    );
  }

  @override
  Future<CustomMovement> publishRevision({
    required CustomMovement current,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required MovementTemplate template,
  }) async {
    validateCustomMovementWrite(
      ownerUid: current.ownerUid,
      template: template,
      name: name,
      description: description,
      difficulty: difficulty,
      propType: propType,
    );
    final movementRef = _movements.doc(current.id);
    final revisionRef = movementRef
        .collection(FirestoreCollections.customMovementRevisions)
        .doc();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(movementRef);
      final persisted = snapshot.exists
          ? CustomMovement.tryFromMap(snapshot.data()!, id: snapshot.id)
          : null;
      if (persisted == null ||
          persisted.ownerUid != current.ownerUid ||
          persisted.ownerRole != current.ownerRole ||
          persisted.activeRevisionId != current.activeRevisionId) {
        throw StateError('Movement changed or is not owned by this user.');
      }
      transaction.set(
        revisionRef,
        _revisionPayload(
          movementId: current.id,
          ownerUid: current.ownerUid,
          ownerRole: current.ownerRole,
          template: template,
        ),
      );
      transaction.update(movementRef, {
        'name': name.trim(),
        'description': description.trim(),
        'difficulty': difficulty,
        'prop_type': propType.protocolValue,
        'active_revision_id': revisionRef.id,
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
    return CustomMovement(
      id: current.id,
      ownerUid: current.ownerUid,
      ownerRole: current.ownerRole,
      name: name.trim(),
      description: description.trim(),
      difficulty: difficulty,
      propType: propType,
      status: current.status,
      activeRevisionId: revisionRef.id,
      createdAt: current.createdAt,
    );
  }

  @override
  Future<void> archiveMovement({
    required String movementId,
    required String ownerUid,
  }) async {
    final movement = await getOwnedMovement(
      movementId: movementId,
      ownerUid: ownerUid,
    );
    if (movement == null) throw StateError('Movement not found.');
    await _movements.doc(movementId).update({
      'status': CustomMovementStatus.archived.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteOwnedMovement({
    required String movementId,
    required String ownerUid,
  }) async {
    // The Firestore rules also require the authenticated owner. Checking the
    // persisted record first keeps this repository safe for every caller and
    // avoids treating an arbitrary ID as a deletable custom movement.
    final snapshot = await _movements.doc(movementId).get();
    if (!snapshot.exists) return;
    final movement = CustomMovement.tryFromMap(
      snapshot.data()!,
      id: snapshot.id,
    );
    if (movement == null || !movement.isOwnedBy(ownerUid)) {
      throw StateError('Movement changed or is not owned by this user.');
    }
    if (!movement.isActive) return;

    // Revisions and results are immutable historical records. Archiving
    // removes the definition from the active library while preserving those
    // references, which is the only deletion-like transition permitted by
    // the Firestore contract.
    await _movements.doc(movementId).update({
      'status': CustomMovementStatus.archived.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> savePersonalResult({
    required String ownerUid,
    required String movementId,
    required String revisionId,
    required double totalScore,
    required Map<String, double> componentScores,
    required List<String> feedback,
  }) async {
    if (!totalScore.isFinite || totalScore < 0 || totalScore > 100) {
      throw ArgumentError.value(totalScore, 'totalScore');
    }
    await _firestore
        .collection(FirestoreCollections.customMovementResults)
        .add({
          'owner_uid': ownerUid,
          'movement_id': movementId,
          'revision_id': revisionId,
          'result_type': 'personal_practice',
          'total_score': totalScore,
          'component_scores': componentScores,
          'feedback': feedback.take(8).toList(growable: false),
          'awards_global_xp': false,
          'created_at': FieldValue.serverTimestamp(),
        });
  }

  Map<String, dynamic> _rootPayload({
    required String ownerUid,
    required CustomMovementOwnerRole ownerRole,
    required String name,
    required String description,
    required String difficulty,
    required TrainingProp propType,
    required String revisionId,
    required Object createdAt,
  }) => {
    'owner_uid': ownerUid,
    'owner_role': ownerRole.wireValue,
    'name': name.trim(),
    'description': description.trim(),
    'difficulty': difficulty,
    'prop_type': propType.protocolValue,
    'status': CustomMovementStatus.active.name,
    'active_revision_id': revisionId,
    'schema_version': CustomMovement.currentSchemaVersion,
    'created_at': createdAt,
    'updated_at': FieldValue.serverTimestamp(),
  };

  Map<String, dynamic> _revisionPayload({
    required String movementId,
    required String ownerUid,
    required CustomMovementOwnerRole ownerRole,
    required MovementTemplate template,
  }) => {
    'movement_id': movementId,
    'owner_uid': ownerUid,
    'owner_role': ownerRole.wireValue,
    'schema_version': CustomMovement.currentSchemaVersion,
    'template': template.toMap(),
    'created_at': FieldValue.serverTimestamp(),
  };
}
