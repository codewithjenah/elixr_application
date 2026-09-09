import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/assigned_movements/assigned_practice_screen.dart';
import 'package:flutter_test/flutter_test.dart';

GroupAssignment _assignment({
  MovementOrigin origin = MovementOrigin.teacherCreated,
  AssessmentMode mode = AssessmentMode.teacherReviewed,
  TrainingProp? allowedProp = TrainingProp.bottle,
  String? officialName,
}) {
  return GroupAssignment(
    id: 'asg1',
    teacherId: 'teacher-1',
    groupId: 'g1',
    movementId: origin == MovementOrigin.officialElixr
        ? 'official_hand_stall'
        : 'tm1',
    revisionId: origin == MovementOrigin.officialElixr
        ? 'official_hand_stall_v1'
        : 'rev1',
    origin: origin,
    assessmentMode: mode,
    status: GroupAssignmentStatus.active,
    displayTitle: officialName ?? 'Classroom Movement',
    teacherDisplayName: 'Grace Hopper',
    groupName: 'BSHM 4A',
    officialMovementName: officialName,
    allowedProp: allowedProp,
  );
}

void main() {
  test('officialGuided dispatches to the official path', () {
    expect(
      dispatchAssignedPractice(
        _assignment(
          origin: MovementOrigin.officialElixr,
          mode: AssessmentMode.officialGuided,
          officialName: 'Hand Stall',
          allowedProp: null,
        ),
      ),
      AssignedPracticeDispatch.officialGuided,
    );
  });

  test('teacherReviewed dispatches to teacher recording', () {
    expect(
      dispatchAssignedPractice(_assignment()),
      AssignedPracticeDispatch.teacherReviewed,
    );
  });

  test(
    'historical template assignment never dispatches to camera practice',
    () {
      expect(
        dispatchAssignedPractice(
          _assignment(mode: AssessmentMode.templateScored),
        ),
        AssignedPracticeDispatch.retiredTemplate,
      );
    },
  );

  test('archived teacher-reviewed assignment is invalid', () {
    expect(
      dispatchAssignedPractice(
        GroupAssignment(
          id: 'asg1',
          teacherId: 'teacher-1',
          groupId: 'g1',
          movementId: 'tm1',
          revisionId: 'rev1',
          origin: MovementOrigin.teacherCreated,
          assessmentMode: AssessmentMode.teacherReviewed,
          status: GroupAssignmentStatus.archived,
          displayTitle: 'Classroom Movement',
          teacherDisplayName: 'Grace Hopper',
          groupName: 'BSHM 4A',
          allowedProp: TrainingProp.bottle,
        ),
      ),
      AssignedPracticeDispatch.invalid,
    );
  });
}
