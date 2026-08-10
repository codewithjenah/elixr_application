import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/gamification_rules.dart';
import '../database/firestore_helper.dart';
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

class _FirestoreLeaderboardPageCursor implements LeaderboardPageCursor {
  _FirestoreLeaderboardPageCursor({
    required this.document,
    required this.period,
    required this.periodKey,
  });

  final DocumentSnapshot<Map<String, dynamic>> document;
  @override
  final LeaderboardPeriod period;

  @override
  final String? periodKey;
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
  LeaderboardRepository({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  /// In-flight sync futures keyed by userId to prevent duplicate concurrent runs.
  static final Map<String, Future<LeaderboardSyncResult>> _syncInFlight = {};

  @visibleForTesting
  static void clearSyncInFlightForTest() => _syncInFlight.clear();

  Stream<List<LeaderboardEntry>> watchTopPlayers({int limit = 10}) {
    return _firestore
        .collection(FirestoreCollections.leaderboard)
        .orderBy('total_xp', descending: true)
        .orderBy('best_score', descending: true)
        .orderBy(FieldPath.documentId)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final entries = snapshot.docs
              .map((doc) => LeaderboardEntry.tryFromMap(doc.data(), id: doc.id))
              .whereType<LeaderboardEntry>()
              .toList(growable: true);
          sortLeaderboardEntries(entries);
          return List<LeaderboardEntry>.unmodifiable(entries);
        });
  }

  Stream<LeaderboardEntry?> watchPlayer(String userId) {
    return _firestore
        .collection(FirestoreCollections.leaderboard)
        .doc(userId)
        .snapshots()
        .map((doc) {
          if (!doc.exists || doc.data() == null) return null;
          return LeaderboardEntry.tryFromMap(doc.data()!, id: doc.id);
        });
  }

