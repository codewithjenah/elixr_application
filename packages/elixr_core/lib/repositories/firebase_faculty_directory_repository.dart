import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../models/chat_user.dart';
import '../models/user.dart';
import 'faculty_directory_repository.dart';

class FirebaseFacultyDirectoryRepository implements FacultyDirectoryRepository {
  FirebaseFacultyDirectoryRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _directory =>
      _firestore.collection(FirestoreCollections.chatUserDirectory);

  @override
  Stream<List<ChatUser>> watchTeachers() {
    return _directory
        .where('role', isEqualTo: User.roleTeacher)
        .snapshots()
        .map(
          (snapshot) => [for (final doc in snapshot.docs) ?_mapTeacher(doc)],
        );
  }

  ChatUser? _mapTeacher(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final lifecycle = data['lifecycle_state'];
    if (lifecycle is String && lifecycle != 'active') return null;
    return ChatUser.tryFromMap(data, id: doc.id);
  }
}
