import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:flutter/foundation.dart';

import '../data/database/firestore_helper.dart';
import '../data/models/feedback.dart';
import '../data/models/practice_feedback.dart';
import '../data/models/rubric_assessment.dart';
import '../data/models/session.dart';
import '../data/models/training_prop.dart';
import '../data/repositories/leaderboard_repository.dart';
import '../data/repositories/public_profile_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/session_evidence_repository.dart';

typedef LeaderboardSessionRecorder =
    Future<void> Function({
      required String sessionId,
      required String userId,
      required String displayName,
      String? profilePictureUrl,
    });

typedef PublicProfileSessionProjector =
    Future<void> Function({
      required String sessionId,
      required Session session,
    });

typedef CompletedSessionAtomicSaver =
    Future<void> Function({
      required String sessionId,
      required Session session,
      required List<Feedback> feedbacks,
    });

/// Thrown when a caller tries to persist an official session for a movement
/// that is not one of the 12 catalog identities.
class UnofficialMovementException implements Exception {
  const UnofficialMovementException(this.movementName);

  final String movementName;

  @override
  String toString() =>
      'Cannot save an official session for non-catalog movement '
      '"$movementName"';
}

class SessionService extends ChangeNotifier {
  SessionService({
    SessionRepository? repository,
    LeaderboardRepository? leaderboardRepository,
    PublicProfileRepository? publicProfileRepository,
    CompletedSessionAtomicSaver? saveCompletedSessionAtomicOverride,
    String Function()? allocateSessionIdOverride,
    LeaderboardSessionRecorder? recordCompletedSessionOverride,
    PublicProfileSessionProjector? projectSessionOverride,
    SessionEvidenceRepository? evidenceRepository,
    TeacherRelationshipRepository? teacherRelationshipRepository,
  }) : _repositoryOrNull = repository,
       _leaderboardRepositoryOrNull = leaderboardRepository,
       _publicProfileRepositoryOrNull = publicProfileRepository,
       _saveCompletedSessionAtomicOverride = saveCompletedSessionAtomicOverride,
       _allocateSessionIdOverride = allocateSessionIdOverride,
       _recordCompletedSessionOverride = recordCompletedSessionOverride,
       _projectSessionOverride = projectSessionOverride,
       _evidenceRepositoryOrNull = evidenceRepository,
       _teacherRelationshipRepository = teacherRelationshipRepository;

  SessionRepository? _repositoryOrNull;
  LeaderboardRepository? _leaderboardRepositoryOrNull;
  final PublicProfileRepository? _publicProfileRepositoryOrNull;
  final CompletedSessionAtomicSaver? _saveCompletedSessionAtomicOverride;
  final String Function()? _allocateSessionIdOverride;
  final LeaderboardSessionRecorder? _recordCompletedSessionOverride;
  final PublicProfileSessionProjector? _projectSessionOverride;
  SessionEvidenceRepository? _evidenceRepositoryOrNull;
  final TeacherRelationshipRepository? _teacherRelationshipRepository;

  SessionRepository get repository => _repositoryOrNull ??= SessionRepository();

  LeaderboardRepository get _leaderboardRepository =>
      _leaderboardRepositoryOrNull ??= LeaderboardRepository();

  SessionEvidenceRepository get _evidenceRepository =>
      _evidenceRepositoryOrNull ??= SessionEvidenceRepository();

  /// Null means no evidence decision has been recorded yet.
  Future<bool?> sessionEvidenceEnabled(String userId) async {
    return (await FirestoreHelper.instance.getUserById(
      userId,
    ))?.sessionEvidenceEnabled;
  }

