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
  });

  Future<ClassroomAnnouncementPage> fetchOlderAnnouncements({
    required String groupId,
    required ClassroomAnnouncementCursor startAfter,
    int pageSize = defaultPageSize,
  });

  Future<ClassroomAnnouncement> createAnnouncement({
    required String groupId,
    required String teacherId,
    required String title,
    required String body,
  });

  Future<void> updateAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
    required String title,
    required String body,
  });

  Future<void> deleteAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
  });
}
