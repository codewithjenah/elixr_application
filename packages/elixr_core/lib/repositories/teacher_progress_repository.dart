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
  Stream<PublicProfileSummary?> watchSummary(String traineeId);
  Future<TeacherProgressPage> fetchSessionsPage({
    required String traineeId,
    int pageSize = 20,
    TeacherProgressCursor? startAfter,
  });
}
