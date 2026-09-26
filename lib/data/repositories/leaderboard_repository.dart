import 'package:elixr_core/database/supabase_support.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;

import '../models/leaderboard_award_plan.dart';
import '../models/leaderboard_entry.dart';
import '../models/leaderboard_period.dart';

/// Opaque pagination cursor. UI stores and returns it; never unwraps it.
abstract class LeaderboardPageCursor {
  LeaderboardPeriod get period;
  String? get periodKey;
}

@visibleForTesting
class FakeLeaderboardPageCursor implements LeaderboardPageCursor {
  FakeLeaderboardPageCursor(
    this.id, {
    this.period = LeaderboardPeriod.allTime,
    this.periodKey,
  });

  final String id;

  @override
  final LeaderboardPeriod period;

  @override
  final String? periodKey;
}

/// Keyset cursor over the shared order: period XP desc, best desc, UID asc.
class _KeysetLeaderboardPageCursor implements LeaderboardPageCursor {
  _KeysetLeaderboardPageCursor({
    required this.xp,
    required this.bestScore,
    required this.userId,
    required this.period,
    required this.periodKey,
  });

  final int xp;
  final int bestScore;
  final String userId;

  @override
  final LeaderboardPeriod period;

  @override
  final String? periodKey;

  String get keysetFilter {
    final xpField = period.xpField;
    final bestField = period.bestScoreField;
    return '$xpField.lt.$xp,'
        'and($xpField.eq.$xp,$bestField.lt.$bestScore),'
        'and($xpField.eq.$xp,$bestField.eq.$bestScore,user_id.gt.$userId)';
  }
}

/// Signals that a pagination cursor belongs to a different resolved period.
///
/// This most commonly occurs when a Today/This month page crosses a Manila
/// day or month boundary between page requests. Callers must restart at page 1
/// instead of retrying the expired cursor or appending a different period.
class LeaderboardPageCursorExpiredException implements Exception {
  const LeaderboardPageCursorExpiredException({
    required this.cursorPeriod,
    required this.cursorPeriodKey,
    required this.requestedPeriod,
    required this.requestedPeriodKey,
  });

  final LeaderboardPeriod cursorPeriod;
  final String? cursorPeriodKey;
  final LeaderboardPeriod requestedPeriod;
  final String? requestedPeriodKey;

  @override
  String toString() => 'Leaderboard pagination period changed';
}

