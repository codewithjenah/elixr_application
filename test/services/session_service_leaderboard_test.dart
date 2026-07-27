import 'package:elixr_application/data/models/feedback.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeFeedback _feedback(String message) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Basic Flip',
    score: 80,
    feedback: message,
    feedbackType: 'positive',
    postureStatus: 'ok',
  );
}

void main() {
  test('failed leaderboard sync does not erase a saved session', () async {
    final savedSessions = <Session>[];
    var saveFeedbackCalls = 0;
    var leaderboardCalls = 0;

    final service = SessionService(
      saveSessionOverride: (session) async {
        savedSessions.add(session);
        return 'session-1';
      },
      saveFeedbacksOverride: (List<Feedback> feedbacks) async {
        saveFeedbackCalls++;
      },
      recordCompletedSessionOverride:
          ({
            required String sessionId,
            required String userId,
            required String displayName,
          }) async {
            leaderboardCalls++;
            throw Exception('firestore unavailable');
          },
    );

    final id = await service.saveCompletedSession(
      userId: 'u1',
      displayName: 'Ada',
      movementName: 'Basic Flip',
      difficulty: 'Easy',
      score: 80,
      durationSeconds: 30,
      feedbackHistory: [_feedback('Nice')],
    );

    expect(id, 'session-1');
    expect(savedSessions, hasLength(1));
    expect(savedSessions.single.userId, 'u1');
    expect(saveFeedbackCalls, 1);
    expect(leaderboardCalls, 1);
  });

  test('successful save records leaderboard with session id', () async {
    String? awardedSessionId;

    final service = SessionService(
      saveSessionOverride: (session) async => 'session-2',
      saveFeedbacksOverride: (_) async {},
      recordCompletedSessionOverride:
          ({
            required String sessionId,
            required String userId,
            required String displayName,
          }) async {
            awardedSessionId = sessionId;
            expect(userId, 'u1');
            expect(displayName, 'Ada');
          },
    );

    final id = await service.saveCompletedSession(
      userId: 'u1',
      displayName: 'Ada',
      movementName: 'Basic Flip',
      difficulty: 'Easy',
      score: 88,
      durationSeconds: 40,
      feedbackHistory: const [],
    );

    expect(id, awardedSessionId);
  });
}
