import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movements_controller.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Teacher Activities library exposes Official ELIXR and teacher activities',
    () {
      expect(TeacherMovementsTab.values, [
        TeacherMovementsTab.official,
        TeacherMovementsTab.mine,
      ]);
    },
  );

  test('official catalog is the enabled ELIXR catalog', () async {
    final groups = InMemoryGroupRepository();
    final movements = InMemoryTeacherMovementRepository();
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(groups.dispose);
    addTearDown(movements.dispose);
    addTearDown(assignments.dispose);
    final controller = TeacherMovementsController(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      groupRepository: groups,
      movementRepository: movements,
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.start();

    expect(controller.officialCatalog, hasLength(12));
    expect(
      controller.officialCatalog.map((movement) => movement.name),
      unorderedEquals(
        movementCatalog
            .where((movement) => movement.enabled)
            .map((movement) => movement.name),
      ),
    );
  });

  test('assigns movements and prevents deleting an in-use movement', () async {
    final groups = InMemoryGroupRepository();
    const group = ElixrGroup(
      id: 'g1',
      teacherId: 'teacher-1',
      name: 'BSHM 4A',
      status: ElixrGroupStatus.active,
    );
    groups.seedGroup(group);
    final movements = InMemoryTeacherMovementRepository();
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(groups.dispose);
    addTearDown(movements.dispose);
    addTearDown(assignments.dispose);
    final custom = await movements.createMovement(
      teacherId: 'teacher-1',
      title: 'Tin Balance',
      instructions: 'Balance the tin upright.',
      requiredProp: TrainingProp.bottle,
    );
    final controller = TeacherMovementsController(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
      groupRepository: groups,
      movementRepository: movements,
      assignmentRepository: assignments,
    );
    addTearDown(controller.dispose);
    await controller.start();

    await controller.assignTeacherCreated(movement: custom, group: group);
    expect(controller.hasAssignmentsForMovement(custom), isTrue);
    expect(controller.canDeleteMovement(custom), isFalse);
    await controller.deleteMovement(custom);
    expect(await movements.getMovement(movementId: custom.id), isNotNull);
    expect(
      controller.errorMessage,
      'This Teacher Activity cannot be deleted because it is used by an assignment.',
    );
  });
}
