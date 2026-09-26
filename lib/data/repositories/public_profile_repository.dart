import 'package:elixr_core/database/supabase_support.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../models/public_profile.dart';
import '../models/public_profile_session.dart';
import '../models/public_profile_summary.dart';
import '../models/session.dart';

/// Opaque pagination cursor for public practice history.
abstract class PublicProfileSessionCursor {}

@visibleForTesting
class FakePublicProfileSessionCursor implements PublicProfileSessionCursor {
  FakePublicProfileSessionCursor(this.id);
  final String id;
}

/// Keyset cursor over the `(created_at desc, session_id desc)` index.
class _KeysetPublicProfileSessionCursor implements PublicProfileSessionCursor {
  _KeysetPublicProfileSessionCursor(this.createdAtUtc, this.sessionId);

  factory _KeysetPublicProfileSessionCursor.fromRow(Map<String, dynamic> row) {
    final createdAt = DateTime.parse(row['created_at'] as String).toUtc();
    return _KeysetPublicProfileSessionCursor(
      createdAt.toIso8601String(),
      row['session_id'] as String,
    );
  }

  final String createdAtUtc;
  final String sessionId;

  String get keysetFilter =>
      'created_at.lt.$createdAtUtc,'
      'and(created_at.eq.$createdAtUtc,session_id.lt.$sessionId)';
}

