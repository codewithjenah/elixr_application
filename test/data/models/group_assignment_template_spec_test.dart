import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assessment_spec.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _base({
  String origin = 'teacher_created',
  String assessmentMode = 'teacher_reviewed',
  String? officialName,
  Object? allowedProp = 'bottle',
  Object? assessmentSpec,
}) {
  return {
    'teacher_id': 'teacher-1',
    'group_id': 'g1',
    'movement_id': 'tm1',
    'revision_id': 'rev1',
    'origin': origin,
    'assessment_mode': assessmentMode,
    'status': 'active',
    'display_title': 'Tin Balance',
    'teacher_display_name': 'Grace Hopper',
    'group_name': 'BSHM 4A',
    'official_movement_name': ?officialName,
    'display_instructions': 'Hold the bottle still.',
    'allowed_prop': ?allowedProp,
    'assessment_spec': ?assessmentSpec,
  };
}

Map<String, dynamic> _spec({String laterality = 'either'}) {
  return {
    'schema_version': 1,
    'template_id': 'balance_stall.wrist_v1',
    'prop': 'bottle',
    'target': 'wrist',
    'laterality': laterality,
  };
}

void main() {
  test(
    'legacy assignment without audience fields is available to entire class',
    () {
      final assignment = GroupAssignment.tryFromMap(_base(), id: 'asg1');

      expect(assignment, isNotNull);
      expect(assignment!.audience.type, AssignmentAudienceType.entireClass);
      expect(assignment.audience.targetTraineeIds, isEmpty);
      expect(assignment.isAvailableToTrainee('any-trainee'), isTrue);
    },
  );

  test(
    'canonical targeted audiences are unresolved until recipients hydrate',
    () {
      final selected = GroupAssignment.tryFromMap({
        ..._base(),
        'audience_type': 'selected_students',
      }, id: 'selected');
      final individual = GroupAssignment.tryFromMap({
        ..._base(),
        'audience_type': 'individual_student',
      }, id: 'individual');

      expect(selected?.audience.type, AssignmentAudienceType.selectedStudents);
      expect(selected?.isAvailableToTrainee('trainee-b'), isFalse);
      expect(selected?.isAvailableToTrainee('trainee-c'), isFalse);
      expect(
        individual?.audience.type,
        AssignmentAudienceType.individualStudent,
      );
      expect(individual?.isAvailableToTrainee('trainee-a'), isFalse);
      expect(individual?.isAvailableToTrainee('trainee-b'), isFalse);
    },
  );

  test('selected audience supports a realistic uncapped recipient subset', () {
    final ids = [for (var index = 0; index < 24; index++) 'trainee-$index'];
    final audience = AssignmentAudience.selectedStudents(ids);
    expect(audience.targetTraineeIds, ids);
    expect(audience.toMap(), {'audience_type': 'selected_students'});
    expect(audience.isAvailableToTrainee('trainee-23'), isTrue);
    expect(
      AssignmentAudience.individualStudent(const ['trainee-a']).isResolved,
      isTrue,
    );
  });

  test('malformed audience combinations fail closed', () {
    final malformed = [
      {'target_trainee_ids': <String>[]},
      {
        'audience_type': 'entire_class',
        'target_trainee_ids': ['trainee-a'],
      },
      {'audience_type': 'selected_students', 'target_trainee_ids': <String>[]},
      {
        'audience_type': 'individual_student',
        'target_trainee_ids': ['trainee-a', 'trainee-b'],
      },
      {
        'audience_type': 'selected_students',
        'target_trainee_ids': ['trainee-a', 'trainee-a'],
      },
    ];

    for (final fields in malformed) {
      expect(
        GroupAssignment.tryFromMap({..._base(), ...fields}, id: 'asg1'),
        isNull,
      );
    }
  });

  test('teacher_reviewed old shape still parses without assessment_spec', () {
    final assignment = GroupAssignment.tryFromMap(_base(), id: 'asg1');
    expect(assignment, isNotNull);
    expect(assignment!.assessmentMode, AssessmentMode.teacherReviewed);
    expect(assignment.assessmentSpec, isNull);
    expect(assignment.allowedProp, TrainingProp.bottle);
  });

  test('teacher_reviewed assignment parses score configuration and lock', () {
    final assignment = GroupAssignment.tryFromMap({
      ..._base(),
      'max_score': 80,
      'grading_locked': true,
      'grading_locked_at': DateTime.utc(2026, 8, 21),
    }, id: 'asg1');

    expect(assignment, isNotNull);
    expect(assignment!.maxScore, 80);
    expect(assignment.gradingLocked, isTrue);
    expect(assignment.gradingLockedAt, DateTime.utc(2026, 8, 21));
  });

  test('teacher_reviewed score configuration is bounded and type-safe', () {
    for (final value in [0, 101, 80.0, '80']) {
      expect(
        GroupAssignment.tryFromMap({
          ..._base(),
          'max_score': value,
        }, id: 'asg1'),
        isNull,
      );
    }
    expect(
      GroupAssignment.tryFromMap({
        ..._base(),
        'grading_locked': true,
      }, id: 'asg1'),
      isNotNull,
    );
    expect(
      GroupAssignment.tryFromMap({
        ..._base(),
        'grading_locked': false,
        'grading_locked_at': DateTime.utc(2026, 8, 21),
      }, id: 'asg1'),
      isNull,
    );
  });

  test('template_scored canonical snapshot parses', () {
    final assignment = GroupAssignment.tryFromMap(
      _base(
        assessmentMode: 'template_scored',
        assessmentSpec: _spec(laterality: 'left'),
      ),
      id: 'asg1',
    );
    expect(assignment, isNotNull);
    expect(assignment!.assessmentMode, AssessmentMode.templateScored);
    expect(
      assignment.assessmentSpec,
      const AssessmentSpec(laterality: AssessmentLaterality.left),
    );
  });

  test('template missing assessment_spec fails', () {
    expect(
      GroupAssignment.tryFromMap(
        _base(assessmentMode: 'template_scored'),
        id: 'asg1',
      ),
      isNull,
    );
  });

  test('template malformed spec fails', () {
    expect(
      GroupAssignment.tryFromMap(
        _base(
          assessmentMode: 'template_scored',
          assessmentSpec: {..._spec(), 'threshold': 0.4},
        ),
        id: 'asg1',
      ),
      isNull,
    );
  });

  test('template allowed_prop mismatch fails', () {
    expect(
      GroupAssignment.tryFromMap(
        _base(
          assessmentMode: 'template_scored',
          allowedProp: 'shaker',
          assessmentSpec: _spec(),
        ),
        id: 'asg1',
      ),
      isNull,
    );
  });

  test('teacher_reviewed + assessment_spec fails', () {
    expect(
      GroupAssignment.tryFromMap(_base(assessmentSpec: _spec()), id: 'asg1'),
      isNull,
    );
  });

  test('official + assessment_spec fails', () {
    expect(
      GroupAssignment.tryFromMap(
        _base(
            origin: 'official_elixr',
            assessmentMode: 'official_guided',
            officialName: 'Hand Stall',
            allowedProp: null,
            assessmentSpec: _spec(),
          )
          ..['movement_id'] = 'official_hand_stall'
          ..['revision_id'] = 'official_hand_stall_v1',
        id: 'asg1',
      ),
      isNull,
    );
  });
}
