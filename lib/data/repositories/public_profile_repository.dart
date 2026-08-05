import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../database/firestore_helper.dart';
import '../models/achievement.dart';
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

class _FirestorePublicProfileSessionCursor
    implements PublicProfileSessionCursor {
  _FirestorePublicProfileSessionCursor(this.document);
  final DocumentSnapshot<Map<String, dynamic>> document;
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
class PublicProfileRepository {
  PublicProfileRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static final Map<String, Future<void>> _ensureInFlight = {};

  @visibleForTesting
  static void clearEnsureInFlightForTest() => _ensureInFlight.clear();

  DocumentReference<Map<String, dynamic>> _rootRef(String userId) =>
      _firestore.collection(FirestoreCollections.publicProfiles).doc(userId);

  DocumentReference<Map<String, dynamic>> _summaryRef(String userId) =>
      _rootRef(userId).collection('details').doc('summary');

  DocumentReference<Map<String, dynamic>> _sessionRef(
    String userId,
    String sessionId,
  ) => _rootRef(userId).collection('sessions').doc(sessionId);

  DocumentReference<Map<String, dynamic>> _achievementRef(
    String userId,
    String achievementId,
  ) => _rootRef(userId).collection('achievements').doc(achievementId);

  Stream<PublicProfile?> watchProfileRoot(String userId) {
    return _rootRef(userId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return PublicProfile.tryFromMap(doc.data()!, id: doc.id);
    });
  }

  Future<PublicProfile?> getProfileRoot(String userId) async {
    final doc = await _rootRef(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return PublicProfile.tryFromMap(doc.data()!, id: doc.id);
  }

  Future<PublicProfileSummary?> getSummary(String userId) async {
    final doc = await _summaryRef(userId).get();
    if (!doc.exists || doc.data() == null) return null;
    return PublicProfileSummary.tryFromMap(doc.data()!);
  }

  Stream<PublicProfileSummary?> watchSummary(String userId) {
    return _summaryRef(userId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return PublicProfileSummary.tryFromMap(doc.data()!);
    });
  }

  Future<List<String>> fetchClaimedAchievementIds(String userId) async {
    final snapshot = await _rootRef(userId).collection('achievements').get();
    return snapshot.docs
        .map((doc) => doc.data()['achievement_id'])
        .whereType<String>()
        .toList(growable: false);
  }

  Future<PublicProfileSessionPage> fetchSessionsPage({
    required String userId,
    int limit = 20,
    PublicProfileSessionCursor? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _rootRef(userId)
        .collection('sessions')
        .orderBy('created_at', descending: true)
        .limit(limit);

    if (startAfter is _FirestorePublicProfileSessionCursor) {
      query = query.startAfterDocument(startAfter.document);
    } else if (startAfter != null) {
      throw ArgumentError(
        'startAfter must be a Firestore-backed PublicProfileSessionCursor',
      );
    }

    final snapshot = await query.get();
    final docs = snapshot.docs;
    final sessions = docs
        .map((doc) => PublicProfileSession.tryFromMap(doc.data(), id: doc.id))
        .whereType<PublicProfileSession>()
        .toList(growable: false);

    final cursor = docs.isEmpty
        ? null
        : _FirestorePublicProfileSessionCursor(docs.last);
    final hasMore = docs.length == limit;

    return PublicProfileSessionPage(
      sessions: sessions,
      hasMore: hasMore,
      nextCursor: hasMore ? cursor : null,
    );
  }

  /// Ensures a safe root document exists and backfills missing projections.
  Future<void> ensurePublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
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

  Future<void> _ensurePublicProfileImpl({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    final trimmedName = displayName.trim().isEmpty
        ? 'Trainee'
        : displayName.trim();

    await _ensureRootDocument(
      userId: userId,
      displayName: trimmedName,
      profilePictureUrl: profilePictureUrl,
    );

    await _syncIdentity(
      userId: userId,
      displayName: trimmedName,
      profilePictureUrl: profilePictureUrl,
    );

    try {
      final sessionsSnap = await _firestore
          .collection(FirestoreCollections.sessions)
          .where('user_id', isEqualTo: userId)
          .get();

      final projectedSnap = await _rootRef(userId).collection('sessions').get();
      final projectedIds = projectedSnap.docs.map((doc) => doc.id).toSet();

      var totalDuration = 0;
      final movementNames = <String>{};

      for (final doc in sessionsSnap.docs) {
        final data = doc.data();
        final session = Session.fromMap({
          'id': doc.id,
          'user_id': data['user_id'],
          'movement_name': data['movement_name'],
          'difficulty': data['difficulty'],
          'score': data['score'],
          'duration_seconds': data['duration_seconds'],
          'prop_type': data['prop_type'],
          'created_at': _readCreatedAt(data['created_at']),
        });

        if (!projectedIds.contains(doc.id)) {
          await projectSession(sessionId: doc.id, session: session);
        }

        totalDuration += session.durationSeconds;
        final movement = session.movementName.trim();
        if (movement.isNotEmpty) {
          movementNames.add(movement);
        }
      }

      await _summaryRef(userId).set({
        'total_duration_seconds': totalDuration,
        'completed_movement_names': movementNames.toList()..sort(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final claimsSnap = await _firestore
          .collection(FirestoreCollections.achievementClaims)
          .where('user_id', isEqualTo: userId)
          .get();

      for (final doc in claimsSnap.docs) {
        final achievementId = doc.data()['achievement_id'];
        if (achievementId is String && isKnownAchievementId(achievementId)) {
          await projectAchievement(userId: userId, achievementId: achievementId);
        }
      }
    } catch (error, stackTrace) {
      _logError('ensurePublicProfile', error, stackTrace, userId: userId);
    }
  }

  Future<void> _ensureRootDocument({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    final ref = _rootRef(userId);
    final snap = await ref.get();
    if (snap.exists) return;

    final payload = <String, dynamic>{
      'user_id': userId,
      'display_name': displayName,
      'visibility': ProfileVisibility.private.firestoreValue,
      'schema_version': 1,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    };
    final trimmedUrl = profilePictureUrl?.trim();
    if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
      payload['profile_picture_url'] = trimmedUrl;
    }
    await ref.set(payload);
  }

  Future<void> updatePublicIdentity({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) return;

    await _ensureRootDocument(
      userId: userId,
      displayName: trimmedName,
      profilePictureUrl: profilePictureUrl,
    );

    await _syncIdentity(
      userId: userId,
      displayName: trimmedName,
      profilePictureUrl: profilePictureUrl,
    );
  }

  Future<void> _syncIdentity({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    final fields = <String, dynamic>{
      'display_name': displayName,
      'updated_at': FieldValue.serverTimestamp(),
    };
    final trimmedUrl = profilePictureUrl?.trim();
    if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
      fields['profile_picture_url'] = trimmedUrl;
    }
    await _rootRef(userId).set(fields, SetOptions(merge: true));
  }

  Future<void> updateVisibility({
    required String userId,
    required ProfileVisibility visibility,
  }) async {
    await _rootRef(userId).set({
      'visibility': visibility.firestoreValue,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Idempotently projects a completed session into the public profile.
  Future<void> projectSession({
    required String sessionId,
    required Session session,
  }) async {
    if (session.userId.isEmpty) {
      throw ArgumentError('Session userId is required');
    }

    final userId = session.userId;
    await _sessionRef(userId, sessionId).set({
      'session_id': sessionId,
      'user_id': userId,
      'movement_name': session.movementName,
      'difficulty': session.difficulty,
      'score': session.score,
      'duration_seconds': session.durationSeconds,
      'prop_type': session.propType.protocolValue,
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _updateSummaryAfterSession(userId: userId, session: session);
  }

  Future<void> _updateSummaryAfterSession({
    required String userId,
    required Session session,
  }) async {
    final summaryRef = _summaryRef(userId);
    final snap = await summaryRef.get();
    final existing = snap.data();

    var totalDuration = session.durationSeconds;
    final movements = <String>{};

    if (existing != null) {
      totalDuration =
          (_readInt(existing['total_duration_seconds']) ?? 0) +
          session.durationSeconds;
      for (final name in _readStringList(existing['completed_movement_names'])) {
        movements.add(name);
      }
    }

    final movement = session.movementName.trim();
    if (movement.isNotEmpty) movements.add(movement);

    await summaryRef.set({
      'total_duration_seconds': totalDuration < 0 ? 0 : totalDuration,
      'completed_movement_names': movements.toList()..sort(),
      'updated_at': FieldValue.serverTimestamp(),
      'last_backfill_session_id': session.id,
    }, SetOptions(merge: true));
  }

  /// Idempotently projects a claimed achievement into the public profile.
  Future<void> projectAchievement({
    required String userId,
    required String achievementId,
  }) async {
    if (!isKnownAchievementId(achievementId)) return;

    await _achievementRef(userId, achievementId).set({
      'user_id': userId,
      'achievement_id': achievementId,
      'claimed_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList(growable: false);
  }

  static String? _readCreatedAt(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is String) return value;
    return null;
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
