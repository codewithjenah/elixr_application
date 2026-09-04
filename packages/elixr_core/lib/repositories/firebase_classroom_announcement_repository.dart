import 'dart:async';

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

  DocumentReference<Map<String, dynamic>> _group(String groupId) =>
      _firestore.collection(FirestoreCollections.groups).doc(groupId);

  @override
  Stream<ClassroomAnnouncementPage> watchAnnouncements({
    required String groupId,
    int pageSize = ClassroomAnnouncementRepository.defaultPageSize,
    bool includeUnpublished = false,
  }) {
    _validatePageSize(pageSize);
    final query = _announcements(groupId)
        .orderBy('created_at', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(pageSize);
    return Stream<ClassroomAnnouncementPage>.multi((controller) {
      QuerySnapshot<Map<String, dynamic>>? latestAnnouncements;
      DocumentSnapshot<Map<String, dynamic>>? latestGroup;
      var generation = 0;
      var cancelled = false;

      Future<void> emit() async {
        final snapshot = latestAnnouncements;
        final groupSnapshot = latestGroup;
        if (snapshot == null || groupSnapshot == null) return;
        final currentGeneration = ++generation;
        final groupData = groupSnapshot.data() ?? const <String, dynamic>{};
        final pinnedId = _readPinnedId(groupData);
        final pinnedAt = _readDateTime(groupData['pinned_announcement_at']);
        final byId = <String, ClassroomAnnouncement>{};
        for (final doc in snapshot.docs) {
          final item = ClassroomAnnouncement.tryFromMap(doc.data(), id: doc.id);
          if (item != null) byId[item.id] = item;
        }
        if (pinnedId != null && !byId.containsKey(pinnedId)) {
          final pinnedSnapshot = await _announcements(
            groupId,
          ).doc(pinnedId).get();
          final pinned = pinnedSnapshot.data() == null
              ? null
              : ClassroomAnnouncement.tryFromMap(
                  pinnedSnapshot.data()!,
                  id: pinnedSnapshot.id,
                );
          if (pinned != null) byId[pinned.id] = pinned;
        }
        if (cancelled || currentGeneration != generation) return;
        final items = [
          for (final item in byId.values)
            item.copyWith(
              isPinned: item.id == pinnedId,
              pinnedAt: item.id == pinnedId ? pinnedAt : null,
              clearPinnedAt: item.id != pinnedId,
            ),
        ]..sort(_compareAnnouncements);
        controller.add(
          ClassroomAnnouncementPage(
            items: items,
            hasMore: snapshot.docs.length == pageSize,
            nextCursor: snapshot.docs.isEmpty
                ? null
                : _FirestoreAnnouncementCursor(snapshot.docs.last),
          ),
        );
      }

      final announcementsSub = query
          .snapshots(includeMetadataChanges: true)
          .listen((snapshot) {
            latestAnnouncements = snapshot;
            unawaited(emit());
          }, onError: controller.addError);
      final groupSub = _group(groupId).snapshots().listen((snapshot) {
        latestGroup = snapshot;
        unawaited(emit());
      }, onError: controller.addError);
      controller.onCancel = () async {
        cancelled = true;
        generation++;
        await Future.wait([announcementsSub.cancel(), groupSub.cancel()]);
      };
    });
  }

  @override
  Future<ClassroomAnnouncementPage> fetchOlderAnnouncements({
    required String groupId,
    required ClassroomAnnouncementCursor startAfter,
    int pageSize = ClassroomAnnouncementRepository.defaultPageSize,
    bool includeUnpublished = false,
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
    final groupData = (await _group(groupId).get()).data() ?? const {};
    final pinnedId = _readPinnedId(groupData);
    final pinnedAt = _readDateTime(groupData['pinned_announcement_at']);
    final items =
        docs
            .map(
              (doc) => ClassroomAnnouncement.tryFromMap(doc.data(), id: doc.id),
            )
            .whereType<ClassroomAnnouncement>()
            .map(
              (item) => item.copyWith(
                isPinned: item.id == pinnedId,
                pinnedAt: item.id == pinnedId ? pinnedAt : null,
                clearPinnedAt: item.id != pinnedId,
              ),
            )
            .toList()
          ..sort(_compareAnnouncements);
    return ClassroomAnnouncementPage(
      items: items,
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
    DateTime? publishAt,
  }) async {
    final trimmedTitle = _validatedTitle(title);
    final trimmedBody = _validatedBody(body);
    final ref = _announcements(groupId).doc();
    final publication = _validatePublishAt(publishAt);
    await ref.set({
      'group_id': groupId,
      'teacher_id': teacherId,
      'title': trimmedTitle,
      'body': trimmedBody,
      'created_at': FieldValue.serverTimestamp(),
      'edited_at': null,
      if (publication != null) 'publish_at': Timestamp.fromDate(publication),
      'schema_version': ClassroomAnnouncement.currentSchemaVersion,
    });
    return ClassroomAnnouncement(
      id: ref.id,
      groupId: groupId,
      teacherId: teacherId,
      title: trimmedTitle,
      body: trimmedBody,
      createdAt: DateTime.now().toUtc(),
      publishAt: publication,
    );
  }

  @override
  Future<void> updateAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
    required String title,
    required String body,
    DateTime? publishAt,
  }) async {
    final trimmedTitle = _validatedTitle(title);
    final trimmedBody = _validatedBody(body);
    final publication = _validatePublishAt(publishAt);
    await _announcements(groupId).doc(announcementId).update({
      'title': trimmedTitle,
      'body': trimmedBody,
      'edited_at': FieldValue.serverTimestamp(),
      'publish_at': publication == null
          ? FieldValue.delete()
          : Timestamp.fromDate(publication),
    });
  }

  @override
  Future<void> deleteAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
  }) async {
    final groupRef = _group(groupId);
    final announcementRef = _announcements(groupId).doc(announcementId);
    await _firestore.runTransaction((transaction) async {
      final groupSnapshot = await transaction.get(groupRef);
      final announcementSnapshot = await transaction.get(announcementRef);
      if (!announcementSnapshot.exists) return;
      transaction.delete(announcementRef);
      if (_readPinnedId(groupSnapshot.data() ?? const {}) == announcementId) {
        transaction.update(groupRef, {
          'pinned_announcement_id': FieldValue.delete(),
          'pinned_announcement_at': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  @override
  Future<void> setPinnedAnnouncement({
    required String groupId,
    required String teacherId,
    String? announcementId,
  }) async {
    final groupRef = _group(groupId);
    final normalized = announcementId?.trim();
    await _firestore.runTransaction((transaction) async {
      final groupSnapshot = await transaction.get(groupRef);
      final groupData = groupSnapshot.data();
      if (!groupSnapshot.exists || groupData?['teacher_id'] != teacherId) {
        throw StateError('Classroom is not available.');
      }
      if (normalized == null || normalized.isEmpty) {
        transaction.update(groupRef, {
          'pinned_announcement_id': FieldValue.delete(),
          'pinned_announcement_at': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        });
        return;
      }
      final targetRef = _announcements(groupId).doc(normalized);
      final target = await transaction.get(targetRef);
      if (!target.exists || target.data()?['teacher_id'] != teacherId) {
        throw StateError('Announcement is not available.');
      }
      final publishAt = _readDateTime(target.data()?['publish_at']);
      if (publishAt != null && DateTime.now().toUtc().isBefore(publishAt)) {
        throw StateError('A scheduled announcement cannot be pinned.');
      }
      transaction.update(groupRef, {
        'pinned_announcement_id': normalized,
        'pinned_announcement_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  static int _compareAnnouncements(
    ClassroomAnnouncement a,
    ClassroomAnnouncement b,
  ) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byTime = bTime.compareTo(aTime);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  static String? _readPinnedId(Map<String, dynamic> data) {
    final value = data['pinned_announcement_id'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed.length > 128 ? null : trimmed;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    return null;
  }

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

  static DateTime? _validatePublishAt(DateTime? value) {
    if (value == null) return null;
    final at = value.toUtc();
    if (!at.isAfter(DateTime.now().toUtc())) {
      throw ArgumentError('Publication time must be in the future.');
    }
    return at;
  }
}

class _FirestoreAnnouncementCursor extends ClassroomAnnouncementCursor {
  const _FirestoreAnnouncementCursor(this.document);

  final DocumentSnapshot<Map<String, dynamic>> document;
}
