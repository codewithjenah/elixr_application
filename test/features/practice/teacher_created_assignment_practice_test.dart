import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/live_practice_screen.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('teacher-created assignment practice always uses Free Practice', () {
    const assignment = GroupAssignment(
      id: 'asg1',
      teacherId: 'teacher-1',
      groupId: 'g1',
      movementId: 'tm1',
      revisionId: 'tm1_v1',
      origin: MovementOrigin.teacherCreated,
      assessmentMode: AssessmentMode.teacherReviewed,
      status: GroupAssignmentStatus.active,
      displayTitle: 'Tin Balance',
      teacherDisplayName: 'Grace Hopper',
      groupName: 'BSHM 4A',
      displayInstructions: 'Hold the tin upright.',
      allowedProp: TrainingProp.shaker,
    );
    const mode = TeacherCreatedAssignmentPractice(assignment: assignment);
    expect(
      TeacherCreatedAssignmentPractice.backendMovementName,
      'Free Practice',
    );
    expect(mode.title, 'Tin Balance');
    expect(mode.instructions, 'Hold the tin upright.');
    expect(mode.prop, TrainingProp.shaker);
  });
}
