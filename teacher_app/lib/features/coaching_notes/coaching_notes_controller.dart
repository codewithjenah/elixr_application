import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/foundation.dart';

enum TeacherCoachingNotesState {
  initial,
  loading,
  ready,
  empty,
  relationshipRequired,
  error,
}

class TeacherCoachingNotesController extends ChangeNotifier {
  TeacherCoachingNotesController({
    required this.repository,
    required this.teacherId,
    required this.traineeId,
  });
  final CoachingNoteRepository repository;
  final String teacherId;
  final String traineeId;
  TeacherCoachingNotesState state = TeacherCoachingNotesState.initial;
  List<CoachingNote> notes = const [];
  CoachingNoteCursor? _cursor;
  bool hasMore = false;
  bool loadingMore = false;
  Object? paginationError;
  bool saving = false;
  String? deletingId;
  int _generation = 0;
  bool _active = false;
  bool _disposed = false;
  bool get canAuthor =>
      _active &&
      !_disposed &&
      state != TeacherCoachingNotesState.relationshipRequired;
  Future<void> start() async {
    _active = true;
    await refresh();
  }

  void pause() {
    _active = false;
    _generation++;
    notes = const [];
    _cursor = null;
    hasMore = false;
    paginationError = null;
    state = TeacherCoachingNotesState.relationshipRequired;
    _notify();
  }

  Future<void> refresh() async {
    if (!_active) return;
    final g = ++_generation;
    state = TeacherCoachingNotesState.loading;
    notes = const [];
    _cursor = null;
    hasMore = false;
    paginationError = null;
    _notify();
    try {
      final page = await repository.fetchForTeacher(
        teacherId: teacherId,
        traineeId: traineeId,
      );
      if (!_current(g)) {
        return;
      }
      notes = page.notes;
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
      state = notes.isEmpty
          ? TeacherCoachingNotesState.empty
          : TeacherCoachingNotesState.ready;
    } on CoachingNoteException catch (e) {
      if (_current(g)) {
        state = _relationship(e)
            ? TeacherCoachingNotesState.relationshipRequired
            : TeacherCoachingNotesState.error;
      }
    } catch (_) {
      if (_current(g)) state = TeacherCoachingNotesState.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (!_active || !hasMore || loadingMore) return;
    final g = _generation;
    loadingMore = true;
    paginationError = null;
    _notify();
    try {
      final page = await repository.fetchForTeacher(
        teacherId: teacherId,
        traineeId: traineeId,
        startAfter: _cursor,
      );
      if (!_current(g)) return;
      final ids = notes.map((n) => n.id).toSet();
      notes = [...notes, ...page.notes.where((n) => ids.add(n.id))];
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
    } catch (e) {
      if (_current(g)) paginationError = e;
    } finally {
      if (_current(g)) {
        loadingMore = false;
        _notify();
      }
    }
  }

  Future<void> create(String body, String? movement) => _mutate(
    () => repository.createNote(
      teacherId: teacherId,
      traineeId: traineeId,
      body: body,
      movementName: movement,
    ),
  );
  Future<void> update(CoachingNote note, String body, String? movement) =>
      _mutate(
        () => repository.updateNote(
          noteId: note.id,
          teacherId: teacherId,
          traineeId: traineeId,
          body: body,
          movementName: movement,
        ),
      );
  Future<void> _mutate(Future<CoachingNote> Function() action) async {
    _requireActiveRelationship();
    saving = true;
    _notify();
    try {
      await action();
      await refresh();
    } on CoachingNoteException catch (e) {
      if (_relationship(e)) pause();
      rethrow;
    } finally {
      saving = false;
      _notify();
    }
  }

  Future<void> delete(CoachingNote note) async {
    _requireActiveRelationship();
    deletingId = note.id;
    _notify();
    try {
      await repository.deleteNote(
        noteId: note.id,
        teacherId: teacherId,
        traineeId: traineeId,
      );
      await refresh();
    } on CoachingNoteException catch (e) {
      if (_relationship(e)) pause();
      rethrow;
    } finally {
      deletingId = null;
      _notify();
    }
  }

  bool _relationship(CoachingNoteException e) =>
      e.code == CoachingNoteError.relationshipRequired ||
      e.code == CoachingNoteError.permissionDenied;
  void _requireActiveRelationship() {
    if (!canAuthor) {
      throw const CoachingNoteException(CoachingNoteError.relationshipRequired);
    }
  }

  bool _current(int g) => !_disposed && _active && g == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
