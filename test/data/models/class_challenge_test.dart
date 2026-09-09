import 'package:elixr_application/data/models/class_challenge.dart';
import 'package:elixr_application/data/models/class_challenge_session_context.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('function payload converts local challenge dates to UTC', () {
    final challenge = ClassChallenge(
      id: '',
      groupId: 'group-1',
      teacherId: 'teacher-1',
      teacherDisplayName: 'Teacher One',
      title: 'Hand Stall Sprint',
      description: 'Set your best rubric score.',
      movementName: 'Hand Stall',
      difficulty: 'Medium',
      prop: TrainingProp.bottle,
      startAt: DateTime.parse('2026-09-09T10:00:00+08:00'),
      deadline: DateTime.parse('2026-09-10T10:00:00+08:00'),
      attemptLimit: 3,
      targetScore: 10,
    );

    expect(challenge.toFunctionPayload(), {
      'group_id': 'group-1',
      'title': 'Hand Stall Sprint',
      'description': 'Set your best rubric score.',
      'movement_name': 'Hand Stall',
      'difficulty': 'Medium',
      'prop_type': 'bottle',
      'start_at': '2026-09-09T02:00:00.000Z',
      'deadline': '2026-09-10T02:00:00.000Z',
      'attempt_limit': 3,
      'target_score': 10,
    });
  });

  test('function response and challenge session context round-trip', () {
    final challenge = ClassChallenge.tryFromMap({
      'group_id': 'group-1',
      'teacher_id': 'teacher-1',
      'teacher_display_name': 'Teacher One',
      'title': 'Hand Stall Sprint',
      'description': 'Set your best rubric score.',
      'movement_name': 'Hand Stall',
      'difficulty': 'Medium',
      'prop_type': 'bottle',
      'start_at': '2026-09-09T02:00:00.000Z',
      'deadline': '2026-09-10T02:00:00.000Z',
      'completed_count': 2,
      'top_score': 11,
    }, id: 'challenge-1');
    const context = ClassChallengeSessionContext(
      challengeId: 'challenge-1',
      groupId: 'group-1',
      teacherId: 'teacher-1',
      attemptId: 'attempt-1',
    );

    expect(challenge, isNotNull);
    expect(challenge!.startAt, DateTime.utc(2026, 9, 9, 2));
    expect(challenge.deadline, DateTime.utc(2026, 9, 10, 2));
    expect(challenge.topScore, 11);
    expect(
      ClassChallengeSessionContext.tryFrom(context.toMap())?.toMap(),
      context.toMap(),
    );
  });
}
