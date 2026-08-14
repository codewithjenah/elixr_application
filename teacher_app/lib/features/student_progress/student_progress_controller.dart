import 'dart:async';

import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/foundation.dart';

enum StudentProgressState {
  loadingRelationship,
  waitingForAccess,
  loading,
  ready,
  empty,
  accessWithdrawn,
  relationshipRevoked,
  connectionRequired,
  error,
}

class StudentProgressController extends ChangeNotifier {
  StudentProgressController({
    required this.relationships,
    required this.progress,
    required this.teacherId,
    required this.traineeId,
  });
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
  Object? paginationError;
  StudentProgressState state = StudentProgressState.loadingRelationship;
  StreamSubscription<TeacherStudentLinkSnapshot>? _linkSub;
  StreamSubscription<PublicProfileSummary?>? _summarySub;
  int _accessEpoch = 0;
  int _pageEpoch = 0;
  bool _active = false;
  bool _hadEffectiveAccess = false;
  bool _firstSummarySettled = false;
  bool _firstPageSettled = false;
  bool _disposed = false;

  Future<void> start() async {
    final epoch = ++_accessEpoch;
    _pageEpoch++;
    _active = true;
    await _summarySub?.cancel();
    await _linkSub?.cancel();
    if (_disposed || epoch != _accessEpoch || !_active) return;
    _summarySub = null;
    _resetData(StudentProgressState.loadingRelationship);
    _linkSub = relationships
        .watchLink(teacherId: teacherId, traineeId: traineeId)
        .listen(
          (snapshot) => _onLink(snapshot, epoch),
          onError: (_) => _clear(StudentProgressState.connectionRequired),
        );
  }

  void _onLink(TeacherStudentLinkSnapshot snapshot, int epoch) {
    if (!_isCurrentAccess(epoch)) return;
    final wasApproved = link?.isApproved ?? false;
    link = snapshot.link;
    if (!snapshot.isServerVerified) {
      return _clear(StudentProgressState.connectionRequired);
    }
    if (link == null || !link!.isApproved) {
      return _clear(StudentProgressState.relationshipRevoked);
    }
    if (!wasApproved) {
      _hadEffectiveAccess = false;
    }
    if (!link!.hasEffectiveProgressAccess) {
      return _clear(
        _hadEffectiveAccess
            ? StudentProgressState.accessWithdrawn
            : StudentProgressState.waitingForAccess,
      );
    }
    _hadEffectiveAccess = true;
    if (_summarySub == null) {
      _beginLoading(epoch);
    }
  }

  void _beginLoading(int epoch) {
    if (!_isCurrentAccess(epoch)) return;
    final pageEpoch = ++_pageEpoch;
    state = StudentProgressState.loading;
    _firstSummarySettled = false;
    _firstPageSettled = false;
    sessions = const [];
    summary = null;
    _cursor = null;
    hasMore = false;
    paginationError = null;
    notifyListeners();
    _summarySub = progress
        .watchSummary(traineeId)
        .listen(
          (value) {
            if (!_isCurrentAccess(epoch)) return;
            summary = value;
            _firstSummarySettled = true;
            _setStateFromData();
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_isCurrentAccess(epoch)) return;
            final next =
                error is TeacherProgressException &&
                    error.code == TeacherProgressError.accessWithdrawn
                ? StudentProgressState.accessWithdrawn
                : StudentProgressState.error;
            _clear(next);
          },
        );
    _loadPage(epoch, pageEpoch, firstPage: true);
  }

  Future<void> refresh() async {
    await start();
  }

  Future<void> retry() => refresh();

  Future<void> loadMore() async {
    if (loadingMore ||
        !hasMore ||
        !_active ||
        link?.hasEffectiveProgressAccess != true) {
      return;
    }
    await _loadPage(_accessEpoch, ++_pageEpoch);
  }

  Future<void> retryLoadMore() => loadMore();

  Future<void> _loadPage(
    int accessEpoch,
    int pageEpoch, {
    bool firstPage = false,
  }) async {
    loadingMore = true;
    if (!firstPage) {
      paginationError = null;
    }
    notifyListeners();
    try {
      final page = await progress.fetchSessionsPage(
        traineeId: traineeId,
        startAfter: _cursor,
      );
      if (!_isCurrent(accessEpoch, pageEpoch)) return;
      final known = sessions.map((item) => item.sessionId).toSet();
      sessions = [
        ...sessions,
        ...page.sessions.where((item) => known.add(item.sessionId)),
      ];
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
      _firstPageSettled = true;
      _setStateFromData();
    } on TeacherProgressException catch (error) {
      if (!_isCurrent(accessEpoch, pageEpoch)) return;
      if (error.code == TeacherProgressError.accessWithdrawn) {
        _clear(StudentProgressState.accessWithdrawn);
      } else if (firstPage) {
        _clear(StudentProgressState.error);
      } else {
        paginationError = error;
      }
    } finally {
      if (_isCurrent(accessEpoch, pageEpoch)) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  bool _isCurrentAccess(int epoch) =>
      !_disposed && _active && epoch == _accessEpoch;
  bool _isCurrent(int accessEpoch, int pageEpoch) =>
      _isCurrentAccess(accessEpoch) && pageEpoch == _pageEpoch;

  void _setStateFromData() {
    if (!_firstSummarySettled || !_firstPageSettled) return;
    final noSummary =
        summary == null ||
        (summary!.totalDurationSeconds == 0 &&
            summary!.completedMovementNames.isEmpty);
    state = sessions.isEmpty && noSummary
        ? StudentProgressState.empty
        : StudentProgressState.ready;
    notifyListeners();
  }

  void pause() {
    _active = false;
    _accessEpoch++;
    _pageEpoch++;
    _linkSub?.cancel();
    _linkSub = null;
    _clear(StudentProgressState.connectionRequired);
  }

  void _clear(StudentProgressState next) {
    _pageEpoch++;
    _summarySub?.cancel();
    _summarySub = null;
    _resetData(next);
  }

  void _resetData(StudentProgressState next) {
    summary = null;
    sessions = const [];
    _cursor = null;
    hasMore = false;
    loadingMore = false;
    paginationError = null;
    _firstSummarySettled = false;
    _firstPageSettled = false;
    state = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    _accessEpoch++;
    _pageEpoch++;
    _linkSub?.cancel();
    _summarySub?.cancel();
    super.dispose();
  }
}
