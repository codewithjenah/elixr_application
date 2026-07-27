import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants/gamification_rules.dart';
import '../database/firestore_helper.dart';
import '../models/leaderboard_award_plan.dart';
import '../models/leaderboard_entry.dart';

class LeaderboardRepository {
  LeaderboardRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// In-flight sync futures keyed by userId to prevent duplicate concurrent runs.
  static final Map<String, Future<LeaderboardSyncResult>> _syncInFlight = {};

  @visibleForTesting
  static void clearSyncInFlightForTest() => _syncInFlight.clear();

  Stream<List<LeaderboardEntry>> watchTopPlayers({int limit = 10}) {
    return _firestore
        .collection(FirestoreCollections.leaderboard)
        .orderBy('total_xp', descending: true)
        .orderBy('best_score', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => LeaderboardEntry.tryFromMap(doc.data(), id: doc.id))
              .whereType<LeaderboardEntry>()
              .toList(growable: false);
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

  /// Idempotently awards XP for a completed session owned by [userId].
  ///
  /// Reads score and ownership from `sessions/{sessionId}`. If a processed
  /// marker already exists, returns without awarding again.
  Future<void> recordCompletedSession({
    required String sessionId,
    required String userId,
    required String displayName,
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
        final plan = LeaderboardAwardPlan.fromExisting(
          markerExists: markerSnap.exists,
          existing: leaderboardSnap.data(),
          score: score,
        );

        if (plan.alreadyProcessed) {
          return;
        }

        final lastSessionAt = sessionData['created_at'] ?? Timestamp.now();

        tx.set(markerRef, {
          'session_id': sessionId,
          'user_id': userId,
          'score': score,
          'xp_awarded': GamificationRules.xpPerSession,
          'processed_at': FieldValue.serverTimestamp(),
        });

        // Write whole scores as ints so rules that compare against session.score
        // succeed even when Dart double math produced .0 values for averages.
        tx.set(leaderboardRef, {
          'user_id': userId,
          'display_name': trimmedName,
          'total_xp': plan.totalXp,
          'sessions_completed': plan.sessionsCompleted,
          'score_sum': plan.scoreSum,
          'average_score': plan.averageScore,
          'best_score': plan.bestScore,
          'last_session_at': lastSessionAt,
          'updated_at': FieldValue.serverTimestamp(),
          'last_awarded_session_id': sessionId,
        }, SetOptions(merge: true));
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
  }) {
    return runWithSyncGuard(
      userId,
      () => _syncCurrentUserLeaderboardImpl(
        userId: userId,
        displayName: displayName,
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

      return LeaderboardSyncResult(
        totalSessionsChecked: refs.length,
        alreadyProcessed: alreadyProcessed,
        newlyProcessed: newlyProcessed,
        failures: failures,
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

  /// Updates public display_name when a leaderboard document already exists.
  Future<void> syncDisplayName({
    required String userId,
    required String displayName,
  }) async {
    final trimmed = displayName.trim();
    if (trimmed.isEmpty) return;

    final ref = _firestore
        .collection(FirestoreCollections.leaderboard)
        .doc(userId);

    try {
      final snap = await ref.get();
      if (!snap.exists) return;

      await ref.set({
        'display_name': trimmed,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error, stackTrace) {
      _logError('syncDisplayName', error, stackTrace, userId: userId);
      rethrow;
    }
  }

  static int _readScore(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    throw LeaderboardAwardException('Session score is missing or invalid');
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