  Future<LeaderboardPage> fetchPlayersPage({
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
    int limit = 50,
    LeaderboardPageCursor? startAfter,
    DateTime? nowUtc,
  }) async {
    final periodKey = period.keyFor((nowUtc ?? DateTime.now()).toUtc());
    Query<Map<String, dynamic>> query = _firestore.collection(
      FirestoreCollections.leaderboard,
    );
    if (periodKey != null) {
      query = query.where(period.keyField!, isEqualTo: periodKey);
    }
    query = query
        .orderBy(period.xpField, descending: true)
        .orderBy(period.bestScoreField, descending: true)
        .orderBy(FieldPath.documentId)
        .limit(limit);

    if (startAfter is _FirestoreLeaderboardPageCursor) {
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
      query = query.startAfterDocument(startAfter.document);
    } else if (startAfter != null) {
      throw ArgumentError(
        'startAfter must be a Firestore-backed LeaderboardPageCursor',
      );
    }

    final snapshot = await query.get();
    final docs = snapshot.docs;
    final entries = docs
        .map((doc) => LeaderboardEntry.tryFromMap(doc.data(), id: doc.id))
        .whereType<LeaderboardEntry>()
        .toList(growable: true);
    sortLeaderboardEntries(entries, period: period);

    final cursor = docs.isEmpty
        ? null
        : _FirestoreLeaderboardPageCursor(
            document: docs.last,
            period: period,
            periodKey: periodKey,
          );

    return buildPage(
      entries: entries,
      returnedDocumentCount: docs.length,
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
  /// Reads score and ownership from `sessions/{sessionId}`. If a processed
  /// marker already exists, returns without awarding again.
  Future<void> recordCompletedSession({
    required String sessionId,
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    final trimmedName = displayName.trim().isEmpty
        ? 'Trainee'
        : displayName.trim();
    final sessionRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId);
    final markerRef = _firestore
        .collection(FirestoreCollections.leaderboardProcessedSessions)
        .doc(sessionId);
    final leaderboardRef = _firestore
        .collection(FirestoreCollections.leaderboard)
        .doc(userId);

    try {
      await _firestore.runTransaction((tx) async {
        final sessionSnap = await tx.get(sessionRef);
        if (!sessionSnap.exists || sessionSnap.data() == null) {
          throw LeaderboardAwardException(
            'Session not found for leaderboard award',
            sessionId: sessionId,
            userId: userId,
          );
        }

        final sessionData = sessionSnap.data()!;
        final sessionOwner = sessionData['user_id'];
        if (sessionOwner != userId) {
          throw LeaderboardAwardException(
            'Session owner mismatch for leaderboard award',
            sessionId: sessionId,
            userId: userId,
          );
        }

        final score = _readScore(sessionData['score']);
        final markerSnap = await tx.get(markerRef);
        final leaderboardSnap = await tx.get(leaderboardRef);
        if (markerSnap.exists) {
          return;
        }

        final sessionCreatedAtUtc = _readSessionCreatedAtUtc(
          sessionData['created_at'],
          sessionId: sessionId,
          userId: userId,
        );
        final plan = LeaderboardAwardPlan.fromExisting(
          markerExists: false,
          existing: leaderboardSnap.data(),
          score: score,
          sessionCreatedAtUtc: sessionCreatedAtUtc,
        );

        if (plan.alreadyProcessed) {
          return;
        }

        final lastSessionAt = sessionData['created_at'];

        tx.set(markerRef, {
          'session_id': sessionId,
          'user_id': userId,
          'score': score,
          'xp_awarded': GamificationRules.xpPerSession,
          'processed_at': FieldValue.serverTimestamp(),
        });

        // Write whole scores as ints so rules that compare against session.score
        // succeed even when Dart double math produced .0 values for averages.
        final leaderboardData = <String, dynamic>{
          'user_id': userId,
          'display_name': trimmedName,
          'total_xp': plan.totalXp,
          'quest_xp': plan.questXp,
          'sessions_completed': plan.sessionsCompleted,
          'score_sum': plan.scoreSum,
          'average_score': plan.averageScore,
          'best_score': plan.bestScore,
          'last_session_at': lastSessionAt,
          'updated_at': FieldValue.serverTimestamp(),
          'last_awarded_session_id': sessionId,
          ...plan.periodFields,
          ...buildPublicProfileFields(profilePictureUrl: profilePictureUrl),
        };
        tx.set(leaderboardRef, leaderboardData, SetOptions(merge: true));
      });
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
      final sessionsSnap = await _firestore
          .collection(FirestoreCollections.sessions)
          .where('user_id', isEqualTo: userId)
          .get();

      final markersSnap = await _firestore
          .collection(FirestoreCollections.leaderboardProcessedSessions)
          .where('user_id', isEqualTo: userId)
          .get();

      final processedIds = markersSnap.docs.map((doc) => doc.id).toSet();
      final refs = sessionsSnap.docs.map((doc) {
        final data = doc.data();
        return SessionRef(
          id: doc.id,
          userId: userId,
          createdAtMs: _createdAtMs(data['created_at']),
        );
      }).toList();

      final missing = LeaderboardSyncPlanner.sessionsMissingAwards(
        sessions: refs,
        processedSessionIds: processedIds,
      );

      final alreadyProcessed = refs
          .where((session) => processedIds.contains(session.id))
          .length;

      var newlyProcessed = 0;
      var failures = 0;

      for (final session in missing) {
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

  /// Updates public display metadata on an existing leaderboard document.
  ///
  /// Does not create a zero-session entry. Preserves XP and session aggregates.
  /// Returns true only when leaderboard-visible profile fields actually changed
  /// and a write was performed. Identical metadata skips the write.
  Future<bool> syncPublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return false;

    final ref = _firestore
        .collection(FirestoreCollections.leaderboard)
        .doc(userId);

    try {
      final snap = await ref.get();
      if (!snap.exists || snap.data() == null) return false;

      final existing = snap.data()!;
      if (!publicProfileNeedsUpdate(
        existing: existing,
        displayName: trimmed,
        profilePictureUrl: profilePictureUrl,
      )) {
        return false;
      }

      await ref.set({
        ...buildPublicProfileFields(
          displayName: trimmed,
          profilePictureUrl: profilePictureUrl,
        ),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (error, stackTrace) {
      _logError('syncPublicProfile', error, stackTrace, userId: userId);
      rethrow;
    }
  }

  /// Deterministic rank for [userId] using the same ordering as leaderboard
  /// queries. Returns null when no leaderboard document exists.
  Future<int?> computeRankForUser(
    String userId, {
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
    DateTime? nowUtc,
  }) async {
    final ref = _firestore
        .collection(FirestoreCollections.leaderboard)
        .doc(userId);
    final snap = await ref.get();
    if (!snap.exists || snap.data() == null) return null;

    final data = snap.data()!;
    final periodKey = period.keyFor((nowUtc ?? DateTime.now()).toUtc());
    if (periodKey != null && data[period.keyField] != periodKey) return null;

    final xp = _readInt(data[period.xpField]) ?? 0;
    final best = _readInt(data[period.bestScoreField]) ?? 0;
    Query<Map<String, dynamic>> ranked = _firestore.collection(
      FirestoreCollections.leaderboard,
    );
    if (periodKey != null) {
      ranked = ranked.where(period.keyField!, isEqualTo: periodKey);
    }

    final aheadByXp = await ranked
        .where(period.xpField, isGreaterThan: xp)
        .count()
        .get();
    final tiedOnXp = ranked.where(period.xpField, isEqualTo: xp);
    final aheadByBest = await tiedOnXp
        .where(period.bestScoreField, isGreaterThan: best)
        .count()
        .get();
    final aheadByDocumentId = await tiedOnXp
        .where(period.bestScoreField, isEqualTo: best)
        .where(FieldPath.documentId, isLessThan: userId)
        .count()
        .get();

    return 1 +
        (aheadByXp.count ?? 0) +
        (aheadByBest.count ?? 0) +
        (aheadByDocumentId.count ?? 0);
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

  @visibleForTesting
  static void sortLeaderboardEntries(
    List<LeaderboardEntry> entries, {
    LeaderboardPeriod period = LeaderboardPeriod.allTime,
  }) {
    entries.sort((a, b) => compareLeaderboardEntries(a, b, period: period));
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  /// Compatibility delegate for callers that only synchronize display_name.
  Future<bool> syncDisplayName({
    required String userId,
    required String displayName,
  }) {
    return syncPublicProfile(userId: userId, displayName: displayName);
  }

  /// Builds merge fields for public profile metadata on leaderboard documents.
  @visibleForTesting
  static Map<String, dynamic> buildPublicProfileFields({
    String? displayName,
    String? profilePictureUrl,
  }) {
    final fields = <String, dynamic>{};
    final trimmedName = displayName?.trim();
    if (trimmedName != null && trimmedName.isNotEmpty) {
      fields['display_name'] = trimmedName;
    }
    final trimmedUrl = profilePictureUrl?.trim();
    if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
      fields['profile_picture_url'] = trimmedUrl;
    }
    return fields;
  }

  /// Whether [existing] leaderboard doc needs a public-profile write for the
  /// normalized [displayName] / [profilePictureUrl]. Empty incoming picture
  /// values are omitted (same as [buildPublicProfileFields]) and do not clear
  /// an existing URL.
  @visibleForTesting
  static bool publicProfileNeedsUpdate({
    required Map<String, dynamic> existing,
    required String displayName,
    String? profilePictureUrl,
  }) {
    final desired = buildPublicProfileFields(
      displayName: displayName,
      profilePictureUrl: profilePictureUrl,
    );
    if (desired.isEmpty) return false;

    for (final entry in desired.entries) {
      final raw = existing[entry.key];
      final current = raw is String ? raw.trim() : raw;
      if (current != entry.value) return true;
    }
    return false;
  }

  static int _readScore(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    throw LeaderboardAwardException('Session score is missing or invalid');
  }

  static DateTime _readSessionCreatedAtUtc(
    dynamic value, {
    required String sessionId,
    required String userId,
  }) {
    final createdAt = switch (value) {
      Timestamp timestamp => timestamp.toDate(),
      DateTime dateTime => dateTime,
      _ => null,
    };
    if (createdAt == null) {
      throw LeaderboardAwardException(
        'Session created_at is missing or is not a server timestamp',
        sessionId: sessionId,
        userId: userId,
      );
    }
    return createdAt.toUtc();
  }

  static int? _createdAtMs(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is String) {
      return DateTime.tryParse(value)?.millisecondsSinceEpoch;
    }
    return null;
  }

  static void _logError(
    String operation,
    Object error,
    StackTrace stackTrace, {
    String? userId,
    String? sessionId,
  }) {
    if (!kDebugMode) return;
    final code = error is FirebaseException ? error.code : null;
    final message = error is FirebaseException ? error.message : null;
    debugPrint(
      'Leaderboard error: op=$operation'
      '${code != null ? ' code=$code' : ''}'
      '${message != null ? ' message=$message' : ''}'
      '${userId != null ? ' userId=$userId' : ''}'
      '${sessionId != null ? ' sessionId=$sessionId' : ''}'
      ' error=$error',
    );
    debugPrint('$stackTrace');
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
