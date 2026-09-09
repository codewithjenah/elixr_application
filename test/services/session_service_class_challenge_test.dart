import 'package:elixr_application/data/models/class_challenge_session_context.dart';
import 'package:elixr_application/data/models/feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/session_assignment_context.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _rubric = RubricAssessment(
  technique: 3,
  stability: 2,
  completion: 3,
  propPositioning: 2,
);

const _challengeContext = ClassChallengeSessionContext(
  challengeId: 'challenge-1',
  groupId: 'group-1',
  teacherId: 'teacher-1',
  attemptId: 'attempt-1',
);

void main() {
  test(
    'challenge save preserves the exact session id and skips global XP',
    () async {
      Session? savedSession;
      var leaderboardCalls = 0;
      var projectionCalls = 0;
      final service = SessionService(
        allocateSessionIdOverride: () => 'allocated-session',
        saveCompletedSessionAtomicOverride:
            ({
              required String sessionId,
              required Session session,
              required List<Feedback> feedbacks,
            }) async {
              expect(sessionId, 'reserved-session');
              savedSession = session;
            },
        recordCompletedSessionOverride:
            ({
              required String sessionId,
              required String userId,
              required String displayName,
              String? profilePictureUrl,
            }) async {
              leaderboardCalls++;
            },
        projectSessionOverride:
            ({required String sessionId, required Session session}) async {
              projectionCalls++;
            },
      );
      addTearDown(service.dispose);

      final sessionId = await service.saveCompletedSession(
        existingSessionId: 'reserved-session',
        userId: 'trainee-1',
        displayName: 'Trainee One',
        movementName: 'Hand Stall',
        difficulty: 'Medium',
        rubric: _rubric,
        durationSeconds: 45,
        sessionImprovements: const [],
        challengeContext: _challengeContext,
      );
      await Future<void>.delayed(Duration.zero);

      expect(sessionId, 'reserved-session');
      expect(
        savedSession?.challengeContext?.toMap(),
        _challengeContext.toMap(),
      );
      expect(savedSession?.assignmentContext, isNull);
      expect(leaderboardCalls, 0);
      expect(projectionCalls, 0);
    },
  );

  test('assignment and challenge contexts cannot collide', () async {
    final service = SessionService(
      saveCompletedSessionAtomicOverride:
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
          }) async {},
    );
    addTearDown(service.dispose);

    await expectLater(
      service.saveCompletedSession(
        userId: 'trainee-1',
        displayName: 'Trainee One',
        movementName: 'Hand Stall',
        difficulty: 'Medium',
        rubric: _rubric,
        durationSeconds: 45,
        sessionImprovements: const [],
        assignmentContext: const SessionAssignmentContext(
          assignmentId: 'assignment-1',
          groupId: 'group-1',
          teacherId: 'teacher-1',
          movementId: 'official_hand_stall',
          revisionId: 'official_hand_stall_v1',
        ),
        challengeContext: _challengeContext,
      ),
      throwsArgumentError,
    );
  });
}
