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

/// Pure builder for a new `public_profiles/{userId}` root document payload.
class PublicProfileRootCreation {
  const PublicProfileRootCreation._();

  /// Fields written when creating a missing public-profile root.
  ///
  /// [createdAt] / [updatedAt] are normally `FieldValue.serverTimestamp()`;
  /// tests may inject markers.
  static Map<String, dynamic> fields({
    required String userId,
    required String displayName,
    required ProfileVisibility initialVisibility,
    String? profilePictureUrl,
    required Object createdAt,
    required Object updatedAt,
  }) {
    final payload = <String, dynamic>{
      'user_id': userId,
      'display_name': displayName,
      'visibility': initialVisibility.firestoreValue,
      'schema_version': 1,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
    final trimmedUrl = profilePictureUrl?.trim();
    if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
      payload['profile_picture_url'] = trimmedUrl;
    }
    return payload;
  }
}

/// Canonical `public_profiles/{userId}/details/summary` writer.
///
/// Replaces the document with the current allowed schema. Unknown legacy
/// keys must not be merged forward — Firestore `hasOnly` validates the
/// final document, so merge writes of old fields fail.
class PublicProfileSummaryWrite {
  const PublicProfileSummaryWrite._();

  static const supportedKeys = {
    'total_duration_seconds',
    'completed_movement_names',
    'updated_at',
    'last_backfill_session_id',
  };

  static String? recognizedLastBackfillSessionId(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 128) return null;
    return trimmed;
  }

  static Map<String, dynamic> canonicalMap({
    required int totalDurationSeconds,
    required Iterable<String> completedMovementNames,
    required Object updatedAt,
    Object? lastBackfillSessionId,
  }) {
    final payload = <String, dynamic>{
      'total_duration_seconds': totalDurationSeconds < 0
          ? 0
          : totalDurationSeconds,
      'completed_movement_names': _sortedUniqueMovements(
        completedMovementNames,
      ),
      'updated_at': updatedAt,
    };
    final backfill = recognizedLastBackfillSessionId(lastBackfillSessionId);
    if (backfill != null) {
      payload['last_backfill_session_id'] = backfill;
    }
    return payload;
  }

  static Map<String, dynamic> rebuildMap({
    required int totalDurationSeconds,
    required Iterable<String> completedMovementNames,
    required Object updatedAt,
    Map<String, dynamic>? existingSummary,
  }) {
    return canonicalMap(
      totalDurationSeconds: totalDurationSeconds,
      completedMovementNames: completedMovementNames,
      updatedAt: updatedAt,
      lastBackfillSessionId: existingSummary?['last_backfill_session_id'],
    );
  }

  static Map<String, dynamic> afterSessionMap({
    required Map<String, dynamic>? existingSummary,
    required int sessionDurationSeconds,
    required String sessionMovementName,
    required String sessionId,
    required Object updatedAt,
  }) {
    var totalDuration = sessionDurationSeconds;
    final movements = <String>{};
    if (existingSummary != null) {
      totalDuration =
          (_readRecognizedInt(existingSummary['total_duration_seconds']) ?? 0) +
          sessionDurationSeconds;
      movements.addAll(
        _readRecognizedStringList(existingSummary['completed_movement_names']),
      );
    }
    final movement = sessionMovementName.trim();
    if (movement.isNotEmpty) movements.add(movement);

    return canonicalMap(
      totalDurationSeconds: totalDuration,
      completedMovementNames: movements,
      updatedAt: updatedAt,
      lastBackfillSessionId: sessionId,
    );
  }

  static int? _readRecognizedInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return null;
  }

  static List<String> _readRecognizedStringList(Object? value) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is String) item,
    ];
  }

  static List<String> _sortedUniqueMovements(Iterable<String> names) {
    final unique = <String>{};
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isNotEmpty) unique.add(trimmed);
    }
    final list = unique.toList()..sort();
    return list;
  }
}

