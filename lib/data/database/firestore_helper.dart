import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/feedback.dart';
import '../models/session.dart';
import '../models/user.dart';
import '../privacy_consent.dart';

abstract final class FirestoreCollections {
  static const users = 'users';
  static const sessions = 'sessions';
  static const feedbacks = 'feedbacks';
  static const leaderboard = 'leaderboard';
  static const leaderboardProcessedSessions = 'leaderboard_processed_sessions';
  static const dailyQuestBoards = 'daily_quest_boards';
  static const dailyQuestClaims = 'daily_quest_claims';
  static const achievementClaims = 'achievement_claims';
  static const userCosmetics = 'user_cosmetics';
  static const publicProfiles = 'public_profiles';
  static const profileVisits = 'profile_visits';
}

/// Partitioned session assessment aggregates. V1 and V2 are never mixed.
class SessionAssessmentStats {
  const SessionAssessmentStats({
    required this.rubricSessionCount,
    required this.averageRubricTotal,
    required this.bestRubricTotal,
    required this.legacySessionCount,
    required this.averageLegacyScore,
    required this.bestLegacyScore,
  });

  final int rubricSessionCount;
  final double? averageRubricTotal;
  final int? bestRubricTotal;
  final int legacySessionCount;
  final double? averageLegacyScore;
  final int? bestLegacyScore;
}

class FirestoreHelper {
  FirestoreHelper._({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static final FirestoreHelper instance = FirestoreHelper._();

  final FirebaseFirestore _firestore;

  static String? _readCreatedAt(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is String) return value;
    return null;
  }

  Map<String, dynamic> _userFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return {
      'id': doc.id,
      'first_name': data['first_name'],
      'middle_name': data['middle_name'],
      'last_name': data['last_name'],
      'full_name': data['full_name'],
      'email': data['email'],
      'role': data['role'],
      'created_at': _readCreatedAt(data['created_at']),
      'profile_picture_path': data['profile_picture_path'],
      'profile_picture_url': data['profile_picture_url'],
      'profile_picture_storage_path': data['profile_picture_storage_path'],
      'privacy_consent_at': _readCreatedAt(data['privacy_consent_at']),
      'privacy_policy_version': data['privacy_policy_version'],
    };
  }

