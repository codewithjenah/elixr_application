import 'package:elixr_application/features/teacher/students/teacher_student_models.dart';
import 'package:elixr_application/features/teacher/students/teacher_students_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

import '../teacher_phase3_test_support.dart';

void main() {
  late InMemoryGroupRepository repository;
  late TeacherStudentsController controller;

  setUp(() {
    repository = InMemoryGroupRepository(now: () => DateTime.utc(2026, 8, 19));
    controller = TeacherStudentsController(
      repository: repository,
      teacherId: 'teacher',
    );
  });

  tearDown(() {
    controller.dispose();
    repository.dispose();
  });

  Future<void> boot() async {
    await controller.start();
    await pumpEventQueue();
  }

  test('approved membership appears', () async {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
    );
    await boot();
    expect(controller.visibleEntries.single.traineeId, 't1');
  });

  test('same trainee in multiple groups aggregates correctly', () async {
    repository.seedGroup(activeGroup(id: 'group-1', name: 'A'));
    repository.seedGroup(activeGroup(id: 'group-2', name: 'B'));
    repository.seedMembership(
      membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
    );
    repository.seedMembership(
      membership(groupId: 'group-2', teacherId: 'teacher', traineeId: 't1'),
    );
    await boot();
    expect(controller.allEntries.single.memberships, hasLength(2));
  });

  test('group filter works', () async {
    repository.seedGroup(activeGroup(id: 'group-1'));
    repository.seedGroup(activeGroup(id: 'group-2'));
    repository.seedMembership(
      membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
    );
    repository.seedMembership(
      membership(groupId: 'group-2', teacherId: 'teacher', traineeId: 't2'),
    );
    await boot();
    controller.setGroupFilter('group-1');
    expect(controller.visibleEntries.single.traineeId, 't1');
  });

  test('status filter works', () async {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(groupId: 'group-1', teacherId: 'teacher', traineeId: 't1'),
    );
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't2',
        status: GroupMembershipStatus.pending,
      ),
    );
    await boot();
    controller.setStatusFilter(TeacherStudentStatusFilter.pending);
    expect(controller.visibleEntries.single.traineeId, 't2');
  });

  test('search is case-insensitive and trimmed', () async {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't1',
        traineeName: 'Ada Lovelace',
      ),
    );
    await boot();
    controller.setSearchQuery('  ada ');
    expect(controller.visibleEntries, hasLength(1));
  });

  test('pending-only student state works', () async {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't1',
        status: GroupMembershipStatus.pending,
      ),
    );
    await boot();
    controller.setStatusFilter(TeacherStudentStatusFilter.all);
    expect(
      controller.visibleEntries.single.effectiveStatus,
      GroupMembershipStatus.pending,
    );
  });

  test('removed states do not become approved accidentally', () async {
    repository.seedGroup(activeGroup());
    repository.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't1',
        status: GroupMembershipStatus.removed,
      ),
    );
    await boot();
    controller.setStatusFilter(TeacherStudentStatusFilter.all);
    expect(
      controller.visibleEntries.single.effectiveStatus,
      GroupMembershipStatus.removed,
    );
    controller.setStatusFilter(TeacherStudentStatusFilter.approved);
    expect(controller.visibleEntries, isEmpty);
  });

  test('unrelated teacher membership excluded', () async {
    repository.seedMembership(
      membership(groupId: 'group-1', teacherId: 'other', traineeId: 't1'),
    );
    await boot();
    expect(controller.allEntries, isEmpty);
  });

  test('empty state', () async {
    await boot();
    expect(controller.visibleEntries, isEmpty);
  });
}
