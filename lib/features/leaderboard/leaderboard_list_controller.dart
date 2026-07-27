import 'package:flutter/foundation.dart';

import '../../data/models/leaderboard_award_plan.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/repositories/leaderboard_repository.dart';

class LeaderboardListController extends ChangeNotifier {
  LeaderboardListController({
    required Future<LeaderboardPage> Function({
      LeaderboardPageCursor? startAfter,
    })
    fetchPage,
  }) : _fetchPage = fetchPage;

  final Future<LeaderboardPage> Function({LeaderboardPageCursor? startAfter})
  _fetchPage;

  List<LeaderboardEntry> entries = const [];
  bool isInitialLoading = false;
  bool isLoadingMore = false;
  bool hasMore = false;
  Object? initialError;
  Object? loadMoreError;

  LeaderboardPageCursor? _nextCursor;
  int _generation = 1;
  bool _disposed = false;
  bool _hasLoadedAdditionalPage = false;
  String? _syncStartedForUserId;
  bool _pendingPostSyncRefresh = false;
  bool _didAutoRefreshAfterSync = false;

  Future<void> loadInitial() => _loadFirstPage();

  Future<void> refresh() {
    _generation++;
    entries = const [];
    _nextCursor = null;
    hasMore = false;
    loadMoreError = null;
    initialError = null;
    _hasLoadedAdditionalPage = false;
    return _loadFirstPage();
  }

  Future<void> loadMore() async {
    if (_disposed || isLoadingMore || isInitialLoading || !hasMore) return;

    final generation = _generation;
    final cursor = _nextCursor;
    isLoadingMore = true;
    loadMoreError = null;
    _notifyIfActive();

    try {
      final page = await _fetchPage(startAfter: cursor);
      if (_disposed || generation != _generation) return;

      if (page.entries.isEmpty) {
        hasMore = false;
        _nextCursor = null;
      } else {
        entries = _appendDeduped(entries, page.entries);
        hasMore = page.hasMore;
        _nextCursor = page.nextCursor;
        _hasLoadedAdditionalPage = true;
      }
    } catch (error) {
      if (_disposed || generation != _generation) return;
      loadMoreError = error;
    } finally {
      if (!_disposed) {
        isLoadingMore = false;
        if (generation == _generation) {
          _notifyIfActive();
        }
      }
    }
  }

  Future<void> startBackgroundSync({
    required String userId,
    required Future<LeaderboardSyncResult> Function() syncUser,
  }) async {
    if (_disposed) return;
    if (_syncStartedForUserId == userId) return;
    _syncStartedForUserId = userId;

    try {
      final result = await syncUser();
      if (_disposed) return;
      _handleSyncResult(result);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Background leaderboard sync failed: userId=$userId error=$error',
        );
        debugPrint('$stackTrace');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    if (_disposed) return;

    final generation = _generation;
    isInitialLoading = true;
    initialError = null;
    _notifyIfActive();

    try {
      final page = await _fetchPage(startAfter: null);
      if (_disposed || generation != _generation) return;

      entries = List<LeaderboardEntry>.unmodifiable(page.entries);
      hasMore = page.hasMore;
      _nextCursor = page.nextCursor;
      initialError = null;
    } catch (error) {
      if (_disposed || generation != _generation) return;
      initialError = error;
    } finally {
      if (!_disposed && generation == _generation) {
        isInitialLoading = false;
        _notifyIfActive();
        if (initialError == null && _pendingPostSyncRefresh) {
          _maybeTriggerAutoRefreshAfterSync();
        }
      }
    }
  }

  void _handleSyncResult(LeaderboardSyncResult result) {
    if (_disposed || result.newlyProcessed <= 0) return;

    if (isInitialLoading) {
      _pendingPostSyncRefresh = true;
      return;
    }

    if (_hasLoadedAdditionalPage) return;
    _maybeTriggerAutoRefreshAfterSync();
  }

  void _maybeTriggerAutoRefreshAfterSync() {
    if (_disposed || _didAutoRefreshAfterSync || _hasLoadedAdditionalPage) {
      _pendingPostSyncRefresh = false;
      return;
    }

    _didAutoRefreshAfterSync = true;
    _pendingPostSyncRefresh = false;
    refresh();
  }

  List<LeaderboardEntry> _appendDeduped(
    List<LeaderboardEntry> current,
    List<LeaderboardEntry> incoming,
  ) {
    final seen = current.map((entry) => entry.userId).toSet();
    final out = [...current];
    for (final entry in incoming) {
      if (seen.add(entry.userId)) out.add(entry);
    }
    return List<LeaderboardEntry>.unmodifiable(out);
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }
}