/// Draft payload for a missing public achievement projection document.
@immutable
class ClaimedAchievementProjectionDraft {
  const ClaimedAchievementProjectionDraft({
    required this.achievementId,
    this.claimedAt,
  });

  final String achievementId;

  /// Authoritative claim timestamp when valid; otherwise null (server timestamp).
  final Object? claimedAt;
}

/// Pure planner for owner-side claimed-achievement projection backfill.
class ClaimedAchievementProjectionPlanner {
  const ClaimedAchievementProjectionPlanner._();

  /// Returns drafts for known claimed achievements missing from the projection.
  ///
  /// Skips unknown, empty, and malformed achievement IDs. Does not rewrite
  /// IDs that already have a projection document.
  static List<ClaimedAchievementProjectionDraft> draftsToCreate({
    required Iterable<Map<String, dynamic>> claimDocuments,
    required Set<String> existingProjectedIds,
  }) {
    final drafts = <ClaimedAchievementProjectionDraft>[];
    final seen = <String>{};

    for (final data in claimDocuments) {
      final rawId = data['achievement_id'];
      if (rawId is! String) {
        _logSkipped('malformed achievement_id type=${rawId.runtimeType}');
        continue;
      }
      final achievementId = rawId.trim();
      if (achievementId.isEmpty) {
        _logSkipped('empty achievement_id');
        continue;
      }
      if (!isKnownAchievementId(achievementId)) {
        _logSkipped('unknown achievement_id=$achievementId');
        continue;
      }
      if (existingProjectedIds.contains(achievementId)) continue;
      if (!seen.add(achievementId)) continue;

      drafts.add(
        ClaimedAchievementProjectionDraft(
          achievementId: achievementId,
          claimedAt: _compatibleClaimedAt(data['claimed_at']),
        ),
      );
    }

    return drafts;
  }

  static Object? _compatibleClaimedAt(dynamic value) {
    if (value is Timestamp) return value;
    if (value is DateTime) return Timestamp.fromDate(value);
    return null;
  }

  static void _logSkipped(String detail) {
    if (!kDebugMode) return;
    debugPrint('PublicProfile achievement sync skipped: $detail');
  }
}

/// Persistence for sanitized public profile projections and privacy settings.
class PublicProfileRepository {
  PublicProfileRepository({FirebaseFirestore? firestore})
    : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  static final Map<String, Future<void>> _ensureInFlight = {};
  static final Map<String, Future<void>> _achievementSyncInFlight = {};

  @visibleForTesting
  static void clearEnsureInFlightForTest() => _ensureInFlight.clear();

  @visibleForTesting
  static void clearAchievementSyncInFlightForTest() =>
      _achievementSyncInFlight.clear();

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

  Future<PublicProfile?> getProfileRoot(
    String userId, {
    bool forceServer = false,
  }) async {
    final doc = await _rootRef(
      userId,
    ).get(forceServer ? const GetOptions(source: Source.server) : null);
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

  /// Seeds a brand-new account's public-profile root as [ProfileVisibility.public].
  ///
  /// Idempotent: if the root already exists, visibility is left unchanged.
  /// Repair and backfill paths must not call this; they create private roots.
  Future<void> seedNewAccountPublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return Future<void>.value();

    final trimmedName = displayName.trim().isEmpty
        ? 'Trainee'
        : displayName.trim();

    return _runWithEnsureGuard(
      trimmedUserId,
      () => _ensureRootDocument(
        userId: trimmedUserId,
        displayName: trimmedName,
        profilePictureUrl: profilePictureUrl,
        initialVisibility: ProfileVisibility.public,
      ),
    );
  }

