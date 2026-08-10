import 'package:flutter/foundation.dart';

import '../../data/models/leaderboard_award_plan.dart';
import '../../data/models/leaderboard_entry.dart';
import '../../data/models/leaderboard_period.dart';
import '../../data/repositories/leaderboard_repository.dart';

typedef LeaderboardPageFetcher =
    Future<LeaderboardPage> Function({LeaderboardPageCursor? startAfter});

typedef LeaderboardPeriodPageFetcher =
    Future<LeaderboardPage> Function({
      required LeaderboardPeriod period,
      LeaderboardPageCursor? startAfter,
    });

class LeaderboardListController extends ChangeNotifier {
  LeaderboardListController({
    LeaderboardPageFetcher? fetchPage,
    LeaderboardPeriodPageFetcher? fetchPageForPeriod,
    LeaderboardPeriod initialPeriod = LeaderboardPeriod.allTime,
  }) : _fetchPage = _resolveFetcher(fetchPage, fetchPageForPeriod),
       _period = initialPeriod;

  final LeaderboardPeriodPageFetcher _fetchPage;

  List<LeaderboardEntry> entries = const [];
  bool isInitialLoading = false;
  bool isLoadingMore = false;
  bool hasMore = false;
  Object? initialError;
  Object? loadMoreError;

  LeaderboardPeriod _period;
  LeaderboardPeriod get period => _period;

  LeaderboardPageCursor? _nextCursor;
  int _generation = 1;
  bool _disposed = false;
  bool _hasLoadedAdditionalPage = false;
  String? _syncStartedForUserId;
  bool _pendingPostSyncRefresh = false;
  bool _didAutoRefreshAfterSync = false;

  Future<void> loadInitial() => _loadFirstPage();

  /// Switches the single persistent list to [period] and starts a clean page-1
  /// load. In-flight work from the previous period is invalidated before the
  /// visible rows and pagination cursor are reset, so periods can never mix.
  Future<void> setPeriod(LeaderboardPeriod period) {
    if (_disposed || period == _period) return Future<void>.value();

    _generation++;
    _period = period;
    entries = const [];
    isInitialLoading = false;
    isLoadingMore = false;
    _nextCursor = null;
    hasMore = false;
    initialError = null;
    loadMoreError = null;
    _hasLoadedAdditionalPage = false;
    return _loadFirstPage();
  }

  Future<void> refresh() {
    _generation++;
    final preserveEntries = entries.isNotEmpty;
    isLoadingMore = false;
    if (!preserveEntries) {
      entries = const [];
    }
    _nextCursor = null;
    hasMore = false;
    loadMoreError = null;
    initialError = null;
    _hasLoadedAdditionalPage = false;
    _didAutoRefreshAfterSync = false;
    return _loadFirstPage(preserveEntries: preserveEntries);
  }

  Future<void> loadMore() async {
    if (_disposed || isLoadingMore || isInitialLoading || !hasMore) return;

    final generation = _generation;
    final cursor = _nextCursor;
    isLoadingMore = true;
    loadMoreError = null;
    _notifyIfActive();

    try {
      final page = await _fetchPage(period: _period, startAfter: cursor);
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
    } on LeaderboardPageCursorExpiredException {
      if (_disposed || generation != _generation) return;
      _generation++;
      entries = const [];
      isLoadingMore = false;
      _nextCursor = null;
      hasMore = false;
      initialError = null;
      loadMoreError = null;
      _hasLoadedAdditionalPage = false;
      await _loadFirstPage();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      loadMoreError = error;
    } finally {
      if (!_disposed && generation == _generation) {
        isLoadingMore = false;
        _notifyIfActive();
      }
    }
  }

  Future<void> startBackgroundSync({
    required String userId,
    required Future<LeaderboardSyncResult> Function() syncUser,
    bool force = false,
  }) async {
    if (_disposed) return;
    if (!force && _syncStartedForUserId == userId) return;
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

  Future<void> _loadFirstPage({bool preserveEntries = false}) async {
    if (_disposed) return;

    final generation = _generation;
    final blockingLoad = !preserveEntries || entries.isEmpty;
    if (blockingLoad) {
      isInitialLoading = true;
    }
    initialError = null;
    _notifyIfActive();

    try {
      final page = await _fetchPage(period: _period, startAfter: null);
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
        if (blockingLoad) {
          isInitialLoading = false;
        }
        _notifyIfActive();
        if (initialError == null && _pendingPostSyncRefresh) {
          _maybeTriggerAutoRefreshAfterSync();
        }
      }
    }
  }

  /// Reloads page 1 without clearing visible [entries] (stale-while-revalidate).
  Future<void> _reloadFirstPageKeepingEntries() {
    _generation++;
    _nextCursor = null;
    hasMore = false;
    loadMoreError = null;
    return _loadFirstPage(preserveEntries: true);
  }

  void _handleSyncResult(LeaderboardSyncResult result) {
    if (_disposed) return;
    if (result.newlyProcessed <= 0 && !result.publicProfileSynced) return;

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
    _reloadFirstPageKeepingEntries();
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

LeaderboardPeriodPageFetcher _resolveFetcher(
  LeaderboardPageFetcher? fetchPage,
  LeaderboardPeriodPageFetcher? fetchPageForPeriod,
) {
  if (fetchPageForPeriod != null) return fetchPageForPeriod;
  if (fetchPage != null) {
    return ({
      required LeaderboardPeriod period,
      LeaderboardPageCursor? startAfter,
    }) => fetchPage(startAfter: startAfter);
  }
  throw ArgumentError('Either fetchPage or fetchPageForPeriod is required.');
}
