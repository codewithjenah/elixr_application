import 'package:flutter/foundation.dart';

import '../data/database/firestore_helper.dart';
import '../data/models/feedback.dart';
import '../data/models/practice_feedback.dart';
import '../data/models/session.dart';
import '../data/models/training_prop.dart';
import '../data/repositories/leaderboard_repository.dart';
import '../data/repositories/session_repository.dart';

typedef LeaderboardSessionRecorder =
    Future<void> Function({
      required String sessionId,
      required String userId,
      required String displayName,
      String? profilePictureUrl,
    });

typedef CompletedSessionAtomicSaver =
    Future<void> Function({
      required String sessionId,
      required Session session,
      required List<Feedback> feedbacks,
    });

class SessionService extends ChangeNotifier {
  SessionService({
    SessionRepository? repository,
    LeaderboardRepository? leaderboardRepository,
    CompletedSessionAtomicSaver? saveCompletedSessionAtomicOverride,
    String Function()? allocateSessionIdOverride,
    LeaderboardSessionRecorder? recordCompletedSessionOverride,
  }) : _repositoryOrNull = repository,
       _leaderboardRepositoryOrNull = leaderboardRepository,
       _saveCompletedSessionAtomicOverride = saveCompletedSessionAtomicOverride,
       _allocateSessionIdOverride = allocateSessionIdOverride,
       _recordCompletedSessionOverride = recordCompletedSessionOverride;

  SessionRepository? _repositoryOrNull;
  LeaderboardRepository? _leaderboardRepositoryOrNull;
  final CompletedSessionAtomicSaver? _saveCompletedSessionAtomicOverride;
  final String Function()? _allocateSessionIdOverride;
  final LeaderboardSessionRecorder? _recordCompletedSessionOverride;

  SessionRepository get repository => _repositoryOrNull ??= SessionRepository();

  LeaderboardRepository get _leaderboardRepository =>
      _leaderboardRepositoryOrNull ??= LeaderboardRepository();

  Future<String> saveCompletedSession({
    required String userId,
    required String displayName,
    required String movementName,
    required String difficulty,
    required int score,
    required int durationSeconds,
    required List<PracticeFeedback> sessionImprovements,
    TrainingProp prop = TrainingProp.bottle,
    String? profilePictureUrl,
    String? existingSessionId,
  }) async {
    final allocateSessionId =
        _allocateSessionIdOverride ?? repository.allocateSessionId;
    final sessionId = existingSessionId ?? allocateSessionId();
    final session = Session(
      id: sessionId,
      userId: userId,
      movementName: movementName,
      difficulty: difficulty,
      score: score,
      durationSeconds: durationSeconds,
      propType: prop,
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

    // Leaderboard sync must not erase a successfully saved practice session.
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
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'Leaderboard sync failed after session save: '
          'sessionId=$sessionId userId=$userId error=$error',
        );
        debugPrint('$stackTrace');
      }
    }

    notifyListeners();
    return sessionId;
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
