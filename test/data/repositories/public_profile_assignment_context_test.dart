import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/session_assignment_context.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public profile projection omits classroom assignment identity', () {
    const session = Session(
      id: 'sessA',
      userId: 'trainee-1',
      movementName: 'Hand Stall',
      difficulty: 'Medium',
      rubric: RubricAssessment(
        technique: 3,
        stability: 2,
        completion: 3,
        propPositioning: 2,
      ),
      assessmentVersion: 2,
      durationSeconds: 40,
      assignmentContext: SessionAssignmentContext(
        assignmentId: 'asg1',
        groupId: 'group-1',
        teacherId: 'teacher-1',
        movementId: 'official_hand_stall',
        revisionId: 'official_hand_stall_v1',
      ),
    );

    final payload = PublicProfileRepository.sanitizedPracticeProjectionFields(
      sessionId: 'sessA',
      session: session,
      createdAt: 'now',
    );

    expect(payload['movement_name'], 'Hand Stall');
    expect(payload['user_id'], 'trainee-1');
    expect(payload.containsKey('assignment_context'), isFalse);
    expect(payload.containsKey('assignment_id'), isFalse);
    expect(payload.containsKey('group_id'), isFalse);
    expect(payload.containsKey('teacher_id'), isFalse);
    expect(payload.containsKey('movement_id'), isFalse);
    expect(payload.containsKey('revision_id'), isFalse);
    expect(payload.values, isNot(contains('asg1')));
    expect(payload.values, isNot(contains('group-1')));
    expect(payload.values, isNot(contains('teacher-1')));
    expect(payload.values, isNot(contains('official_hand_stall')));
  });
}
