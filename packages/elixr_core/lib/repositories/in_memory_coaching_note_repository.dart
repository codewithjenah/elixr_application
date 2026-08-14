import '../models/coaching_note.dart';
import '../models/coaching_note_exception.dart';
import 'coaching_note_repository.dart';

/// Test implementation. Callers may configure [approvedPairs] to mimic the
/// relationship rule without needing Firebase.
class InMemoryCoachingNoteRepository implements CoachingNoteRepository {
  final List<CoachingNote> notes = [];
  final Set<String> approvedPairs = {};
  int _nextId = 0;
  String _pair(String teacher, String trainee) => '${teacher}_$trainee';
  bool _approved(String teacher, String trainee) =>
      approvedPairs.contains(_pair(teacher, trainee));
  @override
  Future<CoachingNotePage> fetchForTeacher({
    required String teacherId,
    required String traineeId,
    int pageSize = CoachingNoteRepository.defaultPageSize,
    CoachingNoteCursor? startAfter,
  }) => _page(
    notes.where((n) => n.teacherId == teacherId && n.traineeId == traineeId),
    pageSize,
    startAfter,
  );
  @override
  Future<CoachingNotePage> fetchReceived({
    required String traineeId,
    int pageSize = CoachingNoteRepository.defaultPageSize,
    CoachingNoteCursor? startAfter,
  }) =>
      _page(notes.where((n) => n.traineeId == traineeId), pageSize, startAfter);
  Future<CoachingNotePage> _page(
    Iterable<CoachingNote> source,
    int size,
    CoachingNoteCursor? cursor,
  ) async {
    CoachingNoteRepository.validatePageSize(size);
    final all = source.toList()
      ..sort((a, b) {
        final time = b.createdAt.compareTo(a.createdAt);
        return time != 0 ? time : b.id.compareTo(a.id);
      });
    final offset = cursor is _MemoryCursor ? cursor.offset : 0;
    if (cursor != null && cursor is! _MemoryCursor)
      throw ArgumentError('Cursor belongs to another repository');
    final page = all.skip(offset).take(size).toList();
    final next = offset + page.length;
    return CoachingNotePage(
      notes: page,
      hasMore: next < all.length,
      nextCursor: next < all.length ? _MemoryCursor(next) : null,
    );
  }

  @override
  Future<CoachingNote> createNote({
    required String teacherId,
    required String traineeId,
    required String body,
    String? movementName,
  }) async {
    final error = CoachingNote.validateDraft(
      body: body,
      movementName: movementName,
    );
    if (error != null)
      throw CoachingNoteException(CoachingNoteError.invalidNote, error);
    if (!_approved(teacherId, traineeId))
      throw const CoachingNoteException(CoachingNoteError.relationshipRequired);
    final now = DateTime.now().toUtc();
    final note = CoachingNote(
      id: 'note_${++_nextId}',
      teacherId: teacherId,
      traineeId: traineeId,
      teacherDisplayName: 'Teacher',
      body: body.trim(),
      movementName: movementName,
      createdAt: now,
      updatedAt: now,
    );
    notes.add(note);
    return note;
  }

  @override
  Future<CoachingNote> updateNote({
    required String noteId,
    required String teacherId,
    required String traineeId,
    required String body,
    String? movementName,
  }) async {
    final error = CoachingNote.validateDraft(
      body: body,
      movementName: movementName,
    );
    if (error != null)
      throw CoachingNoteException(CoachingNoteError.invalidNote, error);
    if (!_approved(teacherId, traineeId))
      throw const CoachingNoteException(CoachingNoteError.relationshipRequired);
    final i = notes.indexWhere(
      (n) =>
          n.id == noteId &&
          n.teacherId == teacherId &&
          n.traineeId == traineeId,
    );
    if (i < 0) throw const CoachingNoteException(CoachingNoteError.notFound);
    final old = notes[i];
    final changed = CoachingNote(
      id: old.id,
      teacherId: old.teacherId,
      traineeId: old.traineeId,
      teacherDisplayName: old.teacherDisplayName,
      body: body.trim(),
      movementName: movementName,
      createdAt: old.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    notes[i] = changed;
    return changed;
  }

  @override
  Future<void> deleteNote({
    required String noteId,
    required String teacherId,
    required String traineeId,
  }) async {
    if (!_approved(teacherId, traineeId))
      throw const CoachingNoteException(CoachingNoteError.relationshipRequired);
    final i = notes.indexWhere(
      (n) =>
          n.id == noteId &&
          n.teacherId == teacherId &&
          n.traineeId == traineeId,
    );
    if (i < 0) throw const CoachingNoteException(CoachingNoteError.notFound);
    notes.removeAt(i);
  }
}

class _MemoryCursor extends CoachingNoteCursor {
  const _MemoryCursor(this.offset);
  final int offset;
}
