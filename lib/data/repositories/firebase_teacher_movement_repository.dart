import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/assessment_mode.dart';
import '../models/classroom_exceptions.dart';
import '../models/teacher_movement.dart';
import '../models/teacher_activity_assessment.dart';
import '../models/training_prop.dart';
import 'teacher_movement_repository.dart';

class FirebaseTeacherMovementRepository implements TeacherMovementRepository {
  FirebaseTeacherMovementRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  CollectionReference<Map<String, dynamic>> get _movements =>
      _firestore.collection(FirestoreCollections.teacherMovements);

  CollectionReference<Map<String, dynamic>> get _assignments =>
      _firestore.collection(FirestoreCollections.groupAssignments);

  @override
  Future<File> openActivityDemonstration(
    TeacherActivityVideoMetadata metadata,
  ) async {
    if (!metadata.storagePath.startsWith('teacher_activity_demos/') ||
        metadata.contentType != 'video/mp4') {
      throw const ClassroomException(ClassroomError.malformed);
    }
    final root = await getTemporaryDirectory();
    final cache = Directory('${root.path}/elixr_activity_demos');
    await cache.create(recursive: true);
    final objectName = metadata.storagePath.split('/').last;
    final destination = File(
      '${cache.path}/${DateTime.now().microsecondsSinceEpoch}_$objectName',
    );
    try {
      await _storage.ref(metadata.storagePath).writeToFile(destination);
      final size = await destination.length();
      if (size < 1 ||
          size > TeacherActivityAssessmentContract.maximumVideoSizeBytes) {
        throw const ClassroomException(ClassroomError.malformed);
      }
      return destination;
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  @override
  Future<void> releaseActivityDemonstration(File localFile) async {
    try {
      if (await localFile.exists()) await localFile.delete();
    } on FileSystemException {
      // A best-effort cache cleanup must not fail page navigation.
    }
  }

  @override
  Future<TeacherActivityVideoMetadata> uploadActivityDemonstration({
    required String teacherId,
    required File localFile,
    required Duration duration,
    required TeacherActivityDemoSource source,
    String? assignmentId,
  }) async {
    final sizeBytes = await _validatedDemoFileSize(
      teacherId: teacherId,
      localFile: localFile,
      duration: duration,
    );
    // A Firestore generated id is opaque and avoids using a user-controlled
    // local filename in the Storage object path.
    final opaqueId = _firestore.collection('_ids').doc().id;
    final assignmentScope = assignmentId?.trim();
    final storagePath = assignmentScope == null || assignmentScope.isEmpty
        ? 'teacher_activity_demos/$teacherId/$opaqueId.mp4'
        : 'teacher_activity_demos/$teacherId/assignments/$assignmentScope/$opaqueId.mp4';
    final reference = _storage.ref().child(storagePath);
    await reference.putFile(
      localFile,
      SettableMetadata(
        contentType: 'video/mp4',
        customMetadata: {'owner_id': teacherId},
      ),
    );
    return TeacherActivityVideoMetadata(
      storagePath: storagePath,
      contentType: 'video/mp4',
      sizeBytes: sizeBytes,
      durationMs: duration.inMilliseconds,
      source: source,
    );
  }

  @override
  Future<TeacherMovement> createMovement({
    required String teacherId,
    required String title,
    required String instructions,
    required TrainingProp requiredProp,
    String? safetyGuidance,
    TeacherActivityAssessmentConfig? assessment,
  }) async {
    final spec = buildTeacherReviewedSpec(
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: assessment,
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
    TeacherActivityAssessmentConfig? assessment,
  }) async {
    final spec = buildTeacherReviewedSpec(
      title: title,
      instructions: instructions,
      requiredProp: requiredProp,
      safetyGuidance: safetyGuidance,
      assessment: assessment,
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
    final currentRevision = await getRevision(
      movementId: movementId,
      revisionId: current.currentRevisionId,
    );
    ensureRevisionAssessmentMode(
      revision: currentRevision,
      expected: AssessmentMode.teacherReviewed,
    );
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
    final currentRevision = await getRevision(
      movementId: movementId,
      revisionId: current.currentRevisionId,
    );
    ensureRevisionAssessmentMode(
      revision: currentRevision,
      expected: AssessmentMode.teacherReviewed,
    );
    await movementRef.update({
      'status': TeacherMovementStatus.archived.name,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteMovement({
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
    final currentRevision = await getRevision(
      movementId: movementId,
      revisionId: current.currentRevisionId,
    );
    ensureRevisionAssessmentMode(
      revision: currentRevision,
      expected: AssessmentMode.teacherReviewed,
    );

    final linkedAssignments = await _assignments
        .where('teacher_id', isEqualTo: teacherId)
        .where('movement_id', isEqualTo: movementId)
        .limit(1)
        .get();
    if (linkedAssignments.docs.isNotEmpty) {
      throw const ClassroomException(
        ClassroomError.invalidState,
        'This movement cannot be deleted because it is used by an assignment.',
      );
    }

    final revisions = await movementRef
        .collection(FirestoreCollections.teacherMovementRevisions)
        .get();
    final revisionDocs = revisions.docs.toList()
      ..sort((a, b) {
        final aIsCurrent = a.id == current.currentRevisionId;
        final bIsCurrent = b.id == current.currentRevisionId;
        if (aIsCurrent == bIsCurrent) return 0;
        return aIsCurrent ? 1 : -1;
      });
    while (revisionDocs.length > 499) {
      final batch = _firestore.batch();
      for (final revision in revisionDocs.take(499)) {
        batch.delete(revision.reference);
      }
      await batch.commit();
      revisionDocs.removeRange(0, 499);
    }

    final batch = _firestore.batch();
    for (final revision in revisionDocs) {
      batch.delete(revision.reference);
    }
    batch.delete(movementRef);
    await batch.commit();
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

Future<int> _validatedDemoFileSize({
  required String teacherId,
  required File localFile,
  required Duration duration,
}) async {
  if (teacherId.trim().isEmpty) {
    throw const ClassroomException(
      ClassroomError.malformed,
      'Missing teacher.',
    );
  }
  if (duration.inMilliseconds < 1 || duration.inMilliseconds > 60000) {
    throw const ClassroomException(
      ClassroomError.malformed,
      'Demonstration videos must be 60 seconds or less.',
    );
  }
  final stat = await localFile.stat();
  if (stat.type != FileSystemEntityType.file ||
      stat.size < 1 ||
      stat.size > 50 * 1024 * 1024) {
    throw const ClassroomException(
      ClassroomError.malformed,
      'Demonstration videos must be an MP4 no larger than 50 MiB.',
    );
  }
  return stat.size;
}
