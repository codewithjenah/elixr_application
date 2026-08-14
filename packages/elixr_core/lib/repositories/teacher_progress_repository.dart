import '../models/public_profile_session.dart';
import '../models/public_profile_summary.dart';

abstract class TeacherProgressCursor {
  const TeacherProgressCursor();
}

class TeacherProgressPage {
  const TeacherProgressPage({
    required this.sessions,
    required this.hasMore,
    this.nextCursor,
  });
  final List<PublicProfileSession> sessions;
  final bool hasMore;
  final TeacherProgressCursor? nextCursor;
}

abstract class TeacherProgressRepository {
  static const defaultPageSize = 20;
  static const minimumPageSize = 1;
  static const maximumPageSize = 50;

  static void validatePageSize(int pageSize) {
    if (pageSize < minimumPageSize || pageSize > maximumPageSize) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be 1..50');
    }
  }

  Stream<PublicProfileSummary?> watchSummary(String traineeId);
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId,
    int pageSize = defaultPageSize,
    TeacherProgressCursor? startAfter,
  });
}
