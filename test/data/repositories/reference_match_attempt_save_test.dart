import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt_policy.dart';
import 'package:elixr_application/data/models/classroom_exceptions.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/movement_template.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final _assignment = GroupAssignment(
  id: 'assignment-ref',
  teacherId: 'teacher-1',
  groupId: 'group-1',
  movementId: 'movement-1',
  revisionId: 'revision-1',
  origin: MovementOrigin.teacherCreated,
  assessmentMode: AssessmentMode.referenceMatched,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Static hold',
  teacherDisplayName: 'Grace Hopper',
  groupName: 'BSHM 4A',
  allowedProp: TrainingProp.bottle,
  attemptPolicy: const AssignmentAttemptPolicy.finite(2),
  movementTemplate: MovementTemplate.tryFrom({
    'schema_version': 1,
    'capture_version': 1,
    'duration_ms': 900,
    'reference_count': 3,
    'required_modalities': ['hands', 'prop_translation'],
    'normalization_metadata': {
      'anchor': 'shoulder_midpoint',
      'scale': 'shoulder_width',
      'mirrored': false,
    },
    'feature_capabilities': {
      'pose': false,
      'hands': true,
      'prop_translation': true,
      'release_catch': false,
      'prop_rotation': false,
      'left_hand': true,
      'right_hand': false,
    },
    'canonical_sequence': [
      {'timestamp_ms': 0, 'pose': <String, dynamic>{}},
      {'timestamp_ms': 900, 'pose': <String, dynamic>{}},
    ],
    'variability_metadata': {'duration_std_ms': 0.0},
    'prop_events': <Map<String, dynamic>>[],
  })!,
);

void main() {
  test('10/12 result with Body technique Not assessed saves once', () async {
    final repo = InMemoryClassroomAssignmentRepository();
    await repo.saveCustomMovementAssignmentAttempt(
      assignment: _assignment,
      traineeId: 'trainee-1',
      total: 10,
      performanceLevel: 'proficient',
      componentScores: const {
        'Body technique': null,
        'Hand technique': 2,
        'Prop path': 2,
        'Timing': 3,
        'Control/stability': 3,
      },
    );

    expect(repo.attempts, hasLength(1));
    final saved = repo.attempts.values.single;
    expect(saved.referenceTotal, 10);
    expect(saved.referencePerformanceLevel, 'proficient');
    expect(saved.referenceComponentScores!.containsKey('Body technique'), true);
    expect(saved.referenceComponentScores!['Body technique'], isNull);
    final written = saved.toCreateMap(createdAt: DateTime.utc(2026));
    expect(
      (written['reference_component_scores'] as Map)['Body technique'],
      isNull,
    );
  });

  test('fully assessed result still saves', () async {
    final repo = InMemoryClassroomAssignmentRepository();
    await repo.saveCustomMovementAssignmentAttempt(
      assignment: _assignment,
      traineeId: 'trainee-1',
      total: 10,
      performanceLevel: 'proficient',
      componentScores: const {
        'Body technique': 3,
        'Hand technique': 2,
        'Prop path': 3,
        'Timing': 2,
        'Control/stability': 2,
      },
    );
    expect(repo.attempts, hasLength(1));
  });

  test('malformed results are rejected without consuming an attempt', () async {
    final repo = InMemoryClassroomAssignmentRepository();
    final cases = <(int, String, Map<String, int?>)>[
      (10, 'proficient', {'Hand technique': 2}),
      (
        10,
        'proficient',
        {
          'Body technique': 4,
          'Hand technique': 2,
          'Prop path': 2,
          'Timing': 3,
          'Control/stability': 3,
        },
      ),
      (
        10,
        'proficient',
        {
          'Body technique': null,
          'Hand technique': null,
          'Prop path': null,
          'Timing': null,
          'Control/stability': null,
        },
      ),
      (
        10,
        'mastered',
        {
          'Body technique': null,
          'Hand technique': 2,
          'Prop path': 2,
          'Timing': 3,
          'Control/stability': 3,
        },
      ),
      (
        13,
        'mastered',
        {
          'Body technique': 3,
          'Hand technique': 3,
          'Prop path': 3,
          'Timing': 3,
          'Control/stability': 3,
        },
      ),
    ];
    for (final (total, level, scores) in cases) {
      await expectLater(
        repo.saveCustomMovementAssignmentAttempt(
          assignment: _assignment,
          traineeId: 'trainee-1',
          total: total,
          performanceLevel: level,
          componentScores: scores,
        ),
        throwsA(isA<ClassroomException>()),
      );
    }
    expect(repo.attempts, isEmpty);
  });
}
