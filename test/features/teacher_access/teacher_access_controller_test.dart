import 'package:elixr_application/features/teacher_access/teacher_access_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTeacherRelationshipRepository repository;
  late TeacherAccessController controller;

  setUp(() async {
    repository = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 16),
    );
    await repository.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Grace Hopper',
    );
    controller = TeacherAccessController(
      repository: repository,
      traineeId: 'trainee-1',
      traineeDisplayName: 'Ada Lovelace',
    );
  });

  tearDown(() {
    controller.dispose();
    repository.dispose();
  });

  test('resolve and explicit confirmation create a V2 join request', () async {
    await controller.start();
    controller.setCodeInput('7kpm-xr4d-q2wt');
    await controller.resolveCode();
    expect(controller.resolvedInvite?.teacherDisplayName, 'Grace Hopper');
    expect(controller.pending, isEmpty);

    expect(await controller.confirmJoin(), isTrue);
    expect(controller.pending.single.requestVersion, 2);
    expect(controller.pending.single.teacherDisplayName, 'Grace Hopper');
  });

  test('Trainee can cancel a pending request', () async {
    await controller.start();
    controller.setCodeInput('7KPMXR4DQ2WT');
    await controller.resolveCode();
    await controller.confirmJoin();
    await controller.cancelPending(controller.pending.single);
    expect(controller.pending, isEmpty);
  });
}
