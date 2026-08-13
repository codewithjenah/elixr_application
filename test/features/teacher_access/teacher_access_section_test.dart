import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/features/teacher_access/teacher_access_controller.dart';
import 'package:elixr_application/features/teacher_access/teacher_access_section.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/in_memory_teacher_relationship_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

TeacherStudentLink pendingLink() {
  return TeacherStudentLink(
    id: 'teacher-1_trainee-1',
    teacherId: 'teacher-1',
    traineeId: 'trainee-1',
    teacherDisplayName: 'Grace Hopper',
    traineeDisplayName: 'Ada Lovelace',
    status: TeacherStudentLinkStatus.pending,
    createdAt: DateTime.utc(2026, 8, 13, 4),
  );
}

TeacherStudentLink approvedLink() {
  return TeacherStudentLink(
    id: 'teacher-1_trainee-1',
    teacherId: 'teacher-1',
    traineeId: 'trainee-1',
    teacherDisplayName: 'Grace Hopper',
    traineeDisplayName: 'Ada Lovelace',
    status: TeacherStudentLinkStatus.approved,
    createdAt: DateTime.utc(2026, 8, 12, 4),
  );
}

Future<void> pumpAccess(
  WidgetTester tester, {
  required TeacherAccessController controller,
}) async {
  await tester.pumpWidget(
    FluentApp(
      theme: AppTheme.dark,
      home: ScaffoldPage(
        content: SingleChildScrollView(
          child: TeacherAccessSection(controller: controller, isActive: true),
        ),
      ),
    ),
  );
  // The section starts the controller; pump to flush FakeAsync futures.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('empty state shows generate action and empty lists', (
    tester,
  ) async {
    await pumpAccess(tester, controller: controller);

    expect(find.text('Generate coach code'), findsOneWidget);
    expect(
      find.byKey(const Key('teacher_access_pending_empty')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('teacher_access_linked_empty')),
      findsOneWidget,
    );
  });

  testWidgets('pending request can be approved or rejected', (tester) async {
    repository.seedLink(pendingLink());
    await pumpAccess(tester, controller: controller);

    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('teacher_access_approve_teacher-1_trainee-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('Approved'), findsOneWidget);
    expect(find.text('Revoke'), findsOneWidget);
  });

  testWidgets('reject removes the pending request', (tester) async {
    repository.seedLink(pendingLink());
    await pumpAccess(tester, controller: controller);

    await tester.tap(
      find.byKey(const Key('teacher_access_reject_teacher-1_trainee-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const Key('teacher_access_pending_empty')),
      findsOneWidget,
    );
    expect(find.text('Approve'), findsNothing);
  });

  testWidgets('linked teacher can be revoked', (tester) async {
    repository.seedLink(approvedLink());
    await pumpAccess(tester, controller: controller);

    expect(find.text('Grace Hopper'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('teacher_access_revoke_teacher-1_trainee-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(
      find.byKey(const Key('teacher_access_linked_empty')),
      findsOneWidget,
    );
  });

  testWidgets('generate shows formatted coach code', (tester) async {
    await pumpAccess(tester, controller: controller);
    await tester.tap(find.byKey(const Key('teacher_access_generate')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('7KPM-XR4D-Q2WT'), findsOneWidget);
    expect(find.textContaining('Expires'), findsOneWidget);
  });
}
