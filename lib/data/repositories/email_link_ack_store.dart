import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/database/firestore_collections.dart';

/// Records that a Firebase email continue URL was opened, including on another
/// device that cannot reach this PC's localhost listener.
abstract class EmailLinkAckStore {
  Future<void> createPending({required String token, required String uid});

  Future<bool> isClicked(String token);

  Future<void> delete(String token);
}

class MemoryEmailLinkAckStore implements EmailLinkAckStore {
  final _statusByToken = <String, String>{};

  void markClicked(String token) {
    _statusByToken[token] = 'clicked';
  }

  @override
  Future<void> createPending({
    required String token,
    required String uid,
  }) async {
    _statusByToken[token] = 'pending';
  }

  @override
  Future<bool> isClicked(String token) async {
    return _statusByToken[token] == 'clicked';
  }

  @override
  Future<void> delete(String token) async {
    _statusByToken.remove(token);
  }
}

class FirestoreEmailLinkAckStore implements EmailLinkAckStore {
  FirestoreEmailLinkAckStore({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _doc(String token) {
    return _firestore.collection(FirestoreCollections.emailLinkAcks).doc(token);
  }

  @override
  Future<void> createPending({
    required String token,
    required String uid,
  }) async {
    await _doc(token).set({
      'uid': uid,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<bool> isClicked(String token) async {
    final snapshot = await _doc(token).get();
    return snapshot.data()?['status'] == 'clicked';
  }

  @override
  Future<void> delete(String token) async {
    await _doc(token).delete();
  }
}
