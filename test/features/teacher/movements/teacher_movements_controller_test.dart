import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/data/repositories/in_memory_teacher_movement_repository.dart';
import 'package:elixr_application/features/teacher/movements/teacher_movements_controller.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('official catalog is the enabled 12 ELIXR movements', () async {
    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    final movements = InMemoryTeacherMovementRepository();
    addTearDown(movements.dispose);
    final assignments = InMemoryClassroomAssignmentRepository();
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
        movementCatalog.where((m) => m.enabled).map((m) => m.name),
      ),
    );
    expect(
      controller.officialCatalog.any(
        (movement) => movement.name == 'Arm Stall',
      ),
      isFalse,
    );
  });

  test('assign official movement to own active group', () async {
    final groups = InMemoryGroupRepository();
    addTearDown(groups.dispose);
    groups.seedGroup(
      const ElixrGroup(
        id: 'g1',
        teacherId: 'teacher-1',
        name: 'BSHM 4A',
        status: ElixrGroupStatus.active,
      ),
    );
    final movements = InMemoryTeacherMovementRepository();
    addTearDown(movements.dispose);
    final assignments = InMemoryClassroomAssignmentRepository(
      generateId: () => 'asg-hand',
    );
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

    final handStall = controller.officialCatalog.firstWhere(
      (movement) => movement.name == 'Hand Stall',
    );
    await controller.assignOfficial(
      movement: handStall,
      group: groups.groups['g1']!,
    );
    expect(controller.assignments, hasLength(1));
    expect(controller.assignments.single.officialMovementName, 'Hand Stall');
    expect(controller.groupName('g1'), 'BSHM 4A');
    expect(handStall.supportedProps, contains(TrainingProp.bottle));
  });
}