class PublicProfileSessionPage {
  const PublicProfileSessionPage({
    required this.sessions,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<PublicProfileSession> sessions;
  final PublicProfileSessionCursor? nextCursor;
  final bool hasMore;
}

/// Persistence for sanitized public profile projections and privacy settings.
///
/// Projection rows are derived server-side from the caller's authoritative
/// sessions and achievement claims; the client only names what to project.
class PublicProfileRepository {
  PublicProfileRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  static final Map<String, Future<void>> _ensureInFlight = {};
  static final Map<String, Future<void>> _achievementSyncInFlight = {};

  @visibleForTesting
  static void clearEnsureInFlightForTest() => _ensureInFlight.clear();

  @visibleForTesting
  static void clearAchievementSyncInFlightForTest() =>
      _achievementSyncInFlight.clear();

  Stream<PublicProfile?> watchProfileRoot(String userId) {
    return _client
        .from('public_profiles')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .map(
          (rows) => rows.isEmpty
              ? null
              : PublicProfile.tryFromMap(compactRow(rows.first), id: userId),
        );
  }

  /// [forceServer] is retained for source compatibility; every read goes to
  /// the server.
  Future<PublicProfile?> getProfileRoot(
    String userId, {
    bool forceServer = false,
  }) async {
    final row = await _client
        .from('public_profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null
        ? null
        : PublicProfile.tryFromMap(compactRow(row), id: userId);
  }

  Future<PublicProfileSummary?> getSummary(String userId) async {
    final row = await _client
        .from('public_profile_summaries')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null
        ? null
        : PublicProfileSummary.tryFromMap(compactRow(row));
  }

  Stream<PublicProfileSummary?> watchSummary(String userId) {
    return _client
        .from('public_profile_summaries')
        .stream(primaryKey: ['user_id'])
        .eq('user_id', userId)
        .map(
          (rows) => rows.isEmpty
              ? null
              : PublicProfileSummary.tryFromMap(compactRow(rows.first)),
        );
  }

  Future<List<String>> fetchClaimedAchievementIds(String userId) async {
    final rows = await _client
        .from('public_profile_achievements')
        .select('achievement_id')
        .eq('user_id', userId);
    return rows
        .map((row) => row['achievement_id'])
        .whereType<String>()
        .toList(growable: false);
  }

  Future<PublicProfileSessionPage> fetchSessionsPage({
    required String userId,
    int limit = 20,
    PublicProfileSessionCursor? startAfter,
  }) async {
    if (startAfter != null &&
        startAfter is! _KeysetPublicProfileSessionCursor) {
      throw ArgumentError(
        'startAfter must be a PublicProfileRepository-issued cursor',
      );
    }
    var query = _client
        .from('public_profile_sessions')
        .select()
        .eq('user_id', userId);
    if (startAfter is _KeysetPublicProfileSessionCursor) {
      query = query.or(startAfter.keysetFilter);
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('session_id', ascending: false)
        .limit(limit);

    final sessions = rows
        .map(
          (row) => PublicProfileSession.tryFromMap(
            compactRow(row),
            id: row['session_id'] as String,
          ),
        )
        .whereType<PublicProfileSession>()
        .toList(growable: false);

    final hasMore = rows.length == limit;
    return PublicProfileSessionPage(
      sessions: sessions,
      hasMore: hasMore,
      nextCursor: hasMore && rows.isNotEmpty
          ? _KeysetPublicProfileSessionCursor.fromRow(rows.last)
          : null,
    );
  }

  /// Ensures a safe root exists and backfills missing projections.
  Future<void> ensurePublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    String? role,
  }) {
    return _runWithEnsureGuard(
      userId,
      () => _ensurePublicProfileImpl(
        userId: userId,
        displayName: displayName,
        profilePictureUrl: profilePictureUrl,
      ),
    );
  }

  /// Seeds a brand-new account's public-profile root as
  /// [ProfileVisibility.public].
  ///
  /// Idempotent: if the root already exists, visibility is left unchanged.
  /// Repair and backfill paths must not call this; they create private roots.
  /// [role] is derived server-side from the authoritative profile.
  Future<void> seedNewAccountPublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    String? role,
  }) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return Future<void>.value();
    return _runWithEnsureGuard(
      trimmedUserId,
      () => _ensureRoot(
        userId: trimmedUserId,
        displayName: displayName,
        profilePictureUrl: profilePictureUrl,
        initialVisibility: ProfileVisibility.public,
      ),
    );
  }

  /// Creates a missing root with the privacy-safe (private) repair schema.
  ///
  /// This deliberately does not overwrite an existing root.
  Future<void> ensurePrivacyProfileRoot({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    String? role,
  }) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return Future<void>.value();
    return _runWithEnsureGuard(
      trimmedUserId,
      () => _ensureRoot(
        userId: trimmedUserId,
        displayName: displayName,
        profilePictureUrl: profilePictureUrl,
        initialVisibility: ProfileVisibility.private,
      ),
    );
  }

  /// Focused owner-side repair of missing public achievement projections.
  ///
  /// The server mirrors authoritative `achievement_claims` only; it does not
  /// award achievements, borders, XP, or leaderboard values.
  Future<void> syncClaimedAchievementProjections({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    bool Function()? isCurrentIdentity,
  }) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return Future<void>.value();

    return runWithAchievementSyncGuard(trimmedUserId, () async {
      try {
        if (isCurrentIdentity?.call() == false) return;
        await _ensureRoot(
          userId: trimmedUserId,
          displayName: displayName,
          profilePictureUrl: profilePictureUrl,
          initialVisibility: ProfileVisibility.private,
        );
        if (isCurrentIdentity?.call() == false) return;
        await _syncIdentity(
          userId: trimmedUserId,
          displayName: displayName,
          profilePictureUrl: profilePictureUrl,
          clearProfilePicture: profilePictureUrl?.trim().isEmpty ?? true,
        );
        if (isCurrentIdentity?.call() == false) return;
        await _client.rpc<dynamic>('sync_public_profile_projections');
      } catch (error, stackTrace) {
        _logError(
          'syncClaimedAchievementProjections',
          error,
          stackTrace,
          userId: trimmedUserId,
        );
        rethrow;
      }
    });
  }

  static Future<void> _runWithEnsureGuard(
    String userId,
    Future<void> Function() action,
  ) {
    final existing = _ensureInFlight[userId];
    if (existing != null) return existing;

    final future = action().whenComplete(() {
      _ensureInFlight.remove(userId);
    });
    _ensureInFlight[userId] = future;
    return future;
  }

  /// Shared single-flight guard for [syncClaimedAchievementProjections].
  @visibleForTesting
  static Future<void> runWithAchievementSyncGuard(
    String userId,
    Future<void> Function() action,
  ) {
    final existing = _achievementSyncInFlight[userId];
    if (existing != null) return existing;

    final future = action().whenComplete(() {
      _achievementSyncInFlight.remove(userId);
    });
    _achievementSyncInFlight[userId] = future;
    return future;
  }

  Future<void> _ensurePublicProfileImpl({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    await _ensureRoot(
      userId: userId,
      displayName: displayName,
      profilePictureUrl: profilePictureUrl,
      initialVisibility: ProfileVisibility.private,
    );
    await _syncIdentity(
      userId: userId,
      displayName: displayName,
      profilePictureUrl: profilePictureUrl,
      clearProfilePicture: profilePictureUrl?.trim().isEmpty ?? true,
    );
    try {
      await _client.rpc<dynamic>('sync_public_profile_projections');
    } catch (error, stackTrace) {
      _logError('ensurePublicProfile', error, stackTrace, userId: userId);
    }
  }

  Future<void> _ensureRoot({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    required ProfileVisibility initialVisibility,
  }) async {
    _requireOwner(userId);
    await _client.rpc<dynamic>(
      'ensure_public_profile_root',
      params: {
        'p_display_name': _nameOrDefault(displayName),
        'p_profile_picture_url': profilePictureUrl?.trim(),
        'p_initial_visibility': initialVisibility.firestoreValue,
      },
    );
  }

  Future<void> updatePublicIdentity({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    String? role,
    bool clearProfilePicture = false,
  }) async {
    if (displayName.trim().isEmpty) return;
    await _ensureRoot(
      userId: userId,
      displayName: displayName,
      profilePictureUrl: profilePictureUrl,
      initialVisibility: ProfileVisibility.private,
    );
    await _syncIdentity(
      userId: userId,
      displayName: displayName,
      profilePictureUrl: profilePictureUrl,
      clearProfilePicture:
          clearProfilePicture || profilePictureUrl?.trim().isEmpty == true,
    );
  }

  Future<void> _syncIdentity({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    bool clearProfilePicture = false,
  }) async {
    _requireOwner(userId);
    await _client.rpc<dynamic>(
      'update_public_identity',
      params: {
        'p_display_name': _nameOrDefault(displayName),
        'p_profile_picture_url': profilePictureUrl?.trim(),
        'p_clear_picture': clearProfilePicture,
      },
    );
  }

  Future<void> updateVisibility({
    required String userId,
    required ProfileVisibility visibility,
  }) async {
    _requireOwner(userId);
    await _client.rpc<dynamic>(
      'set_public_profile_visibility',
      params: {'p_visibility': visibility.firestoreValue},
    );
  }

  /// Idempotently projects a completed session into the public profile. The
  /// server copies only sanitized official-practice fields; classroom
  /// assignment identity never appears in public projections.
  Future<void> projectSession({
    required String sessionId,
    required Session session,
  }) async {
    if (session.userId.isEmpty) {
      throw ArgumentError('Session userId is required');
    }
    _requireOwner(session.userId);
    await _client.rpc<dynamic>(
      'project_public_session',
      params: {'p_session_id': sessionId},
    );
  }

  void _requireOwner(String userId) {
    if (_client.auth.currentUser?.id != userId) {
      throw StateError('Public profiles can only be changed by their owner.');
    }
  }

  static String _nameOrDefault(String displayName) {
    final trimmed = displayName.trim();
    return trimmed.isEmpty ? 'Trainee' : trimmed;
  }

  static void _logError(
    String operation,
    Object error,
    StackTrace stackTrace, {
    String? userId,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      'PublicProfile error: op=$operation'
      '${userId != null ? ' userId=$userId' : ''}'
      ' error=$error',
    );
    debugPrint('$stackTrace');
  }
}