class LeaderboardPage {
  const LeaderboardPage({
    required this.entries,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<LeaderboardEntry> entries;
  final LeaderboardPageCursor? nextCursor;
  final bool hasMore;
}

class LeaderboardRepository {
  LeaderboardRepository({
    SupabaseClient? client,
    String? Function()? productUserId,
  }) : _clientOverride = client,
       _productUserId = productUserId;

  final SupabaseClient? _clientOverride;
  final String? Function()? _productUserId;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  /// In-flight sync futures keyed by userId to prevent duplicate concurrent runs.
  static final Map<String, Future<LeaderboardSyncResult>> _syncInFlight = {};

  @visibleForTesting
  static void clearSyncInFlightForTest() => _syncInFlight.clear();

  static final Map<String, DateTime> _lastActiveWriteAt = {};
  static final Map<String, Future<bool>> _lastActiveInFlight = {};

  @visibleForTesting
  static void clearLastActiveTouchForTest() {
    _lastActiveWriteAt.clear();
    _lastActiveInFlight.clear();
  }

  /// Updates `last_active_at` on the caller's existing leaderboard row.
  ///
  /// Never creates a zero-XP ranking row. The server enforces at most one
  /// write per [LeaderboardPresencePolicy.minInterval]; the client also
  /// rate-limits requests. Never mutates XP, session, period, quest,
  /// identity, or cosmetic fields, and does not touch `updated_at`.
  Future<bool> touchLastActive({required String userId, DateTime? nowUtc}) {
    final trimmed = userId.trim();
    if (trimmed.isEmpty) return Future<bool>.value(false);
    if (!_isCurrentOwner(trimmed)) return Future<bool>.value(false);

    final existing = _lastActiveInFlight[trimmed];
    if (existing != null) return existing;

    final future = _touchLastActiveImpl(userId: trimmed, nowUtc: nowUtc)
        .whenComplete(() {
          _lastActiveInFlight.remove(trimmed);
        });
    _lastActiveInFlight[trimmed] = future;
    return future;
  }

  Future<bool> _touchLastActiveImpl({
    required String userId,
    DateTime? nowUtc,
  }) async {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    if (!LeaderboardPresencePolicy.shouldWrite(
      documentExists: true,
      nowUtc: now,
      lastWriteUtc: _lastActiveWriteAt[userId],
    )) {
      return false;
    }
    try {
      if (!_isCurrentOwner(userId)) return false;
      final wrote = await _client.rpc<dynamic>('touch_leaderboard_presence');
      // Rate-limit missing-row and too-recent outcomes as well as writes so
      // login/resume cannot poll the server every foreground event.
      _lastActiveWriteAt[userId] = now;
      return wrote == true;
    } catch (error, stackTrace) {
      _logError('touchLastActive', error, stackTrace, userId: userId);
      return false;
    }
  }

  bool _isCurrentOwner(String requestedUserId) {
    return LeaderboardPresencePolicy.isAuthenticatedOwner(
      requestedUserId: requestedUserId,
      currentAuthUid: _currentAuthUid,
    );
  }

  String? get _currentAuthUid {
    try {
      return _client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Stream<List<LeaderboardEntry>> watchTopPlayers({
    int limit = 10,
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
    DateTime? nowUtc,
  }) {
    final periodKey = period.keyFor((nowUtc ?? DateTime.now()).toUtc());
    // Realtime streams support one filter; the period key (when any) is it.
    // Rows are fetched with a small overfetch so best-score/UID tie-breaks
    // at the boundary resolve the same way as the paged query.
    final fetchLimit = limit * 2;
    final table = _client.from('leaderboard');
    final stream = periodKey == null
        ? table
              .stream(primaryKey: ['user_id'])
              .order(period.xpField)
              .limit(fetchLimit)
        : table
              .stream(primaryKey: ['user_id'])
              .eq(period.keyField!, periodKey)
              .order(period.xpField)
              .limit(fetchLimit);
    return stream.map((rows) {
      final entries = _entries(rows);
      sortLeaderboardEntries(entries, period: period);
      return List<LeaderboardEntry>.unmodifiable(entries.take(limit));
    });
  }

  Stream<LeaderboardEntry?> watchPlayer(String userId) {
    return _client
        .from('leaderboard')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .map((rows) {
          if (rows.isEmpty) return null;
          final entry = LeaderboardEntry.tryFromMap(
            compactRow(rows.first),
            id: userId,
          );
          if (entry == null) {
            // A malformed existing row is not an authoritative zero-XP
            // absence. Let personal progression retain its last trusted
            // snapshot and otherwise fail closed.
            throw FormatException('Invalid leaderboard entry: $userId');
          }
          return entry;
        });
  }

  Future<LeaderboardPage> fetchPlayersPage({
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
    int limit = 50,
    LeaderboardPageCursor? startAfter,
    DateTime? nowUtc,
  }) async {
    final periodKey = period.keyFor((nowUtc ?? DateTime.now()).toUtc());
    var query = _client.from('leaderboard').select();
    if (periodKey != null) {
      query = query.eq(period.keyField!, periodKey);
    }
    if (startAfter is _KeysetLeaderboardPageCursor) {
      if (!isCursorCompatible(
        cursor: startAfter,
        period: period,
        periodKey: periodKey,
      )) {
        throw LeaderboardPageCursorExpiredException(
          cursorPeriod: startAfter.period,
          cursorPeriodKey: startAfter.periodKey,
          requestedPeriod: period,
          requestedPeriodKey: periodKey,
        );
      }
      query = query.or(startAfter.keysetFilter);
    } else if (startAfter != null) {
      throw ArgumentError(
        'startAfter must be a LeaderboardRepository-issued cursor',
      );
    }

    final rows = await query
        .order(period.xpField, ascending: false)
        .order(period.bestScoreField, ascending: false)
        .order('user_id', ascending: true)
        .limit(limit);
    final entries = _entries(rows);
    sortLeaderboardEntries(entries, period: period);

    final last = rows.isEmpty ? null : rows.last;
    final cursor = last == null
        ? null
        : _KeysetLeaderboardPageCursor(
            xp: (last[period.xpField] as num?)?.toInt() ?? 0,
            bestScore: (last[period.bestScoreField] as num?)?.toInt() ?? 0,
            userId: last['user_id'] as String,
            period: period,
            periodKey: periodKey,
          );

    return buildPage(
      entries: entries,
      returnedDocumentCount: rows.length,
      limit: limit,
      cursorFromLastDoc: cursor,
    );
  }

  @visibleForTesting
  static bool isCursorCompatible({
    required LeaderboardPageCursor cursor,
    required LeaderboardPeriod period,
    required String? periodKey,
  }) {
    return cursor.period == period && cursor.periodKey == periodKey;
  }

  @visibleForTesting
  static LeaderboardPage buildPage({
    required List<LeaderboardEntry> entries,
    required int returnedDocumentCount,
    required int limit,
    required LeaderboardPageCursor? cursorFromLastDoc,
  }) {
    final hasMore = returnedDocumentCount == limit;
    if (hasMore && cursorFromLastDoc == null) {
      throw ArgumentError(
        'hasMore requires cursorFromLastDoc when returnedDocumentCount == limit',
      );
    }
    return LeaderboardPage(
      entries: List<LeaderboardEntry>.unmodifiable(entries),
      hasMore: hasMore,
      nextCursor: hasMore ? cursorFromLastDoc : null,
    );
  }

  /// Idempotently awards XP for a completed session owned by [userId].
  ///
  /// The server reads score, ownership, official-movement eligibility and
  /// Manila period keys from the stored session. The processed-session marker
  /// insert decides idempotency atomically; a repeated call awards nothing.
  Future<void> recordCompletedSession({
    required String sessionId,
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    try {
      if (!_isCurrentOwner(userId)) {
        throw LeaderboardAwardException(
          'Session owner mismatch for leaderboard award',
          sessionId: sessionId,
          userId: userId,
        );
      }
      final trimmedName = displayName.trim().isEmpty
          ? 'Trainee'
          : displayName.trim();
      try {
        await _client.rpc<dynamic>(
          'award_session_xp',
          params: {
            'p_session_id': sessionId,
            'p_display_name': trimmedName,
            'p_profile_picture_url': profilePictureUrl?.trim(),
          },
        );
      } on PostgrestException catch (error) {
        final message = switch (error.message) {
          'session_not_found' => 'Session not found for leaderboard award',
          'forbidden' => 'Session owner mismatch for leaderboard award',
          'not_awardable' =>
            'Session movement is not an official ELIXR movement',
          _ => null,
        };
        if (message == null) rethrow;
        throw LeaderboardAwardException(
          message,
          sessionId: sessionId,
          userId: userId,
        );
      }
    } catch (error, stackTrace) {
      _logError(
        'recordCompletedSession',
        error,
        stackTrace,
        userId: userId,
        sessionId: sessionId,
      );
      rethrow;
    }
  }

  /// Awards any of the current user's sessions that lack a processed marker.
  /// Safe to call repeatedly; concurrent calls for the same user share one Future.
  Future<LeaderboardSyncResult> syncCurrentUserLeaderboard({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) {
    return runWithSyncGuard(
      userId,
      () => _syncCurrentUserLeaderboardImpl(
        userId: userId,
        displayName: displayName,
        profilePictureUrl: profilePictureUrl,
      ),
    );
  }

  /// Shared single-flight guard used by [syncCurrentUserLeaderboard].
  @visibleForTesting
  static Future<LeaderboardSyncResult> runWithSyncGuard(
    String userId,
    Future<LeaderboardSyncResult> Function() action,
  ) {
    final existing = _syncInFlight[userId];
    if (existing != null) return existing;

    final future = action().whenComplete(() {
      _syncInFlight.remove(userId);
    });
    _syncInFlight[userId] = future;
    return future;
  }

  Future<LeaderboardSyncResult> _syncCurrentUserLeaderboardImpl({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    try {
      // Challenge and custom-movement sessions never earn global XP; the
      // server rejects them too, so they are excluded from the award plan.
      final sessionRows = await _client
          .from('sessions')
          .select('id, created_at, movement_name')
          .eq('user_id', userId)
          .isFilter('challenge_context', null)
          .isFilter('custom_movement_id', null);
      final markerRows = await _client
          .from('leaderboard_processed_sessions')
          .select('session_id')
          .eq('user_id', userId);

      final processedIds = markerRows
          .map((row) => row['session_id'])
          .whereType<String>()
          .toSet();
      final refs = sessionRows.map((row) {
        final movementName = row['movement_name'];
        final createdAt = row['created_at'];
        return SessionRef(
          id: row['id'] as String,
          userId: userId,
          createdAtMs: createdAt is String
              ? DateTime.tryParse(createdAt)?.millisecondsSinceEpoch
              : null,
          movementName: movementName is String ? movementName : null,
        );
      }).toList();

      final missing = LeaderboardSyncPlanner.sessionsMissingAwards(
        sessions: refs,
        processedSessionIds: processedIds,
      );
      final awardable = LeaderboardSyncPlanner.sessionsEligibleForGlobalXp(
        missing,
      );

      final alreadyProcessed = refs
          .where((session) => processedIds.contains(session.id))
          .length;

      var newlyProcessed = 0;
      var failures = 0;

      for (final session in awardable) {
        try {
          await recordCompletedSession(
            sessionId: session.id,
            userId: userId,
            displayName: displayName,
            profilePictureUrl: profilePictureUrl,
          );
          newlyProcessed++;
        } catch (error, stackTrace) {
          failures++;
          _logError(
            'syncCurrentUserLeaderboard',
            error,
            stackTrace,
            userId: userId,
            sessionId: session.id,
          );
        }
      }

      var publicProfileSynced = false;
      try {
        publicProfileSynced = await syncPublicProfile(
          userId: userId,
          displayName: displayName,
          profilePictureUrl: profilePictureUrl,
          clearProfilePicture: profilePictureUrl?.trim().isEmpty ?? true,
        );
      } catch (error, stackTrace) {
        _logError('syncPublicProfile', error, stackTrace, userId: userId);
      }

      return LeaderboardSyncResult(
        totalSessionsChecked: refs.length,
        alreadyProcessed: alreadyProcessed,
        newlyProcessed: newlyProcessed,
        failures: failures,
        publicProfileSynced: publicProfileSynced,
      );
    } catch (error, stackTrace) {
      _logError(
        'syncCurrentUserLeaderboard',
        error,
        stackTrace,
        userId: userId,
      );
      rethrow;
    }
  }

  /// Updates public display metadata on an existing leaderboard row.
  ///
  /// Does not create a zero-session entry. Preserves XP and session aggregates.
  /// Returns true only when leaderboard-visible profile fields actually changed
  /// and a write was performed. Empty incoming picture values do not clear an
  /// existing URL unless [clearProfilePicture] is set.
  Future<bool> syncPublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    bool clearProfilePicture = false,
  }) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return false;
    if (!_isCurrentOwner(userId)) return false;
    try {
      final changed = await _client.rpc<dynamic>(
        'sync_leaderboard_public_profile',
        params: {
          'p_display_name': trimmed,
          'p_profile_picture_url': profilePictureUrl?.trim(),
          'p_clear_picture': clearProfilePicture,
        },
      );
      return changed == true;
    } catch (error, stackTrace) {
      _logError('syncPublicProfile', error, stackTrace, userId: userId);
      rethrow;
    }
  }

  /// Deterministic rank for [userId] using the same ordering as leaderboard
  /// queries. Returns null when no (current-period) leaderboard row exists.
  /// The server resolves the Manila period, so [nowUtc] is not sent.
  Future<int?> computeRankForUser(
    String userId, {
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
    DateTime? nowUtc,
  }) async {
    final rank = await _client.rpc<dynamic>(
      'leaderboard_rank',
      params: {'p_user_id': userId, 'p_period': period.name},
    );
    return (rank as num?)?.toInt();
  }

  /// Chunk size used when loading known member UIDs.
  static const int userIdQueryChunkSize = 30;

  /// Loads leaderboard rows for [userIds] in bounded identity chunks.
  ///
  /// Missing rows are omitted; callers that need 0-XP roster rows must
  /// merge their own membership fallbacks.
  Future<Map<String, LeaderboardEntry>> fetchEntriesByUserIds(
    Iterable<String> userIds,
  ) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    final result = <String, LeaderboardEntry>{};
    for (var offset = 0; offset < ids.length; offset += userIdQueryChunkSize) {
      final chunk = ids.skip(offset).take(userIdQueryChunkSize).toList();
      if (chunk.isEmpty) continue;
      final rows = await _client
          .from('leaderboard')
          .select()
          .inFilter('user_id', chunk);
      for (final entry in _entries(rows)) {
        result[entry.userId] = entry;
      }
    }
    return result;
  }

  static List<LeaderboardEntry> _entries(List<Map<String, dynamic>> rows) {
    return rows
        .map(
          (row) => LeaderboardEntry.tryFromMap(
            compactRow(row),
            id: row['user_id'] as String,
          ),
        )
        .whereType<LeaderboardEntry>()
        .toList(growable: true);
  }

  /// Stable ordering for leaderboard rows when XP and best score tie.
  @visibleForTesting
  static int compareLeaderboardEntries(
    LeaderboardEntry a,
    LeaderboardEntry b, {
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
  }) {
    final xpCmp = b.xpFor(period).compareTo(a.xpFor(period));
    if (xpCmp != 0) return xpCmp;
    final bestCmp = b.bestScoreFor(period).compareTo(a.bestScoreFor(period));
    if (bestCmp != 0) return bestCmp;
    return a.userId.compareTo(b.userId);
  }

  /// Shared Trainee and Teacher ranking order: period XP, then best score, then UID.
  static void sortLeaderboardEntries(
    List<LeaderboardEntry> entries, {
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
  }) {
    entries.sort((a, b) => compareLeaderboardEntries(a, b, period: period));
  }

  /// Compatibility delegate for callers that only synchronize display_name.
  Future<bool> syncDisplayName({
    required String userId,
    required String displayName,
  }) {
    return syncPublicProfile(userId: userId, displayName: displayName);
  }

  void _logError(
    String operation,
    Object error,
    StackTrace stackTrace, {
    String? userId,
    String? sessionId,
  }) {
    if (!kDebugMode) return;
    final code = error is PostgrestException ? error.code : null;
    final message = error is PostgrestException ? error.message : null;
    debugPrint(
      'Leaderboard error: op=$operation'
      '${code != null ? ' code=$code' : ''}'
      '${message != null ? ' message=$message' : ''}'
      '${userId != null ? ' userId=$userId' : ''}'
      ' currentAuthUid=$_currentAuthUid'
      ' currentProductUserId=${_productUserId?.call()}'
      '${sessionId != null ? ' sessionId=$sessionId' : ''}'
      ' error=$error',
    );
    debugPrint('$stackTrace');
  }
}

/// Client-side last-active request policy. Ranking fields are never included;
/// the server applies the same interval authoritatively.
abstract final class LeaderboardPresencePolicy {
  static const Duration minInterval = Duration(minutes: 10);

  static bool isAuthenticatedOwner({
    required String requestedUserId,
    required String? currentAuthUid,
  }) {
    final requested = requestedUserId.trim();
    final current = currentAuthUid?.trim();
    return requested.isNotEmpty && current != null && current == requested;
  }

  static bool shouldWrite({
    required bool documentExists,
    required DateTime nowUtc,
    DateTime? lastWriteUtc,
    DateTime? persistedLastActiveAt,
  }) {
    if (!documentExists) return false;
    final last = _mostRecent(lastWriteUtc, persistedLastActiveAt);
    if (last == null) return true;
    return nowUtc.toUtc().difference(last.toUtc()) >= minInterval;
  }

  static DateTime? _mostRecent(DateTime? left, DateTime? right) {
    if (left == null) return right?.toUtc();
    if (right == null) return left.toUtc();
    final leftUtc = left.toUtc();
    final rightUtc = right.toUtc();
    return leftUtc.isAfter(rightUtc) ? leftUtc : rightUtc;
  }
}

class LeaderboardAwardException implements Exception {
  LeaderboardAwardException(this.message, {this.sessionId, this.userId});

  final String message;
  final String? sessionId;
  final String? userId;

  @override
  String toString() => message;
}
