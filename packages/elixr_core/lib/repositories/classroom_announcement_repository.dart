import '../models/classroom_announcement.dart';

abstract class ClassroomAnnouncementCursor {
  const ClassroomAnnouncementCursor();
}

class ClassroomAnnouncementPage {
  const ClassroomAnnouncementPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<ClassroomAnnouncement> items;
  final bool hasMore;
  final ClassroomAnnouncementCursor? nextCursor;
}

abstract class ClassroomAnnouncementRepository {
  static const defaultPageSize = 30;

  Stream<ClassroomAnnouncementPage> watchAnnouncements({
    required String groupId,
    int pageSize = defaultPageSize,
    bool includeUnpublished = false,
  });

  Future<ClassroomAnnouncementPage> fetchOlderAnnouncements({
    required String groupId,
    required ClassroomAnnouncementCursor startAfter,
    int pageSize = defaultPageSize,
    bool includeUnpublished = false,
  });

  Future<ClassroomAnnouncement> createAnnouncement({
    required String groupId,
    required String teacherId,
    required String title,
    required String body,
    DateTime? publishAt,
  });

  Future<void> updateAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
    required String title,
    required String body,
    DateTime? publishAt,
  });

  Future<void> deleteAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
  });

  /// Sets the classroom's single pinned announcement. Passing null unpins the
  /// current announcement. Implementations must update the pointer atomically.
  Future<void> setPinnedAnnouncement({
    required String groupId,
    required String teacherId,
    String? announcementId,
  });
}
