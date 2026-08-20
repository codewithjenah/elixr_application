import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';

import '../models/classroom_exceptions.dart';
import '../models/teacher_movement.dart';
import '../models/training_prop.dart';
import 'teacher_movement_repository.dart';

class FirebaseTeacherMovementRepository implements TeacherMovementRepository {
  FirebaseTeacherMovementRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _movements =>
      _firestore.collection(FirestoreCollections.teacherMovements);

  @override
  Future<TeacherMovement> createMovement({
    required String teacherId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) async {
    final spec = buildTeacherReviewedSpec(
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
    );
    final movementRef = _movements.doc();
    final revisionRef = movementRef
        .collection(FirestoreCollections.teacherMovementRevisions)
        .doc();
    final batch = _firestore.batch();
    batch.set(
      revisionRef,
      teacherMovementRevisionPayload(
        movementId: movementRef.id,
        teacherId: teacherId,
        spec: spec,
        createdAt: FieldValue.serverTimestamp(),
      ),
    );
    batch.set(
      movementRef,
      teacherMovementRootPayload(
        teacherId: teacherId,
        title: title,
        currentRevisionId: revisionRef.id,
        status: TeacherMovementStatus.active.name,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      ),
    );
    await batch.commit();
    return TeacherMovement(
      id: movementRef.id,
      teacherId: teacherId,
      title: title.trim(),
      status: TeacherMovementStatus.active,
      currentRevisionId: revisionRef.id,
    );
  }

  @override
  Future<TeacherMovement> editMovement({
    required String teacherId,
    required String movementId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
  }) async {
    final spec = buildTeacherReviewedSpec(
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
    );
    final movementRef = _movements.doc(movementId);
    final existing = await movementRef.get();
    if (!existing.exists) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    final current = TeacherMovement.tryFromMap(
      existing.data() ?? const {},
      id: existing.id,
    );
    if (current == null) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    if (current.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    final previousRevisionId = current.currentRevisionId;
    final revisionRef = movementRef
        .collection(FirestoreCollections.teacherMovementRevisions)
        .doc();
    final batch = _firestore.batch();
    batch.set(
      revisionRef,
      teacherMovementRevisionPayload(
        movementId: movementId,
        teacherId: teacherId,
        spec: spec,
        createdAt: FieldValue.serverTimestamp(),
      ),
    );
    batch.update(movementRef, {
      'title': title.trim(),
      'current_revision_id': revisionRef.id,
      'updated_at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    assert(previousRevisionId != revisionRef.id);
    return TeacherMovement(
      id: movementId,
      teacherId: teacherId,
      title: title.trim(),
      status: current.status,
      currentRevisionId: revisionRef.id,
      createdAt: current.createdAt,
    );
  }

  @override
  Future<void> archiveMovement({
    required String teacherId,
    required String movementId,
  }) async {
    final movementRef = _movements.doc(movementId);
    final existing = await movementRef.get();
    if (!existing.exists) {
      throw const ClassroomException(ClassroomError.notFound);
    }
    final current = TeacherMovement.tryFromMap(
      existing.data() ?? const {},
      id: existing.id,
    );
    if (current == null) {
      throw const ClassroomException(ClassroomError.malformed);
    }
    if (current.teacherId != teacherId) {
      throw const ClassroomException(ClassroomError.forbidden);
    }
    await movementRef.update({
      'status': TeacherMovementStatus.archived.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Stream<List<TeacherMovement>> watchTeacherMovements({
    required String teacherId,
  }) {
    return _movements.where('teacher_id', isEqualTo: teacherId).snapshots().map(
      (snapshot) {
        final items = snapshot.docs
            .map((doc) => TeacherMovement.tryFromMap(doc.data(), id: doc.id))
            .whereType<TeacherMovement>()
            .toList();
        items.sort((a, b) {
          final aAt =
              a.updatedAt ??
              a.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bAt =
              b.updatedAt ??
              b.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bAt.compareTo(aAt);
        });
        return items;
      },
    );
  }

  @override
  Future<TeacherMovement?> getMovement({required String movementId}) async {
    final doc = await _movements.doc(movementId).get();
    if (!doc.exists || doc.data() == null) return null;
    return TeacherMovement.tryFromMap(doc.data()!, id: doc.id);
  }

  @override
  Future<TeacherMovementRevision?> getRevision({
    required String movementId,
    required String revisionId,
  }) async {
    final doc = await _movements
        .doc(movementId)
        .collection(FirestoreCollections.teacherMovementRevisions)
        .doc(revisionId)
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return TeacherMovementRevision.tryFromMap(doc.data()!, id: doc.id);
  }
}
