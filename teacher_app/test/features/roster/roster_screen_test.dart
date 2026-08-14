import 'package:elixr_core/models/teacher_invite.dart';
import 'package:elixr_core/models/teacher_student_link.dart';
import 'package:elixr_core/repositories/in_memory_teacher_relationship_repository.dart';
import 'package:elixr_core/repositories/teacher_relationship_repository.dart';
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

  testWidgets('approved student shows its consent-gated progress state', (tester) async {
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
      find.text('Waiting for progress access'),
      findsOneWidget,
    );
    expect(find.byType(ListTile), findsOneWidget);
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

  testWidgets('pending request shows a specific waiting error', (tester) async {
    relationships.seedInvite(
      TeacherInvite(
        normalizedCode: '7KPMXR4DQ2WT',
        traineeId: 'trainee-1',
        traineeDisplayName: 'Carol Shaw',
        createdAt: DateTime.utc(2026, 8, 13),
        expiresAt: DateTime.utc(2026, 8, 20),
      ),
    );
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
    await pumpAddSheet(tester);

    await tester.enterText(
      find.byKey(const Key('add_student_code_field')),
      '7KPM-XR4D-Q2WT',
    );
    await tester.tap(find.byKey(const Key('add_student_continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('add_student_confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('A request is already waiting for this trainee.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('add_student_confirm')), findsOneWidget);
    expect(roster.pending, hasLength(1));
  });

  testWidgets('approved trainee shows a specific roster error', (tester) async {
    relationships.seedInvite(
      TeacherInvite(
        normalizedCode: '7KPMXR4DQ2WT',
        traineeId: 'trainee-1',
        traineeDisplayName: 'Carol Shaw',
        createdAt: DateTime.utc(2026, 8, 13),
        expiresAt: DateTime.utc(2026, 8, 20),
      ),
    );
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
    await pumpAddSheet(tester);

    await tester.enterText(
      find.byKey(const Key('add_student_code_field')),
      '7KPM-XR4D-Q2WT',
    );
    await tester.tap(find.byKey(const Key('add_student_continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('add_student_confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      find.text('This trainee is already on your roster.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('add_student_confirm')), findsOneWidget);
  });

  testWidgets('unexpected send failures stay generic', (tester) async {
    final throwing = _ThrowingRelationshipRepository(
      invite: TeacherInvite(
        normalizedCode: '7KPMXR4DQ2WT',
        traineeId: 'trainee-1',
        traineeDisplayName: 'Carol Shaw',
        createdAt: DateTime.utc(2026, 8, 13),
        expiresAt: DateTime.utc(2026, 8, 20),
      ),
      requestError: Exception(
        '[cloud_firestore/permission-denied] PERMISSION_DENIED: '
        'Missing or insufficient permissions.',
      ),
    );
    roster.dispose();
    roster = RosterController(
      repository: throwing,
      teacherId: 'teacher-1',
      teacherDisplayName: 'Ada Lovelace',
    );
    await pumpAddSheet(tester);

    await tester.enterText(
      find.byKey(const Key('add_student_code_field')),
      '7KPM-XR4D-Q2WT',
    );
    await tester.tap(find.byKey(const Key('add_student_continue')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byKey(const Key('add_student_confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Could not send that request.'), findsOneWidget);
    expect(find.textContaining('PERMISSION_DENIED'), findsNothing);
    expect(find.textContaining('permission-denied'), findsNothing);
  });
}

class _ThrowingRelationshipRepository implements TeacherRelationshipRepository {
  _ThrowingRelationshipRepository({
    required this.invite,
    required this.requestError,
  });

  final TeacherInvite invite;
  final Object requestError;

  @override
  Future<TeacherInvite> resolveCoachCode(String code) async => invite;

  @override
  Future<TeacherStudentLink> requestLink({
    required String teacherId,
    required String teacherDisplayName,
    required String code,
  }) {
    throw requestError;
  }

  @override
  Future<void> approveLink({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<void> cancelLink({
    required String linkId,
    required String teacherId,
  }) => throw UnimplementedError();

  @override
  Future<TeacherInvite> createOrRotateInvite({
    required String traineeId,
    required String traineeDisplayName,
  }) => throw UnimplementedError();

  @override
  Future<TeacherInvite?> getActiveInvite({required String traineeId}) =>
      throw UnimplementedError();

  @override
  Future<void> rejectLink({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<void> revokeInvite({required String traineeId}) =>
      throw UnimplementedError();

  @override
  Future<void> revokeLink({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<void> grantProgressAccess({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Future<void> removeProgressAccess({
    required String linkId,
    required String traineeId,
  }) => throw UnimplementedError();

  @override
  Stream<TeacherStudentLinkSnapshot> watchLink({
    required String teacherId,
    required String traineeId,
  }) => const Stream.empty();

  @override
  Stream<List<TeacherStudentLink>> watchTeacherLinks({
    required String teacherId,
  }) => Stream.value(const []);

  @override
  Stream<List<TeacherStudentLink>> watchTraineeLinks({
    required String traineeId,
  }) => Stream.value(const []);
}
