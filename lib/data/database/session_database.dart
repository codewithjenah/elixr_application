import 'package:elixr_core/database/supabase_support.dart';
import 'package:elixr_core/database/user_profile_store.dart';
import 'package:elixr_core/models/user.dart';
import 'package:elixr_core/privacy/privacy_consent.dart';
import 'package:elixr_core/utils/comparable_rubric_progress.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import '../models/assignment_attempt.dart';
import '../models/feedback.dart';
import '../models/session.dart';

export 'package:elixr_core/database/supabase_support.dart';
export 'package:elixr_core/database/user_profile_store.dart';

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

/// Supabase access for the caller's own practice sessions and profile.
class SessionDatabase implements UserProfileStore {
  SessionDatabase({SupabaseClient? client, UserProfileStore? profiles})
    : _clientOverride = client,
      _profilesOverride = profiles;

  static final SessionDatabase instance = SessionDatabase();

  final SupabaseClient? _clientOverride;
  final UserProfileStore? _profilesOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;
  UserProfileStore get _profiles =>
      _profilesOverride ?? SupabaseUserProfileStore(client: _clientOverride);

  static const _sessionColumns =
      'id, user_id, movement_name, difficulty, score, duration_seconds, '
      'prop_type, created_at, assessment_version, rubric, rubric_total, '
      'performance_level, evidence_storage_path, evidence_kind, '
      'evidence_size_bytes, assignment_context, challenge_context, '
      'custom_movement_id, custom_movement_revision_id, '
      'reference_image_storage_path';

  @override
  Future<void> upsertUserProfile(
    User user, {
    RegistrationLegalConsent? legalConsent,
  }) {
    return _profiles.upsertUserProfile(user, legalConsent: legalConsent);
  }

  @override
  Future<void> updateUserProfileField(
    String userId,
    Map<String, dynamic> fields,
  ) {
    return _profiles.updateUserProfileField(userId, fields);
  }

  @override
  Future<User?> getUserById(String id) {
    return _profiles.getUserById(id);
  }

  /// Allocates a session ID without writing. Safe to reuse on retry: the
  /// server treats a repeated save of the same ID as already committed.
  String allocateSessionId() => newDocumentId();

  /// Deterministic feedback row ID for retry-safe session saves.
  static String feedbackDocumentId(String sessionId, int index) {
    return '${sessionId}_fb_$index';
  }

  /// The session payload accepted by the `save_session` RPC. Identity and
  /// timestamps are assigned by the server.
  static Map<String, dynamic> sessionPayload(Session session) {
    final payload = <String, dynamic>{
      'movement_name': session.movementName,
      'difficulty': session.difficulty,
      'duration_seconds': session.durationSeconds,
      'prop_type': session.propType.protocolValue,
      'evidence_storage_path': ?session.evidenceStoragePath,
      'evidence_kind': ?session.evidenceKind,
      'evidence_size_bytes': ?session.evidenceSizeBytes,
      if (session.assignmentContext != null)
        'assignment_context': session.assignmentContext!.toMap(),
      if (session.challengeContext != null)
        'challenge_context': session.challengeContext!.toMap(),
    };
    if (session.isRubricAssessed && session.rubric != null) {
      payload.addAll(session.rubric!.toFirestoreFields());
    } else if (session.legacyScore != null) {
      payload['score'] = session.legacyScore;
      payload['assessment_version'] = 1;
    } else {
      throw ArgumentError(
        'Session must include Assessment V2 rubric or a legacy score',
      );
    }
    return payload;
  }

  /// Writes the session and all feedback rows in one database transaction.
  ///
  /// Official assignment sessions are completed by the server-authoritative
  /// assignment path (see SessionRepository) and are rejected here.
  Future<void> saveSessionWithFeedbacks({
    required String sessionId,
    required Session session,
    required List<Feedback> feedbacks,
    AssignmentAttempt? officialAssignmentPointer,
  }) async {
    if (officialAssignmentPointer != null ||
        session.assignmentContext != null) {
      throw ArgumentError(
        'Official assignment sessions require the server completion path',
      );
    }
    await _client.rpc<dynamic>(
      'save_session',
      params: {
        'p_session_id': sessionId,
        'p_session': sessionPayload(session),
        'p_feedbacks': [
          for (var index = 0; index < feedbacks.length; index++)
            {
              'id': feedbacks[index].id ?? feedbackDocumentId(sessionId, index),
              'message': feedbacks[index].message,
              'feedback_type': feedbacks[index].feedbackType,
            },
        ],
      },
    );
  }

  Future<List<Session>> getSessionsForUser(String userId) async {
    final rows = await _client
        .from('sessions')
        .select(_sessionColumns)
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.map((row) => Session.fromMap(compactRow(row))).toList();
  }

  Future<List<Feedback>> getFeedbacksForSession(String sessionId) async {
    final rows = await _client
        .from('feedbacks')
        .select('id, session_id, message, feedback_type, created_at')
        .eq('session_id', sessionId)
        .order('created_at');
    return rows.map((row) => Feedback.fromMap(compactRow(row))).toList();
  }

  Future<int> countSessionsForUser(String userId) async {
    return _client.from('sessions').count().eq('user_id', userId);
  }

  /// Partitioned assessment aggregates — never mix V1 and V2 numerics.
  Future<SessionAssessmentStats> sessionAssessmentStatsForUser(
    String userId,
  ) async {
    final sessions = await getSessionsForUser(userId);
    var rubricCount = 0;
    var rubricSum = 0;
    var rubricBest = 0;
    var legacyCount = 0;
    var legacySum = 0;
    var legacyBest = 0;

    for (final session in sessions) {
      final rubricTotal = ComparableRubricProgress.scoreFor(
        assessmentVersion: session.assessmentVersion,
        rubricTotal: session.rubricTotal,
      );
      if (rubricTotal != null) {
        rubricCount++;
        rubricSum += rubricTotal;
        if (rubricTotal > rubricBest) rubricBest = rubricTotal;
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

  Future<Map<String, int>> sessionCountByMovement(String userId) async {
    final sessions = await getSessionsForUser(userId);
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
}
