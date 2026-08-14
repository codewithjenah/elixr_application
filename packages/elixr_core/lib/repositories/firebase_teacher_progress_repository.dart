import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../models/public_profile_session.dart';
import '../models/public_profile_summary.dart';
import '../models/teacher_progress_exception.dart';
import 'teacher_progress_repository.dart';

class FirebaseTeacherProgressRepository implements TeacherProgressRepository {
  FirebaseTeacherProgressRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _sessions(String traineeId) =>
      _firestore.collection(FirestoreCollections.publicProfiles).doc(traineeId)
          .collection('sessions');
  DocumentReference<Map<String, dynamic>> _summary(String traineeId) =>
      _firestore.collection(FirestoreCollections.publicProfiles).doc(traineeId)
          .collection('details').doc('summary');

  @override
  Stream<PublicProfileSummary?> watchSummary(String traineeId) =>
      _summary(traineeId).snapshots().map((doc) {
        if (!doc.exists || doc.data() == null) return null;
        return PublicProfileSummary.tryFromMap(doc.data()!);
      }).handleError(_mapError);

  @override
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId,
    int pageSize = 20,
    TeacherProgressCursor? startAfter,
  }) async {
    if (pageSize < 1 || pageSize > 50) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be 1..50');
    }
    Query<Map<String, dynamic>> query = _sessions(traineeId)
        .orderBy('created_at', descending: true).limit(pageSize);
    if (startAfter != null) {
      if (startAfter is! _FirestoreTeacherProgressCursor) {
        throw ArgumentError('Cursor belongs to another repository');
      }
      query = query.startAfterDocument(startAfter.document);
    }
    try {
      final result = await query.get(const GetOptions(source: Source.server));
      final sessions = result.docs
          .map((doc) => PublicProfileSession.tryFromMap(doc.data(), id: doc.id))
          .whereType<PublicProfileSession>().toList(growable: false);
      final hasMore = result.docs.length == pageSize;
      return TeacherProgressPage(
        sessions: sessions,
        hasMore: hasMore,
        nextCursor: hasMore ? _FirestoreTeacherProgressCursor(result.docs.last) : null,
      );
    } on Object catch (error) {
      throw _asProgressError(error);
    }
  }

  Never _mapError(Object error, StackTrace stackTrace) => throw _asProgressError(error);
  TeacherProgressException _asProgressError(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return const TeacherProgressException(TeacherProgressError.accessWithdrawn);
    }
    return TeacherProgressException(TeacherProgressError.unavailable, '$error');
  }
}

class _FirestoreTeacherProgressCursor extends TeacherProgressCursor {
  const _FirestoreTeacherProgressCursor(this.document);
  final DocumentSnapshot<Map<String, dynamic>> document;
}
