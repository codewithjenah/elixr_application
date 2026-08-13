import 'package:elixr_application/features/teacher_access/teacher_access_controller.dart';
import 'package:elixr_core/models/teacher_invite.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/in_memory_teacher_relationship_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTeacherRelationshipRepository repository;
  late TeacherAccessController controller;

  setUp(() {
    repository = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 13, 8),
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

  test('start loads invite and splits pending vs approved', () async {
    repository.seedInvite(
      TeacherInvite(
        normalizedCode: '7KPMXR4DQ2WT',
        traineeId: 'trainee-1',
        traineeDisplayName: 'Ada Lovelace',
        createdAt: DateTime.utc(2026, 8, 13),
        expiresAt: DateTime.utc(2026, 8, 20),
      ),
    );
    repository.seedLink(
      TeacherStudentLink(
        id: 't1_trainee-1',
        teacherId: 't1',
        traineeId: 'trainee-1',
        teacherDisplayName: 'Grace Hopper',
        traineeDisplayName: 'Ada Lovelace',
        status: TeacherStudentLinkStatus.pending,
      ),
    );
    repository.seedLink(
      TeacherStudentLink(
        id: 't2_trainee-1',
        teacherId: 't2',
        traineeId: 'trainee-1',
        teacherDisplayName: 'Alan Turing',
        traineeDisplayName: 'Ada Lovelace',
        status: TeacherStudentLinkStatus.approved,
      ),
    );

    await controller.start();

    expect(controller.invite?.displayCode, '7KPM-XR4D-Q2WT');
    expect(controller.pending, hasLength(1));
    expect(controller.approved, hasLength(1));
    expect(controller.loading, isFalse);
  });

  test('approve moves a pending teacher into linked', () async {
    repository.seedLink(
      TeacherStudentLink(
        id: 't1_trainee-1',
        teacherId: 't1',
        traineeId: 'trainee-1',
        teacherDisplayName: 'Grace Hopper',
        traineeDisplayName: 'Ada Lovelace',
        status: TeacherStudentLinkStatus.pending,
      ),
    );
    await controller.start();
    await controller.approve(controller.pending.single);

    expect(controller.pending, isEmpty);
    expect(controller.approved.single.teacherDisplayName, 'Grace Hopper');
  });
}
