import 'package:flutter/foundation.dart';

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

class SessionService extends ChangeNotifier {
  SessionService({
    SessionRepository? repository,
    LeaderboardRepository? leaderboardRepository,
    Future<String> Function(Session session)? saveSessionOverride,
    Future<void> Function(List<Feedback> feedbacks)? saveFeedbacksOverride,
    LeaderboardSessionRecorder? recordCompletedSessionOverride,
  }) : _repositoryOrNull = repository,
       _leaderboardRepositoryOrNull = leaderboardRepository,
       _saveSessionOverride = saveSessionOverride,
       _saveFeedbacksOverride = saveFeedbacksOverride,
       _recordCompletedSessionOverride = recordCompletedSessionOverride;

  SessionRepository? _repositoryOrNull;
  LeaderboardRepository? _leaderboardRepositoryOrNull;
  final Future<String> Function(Session session)? _saveSessionOverride;
  final Future<void> Function(List<Feedback> feedbacks)? _saveFeedbacksOverride;
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
    required List<PracticeFeedback> feedbackHistory,
    TrainingProp prop = TrainingProp.bottle,
    String? profilePictureUrl,
  }) async {
    final session = Session(
      userId: userId,
      movementName: movementName,
      difficulty: difficulty,
      score: score,
      durationSeconds: durationSeconds,
      propType: prop,
    );
    final saveSession = _saveSessionOverride ?? repository.saveSession;
    final sessionId = await saveSession(session);

    final seen = <String>{};
    final feedbacks = <Feedback>[];
    for (final item in feedbackHistory.reversed) {
      if (seen.add(item.feedback)) {
        feedbacks.add(
          Feedback(
            sessionId: sessionId,
            message: item.feedback,
            feedbackType: item.feedbackType,
          ),
        );
      }
    }

    if (feedbacks.isNotEmpty) {
      final saveFeedbacks = _saveFeedbacksOverride ?? repository.saveFeedbacks;
      await saveFeedbacks(feedbacks);
    }

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
}
