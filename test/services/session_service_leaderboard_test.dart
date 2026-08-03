import 'package:elixr_application/data/database/firestore_helper.dart';
import 'package:elixr_application/data/models/feedback.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/training_prop.dart';
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
  test(
    'atomic save issues one persistence call with session and feedbacks',
    () async {
      var atomicCalls = 0;
      String? capturedSessionId;
      Session? capturedSession;
      List<Feedback>? capturedFeedbacks;

      final service = SessionService(
        allocateSessionIdOverride: () => 'session-atomic',
        saveCompletedSessionAtomicOverride:
            ({
              required String sessionId,
              required Session session,
              required List<Feedback> feedbacks,
            }) async {
              atomicCalls++;
              capturedSessionId = sessionId;
              capturedSession = session;
              capturedFeedbacks = feedbacks;
            },
        recordCompletedSessionOverride:
            ({
              required String sessionId,
              required String userId,
              required String displayName,
              String? profilePictureUrl,
            }) async {},
      );

      final id = await service.saveCompletedSession(
        userId: 'u1',
        displayName: 'Ada',
        movementName: 'Basic Flip',
        difficulty: 'Easy',
        score: 80,
        durationSeconds: 30,
        feedbackHistory: [_feedback('Nice'), _feedback('Nice')],
      );

      expect(atomicCalls, 1);
      expect(id, capturedSessionId);
      expect(capturedSession?.id, id);
      expect(capturedFeedbacks, hasLength(1));
      expect(
        capturedFeedbacks!.single.id,
        FirestoreHelper.feedbackDocumentId(id, 0),
      );
    },
  );

  test('atomic save failure does not leave a session-only record', () async {
    var atomicCalls = 0;

    final service = SessionService(
      allocateSessionIdOverride: () => 'session-atomic',
      saveCompletedSessionAtomicOverride:
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
          }) async {
            atomicCalls++;
            throw Exception('feedback batch failed');
          },
      recordCompletedSessionOverride:
          ({
            required String sessionId,
            required String userId,
            required String displayName,
            String? profilePictureUrl,
          }) async {},
    );

    await expectLater(
      service.saveCompletedSession(
        userId: 'u1',
        displayName: 'Ada',
        movementName: 'Basic Flip',
        difficulty: 'Easy',
        score: 80,
        durationSeconds: 30,
        feedbackHistory: [_feedback('Nice')],
      ),
      throwsA(isA<Exception>()),
    );

    expect(atomicCalls, 1);
  });

  test('retry reuses the same session id', () async {
    final sessionIds = <String>[];

    final service = SessionService(
      allocateSessionIdOverride: () => 'session-atomic',
      saveCompletedSessionAtomicOverride:
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
          }) async {
            sessionIds.add(sessionId);
            if (sessionIds.length == 1) {
              throw Exception('transient failure');
            }
          },
      recordCompletedSessionOverride:
          ({
            required String sessionId,
            required String userId,
            required String displayName,
            String? profilePictureUrl,
          }) async {},
    );

    await expectLater(
      service.saveCompletedSession(
        userId: 'u1',
        displayName: 'Ada',
        movementName: 'Basic Flip',
        difficulty: 'Easy',
        score: 80,
        durationSeconds: 30,
        feedbackHistory: const [],
      ),
      throwsA(isA<Exception>()),
    );

    final firstSessionId = sessionIds.single;

    final id = await service.saveCompletedSession(
      userId: 'u1',
      displayName: 'Ada',
      movementName: 'Basic Flip',
      difficulty: 'Easy',
      score: 80,
      durationSeconds: 30,
      feedbackHistory: const [],
      existingSessionId: firstSessionId,
    );

    expect(sessionIds, hasLength(2));
    expect(sessionIds.first, sessionIds.last);
    expect(id, firstSessionId);
  });

  test('failed leaderboard sync does not erase a saved session', () async {
    var atomicCalls = 0;
    var leaderboardCalls = 0;

    final service = SessionService(
      allocateSessionIdOverride: () => 'session-atomic',
      saveCompletedSessionAtomicOverride:
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
          }) async {
            atomicCalls++;
          },
      recordCompletedSessionOverride:
          ({
            required String sessionId,
            required String userId,
            required String displayName,
            String? profilePictureUrl,
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

    expect(id, isNotEmpty);
    expect(atomicCalls, 1);
    expect(leaderboardCalls, 1);
  });

  test('successful save records leaderboard with session id', () async {
    String? awardedSessionId;

    final service = SessionService(
      allocateSessionIdOverride: () => 'session-atomic',
      saveCompletedSessionAtomicOverride:
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
          }) async {},
      recordCompletedSessionOverride:
          ({
            required String sessionId,
            required String userId,
            required String displayName,
            String? profilePictureUrl,
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

  test('completed shaker session saves its selected prop', () async {
    Session? saved;
    final service = SessionService(
      allocateSessionIdOverride: () => 'session-atomic',
      saveCompletedSessionAtomicOverride:
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
          }) async {
            saved = session;
          },
      recordCompletedSessionOverride:
          ({
            required String sessionId,
            required String userId,
            required String displayName,
            String? profilePictureUrl,
          }) async {},
    );

    await service.saveCompletedSession(
      userId: 'u1',
      displayName: 'Ada',
      movementName: 'Hand Stall',
      difficulty: 'Medium',
      score: 92,
      durationSeconds: 45,
      feedbackHistory: const [],
      prop: TrainingProp.shaker,
    );

    expect(saved?.propType, TrainingProp.shaker);
    expect(saved?.toMap()['prop_type'], 'shaker');
  });
}