  Future<void> setSessionEvidenceEnabled({
    required String userId,
    required bool enabled,
  }) {
    return FirestoreHelper.instance.updateUserProfileField(userId, {
      'session_evidence_enabled': enabled,
      'session_evidence_policy_version': 'v1',
      'session_evidence_decision_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> revokeSessionEvidence(String userId) async {
    // Remove the authorization edge first so a Teacher cannot begin another
    // read while retained objects are being purged.
    await _teacherRelationshipRepository?.revokeAllEvidenceAccess(
      traineeId: userId,
    );
    await _evidenceRepository.deleteAllForUser(userId);
    await setSessionEvidenceEnabled(userId: userId, enabled: false);
    notifyListeners();
  }

  Future<String> saveCompletedSession({
    required String userId,
    required String displayName,
    required String movementName,
    required String difficulty,
    required RubricAssessment rubric,
    required int durationSeconds,
    required List<PracticeFeedback> sessionImprovements,
    TrainingProp prop = TrainingProp.bottle,
    String? profilePictureUrl,
    String? existingSessionId,
    Uint8List? evidenceJpegBytes,
    bool saveEvidence = false,
  }) async {
    if (!isOfficialElixrMovementName(movementName)) {
      throw UnofficialMovementException(movementName);
    }
    final allocateSessionId =
        _allocateSessionIdOverride ?? repository.allocateSessionId;
    final sessionId = existingSessionId ?? allocateSessionId();
    String? evidencePath;
    if (saveEvidence && evidenceJpegBytes != null) {
      await _evidenceRepository.upload(
        userId: userId,
        sessionId: sessionId,
        jpegBytes: evidenceJpegBytes,
      );
      evidencePath = SessionEvidenceRepository.pathFor(
        userId: userId,
        sessionId: sessionId,
      );
    }
    final session = Session(
      id: sessionId,
      userId: userId,
      movementName: movementName,
      difficulty: difficulty,
      rubric: rubric,
      assessmentVersion: 2,
      durationSeconds: durationSeconds,
      propType: prop,
      evidenceStoragePath: evidencePath,
      evidenceKind: evidencePath == null ? null : 'hold_confirmed',
      evidenceSizeBytes: evidencePath == null
          ? null
          : evidenceJpegBytes!.lengthInBytes,
    );
    final feedbacks = _buildSessionImprovementFeedbacks(
      sessionId,
      sessionImprovements,
    );

    final saveAtomic =
        _saveCompletedSessionAtomicOverride ??
        repository.saveSessionWithFeedbacks;
    await saveAtomic(
      sessionId: sessionId,
      session: session,
      feedbacks: feedbacks,
    );

    if (kDebugMode) {
      debugPrint(
        'Session persistence completed: sessionId=$sessionId userId=$userId',
      );
    }

    // Authoritative persistence already succeeded. Leaderboard XP and public
    // profile projection are idempotent side effects and must not keep the
    // Session Complete UI pending if a Firestore Future never resolves.
    _synchronizeAfterSessionCommit(
      sessionId: sessionId,
      session: session,
      userId: userId,
      displayName: displayName,
      profilePictureUrl: profilePictureUrl,
    );

    notifyListeners();
    return sessionId;
  }

  /// Best-effort post-commit projections. Failures and hangs must not throw
  /// back into [saveCompletedSession]. Late completion remains safe because
  /// [LeaderboardRepository.recordCompletedSession] is idempotent via the
  /// processed-session marker, and [PublicProfileRepository.projectSession]
  /// merge-writes the same session document. Missed awards are recoverable
  /// through [LeaderboardRepository.syncCurrentUserLeaderboard]; missed
  /// profile rows through [PublicProfileRepository.ensurePublicProfile].
  void _synchronizeAfterSessionCommit({
    required String sessionId,
    required Session session,
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) {
    unawaited(
      _attemptLeaderboardAward(
        sessionId: sessionId,
        userId: userId,
        displayName: displayName,
        profilePictureUrl: profilePictureUrl,
      ),
    );
    unawaited(
      _attemptPublicProfileProjection(sessionId: sessionId, session: session),
    );
  }

  Future<void> _attemptLeaderboardAward({
    required String sessionId,
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    if (kDebugMode) {
      debugPrint(
        'Leaderboard projection started: sessionId=$sessionId userId=$userId',
      );
    }
    try {
      final recorder =
          _recordCompletedSessionOverride ??
          _leaderboardRepository.recordCompletedSession;
      await recorder(
        sessionId: sessionId,
        userId: userId,
        displayName: displayName,
        profilePictureUrl: profilePictureUrl,
      );
      if (kDebugMode) {
        debugPrint(
          'Leaderboard projection completed: sessionId=$sessionId userId=$userId',
        );
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Leaderboard projection failed: '
          'sessionId=$sessionId userId=$userId error=$error',
        );
        debugPrint('$stackTrace');
      }
    }
  }

  Future<void> _attemptPublicProfileProjection({
    required String sessionId,
    required Session session,
  }) async {
    final projector =
        _projectSessionOverride ??
        _publicProfileRepositoryOrNull?.projectSession;
    if (projector == null) return;

    if (kDebugMode) {
      debugPrint(
        'Public profile projection started: '
        'sessionId=$sessionId userId=${session.userId}',
      );
    }
    try {
      await projector(sessionId: sessionId, session: session);
      if (kDebugMode) {
        debugPrint(
          'Public profile projection completed: '
          'sessionId=$sessionId userId=${session.userId}',
        );
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Public profile projection failed: '
          'sessionId=$sessionId userId=${session.userId} error=$error',
        );
        debugPrint('$stackTrace');
      }
    }
  }

  static List<Feedback> _buildSessionImprovementFeedbacks(
    String sessionId,
    List<PracticeFeedback> sessionImprovements,
  ) {
    final feedbacks = <Feedback>[];
    for (var index = 0; index < sessionImprovements.length; index++) {
      final item = sessionImprovements[index];
      feedbacks.add(
        Feedback(
          id: FirestoreHelper.feedbackDocumentId(sessionId, index),
          sessionId: sessionId,
          message: item.feedback,
          feedbackType: item.feedbackType,
        ),
      );
    }
    return feedbacks;
  }
}
