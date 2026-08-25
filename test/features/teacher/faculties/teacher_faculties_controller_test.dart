import 'dart:async';

import 'package:elixr_application/features/teacher/faculties/teacher_faculties_controller.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _ErrorDirectory implements FacultyDirectoryRepository {
  @override
  Stream<List<ChatUser>> watchTeachers() =>
      Stream.error(Exception('permission-denied'));
}

class _HangingDirectory implements FacultyDirectoryRepository {
  @override
  Stream<List<ChatUser>> watchTeachers() => const Stream.empty();
}

void main() {
  const self = ChatUser(
    id: 'teacher',
    displayName: 'Grace Hopper',
    role: User.roleTeacher,
  );
  const ada = ChatUser(
    id: 'ada',
    displayName: 'Ada Teacher',
    role: User.roleTeacher,
  );
  const zoe = ChatUser(
    id: 'zoe',
    displayName: 'Zoe Faculty',
    role: User.roleTeacher,
  );

  late InMemoryFacultyDirectoryRepository directory;
  late InMemoryTeacherAccessCodeRepository accessCodes;

  setUp(() {
    directory = InMemoryFacultyDirectoryRepository();
    accessCodes = InMemoryTeacherAccessCodeRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 25, 4),
    );
  });

  tearDown(() {
    directory.dispose();
    accessCodes.dispose();
  });

  TeacherFacultiesController controller() {
    return TeacherFacultiesController(
      directory: directory,
      accessCodes: accessCodes,
      teacherId: 'teacher',
    );
  }

  test('excludes the signed-in Teacher and sorts by display name', () async {
    directory.seed(self);
    directory.seed(zoe);
    directory.seed(ada);
    final faculties = controller();
    addTearDown(faculties.dispose);
    await faculties.start();

    expect(faculties.teachers.map((user) => user.id), ['ada', 'zoe']);
    expect(faculties.loading, isFalse);
    expect(faculties.errorMessage, isNull);
  });

  test('empty list when only the signed-in Teacher is present', () async {
    directory.seed(self);
    final faculties = controller();
    addTearDown(faculties.dispose);
    await faculties.start();
    expect(faculties.teachers, isEmpty);
  });

  test('pending codes are unused codes minted by the Teacher', () async {
    accessCodes.seed(
      const TeacherAccessCode(
        normalizedCode: '7KPMXR4DQ2WT',
        consumed: false,
        createdBy: 'teacher',
      ),
    );
    accessCodes.seed(
      const TeacherAccessCode(
        normalizedCode: 'ABCD2345EFGH',
        consumed: true,
        createdBy: 'teacher',
      ),
    );
    accessCodes.seed(
      const TeacherAccessCode(
        normalizedCode: '23456789ABCD',
        consumed: false,
        createdBy: 'other',
      ),
    );
    final faculties = controller();
    addTearDown(faculties.dispose);
    await faculties.start();
    expect(faculties.pendingCodes.map((code) => code.normalizedCode), [
      '7KPMXR4DQ2WT',
    ]);
  });

  test('inviteFaculty mints a code that appears as pending', () async {
    final faculties = controller();
    addTearDown(faculties.dispose);
    await faculties.start();
    final minted = await faculties.inviteFaculty();
    expect(minted?.normalizedCode, '7KPMXR4DQ2WT');
    expect(faculties.pendingCodes.single.normalizedCode, '7KPMXR4DQ2WT');
  });

  test('revokePendingCode removes an unused owned code', () async {
    accessCodes.seed(
      const TeacherAccessCode(
        normalizedCode: '7KPMXR4DQ2WT',
        consumed: false,
        createdBy: 'teacher',
      ),
    );
    final faculties = controller();
    addTearDown(faculties.dispose);
    await faculties.start();
    await faculties.revokePendingCode(faculties.pendingCodes.single);
    expect(faculties.pendingCodes, isEmpty);
  });

  test('directory errors surface a load message', () async {
    final faculties = TeacherFacultiesController(
      directory: _ErrorDirectory(),
      accessCodes: accessCodes,
      teacherId: 'teacher',
    );
    addTearDown(faculties.dispose);
    await faculties.start();
    expect(faculties.errorMessage, 'Could not load faculties.');
    expect(faculties.loading, isFalse);
  });

  test('start stays loading until the first directory snapshot', () {
    final faculties = TeacherFacultiesController(
      directory: _HangingDirectory(),
      accessCodes: accessCodes,
      teacherId: 'teacher',
    );
    addTearDown(faculties.dispose);
    unawaited(faculties.start());
    expect(faculties.loading, isTrue);
  });
}
