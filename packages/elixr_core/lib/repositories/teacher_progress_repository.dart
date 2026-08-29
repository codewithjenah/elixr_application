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
  static const rangePageSize = maximumPageSize;

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

  /// Returns sanitized session projections in the half-open UTC interval
  /// `[startUtc, endUtc)`.
  ///
  /// The default implementation deliberately uses the existing paged API so
  /// lightweight subclasses and test doubles can reuse the behavior. Firebase
  /// overrides this with a bounded Firestore range query. Callers must not use
  /// this method as a live listener: projections are a best-effort snapshot of
  /// the authorized trainee history.
  Future<List<PublicProfileSession>> fetchSessionsInRange({
    required String traineeId,
    required DateTime startUtc,
    required DateTime endUtc,
  }) async {
    final start = startUtc.toUtc();
    final end = endUtc.toUtc();
    if (!end.isAfter(start)) return const [];

    final sessions = <PublicProfileSession>[];
    TeacherProgressCursor? cursor;
    do {
      final page = await fetchSessionsPage(
        traineeId: traineeId,
        pageSize: rangePageSize,
        startAfter: cursor,
      );
      sessions.addAll(
        page.sessions.where((session) {
          final createdAt = session.createdAt == null
              ? null
              : DateTime.tryParse(session.createdAt!);
          return createdAt != null &&
              !createdAt.toUtc().isBefore(start) &&
              createdAt.toUtc().isBefore(end);
        }),
      );
      if (!page.hasMore) break;
      cursor = page.nextCursor;
    } while (cursor != null);

    return List<PublicProfileSession>.unmodifiable(sessions);
  }
}
