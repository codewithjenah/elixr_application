import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> referenceAttempt({
  int total = 10,
  String level = 'proficient',
  Map<String, int>? scores,
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

  test('reference match rejects a forged total', () {
    expect(
      AssignmentAttempt.tryFromMap(
        referenceAttempt(total: 12, level: 'mastered'),
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

  test('shared total projection remains bounded and deterministic', () {
    expect(referenceMatchedTotal([0, 0, 0, 0, 0]), 0);
    expect(referenceMatchedTotal([3, 2, 3, 2, 2]), 10);
    expect(referenceMatchedTotal([3, 3, 3, 3, 3]), 12);
  });
}