  /// Creates a missing root with the existing privacy-safe repair schema.
  ///
  /// This deliberately does not overwrite an existing (including legacy or
  /// malformed) root. Such documents must be repaired through their dedicated
  /// migration path rather than being silently reshaped by a settings toggle.
  Future<void> ensurePrivacyProfileRoot({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return Future<void>.value();

    final trimmedName = displayName.trim().isEmpty
        ? 'Trainee'
        : displayName.trim();
    return _runWithEnsureGuard(
      trimmedUserId,
      () => _ensureRootDocument(
        userId: trimmedUserId,
        displayName: trimmedName,
        profilePictureUrl: profilePictureUrl,
        initialVisibility: ProfileVisibility.private,
      ),
    );
  }

  /// Focused owner-side repair of missing public achievement projections.
  ///
  /// Reads authoritative `achievement_claims` for [userId] and creates only
  /// missing `public_profiles/{userId}/achievements/{achievementId}` docs.
  /// Does not award achievements, borders, XP, or leaderboard values.
  Future<void> syncClaimedAchievementProjections({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return Future<void>.value();

    return runWithAchievementSyncGuard(
      trimmedUserId,
      () => _syncClaimedAchievementProjectionsImpl(
        userId: trimmedUserId,
        displayName: displayName,
        profilePictureUrl: profilePictureUrl,
        ensureIdentity: true,
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
    final trimmedName = displayName.trim().isEmpty
        ? 'Trainee'
        : displayName.trim();

    await _ensureRootDocument(
      userId: userId,
      displayName: trimmedName,
      profilePictureUrl: profilePictureUrl,
      initialVisibility: ProfileVisibility.private,
    );

    await _syncIdentity(
      userId: userId,
      displayName: trimmedName,
      profilePictureUrl: profilePictureUrl,
      clearProfilePicture: profilePictureUrl?.trim().isEmpty ?? true,
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
          'assessment_version': data['assessment_version'],
          'rubric': data['rubric'],
          'rubric_total': data['rubric_total'],
          'performance_level': data['performance_level'],
          'duration_seconds': data['duration_seconds'],
          'prop_type': data['prop_type'],
          'created_at': _readCreatedAt(data['created_at']),
          'evidence_storage_path': data['evidence_storage_path'],
          'evidence_kind': data['evidence_kind'],
          'evidence_size_bytes': data['evidence_size_bytes'],
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

      final existingSummary = (await _summaryRef(userId).get()).data();
      await _summaryRef(userId).set(
        PublicProfileSummaryWrite.rebuildMap(
          totalDurationSeconds: totalDuration,
          completedMovementNames: movementNames,
          updatedAt: FieldValue.serverTimestamp(),
          existingSummary: existingSummary,
        ),
      );

      // Reuse the focused achievement sync implementation directly (no nested
      // achievement-sync guard) to avoid deadlocking with ensure's guard.
      await _syncClaimedAchievementProjectionsImpl(
        userId: userId,
        displayName: trimmedName,
        profilePictureUrl: profilePictureUrl,
        ensureIdentity: false,
      );
    } catch (error, stackTrace) {
      _logError('ensurePublicProfile', error, stackTrace, userId: userId);
    }
  }

  Future<void> _syncClaimedAchievementProjectionsImpl({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    required bool ensureIdentity,
  }) async {
    final trimmedName = displayName.trim().isEmpty
        ? 'Trainee'
        : displayName.trim();

    try {
      if (ensureIdentity) {
        await _ensureRootDocument(
          userId: userId,
          displayName: trimmedName,
          profilePictureUrl: profilePictureUrl,
          initialVisibility: ProfileVisibility.private,
        );
        await _syncIdentity(
          userId: userId,
          displayName: trimmedName,
          profilePictureUrl: profilePictureUrl,
          clearProfilePicture: profilePictureUrl?.trim().isEmpty ?? true,
        );
      }

      final claimsSnap = await _firestore
          .collection(FirestoreCollections.achievementClaims)
          .where('user_id', isEqualTo: userId)
          .get();

      final projectedSnap = await _rootRef(
        userId,
      ).collection('achievements').get();
      final projectedIds = projectedSnap.docs.map((doc) => doc.id).toSet();

      final drafts = ClaimedAchievementProjectionPlanner.draftsToCreate(
        claimDocuments: claimsSnap.docs.map((doc) => doc.data()),
        existingProjectedIds: projectedIds,
      );

      if (drafts.isEmpty) return;

      // Firestore batches are capped at 500 operations.
      const batchLimit = 500;
      for (var offset = 0; offset < drafts.length; offset += batchLimit) {
        final chunk = drafts.skip(offset).take(batchLimit);
        final batch = _firestore.batch();
        for (final draft in chunk) {
          batch.set(_achievementRef(userId, draft.achievementId), {
            'user_id': userId,
            'achievement_id': draft.achievementId,
            'claimed_at': draft.claimedAt ?? FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
    } catch (error, stackTrace) {
      _logError(
        'syncClaimedAchievementProjections',
        error,
        stackTrace,
        userId: userId,
      );
      rethrow;
    }
  }

  Future<void> _ensureRootDocument({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    required ProfileVisibility initialVisibility,
  }) async {
    final ref = _rootRef(userId);
    final snap = await ref.get();
    if (snap.exists) return;

    await ref.set(
      PublicProfileRootCreation.fields(
        userId: userId,
        displayName: displayName,
        initialVisibility: initialVisibility,
        profilePictureUrl: profilePictureUrl,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      ),
    );
  }

  Future<void> updatePublicIdentity({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
    bool clearProfilePicture = false,
  }) async {
    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) return;

    await _ensureRootDocument(
      userId: userId,
      displayName: trimmedName,
      profilePictureUrl: profilePictureUrl,
      initialVisibility: ProfileVisibility.private,
    );

    await _syncIdentity(
      userId: userId,
      displayName: trimmedName,
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
    final fields = <String, dynamic>{
      'display_name': displayName,
      'updated_at': FieldValue.serverTimestamp(),
    };
    final trimmedUrl = profilePictureUrl?.trim();
    if (clearProfilePicture) {
      fields['profile_picture_url'] = FieldValue.delete();
    } else if (trimmedUrl != null && trimmedUrl.isNotEmpty) {
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
    final payload = sanitizedPracticeProjectionFields(
      sessionId: sessionId,
      session: session,
      createdAt: session.createdAt ?? FieldValue.serverTimestamp(),
    );
    await _sessionRef(userId, sessionId).set(payload, SetOptions(merge: true));

    await _updateSummaryAfterSession(
      userId: userId,
      session: session,
      sessionId: sessionId,
    );
  }

  /// Sanitized official-practice fields only. Classroom assignment identity
  /// never appears on public_profiles.
  @visibleForTesting
  static Map<String, dynamic> sanitizedPracticeProjectionFields({
    required String sessionId,
    required Session session,
    required Object createdAt,
  }) {
    final payload = <String, dynamic>{
      'session_id': sessionId,
      'user_id': session.userId,
      'movement_name': session.movementName,
      'difficulty': session.difficulty,
      'duration_seconds': session.durationSeconds,
      'prop_type': session.propType.protocolValue,
      'created_at': createdAt,
      if (session.evidenceStoragePath != null &&
          session.evidenceKind == 'hold_confirmed')
        'evidence_available': true,
    };
    if (session.isRubricAssessed && session.rubric != null) {
      payload.addAll(session.rubric!.toFirestoreFields());
    } else if (session.legacyScore != null) {
      payload['score'] = session.legacyScore;
    } else {
      throw ArgumentError(
        'Session projection requires Assessment V2 rubric or legacy score',
      );
    }
    return payload;
  }

  Future<void> _updateSummaryAfterSession({
    required String userId,
    required Session session,
    required String sessionId,
  }) async {
    final summaryRef = _summaryRef(userId);
    final existing = (await summaryRef.get()).data();
    await summaryRef.set(
      PublicProfileSummaryWrite.afterSessionMap(
        existingSummary: existing,
        sessionDurationSeconds: session.durationSeconds,
        sessionMovementName: session.movementName,
        sessionId: sessionId,
        updatedAt: FieldValue.serverTimestamp(),
      ),
    );
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