  Map<String, dynamic> _sessionFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return {
      'id': doc.id,
      'user_id': data['user_id'],
      'movement_name': data['movement_name'],
      'difficulty': data['difficulty'],
      'score': data['score'],
      'duration_seconds': data['duration_seconds'],
      'prop_type': data['prop_type'],
      'created_at': _readCreatedAt(data['created_at']),
      'assessment_version': data['assessment_version'],
      'rubric': data['rubric'],
      'rubric_total': data['rubric_total'],
      'performance_level': data['performance_level'],
    };
  }

  Map<String, dynamic> _feedbackFromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return {
      'id': doc.id,
      'session_id': data['session_id'],
      'message': data['message'],
      'feedback_type': data['feedback_type'],
      'created_at': _readCreatedAt(data['created_at']),
    };
  }

  /// Builds the Firestore payload for [upsertUserProfile].
  ///
  /// When [includePrivacyConsent] is true, registration consent markers are
  /// included. [serverTimestamp] defaults to `FieldValue.serverTimestamp()`.
  static Map<String, dynamic> userProfileWriteData(
    User user, {
    bool includePrivacyConsent = false,
    Object Function()? serverTimestamp,
  }) {
    final timestamp = serverTimestamp ?? () => FieldValue.serverTimestamp();
    return {
      'first_name': user.firstName,
      if (user.middleName != null && user.middleName!.isNotEmpty)
        'middle_name': user.middleName,
      'last_name': user.lastName,
      'full_name': user.fullName,
      'email': user.email,
      'role': user.role,
      'created_at': timestamp(),
      if (user.profilePictureUrl != null)
        'profile_picture_url': user.profilePictureUrl,
      if (user.profilePictureStoragePath != null)
        'profile_picture_storage_path': user.profilePictureStoragePath,
      if (user.profilePictureUrl == null && user.profilePicturePath != null)
        'profile_picture_path': user.profilePicturePath,
      if (includePrivacyConsent)
        ...RegistrationPrivacyConsent.documentFields(
          consentTimestamp: timestamp(),
        ),
    };
  }

  Future<void> upsertUserProfile(
    User user, {
    bool includePrivacyConsent = false,
  }) async {
    if (user.id == null) {
      throw ArgumentError('User id is required');
    }
    await _firestore
        .collection(FirestoreCollections.users)
        .doc(user.id)
        .set(
          userProfileWriteData(
            user,
            includePrivacyConsent: includePrivacyConsent,
          ),
          SetOptions(merge: true),
        );
  }

  Future<void> updateUserProfileField(
    String userId,
    Map<String, dynamic> fields,
  ) async {
    await _firestore
        .collection(FirestoreCollections.users)
        .doc(userId)
        .update(fields);
  }

  Future<User?> getUserById(String id) async {
    final doc = await _firestore
        .collection(FirestoreCollections.users)
        .doc(id)
        .get();
    if (!doc.exists) return null;
    return User.fromMap(_userFromDoc(doc));
  }

  /// Allocates a Firestore document ID without writing. Safe to reuse on retry.
  String allocateSessionId() {
    return _firestore.collection(FirestoreCollections.sessions).doc().id;
  }

  /// Deterministic feedback document ID for retry-safe session saves.
  static String feedbackDocumentId(String sessionId, int index) {
    return '${sessionId}_fb_$index';
  }

  /// Writes the session and all feedback documents in one atomic batch.
  Future<void> saveSessionWithFeedbacks({
    required String sessionId,
    required Session session,
    required List<Feedback> feedbacks,
  }) async {
    final batch = _firestore.batch();
    final sessionRef = _firestore
        .collection(FirestoreCollections.sessions)
        .doc(sessionId);
    final sessionPayload = <String, dynamic>{
      'user_id': session.userId,
      'movement_name': session.movementName,
      'difficulty': session.difficulty,
      'duration_seconds': session.durationSeconds,
      'prop_type': session.propType.protocolValue,
      'created_at': FieldValue.serverTimestamp(),
    };
    if (session.isRubricAssessed && session.rubric != null) {
      sessionPayload.addAll(session.rubric!.toFirestoreFields());
    } else if (session.legacyScore != null) {
      sessionPayload['score'] = session.legacyScore;
      sessionPayload['assessment_version'] = 1;
    } else {
      throw ArgumentError(
        'Session must include Assessment V2 rubric or a legacy score',
      );
    }
    batch.set(sessionRef, sessionPayload);

    for (var index = 0; index < feedbacks.length; index++) {
      final feedback = feedbacks[index];
      final feedbackId = feedback.id ?? feedbackDocumentId(sessionId, index);
      final feedbackRef = _firestore
          .collection(FirestoreCollections.feedbacks)
          .doc(feedbackId);
      batch.set(feedbackRef, {
        'session_id': sessionId,
        'message': feedback.message,
        'feedback_type': feedback.feedbackType,
        'created_at': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  Future<String> insertSession(Session session) async {
    final sessionId = allocateSessionId();
    await saveSessionWithFeedbacks(
      sessionId: sessionId,
      session: session,
      feedbacks: const [],
    );
    return sessionId;
  }

  Future<List<Session>> getSessionsForUser(String userId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.sessions)
        .where('user_id', isEqualTo: userId)
        .orderBy('created_at', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => Session.fromMap(_sessionFromDoc(doc)))
        .toList();
  }

  Future<String> insertFeedback(Feedback feedback) async {
    final doc = _firestore.collection(FirestoreCollections.feedbacks).doc();
    await doc.set({
      'session_id': feedback.sessionId,
      'message': feedback.message,
      'feedback_type': feedback.feedbackType,
      'created_at': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> insertFeedbacks(List<Feedback> feedbacks) async {
    if (feedbacks.isEmpty) return;
    final batch = _firestore.batch();
    for (final feedback in feedbacks) {
      final doc = _firestore.collection(FirestoreCollections.feedbacks).doc();
      batch.set(doc, {
        'session_id': feedback.sessionId,
        'message': feedback.message,
        'feedback_type': feedback.feedbackType,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<List<Feedback>> getFeedbacksForSession(String sessionId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.feedbacks)
        .where('session_id', isEqualTo: sessionId)
        .orderBy('created_at')
        .get();
    return snapshot.docs
        .map((doc) => Feedback.fromMap(_feedbackFromDoc(doc)))
        .toList();
  }

  Future<int> countSessionsForUser(String userId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.sessions)
        .where('user_id', isEqualTo: userId)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  /// Partitioned assessment aggregates — never mix V1 and V2 numerics.
  Future<SessionAssessmentStats> sessionAssessmentStatsForUser(
    String userId,
  ) async {
    final sessions = await _sessionsForUser(userId);
    var rubricCount = 0;
    var rubricSum = 0;
    var rubricBest = 0;
    var legacyCount = 0;
    var legacySum = 0;
    var legacyBest = 0;

    for (final session in sessions) {
      if (session.isRubricAssessed) {
        final total = session.rubric!.total;
        rubricCount++;
        rubricSum += total;
        if (total > rubricBest) rubricBest = total;
      } else if (session.legacyScore != null) {
        final score = session.legacyScore!;
        legacyCount++;
        legacySum += score;
        if (score > legacyBest) legacyBest = score;
      }
    }

    return SessionAssessmentStats(
      rubricSessionCount: rubricCount,
      averageRubricTotal: rubricCount == 0 ? null : rubricSum / rubricCount,
      bestRubricTotal: rubricCount == 0 ? null : rubricBest,
      legacySessionCount: legacyCount,
      averageLegacyScore: legacyCount == 0 ? null : legacySum / legacyCount,
      bestLegacyScore: legacyCount == 0 ? null : legacyBest,
    );
  }

  @Deprecated('Use sessionAssessmentStatsForUser — never mix V1/V2')
  Future<double?> averageScoreForUser(String userId) async {
    final stats = await sessionAssessmentStatsForUser(userId);
    return stats.averageLegacyScore;
  }

  @Deprecated('Use sessionAssessmentStatsForUser — never mix V1/V2')
  Future<int?> bestScoreForUser(String userId) async {
    final stats = await sessionAssessmentStatsForUser(userId);
    return stats.bestLegacyScore;
  }

  Future<Map<String, int>> sessionCountByMovement(String userId) async {
    final sessions = await _sessionsForUser(userId);
    final counts = <String, int>{};
    for (final session in sessions) {
      counts.update(
        session.movementName,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    return counts;
  }

  Future<List<Session>> _sessionsForUser(String userId) async {
    final snapshot = await _firestore
        .collection(FirestoreCollections.sessions)
        .where('user_id', isEqualTo: userId)
        .get();
    return snapshot.docs
        .map((doc) => Session.fromMap(_sessionFromDoc(doc)))
        .toList();
  }
}
