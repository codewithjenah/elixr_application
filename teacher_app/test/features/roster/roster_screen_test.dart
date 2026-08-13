import 'package:elixr_core/models/teacher_invite.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/in_memory_teacher_relationship_repository.dart';
import 'package:elixr_teacher/core/theme/teacher_theme.dart';
import 'package:elixr_teacher/features/auth/teacher_auth_controller.dart';
import 'package:elixr_teacher/features/roster/add_student_sheet.dart';
import 'package:elixr_teacher/features/roster/roster_controller.dart';
import 'package:elixr_teacher/features/roster/roster_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_auth_repository.dart';

Future<void> setPhoneSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAuthRepository authRepository;
  late TeacherAuthController auth;
  late InMemoryTeacherRelationshipRepository relationships;
  late RosterController roster;

  setUp(() async {
    authRepository = FakeAuthRepository()
      ..persistedUser = fakeTeacher()
      ..emailVerified = true;
    auth = TeacherAuthController(repository: authRepository);
    await auth.initialize();
    relationships = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 13, 8),
    );
    roster = RosterController(
      repository: relationships,
      teacherId: 'teacher-1',
      teacherDisplayName: 'Ada Lovelace',
    );
  });

  tearDown(() {
    roster.dispose();
    relationships.dispose();
    auth.dispose();
  });

  Future<void> pumpRoster(WidgetTester tester) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<TeacherAuthController>.value(value: auth),
        ],
        child: MaterialApp(
          theme: buildTeacherTheme(),
          home: RosterScreen(controller: roster),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> pumpAddSheet(WidgetTester tester) async {
    await roster.start();
    await setPhoneSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTeacherTheme(),
        home: Scaffold(body: AddStudentSheet(controller: roster)),
      ),
    );
    await tester.pump();
  }

  testWidgets('empty roster shows add-student empty state', (tester) async {
    await pumpRoster(tester);
    expect(find.byKey(const Key('roster_empty')), findsOneWidget);
    expect(find.byKey(const Key('roster_add_student')), findsOneWidget);
    expect(find.text('No students linked yet'), findsOneWidget);
  });

  testWidgets('pending request can be cancelled', (tester) async {
    relationships.seedLink(
      TeacherStudentLink(
        id: 'teacher-1_trainee-1',
        teacherId: 'teacher-1',
        traineeId: 'trainee-1',
        teacherDisplayName: 'Ada Lovelace',
        traineeDisplayName: 'Carol Shaw',
        status: TeacherStudentLinkStatus.pending,
      ),
    );
    await pumpRoster(tester);

    expect(find.text('Carol Shaw'), findsOneWidget);
    expect(find.text('Waiting for Trainee approval'), findsOneWidget);

    await tester.tap(
      find.byKey(const Key('roster_cancel_teacher-1_trainee-1')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('roster_empty')), findsOneWidget);
  });

  testWidgets('approved student is not interactive', (tester) async {
    relationships.seedLink(
      TeacherStudentLink(
        id: 'teacher-1_trainee-1',
        teacherId: 'teacher-1',
        traineeId: 'trainee-1',
        teacherDisplayName: 'Ada Lovelace',
        traineeDisplayName: 'Carol Shaw',
        status: TeacherStudentLinkStatus.approved,
      ),
    );
    await pumpRoster(tester);

    expect(find.text('Carol Shaw'), findsOneWidget);
    expect(
      find.text('Linked. Progress review will be available in the next phase.'),
      findsOneWidget,
    );
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('add student opens the coach-code sheet', (tester) async {
    await pumpRoster(tester);
    await tester.tap(find.byKey(const Key('roster_add_student')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('add_student_code_field')), findsOneWidget);
  });

  testWidgets('add student rejects malformed and expired codes', (
    tester,
  ) async {
    await pumpAddSheet(tester);

    await tester.enterText(
      find.byKey(const Key('add_student_code_field')),
      '123',
    );
    await tester.tap(find.byKey(const Key('add_student_continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('add_student_error')), findsOneWidget);
    expect(find.text('That coach code is not valid.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('add_student_code_field')),
      '7KPM-XR4D-Q2WT',
    );
    relationships.seedInvite(
      TeacherInvite(
        normalizedCode: '7KPMXR4DQ2WT',
        traineeId: 'trainee-1',
        traineeDisplayName: 'Carol Shaw',
        createdAt: DateTime.utc(2026, 8, 1),
        expiresAt: DateTime.utc(2026, 8, 8),
      ),
    );
    await tester.tap(find.byKey(const Key('add_student_continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('That coach code has expired.'), findsOneWidget);
  });

  testWidgets('valid code confirmation sends a pending request', (
    tester,
  ) async {
    relationships.seedInvite(
      TeacherInvite(
        normalizedCode: '7KPMXR4DQ2WT',
        traineeId: 'trainee-1',
        traineeDisplayName: 'Carol Shaw',
        createdAt: DateTime.utc(2026, 8, 13),
        expiresAt: DateTime.utc(2026, 8, 20),
      ),
    );
    await pumpAddSheet(tester);

    await tester.enterText(
      find.byKey(const Key('add_student_code_field')),
      '7kpm-xr4d-q2wt',
    );
    await tester.tap(find.byKey(const Key('add_student_continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const Key('add_student_confirm_name')), findsOneWidget);
    expect(find.text('Carol Shaw'), findsWidgets);

    await tester.tap(find.byKey(const Key('add_student_confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(roster.pending, hasLength(1));
    expect(roster.pending.single.traineeDisplayName, 'Carol Shaw');
  });
}
