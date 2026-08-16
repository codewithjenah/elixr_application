import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';

/// Private Firebase Storage access for one confirmed-movement image per session.
class SessionEvidenceRepository {
  SessionEvidenceRepository({
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
  }) : _storage = storage ?? FirebaseStorage.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseStorage _storage;
  final FirebaseFirestore _firestore;

  static String pathFor({required String userId, required String sessionId}) =>
      'users/$userId/session_evidence/$sessionId.jpg';

  Future<void> upload({
    required String userId,
    required String sessionId,
    required Uint8List jpegBytes,
  }) async {
    if (jpegBytes.lengthInBytes < 1024 ||
        jpegBytes.lengthInBytes > 256 * 1024) {
      throw ArgumentError.value(
        jpegBytes.lengthInBytes,
        'jpegBytes',
        'Evidence JPEG must be 1–256 KiB',
      );
    }
    await _storage
        .ref(pathFor(userId: userId, sessionId: sessionId))
        .putData(jpegBytes, SettableMetadata(contentType: 'image/jpeg'));
  }

  Future<Uint8List?> download(String storagePath) =>
      _storage.ref(storagePath).getData(256 * 1024);

  /// Idempotently removes evidence objects and their session references.
  /// Storage is purged first: a failure leaves the Firestore references intact
  /// so the user can retry rather than losing track of an object.
  Future<void> deleteAllForUser(String userId) async {
    final listed = await _storage
        .ref('users/$userId/session_evidence')
        .listAll();
    for (final item in listed.items) {
      try {
        await item.delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
    }
    final sessions = await _firestore
        .collection(FirestoreCollections.sessions)
        .where('user_id', isEqualTo: userId)
        .get();
    for (var i = 0; i < sessions.docs.length; i += 400) {
      final batch = _firestore.batch();
      for (final doc in sessions.docs.skip(i).take(400)) {
        if (doc.data().containsKey('evidence_storage_path')) {
          batch.update(doc.reference, {
            'evidence_storage_path': FieldValue.delete(),
            'evidence_kind': FieldValue.delete(),
            'evidence_size_bytes': FieldValue.delete(),
          });
        }
      }
      await batch.commit();
    }
  }
}
