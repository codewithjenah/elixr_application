import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/features/teacher/faculties/teacher_faculties_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

class _HangingDirectory implements FacultyDirectoryRepository {
  @override
  Stream<List<ChatUser>> watchTeachers() => const Stream.empty();
}

class _ErrorDirectory implements FacultyDirectoryRepository {
  @override
  Stream<List<ChatUser>> watchTeachers() =>
      Stream.error(Exception('permission-denied'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryFacultyDirectoryRepository directory;
  late InMemoryTeacherAccessCodeRepository accessCodes;
  late AuthService auth;

  setUp(() {
    directory = InMemoryFacultyDirectoryRepository();
    accessCodes = InMemoryTeacherAccessCodeRepository(
      generateNormalizedCode: () => '7KPMXR4DQ2WT',
      now: () => DateTime.utc(2026, 8, 25, 4),
    );
    auth = phase3TeacherAuth();
  });

  tearDown(() {
    directory.dispose();
    accessCodes.dispose();
    auth.dispose();
  });

  Future<void> pumpFaculties(
    WidgetTester tester, {
    FacultyDirectoryRepository? directoryOverride,
  }) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherFaculties,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherFaculties,
          builder: (context, state) => const TeacherFacultiesScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<FacultyDirectoryRepository>.value(
            value: directoryOverride ?? directory,
          ),
          Provider<TeacherAccessCodeRepository>.value(value: accessCodes),
        ],
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows loading while the directory has not emitted', (
    tester,
  ) async {
    await pumpFaculties(tester, directoryOverride: _HangingDirectory());
    expect(find.byType(ProgressRing), findsOneWidget);
  });

  testWidgets('shows empty copy when no other Teachers exist', (tester) async {
    directory.seed(
      const ChatUser(
        id: 'teacher',
        displayName: 'Grace Hopper',
        role: User.roleTeacher,
      ),
    );
    await pumpFaculties(tester);
    expect(find.byKey(const Key('teacher_faculties_empty')), findsOneWidget);
    expect(find.text('No other faculty members yet.'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsNothing);
  });

  testWidgets('lists other Teachers and hides the signed-in user', (
    tester,
  ) async {
    directory.seed(
      const ChatUser(
        id: 'teacher',
        displayName: 'Grace Hopper',
        role: User.roleTeacher,
      ),
    );
    directory.seed(
      const ChatUser(
        id: 'zoe',
        displayName: 'Zoe Faculty',
        role: User.roleTeacher,
      ),
    );
    directory.seed(
      const ChatUser(
        id: 'ada',
        displayName: 'Ada Teacher',
        role: User.roleTeacher,
      ),
    );
    await pumpFaculties(tester);

    expect(find.byKey(const Key('teacher_faculty_tile_ada')), findsOneWidget);
    expect(find.byKey(const Key('teacher_faculty_tile_zoe')), findsOneWidget);
    expect(find.text('Ada Teacher'), findsOneWidget);
    expect(find.text('Zoe Faculty'), findsOneWidget);
    expect(find.text('Teacher'), findsWidgets);
    expect(find.byKey(const Key('teacher_faculty_tile_teacher')), findsNothing);
  });

  testWidgets('shows a pending unused code with Copy and Revoke', (
    tester,
  ) async {
    accessCodes.seed(
      const TeacherAccessCode(
        normalizedCode: '7KPMXR4DQ2WT',
        consumed: false,
        createdBy: 'teacher',
      ),
    );
    await pumpFaculties(tester);
    expect(find.text('Pending access codes'), findsOneWidget);
    expect(find.text('7KPM-XR4D-Q2WT'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Revoke'), findsOneWidget);

    await tester.tap(find.text('Revoke'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Pending access codes'), findsNothing);
  });

  testWidgets('invite mints a code and shows it in a dialog', (tester) async {
    await pumpFaculties(tester);
    await tester.tap(find.text('Invite a faculty member'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Faculty access code'), findsOneWidget);
    expect(find.text('7KPM-XR4D-Q2WT'), findsWidgets);
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Pending access codes'), findsOneWidget);
  });

  testWidgets('shows an error when the directory stream fails', (tester) async {
    await pumpFaculties(tester, directoryOverride: _ErrorDirectory());
    expect(find.byKey(const Key('teacher_faculties_error')), findsOneWidget);
    expect(find.text('Could not load faculties.'), findsOneWidget);
  });
}
