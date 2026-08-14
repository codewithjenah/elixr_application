import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/foundation.dart';

enum CoachingNotesState { loading, ready, empty, error }

class CoachingNotesController extends ChangeNotifier {
  CoachingNotesController({required this.repository, required this.traineeId});
  final CoachingNoteRepository repository;
  String? traineeId;
  CoachingNotesState state = CoachingNotesState.loading;
  List<CoachingNote> notes = const [];
  CoachingNoteCursor? _cursor;
  bool hasMore = false;
  bool loadingMore = false;
  Object? paginationError;
  int _generation = 0;
  bool _disposed = false;

  Future<void> start(String? userId) async {
    if (traineeId == userId && state != CoachingNotesState.loading) return;
    traineeId = userId;
    await refresh();
  }

  Future<void> refresh() async {
    final id = traineeId;
    final generation = ++_generation;
    notes = const [];
    _cursor = null;
    hasMore = false;
    paginationError = null;
    state = id == null ? CoachingNotesState.empty : CoachingNotesState.loading;
    _notify();
    if (id == null) return;
    try {
      final page = await repository.fetchReceived(traineeId: id);
      if (!_current(generation, id)) return;
      notes = page.notes;
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
      state = notes.isEmpty
          ? CoachingNotesState.empty
          : CoachingNotesState.ready;
    } catch (_) {
      if (_current(generation, id)) state = CoachingNotesState.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    final id = traineeId;
    if (id == null || !hasMore || loadingMore) return;
    final generation = _generation;
    loadingMore = true;
    paginationError = null;
    _notify();
    try {
      final page = await repository.fetchReceived(
        traineeId: id,
        startAfter: _cursor,
      );
      if (!_current(generation, id)) return;
      final ids = notes.map((n) => n.id).toSet();
      notes = [...notes, ...page.notes.where((n) => ids.add(n.id))];
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
    } catch (error) {
      if (_current(generation, id)) paginationError = error;
    } finally {
      if (_current(generation, id)) {
        loadingMore = false;
        _notify();
      }
    }
  }

  Future<void> retryLoadMore() => loadMore();
  void clear() {
    _generation++;
    traineeId = null;
    notes = const [];
    _cursor = null;
    hasMore = false;
    loadingMore = false;
    paginationError = null;
    state = CoachingNotesState.empty;
    _notify();
  }

  bool _current(int generation, String id) =>
      !_disposed && generation == _generation && traineeId == id;
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
