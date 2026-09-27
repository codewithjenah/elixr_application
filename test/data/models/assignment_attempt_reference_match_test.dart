import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> referenceAttempt({
  int total = 10,
  String level = 'proficient',
  Map<String, Object?>? scores,
}) => {
  'trainee_id': 'trainee-1',
  'teacher_id': 'teacher-1',
  'group_id': 'group-1',
  'assignment_id': 'assignment-1',
  'movement_id': 'movement-1',
  'revision_id': 'revision-1',
  'origin': 'teacher_created',
  'assessment_mode': 'reference_matched',
  'attempt_kind': 'reference_match',
  'status': 'submitted',
  'awards_global_xp': false,
  'reference_total': total,
  'reference_max_total': 12,
  'reference_component_scores':
      scores ??
      {
        'Body technique': 3,
        'Hand technique': 2,
        'Prop path': 3,
        'Timing': 2,
        'Control/stability': 2,
      },
  'performance_level': level,
  'prop_type': 'bottle',
  'created_at': DateTime.utc(2026, 9, 21),
  'completed_at': DateTime.utc(2026, 9, 21),
};

void main() {
  test('reference match parses a self-consistent automatic result', () {
    final attempt = AssignmentAttempt.tryFromMap(
      referenceAttempt(),
      id: 'custom_assignment-1_trainee-1_1',
    );

    expect(attempt, isNotNull);
    expect(attempt!.referenceTotal, 10);
    expect(attempt.referencePerformanceLevel, 'proficient');
    expect(attempt.awardsGlobalXp, isFalse);
  });

  test('reference match rejects an out-of-range total', () {
    expect(
      AssignmentAttempt.tryFromMap(
        referenceAttempt(total: 13, level: 'mastered'),
        id: 'custom_assignment-1_trainee-1_1',
      ),
      isNull,
    );
  });

  test('reference match requires the exact five component categories', () {
    expect(
      AssignmentAttempt.tryFromMap(
        referenceAttempt(
          scores: {
            'Body technique': 3,
            'Hand technique': 3,
            'Prop path': 3,
            'Timing': 3,
            'Made up': 3,
          },
        ),
        id: 'custom_assignment-1_trainee-1_1',
      ),
      isNull,
    );
  });

  test('reference match keeps a Not assessed component as null', () {
    final attempt = AssignmentAttempt.tryFromMap(
      referenceAttempt(
        scores: {
          'Body technique': null,
          'Hand technique': 2,
          'Prop path': 2,
          'Timing': 3,
          'Control/stability': 3,
        },
      ),
      id: 'custom_assignment-1_trainee-1_1',
    );

    expect(attempt, isNotNull);
    expect(attempt!.referenceTotal, 10);
    expect(
      attempt.referenceComponentScores!.containsKey('Body technique'),
      isTrue,
    );
    expect(attempt.referenceComponentScores!['Body technique'], isNull);
  });

  test('reference match rejects malformed component values', () {
    for (final bad in <Object?>[4, -1, 'x', 2.5]) {
      expect(
        AssignmentAttempt.tryFromMap(
          referenceAttempt(
            scores: {
              'Body technique': bad,
              'Hand technique': 2,
              'Prop path': 2,
              'Timing': 3,
              'Control/stability': 3,
            },
          ),
          id: 'custom_assignment-1_trainee-1_1',
        ),
        isNull,
        reason: '$bad',
      );
    }
  });

  test('reference match rejects inconsistent performance level', () {
    expect(
      AssignmentAttempt.tryFromMap(
        referenceAttempt(level: 'mastered'),
        id: 'custom_assignment-1_trainee-1_1',
      ),
      isNull,
    );
  });
}
