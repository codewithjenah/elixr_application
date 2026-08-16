import 'package:elixr_core/elixr_core.dart';
import 'package:elixr_teacher/core/theme/teacher_theme.dart';
import 'package:elixr_teacher/features/auth/teacher_auth_controller.dart';
import 'package:elixr_teacher/features/roster/add_student_sheet.dart';
import 'package:elixr_teacher/features/roster/roster_controller.dart';
import 'package:elixr_teacher/features/roster/roster_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../helpers/fake_auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InMemoryTeacherRelationshipRepository relationships;
  late RosterController roster;
  late TeacherAuthController auth;

  setUp(() async {
    final authRepository = FakeAuthRepository()
      ..persistedUser = fakeTeacher()
      ..emailVerified = true;
    auth = TeacherAuthController(repository: authRepository);
    await auth.initialize();
    relationships = InMemoryTeacherRelationshipRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 16),
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

  testWidgets('Teacher generates durable code, URI, and QR', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTeacherTheme(),
        home: Scaffold(body: AddStudentSheet(controller: roster)),
      ),
    );
    await tester.tap(find.byKey(const Key('roster_generate_invite')));
    await tester.pumpAndSettle();
    expect(find.text('7KPM-XR4D-Q2WT'), findsOneWidget);
    expect(find.text('elixr://join?code=7KPMXR4DQ2WT'), findsOneWidget);
    expect(find.byKey(const Key('roster_invite_qr')), findsOneWidget);
  });

  testWidgets('incoming V2 request can be approved', (tester) async {
    await relationships.createOrRotateRosterInvite(
      teacherId: 'teacher-1',
      teacherDisplayName: 'Ada Lovelace',
    );
    await relationships.requestTeacherJoin(
      traineeId: 'trainee-1',
      traineeDisplayName: 'Carol Shaw',
      code: '7KPMXR4DQ2WT',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<TeacherAuthController>.value(
        value: auth,
        child: MaterialApp(
          theme: buildTeacherTheme(),
          home: RosterScreen(controller: roster),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Incoming join request'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('roster_approve_teacher-1_trainee-1')),
    );
    await tester.pumpAndSettle();
    expect(roster.approved.single.traineeDisplayName, 'Carol Shaw');
  });
}
