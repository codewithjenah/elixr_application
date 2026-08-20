import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/feedback.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/session_assignment_context.dart';
import 'package:elixr_application/data/models/assignment_attempt_ids.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _rubric = RubricAssessment(
  technique: 3,
  stability: 2,
  completion: 2,
  propPositioning: 3,
);

PracticeFeedback _feedback() {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Hand Stall',
    assessment: _rubric,
    feedback: 'Keep your wrist steady',
    feedbackType: 'warning',
    postureStatus: 'ok',
  );
}

const _context = SessionAssignmentContext(
  assignmentId: 'asg1',
  groupId: 'g1',
  teacherId: 'teacher-1',
  movementId: 'official_hand_stall',
  revisionId: 'official_hand_stall_v1',
);

void main() {
  test(
    'official assignment save is atomic session+pointer then XP once',
    () async {
      var assignedCalls = 0;
      var ordinaryCalls = 0;
      var xpCalls = 0;
      AssignmentAttempt? pointer;

      final service = SessionService(
        allocateSessionIdOverride: () => 'sessA',
        saveCompletedSessionAtomicOverride:
            ({
              required String sessionId,
              required Session session,
              required List<Feedback> feedbacks,
            }) async {
              ordinaryCalls++;
            },
        saveAssignedSessionAtomicOverride:
            ({
              required String sessionId,
              required Session session,
              required List<Feedback> feedbacks,
              required AssignmentAttempt officialAssignmentPointer,
            }) async {
              assignedCalls++;
              pointer = officialAssignmentPointer;
              expect(session.assignmentContext, _context);
              expect(sessionId, 'sessA');
            },
        recordCompletedSessionOverride:
            ({
              required String sessionId,
              required String userId,
              required String displayName,
              String? profilePictureUrl,
            }) async {
              xpCalls++;
              expect(sessionId, 'sessA');
            },
        projectSessionOverride:
            ({required String sessionId, required Session session}) async {},
      );

      final id = await service.saveCompletedSession(
        userId: 'trainee-1',
        displayName: 'Ada',
        movementName: 'Hand Stall',
        difficulty: 'Medium',
        rubric: _rubric,
        durationSeconds: 30,
        sessionImprovements: [_feedback()],
        assignmentContext: _context,
      );

      expect(id, 'sessA');
      expect(assignedCalls, 1);
      expect(ordinaryCalls, 0);
      expect(pointer?.awardsGlobalXp, isFalse);
      expect(pointer?.sourceSessionId, 'sessA');
      expect(pointer?.id, assignmentAttemptIdForOfficialSession('sessA'));
      await Future<void>.delayed(Duration.zero);
      expect(xpCalls, 1);

      await service.saveCompletedSession(
        existingSessionId: 'sessA',
        userId: 'trainee-1',
        displayName: 'Ada',
        movementName: 'Hand Stall',
        difficulty: 'Medium',
        rubric: _rubric,
        durationSeconds: 30,
        sessionImprovements: [_feedback()],
        assignmentContext: _context,
      );
      await Future<void>.delayed(Duration.zero);
      expect(assignedCalls, 2);
      expect(xpCalls, 2);
    },
  );

  test('ordinary practice still uses the 3-argument atomic saver', () async {
    var ordinaryCalls = 0;
    var assignedCalls = 0;
    final service = SessionService(
      allocateSessionIdOverride: () => 'sessB',
      saveCompletedSessionAtomicOverride:
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
          }) async {
            ordinaryCalls++;
            expect(session.assignmentContext, isNull);
          },
      saveAssignedSessionAtomicOverride:
          ({
            required String sessionId,
            required Session session,
            required List<Feedback> feedbacks,
            required AssignmentAttempt officialAssignmentPointer,
          }) async {
            assignedCalls++;
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
      userId: 'trainee-1',
      displayName: 'Ada',
      movementName: 'Hand Stall',
      difficulty: 'Medium',
      rubric: _rubric,
      durationSeconds: 30,
      sessionImprovements: const [],
    );
    expect(ordinaryCalls, 1);
    expect(assignedCalls, 0);
  });
}
