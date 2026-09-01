import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/widgets/elix_status_panel.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/features/teacher/students/teacher_student_practice_history_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository groups;
  late TrackingTeacherProgressRepository progress;
  late FakePublicProfileRepository profiles;
  late AuthService auth;

  setUp(() {
    groups = InMemoryGroupRepository();
    progress = TrackingTeacherProgressRepository();
    profiles = FakePublicProfileRepository();
    auth = phase3TeacherAuth();
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'trainee',
      ),
    );
  });

  tearDown(() {
    groups.dispose();
    auth.dispose();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherStudentPracticeHistory(
        'trainee',
        groupId: 'group-1',
      ),
      routes: [
        GoRoute(
          path: '/teacher/students/:traineeId/practice',
          builder: (context, state) => TeacherStudentPracticeHistoryScreen(
            traineeId: state.pathParameters['traineeId']!,
            groupId: state.uri.queryParameters['groupId'],
          ),
        ),
        GoRoute(
          path: '/teacher/students/:traineeId',
          builder: (_, _) => const Text('student details'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: groups),
          Provider<TeacherProgressRepository>.value(value: progress),
          Provider<PublicProfileRepository>.value(value: profiles),
        ],
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'uses a bounded paginated history list at desktop and narrow widths',
    (tester) async {
      progress.inner.sessions['trainee'] = [
        for (var index = 0; index < 21; index++)
          sampleSession(id: 'session-$index'),
      ];
      await pumpScreen(tester, size: const Size(700, 720));

      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.text('Hand Stall'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Load more'),
        400,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('Load more'), findsOneWidget);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(progress.sessionFetches, ['trainee', 'trainee']);
    },
  );

  testWidgets(
    'shows empty and authorization-blocked states without a history list',
    (tester) async {
      await pumpScreen(tester);
      expect(find.text('No practice history yet.'), findsOneWidget);

      groups = InMemoryGroupRepository();
      groups.seedGroup(activeGroup());
      await pumpScreen(tester);
      expect(find.byType(ElixStatusPanel), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    },
  );
}
