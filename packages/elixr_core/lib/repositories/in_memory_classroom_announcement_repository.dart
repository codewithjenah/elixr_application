import 'dart:async';

import '../models/classroom_announcement.dart';
import 'classroom_announcement_repository.dart';

class InMemoryClassroomAnnouncementRepository
    implements ClassroomAnnouncementRepository {
  InMemoryClassroomAnnouncementRepository({
    DateTime Function()? now,
    String Function()? generateId,
  }) : _now = now,
       _generateId = generateId ?? _defaultId;

  final DateTime Function()? _now;
  final String Function() _generateId;
  final Map<String, ClassroomAnnouncement> announcements = {};
  final Map<String, String> pinnedAnnouncementIds = {};
  final Map<String, StreamController<List<ClassroomAnnouncement>>> _streams =
      {};

  DateTime get now => (_now?.call() ?? DateTime.now()).toUtc();

  static String _defaultId() =>
      'announcement-${DateTime.now().microsecondsSinceEpoch}';

  void dispose() {
    for (final stream in _streams.values) {
      stream.close();
    }
  }

  void seedAnnouncement(ClassroomAnnouncement announcement) {
    announcements[announcement.id] = announcement;
    _emit(announcement.groupId);
  }

  @override
  Stream<ClassroomAnnouncementPage> watchAnnouncements({
    required String groupId,
    int pageSize = ClassroomAnnouncementRepository.defaultPageSize,
    bool includeUnpublished = false,
  }) {
    _validatePageSize(pageSize);
    final stream = _streams.putIfAbsent(
      groupId,
      () => StreamController<List<ClassroomAnnouncement>>.broadcast(),
    );
    return Stream.multi((controller) {
      controller.add(_pageFor(groupId, pageSize, includeUnpublished));
      final subscription = stream.stream.listen(
        (_) => controller.add(_pageFor(groupId, pageSize, includeUnpublished)),
        onError: controller.addError,
      );
      controller.onCancel = subscription.cancel;
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
    if (startAfter is! _InMemoryAnnouncementCursor) {
      throw ArgumentError('Cursor belongs to another repository.');
    }
    final all = _itemsFor(groupId, includeUnpublished: includeUnpublished);
    final start = all.indexWhere((item) => item.id == startAfter.id);
    if (start < 0) {
      return const ClassroomAnnouncementPage(items: [], hasMore: false);
    }
    final remaining = all.skip(start + 1).toList(growable: false);
    final items = remaining.take(pageSize).toList(growable: false);
    return ClassroomAnnouncementPage(
      items: items,
      hasMore: remaining.length > pageSize,
      nextCursor: remaining.length > pageSize && items.isNotEmpty
          ? _InMemoryAnnouncementCursor(items.last.id)
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
    final item = ClassroomAnnouncement(
      id: _generateId(),
      groupId: groupId,
      teacherId: teacherId,
      title: _validatedTitle(title),
      body: _validatedBody(body),
      createdAt: now,
      publishAt: _validatePublishAt(publishAt),
    );
    announcements[item.id] = item;
    _emit(groupId);
    return item;
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
    final existing = announcements[announcementId];
    if (existing == null ||
        existing.groupId != groupId ||
        existing.teacherId != teacherId) {
      throw StateError('Announcement is not available.');
    }
    announcements[announcementId] = existing.copyWith(
      title: _validatedTitle(title),
      body: _validatedBody(body),
      editedAt: now,
      publishAt: _validatePublishAt(publishAt),
      clearPublishAt: publishAt == null,
    );
    _emit(groupId);
  }

  @override
  Future<void> deleteAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
  }) async {
    final existing = announcements[announcementId];
    if (existing == null ||
        existing.groupId != groupId ||
        existing.teacherId != teacherId) {
      throw StateError('Announcement is not available.');
    }
    announcements.remove(announcementId);
    if (pinnedAnnouncementIds[groupId] == announcementId) {
      pinnedAnnouncementIds.remove(groupId);
    }
    _emit(groupId);
  }

  @override
  Future<void> setPinnedAnnouncement({
    required String groupId,
    required String teacherId,
    String? announcementId,
  }) async {
    final normalized = announcementId?.trim();
    if (normalized == null || normalized.isEmpty) {
      pinnedAnnouncementIds.remove(groupId);
      _emit(groupId);
      return;
    }
    final target = announcements[normalized];
    if (target == null ||
        target.groupId != groupId ||
        target.teacherId != teacherId) {
      throw StateError('Announcement is not available.');
    }
    if (!target.isPublishedAt(now)) {
      throw StateError('A scheduled announcement cannot be pinned.');
    }
    pinnedAnnouncementIds[groupId] = normalized;
    announcements[normalized] = target.copyWith(isPinned: true, pinnedAt: now);
    _emit(groupId);
  }

  ClassroomAnnouncementPage _pageFor(
    String groupId,
    int pageSize,
    bool includeUnpublished,
  ) {
    final all = _itemsFor(groupId, includeUnpublished: includeUnpublished);
    final items = all.take(pageSize).toList(growable: false);
    return ClassroomAnnouncementPage(
      items: items,
      hasMore: all.length > pageSize,
      nextCursor: all.length > pageSize && items.isNotEmpty
          ? _InMemoryAnnouncementCursor(items.last.id)
          : null,
    );
  }

  List<ClassroomAnnouncement> _itemsFor(
    String groupId, {
    bool includeUnpublished = false,
  }) {
    final pinnedId = pinnedAnnouncementIds[groupId];
    final items = announcements.values
        .where(
          (item) =>
              item.groupId == groupId &&
              (includeUnpublished || item.isPublishedAt(now)),
        )
        .map(
          (item) => item.copyWith(
            isPinned: item.id == pinnedId,
            pinnedAt: item.id == pinnedId ? item.pinnedAt : null,
            clearPinnedAt: item.id != pinnedId,
          ),
        )
        .toList(growable: false);
    items.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final byTime = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return items;
  }

  void _emit(String groupId) => _streams[groupId]?.add(_itemsFor(groupId));

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

  DateTime? _validatePublishAt(DateTime? value) {
    if (value == null) return null;
    final at = value.toUtc();
    if (!at.isAfter(now)) {
      throw ArgumentError('Publication time must be in the future.');
    }
    return at;
  }
}

class _InMemoryAnnouncementCursor extends ClassroomAnnouncementCursor {
  const _InMemoryAnnouncementCursor(this.id);

  final String id;
}
