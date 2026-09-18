import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:elixr_core/constants/coaching_movement_names.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
import 'package:flutter/foundation.dart';

import '../data/database/firestore_helper.dart';
import '../data/models/assessment_mode.dart';
import '../data/models/assignment_attempt.dart';
import '../data/models/assignment_attempt_ids.dart';
import '../data/models/classroom_exceptions.dart';
import '../data/models/class_challenge_session_context.dart';
import '../data/models/feedback.dart';
import '../data/models/movement_origin.dart';
import '../data/models/practice_feedback.dart';
import '../data/models/rubric_assessment.dart';
import '../data/models/session.dart';
import '../data/models/session_assignment_context.dart';
import '../data/models/training_prop.dart';
import '../data/repositories/leaderboard_repository.dart';
import '../data/repositories/public_profile_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/session_evidence_repository.dart';
import 'session_evidence_preference_store.dart';

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

typedef AssignedSessionAtomicSaver =
    Future<void> Function({
      required String sessionId,
      required Session session,
      required List<Feedback> feedbacks,
      required AssignmentAttempt officialAssignmentPointer,
    });

typedef SessionEvidencePreferenceRemoteWriter =
    Future<void> Function({required String userId, required bool enabled});

/// Thrown when a caller tries to persist an official session for a movement
/// that is not one of the 15 catalog identities.
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
    AssignedSessionAtomicSaver? saveAssignedSessionAtomicOverride,
    String Function()? allocateSessionIdOverride,
    LeaderboardSessionRecorder? recordCompletedSessionOverride,
    PublicProfileSessionProjector? projectSessionOverride,
    SessionEvidenceRepository? evidenceRepository,
    SessionEvidencePreferenceStore? evidencePreferenceStore,
    SessionEvidencePreferenceRemoteWriter? evidencePreferenceRemoteWriter,
    TeacherRelationshipRepository? teacherRelationshipRepository,
  }) : _repositoryOrNull = repository,
       _leaderboardRepositoryOrNull = leaderboardRepository,
       _publicProfileRepositoryOrNull = publicProfileRepository,
       _saveCompletedSessionAtomicOverride = saveCompletedSessionAtomicOverride,
       _saveAssignedSessionAtomicOverride = saveAssignedSessionAtomicOverride,
       _allocateSessionIdOverride = allocateSessionIdOverride,
       _recordCompletedSessionOverride = recordCompletedSessionOverride,
       _projectSessionOverride = projectSessionOverride,
       _evidenceRepositoryOrNull = evidenceRepository,
       _evidencePreferenceStore =
           evidencePreferenceStore ?? SessionEvidencePreferenceStore(),
       _evidencePreferenceRemoteWriter = evidencePreferenceRemoteWriter,
       _teacherRelationshipRepository = teacherRelationshipRepository;

  SessionRepository? _repositoryOrNull;
  LeaderboardRepository? _leaderboardRepositoryOrNull;
  final PublicProfileRepository? _publicProfileRepositoryOrNull;
  final CompletedSessionAtomicSaver? _saveCompletedSessionAtomicOverride;
  final AssignedSessionAtomicSaver? _saveAssignedSessionAtomicOverride;
  final String Function()? _allocateSessionIdOverride;
  final LeaderboardSessionRecorder? _recordCompletedSessionOverride;
  final PublicProfileSessionProjector? _projectSessionOverride;
  SessionEvidenceRepository? _evidenceRepositoryOrNull;
  final SessionEvidencePreferenceStore _evidencePreferenceStore;
  final SessionEvidencePreferenceRemoteWriter? _evidencePreferenceRemoteWriter;
  final TeacherRelationshipRepository? _teacherRelationshipRepository;
  final Map<String, ({int revision, bool enabled})> _pendingEvidenceSync = {};
  final Set<String> _evidenceSyncingUsers = <String>{};
  final Map<String, int> _evidenceRevisions = <String, int>{};

  SessionRepository get repository => _repositoryOrNull ??= SessionRepository();

  LeaderboardRepository get _leaderboardRepository =>
      _leaderboardRepositoryOrNull ??= LeaderboardRepository();

  SessionEvidenceRepository get _evidenceRepository =>
      _evidenceRepositoryOrNull ??= SessionEvidenceRepository();

  /// Reserves a Firestore document ID for one logical completed attempt.
  ///
  /// The ID is deliberately allocated without writing so a caller can retain
  /// it across an ambiguous persistence failure and retry the same atomic
  /// session/feedback write rather than creating another history record.
  String reserveSessionId() =>
      (_allocateSessionIdOverride ?? repository.allocateSessionId)();

  /// Null means no evidence decision has been recorded yet.
  Future<bool?> sessionEvidenceEnabled(String userId) async {
    final cached = await _evidencePreferenceStore.read(userId);
    if (cached != null) return cached;
    final revision = _evidenceRevisions[userId] ?? 0;
    final remote = FirestoreHelper.instance.getUserById(userId);
    // A profile read is not the local durability boundary. Do not leave the
    // completion flow waiting indefinitely when Firebase is unreachable.
    try {
      final user = await remote.timeout(const Duration(seconds: 2));
      final enabled = user?.sessionEvidenceEnabled;
      if (enabled != null && _evidenceRevisions[userId] == revision) {
        await _evidencePreferenceStore.write(userId, enabled);
      }
      return enabled;
    } on TimeoutException {
      return null;
    }
  }

  Future<void> setSessionEvidenceEnabled({
    required String userId,
    required bool enabled,
  }) async {
    // This local account-scoped value is the practice-flow durability
    // boundary. In particular an offline first decision must not hold the
    // session summary or local outbox behind a Firestore write.
    await _setLocalSessionEvidencePreference(userId: userId, enabled: enabled);
    _scheduleSessionEvidencePreferenceSync(userId: userId, enabled: enabled);
  }

  /// Best-effort profile projection for an already durable local decision.
  /// Calling this again after connectivity returns is safe and preserves an
  /// explicit false decision; it never uploads or retains evidence itself.
  Future<void> syncSessionEvidencePreference(String userId) async {
    final enabled = await _evidencePreferenceStore.read(userId);
    if (enabled == null) return;
    _scheduleSessionEvidencePreferenceSync(userId: userId, enabled: enabled);
  }

  void _scheduleSessionEvidencePreferenceSync({
    required String userId,
    required bool enabled,
  }) {
    final revision = (_evidenceRevisions[userId] ?? 0) + 1;
    _evidenceRevisions[userId] = revision;
    _pendingEvidenceSync[userId] = (revision: revision, enabled: enabled);
    if (_evidenceSyncingUsers.add(userId)) {
      unawaited(_drainSessionEvidencePreferenceSync(userId));
    }
  }

  Future<void> _drainSessionEvidencePreferenceSync(String userId) async {
    var completedWithoutFailure = true;
    try {
      while (true) {
        final pending = _pendingEvidenceSync[userId];
        if (pending == null) return;
        try {
          final writer = _evidencePreferenceRemoteWriter;
          if (writer != null) {
            await writer(userId: userId, enabled: pending.enabled);
          } else {
            await FirestoreHelper.instance.updateUserProfileField(userId, {
              'session_evidence_enabled': pending.enabled,
              'session_evidence_policy_version': 'v1',
              'session_evidence_decision_at': FieldValue.serverTimestamp(),
            });
          }
        } catch (_) {
          // The latest desired value is retained for a foreground retry.
          completedWithoutFailure = false;
          return;
        }
        final latest = _pendingEvidenceSync[userId];
        if (latest?.revision == pending.revision) {
          _pendingEvidenceSync.remove(userId);
        }
      }
    } finally {
      _evidenceSyncingUsers.remove(userId);
      // A value can arrive after the drain's final map check but before the
      // syncing marker is cleared.
      final latest = _pendingEvidenceSync[userId];
      if (completedWithoutFailure && latest != null) {
        _scheduleSessionEvidencePreferenceSync(
          userId: userId,
          enabled: latest.enabled,
        );
      }
    }
  }

  Future<void> revokeSessionEvidence(String userId) async {
    await _setLocalSessionEvidencePreference(userId: userId, enabled: false);
    // Remove the authorization edge first so a Teacher cannot begin another
    // read while retained objects are being purged.
    await _teacherRelationshipRepository?.revokeAllEvidenceAccess(
      traineeId: userId,
    );
    await _evidenceRepository.deleteAllForUser(userId);
    _scheduleSessionEvidencePreferenceSync(userId: userId, enabled: false);
    notifyListeners();
  }

  Future<void> purgeLocalSessionEvidencePreference(String userId) async {
    _evidenceRevisions[userId] = (_evidenceRevisions[userId] ?? 0) + 1;
    _pendingEvidenceSync.remove(userId);
    await _evidencePreferenceStore.purge(userId);
  }

  Future<void> _setLocalSessionEvidencePreference({
    required String userId,
    required bool enabled,
  }) {
    // Invalidate a remote profile read before awaiting the file write so a
    // late old value cannot repopulate or reverse the new local decision.
    _evidenceRevisions[userId] = (_evidenceRevisions[userId] ?? 0) + 1;
    return _evidencePreferenceStore.write(userId, enabled);
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
    SessionAssignmentContext? assignmentContext,
    ClassChallengeSessionContext? challengeContext,
  }) async {
    if (!isOfficialElixrMovementName(movementName)) {
      throw UnofficialMovementException(movementName);
    }
    if (assignmentContext != null) {
      final identity = officialElixrIdentityForName(movementName);
      if (identity == null ||
          assignmentContext.movementId != identity.movementId ||
          assignmentContext.revisionId != identity.revisionId) {
        throw const ClassroomException(
          ClassroomError.identityMismatch,
          'Assignment context does not match this official movement.',
        );
      }
    }
    if (assignmentContext != null && challengeContext != null) {
      throw ArgumentError(
        'A session cannot be both an assignment and a class challenge.',
      );
    }
    final sessionId = existingSessionId ?? reserveSessionId();
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
      assignmentContext: assignmentContext,
      challengeContext: challengeContext,
    );
    final feedbacks = _buildSessionImprovementFeedbacks(
      sessionId,
      sessionImprovements,
    );

    if (assignmentContext != null) {
      final pointer = AssignmentAttempt(
        id: assignmentAttemptIdForOfficialSession(sessionId),
        traineeId: userId,
        teacherId: assignmentContext.teacherId,
        groupId: assignmentContext.groupId,
        assignmentId: assignmentContext.assignmentId,
        movementId: assignmentContext.movementId,
        revisionId: assignmentContext.revisionId,
        origin: MovementOrigin.officialElixr,
        assessmentMode: AssessmentMode.officialGuided,
        attemptKind: AssignmentAttemptKind.practicePointer,
        status: AssignmentAttemptStatus.submitted,
        sourceSessionId: sessionId,
        rubric: rubric,
        durationSeconds: durationSeconds,
        propType: prop,
      );
      final saveAssigned =
          _saveAssignedSessionAtomicOverride ??
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
            required AssignmentAttempt officialAssignmentPointer,
          }) {
            return repository.saveSessionWithFeedbacks(
              sessionId: sessionId,
              session: session,
              feedbacks: feedbacks,
              officialAssignmentPointer: officialAssignmentPointer,
            );
          };
      await saveAssigned(
        sessionId: sessionId,
        session: session,
        feedbacks: feedbacks,
        officialAssignmentPointer: pointer,
      );
    } else {
      final saveAtomic =
          _saveCompletedSessionAtomicOverride ??
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
          }) {
            return repository.saveSessionWithFeedbacks(
              sessionId: sessionId,
              session: session,
              feedbacks: feedbacks,
            );
          };
      await saveAtomic(
        sessionId: sessionId,
        session: session,
        feedbacks: feedbacks,
      );
    }

    if (kDebugMode) {
      debugPrint(
        'Session persistence completed: sessionId=$sessionId userId=$userId',
      );
    }

    // Authoritative persistence already succeeded. Leaderboard XP and public
    // profile projection are idempotent side effects and must not keep the
    // Session Complete UI pending if a Firestore Future never resolves.
    // Challenge sessions are classroom-scoped competitive results. They must
    // never award global XP or appear in the global leaderboard projection.
    if (challengeContext == null) {
      _synchronizeAfterSessionCommit(
        sessionId: sessionId,
        session: session,
        userId: userId,
        displayName: displayName,
        profilePictureUrl: profilePictureUrl,
      );
    }

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
