import 'package:flutter/foundation.dart';

import '../data/models/feedback.dart';
import '../data/models/practice_feedback.dart';
import '../data/models/session.dart';
import '../data/repositories/session_repository.dart';

class SessionService extends ChangeNotifier {
  SessionService({SessionRepository? repository})
      : _repository = repository ?? SessionRepository();

  final SessionRepository _repository;

  SessionRepository get repository => _repository;

  Future<String> saveCompletedSession({
    required String userId,
    required String movementName,
    required String difficulty,
    required int score,
    required int durationSeconds,
    required List<PracticeFeedback> feedbackHistory,
  }) async {
    final sessionId = await _repository.saveSession(
      Session(
        userId: userId,
        movementName: movementName,
        difficulty: difficulty,
        score: score,
        durationSeconds: durationSeconds,
      ),
    );

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
      await _repository.saveFeedbacks(feedbacks);
    }

    notifyListeners();
    return sessionId;
  }
}
