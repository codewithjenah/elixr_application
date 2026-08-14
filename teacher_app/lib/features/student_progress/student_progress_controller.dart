import 'dart:async';

import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/foundation.dart';

enum StudentProgressState { loadingRelationship, waitingForAccess, loading, ready, empty, withdrawn, connectionRequired, error }

class StudentProgressController extends ChangeNotifier {
  StudentProgressController({required this.relationships, required this.progress, required this.teacherId, required this.traineeId});
  final TeacherRelationshipRepository relationships;
  final TeacherProgressRepository progress;
  final String teacherId;
  final String traineeId;
  TeacherStudentLink? link;
  PublicProfileSummary? summary;
  List<PublicProfileSession> sessions = const [];
  TeacherProgressCursor? _cursor;
  bool hasMore = false;
  bool loadingMore = false;
  StudentProgressState state = StudentProgressState.loadingRelationship;
  StreamSubscription<TeacherStudentLinkSnapshot>? _linkSub;
  StreamSubscription<PublicProfileSummary?>? _summarySub;
  int _generation = 0;
  bool _disposed = false;

  Future<void> start() async {
    await _linkSub?.cancel();
    _linkSub = relationships.watchLink(teacherId: teacherId, traineeId: traineeId).listen(_onLink, onError: (_) => _clear(StudentProgressState.connectionRequired));
  }

  void _onLink(TeacherStudentLinkSnapshot snapshot) {
    link = snapshot.link;
    if (!snapshot.isServerVerified) return _clear(StudentProgressState.connectionRequired);
    if (link == null || !link!.isApproved) return _clear(StudentProgressState.withdrawn);
    if (!link!.hasEffectiveProgressAccess) return _clear(StudentProgressState.waitingForAccess);
    if (_summarySub == null) _beginLoading();
  }

  void _beginLoading() {
    final generation = ++_generation;
    state = StudentProgressState.loading;
    notifyListeners();
    _summarySub = progress.watchSummary(traineeId).listen((value) {
      if (generation != _generation) return;
      summary = value;
      _setStateFromData();
    }, onError: (_) => _clear(StudentProgressState.withdrawn));
    refresh();
  }

  Future<void> refresh() async {
    if (link?.hasEffectiveProgressAccess != true) return;
    final generation = _generation;
    sessions = const [];
    _cursor = null;
    hasMore = false;
    await _loadPage(generation);
  }

  Future<void> loadMore() async {
    if (loadingMore || !hasMore) return;
    await _loadPage(_generation);
  }

  Future<void> _loadPage(int generation) async {
    loadingMore = true;
    notifyListeners();
    try {
      final page = await progress.fetchSessionsPage(traineeId: traineeId, startAfter: _cursor);
      if (generation != _generation) return;
      final known = sessions.map((item) => item.sessionId).toSet();
      sessions = [...sessions, ...page.sessions.where((item) => known.add(item.sessionId))];
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
      _setStateFromData();
    } on TeacherProgressException catch (error) {
      if (generation == _generation) _clear(error.code == TeacherProgressError.accessWithdrawn ? StudentProgressState.withdrawn : StudentProgressState.error);
    } finally {
      if (generation == _generation) { loadingMore = false; notifyListeners(); }
    }
  }

  void _setStateFromData() { state = sessions.isEmpty && summary == null ? StudentProgressState.empty : StudentProgressState.ready; notifyListeners(); }
  void pause() => _clear(StudentProgressState.connectionRequired);
  void _clear(StudentProgressState next) {
    _generation++; _summarySub?.cancel(); _summarySub = null; summary = null; sessions = const []; _cursor = null; hasMore = false; loadingMore = false; state = next; if (!_disposed) notifyListeners();
  }
  @override void dispose() { _disposed = true; _generation++; _linkSub?.cancel(); _summarySub?.cancel(); super.dispose(); }
}
