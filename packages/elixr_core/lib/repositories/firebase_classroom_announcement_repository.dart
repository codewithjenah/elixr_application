import 'package:cloud_firestore/cloud_firestore.dart';

import '../database/firestore_collections.dart';
import '../models/classroom_announcement.dart';
import 'classroom_announcement_repository.dart';

class FirebaseClassroomAnnouncementRepository
    implements ClassroomAnnouncementRepository {
  FirebaseClassroomAnnouncementRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _announcements(String groupId) =>
      _firestore
          .collection(FirestoreCollections.groups)
          .doc(groupId)
          .collection(FirestoreCollections.classroomAnnouncements);

  @override
  Stream<ClassroomAnnouncementPage> watchAnnouncements({
    required String groupId,
    int pageSize = ClassroomAnnouncementRepository.defaultPageSize,
  }) {
    _validatePageSize(pageSize);
    return _announcements(groupId)
        .orderBy('created_at', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(pageSize)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final items = snapshot.docs
              .map(
                (doc) =>
                    ClassroomAnnouncement.tryFromMap(doc.data(), id: doc.id),
              )
              .whereType<ClassroomAnnouncement>()
              .toList(growable: false);
          return ClassroomAnnouncementPage(
            items: items,
            hasMore: snapshot.docs.length == pageSize,
            nextCursor: snapshot.docs.isEmpty
                ? null
                : _FirestoreAnnouncementCursor(snapshot.docs.last),
          );
        });
  }

  @override
  Future<ClassroomAnnouncementPage> fetchOlderAnnouncements({
    required String groupId,
    required ClassroomAnnouncementCursor startAfter,
    int pageSize = ClassroomAnnouncementRepository.defaultPageSize,
  }) async {
    _validatePageSize(pageSize);
    if (startAfter is! _FirestoreAnnouncementCursor) {
      throw ArgumentError('Cursor belongs to another repository.');
    }
    final snapshot = await _announcements(groupId)
        .orderBy('created_at', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .startAfterDocument(startAfter.document)
        .limit(pageSize + 1)
        .get();
    final docs = snapshot.docs.take(pageSize).toList(growable: false);
    return ClassroomAnnouncementPage(
      items: docs
          .map(
            (doc) => ClassroomAnnouncement.tryFromMap(doc.data(), id: doc.id),
          )
          .whereType<ClassroomAnnouncement>()
          .toList(growable: false),
      hasMore: snapshot.docs.length > pageSize,
      nextCursor: snapshot.docs.length > pageSize && docs.isNotEmpty
          ? _FirestoreAnnouncementCursor(docs.last)
          : null,
    );
  }

  @override
  Future<ClassroomAnnouncement> createAnnouncement({
    required String groupId,
    required String teacherId,
    required String title,
    required String body,
  }) async {
    final trimmedTitle = _validatedTitle(title);
    final trimmedBody = _validatedBody(body);
    final ref = _announcements(groupId).doc();
    await ref.set({
      'group_id': groupId,
      'teacher_id': teacherId,
      'title': trimmedTitle,
      'body': trimmedBody,
      'created_at': FieldValue.serverTimestamp(),
      'edited_at': null,
      'schema_version': ClassroomAnnouncement.currentSchemaVersion,
    });
    return ClassroomAnnouncement(
      id: ref.id,
      groupId: groupId,
      teacherId: teacherId,
      title: trimmedTitle,
      body: trimmedBody,
      createdAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> updateAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
    required String title,
    required String body,
  }) async {
    final trimmedTitle = _validatedTitle(title);
    final trimmedBody = _validatedBody(body);
    await _announcements(groupId).doc(announcementId).update({
      'title': trimmedTitle,
      'body': trimmedBody,
      'edited_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> deleteAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
  }) => _announcements(groupId).doc(announcementId).delete();

  static void _validatePageSize(int pageSize) {
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Must be 1 through 100.');
    }
  }

  static String _validatedTitle(String value) {
    final error = ClassroomAnnouncement.validateTitle(value);
    if (error != null) throw ArgumentError(error);
    return value.trim();
  }

  static String _validatedBody(String value) {
    final error = ClassroomAnnouncement.validateBody(value);
    if (error != null) throw ArgumentError(error);
    return value.trim();
  }
}

class _FirestoreAnnouncementCursor extends ClassroomAnnouncementCursor {
  const _FirestoreAnnouncementCursor(this.document);

  final DocumentSnapshot<Map<String, dynamic>> document;
}
