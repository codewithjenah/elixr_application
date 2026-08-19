import '../models/coaching_note.dart';

abstract class CoachingNoteCursor {
  const CoachingNoteCursor();
}

class CoachingNotePage {
  const CoachingNotePage({
    required this.notes,
    required this.hasMore,
    this.nextCursor,
  });
  final List<CoachingNote> notes;
  final bool hasMore;
  final CoachingNoteCursor? nextCursor;
}

abstract class CoachingNoteRepository {
  static const defaultPageSize = 20;
  static void validatePageSize(int pageSize) {
    if (pageSize < 1 || pageSize > 50)
      throw ArgumentError.value(pageSize, 'pageSize', 'must be 1..50');
  }

  Future<CoachingNotePage> fetchForTeacher({
    required String teacherId,
    required String traineeId,
    String? groupId,
    int pageSize = defaultPageSize,
    CoachingNoteCursor? startAfter,
  });
  Future<CoachingNotePage> fetchReceived({
    required String traineeId,
    int pageSize = defaultPageSize,
    CoachingNoteCursor? startAfter,
  });
  Future<CoachingNote> createNote({
    required String teacherId,
    required String traineeId,
    required String body,
    String? movementName,
    String? groupId,
  });
  Future<CoachingNote> updateNote({
    required String noteId,
    required String teacherId,
    required String traineeId,
    required String body,
    String? movementName,
  });
  Future<void> deleteNote({
    required String noteId,
    required String teacherId,
    required String traineeId,
  });
}
