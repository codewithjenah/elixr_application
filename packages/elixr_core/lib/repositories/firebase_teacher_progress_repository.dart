import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
      _firestore
          .collection(FirestoreCollections.publicProfiles)
          .doc(traineeId)
          .collection('sessions');
  DocumentReference<Map<String, dynamic>> _summary(String traineeId) =>
      _firestore
          .collection(FirestoreCollections.publicProfiles)
          .doc(traineeId)
          .collection('details')
          .doc('summary');

  @override
  Stream<PublicProfileSummary?> watchSummary(String traineeId) =>
      _summary(traineeId)
          .snapshots()
          .map((doc) {
            if (!doc.exists || doc.data() == null) return null;
            return PublicProfileSummary.tryFromMap(doc.data()!);
          })
          .handleError(_mapError);

  @override
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId,
    int pageSize = TeacherProgressRepository.defaultPageSize,
    TeacherProgressCursor? startAfter,
  }) async {
    TeacherProgressRepository.validatePageSize(pageSize);
    Query<Map<String, dynamic>> query = _sessions(
      traineeId,
    ).orderBy('created_at', descending: true).limit(pageSize + 1);
    if (startAfter != null) {
      if (startAfter is! _FirestoreTeacherProgressCursor) {
        throw ArgumentError('Cursor belongs to another repository');
      }
      query = query.startAfterDocument(startAfter.document);
    }
    try {
      final result = await query.get(const GetOptions(source: Source.server));
      final hasMore = result.docs.length > pageSize;
      final pageDocuments = result.docs.take(pageSize).toList(growable: false);
      final sessions = pageDocuments
          .map((doc) => PublicProfileSession.tryFromMap(doc.data(), id: doc.id))
          .whereType<PublicProfileSession>()
          .toList(growable: false);
      return TeacherProgressPage(
        sessions: sessions,
        hasMore: hasMore,
        nextCursor: hasMore
            ? _FirestoreTeacherProgressCursor(pageDocuments.last)
            : null,
      );
    } on Object catch (error) {
      throw _asProgressError(error);
    }
  }

  Never _mapError(Object error, StackTrace stackTrace) =>
      throw _asProgressError(error);
  @visibleForTesting
  static TeacherProgressException classifyError(Object error) {
    if (error is FirebaseException && error.code == 'permission-denied') {
      return const TeacherProgressException(
        TeacherProgressError.accessWithdrawn,
      );
    }
    return TeacherProgressException(TeacherProgressError.unavailable, '$error');
  }

  TeacherProgressException _asProgressError(Object error) =>
      classifyError(error);
}

class _FirestoreTeacherProgressCursor extends TeacherProgressCursor {
  const _FirestoreTeacherProgressCursor(this.document);
  final DocumentSnapshot<Map<String, dynamic>> document;
}
