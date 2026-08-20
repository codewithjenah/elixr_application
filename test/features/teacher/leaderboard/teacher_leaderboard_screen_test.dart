import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/features/teacher/leaderboard/teacher_leaderboard_controller.dart';
import 'package:elixr_application/features/teacher/leaderboard/teacher_leaderboard_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../teacher_phase3_test_support.dart';

LeaderboardEntry _entry(String id, {required String name, int xp = 25}) {
  return LeaderboardEntry(
    userId: id,
    displayName: name,
    totalXp: xp,
    sessionsCompleted: xp ~/ 25,
    scoreSum: 0,
    averageScore: 0,
    bestScore: 0,
  );
}

void expectNoUnboundedFlex(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryGroupRepository groups;
  late AuthService auth;
  late TeacherLeaderboardController controller;

  setUp(() {
    groups = InMemoryGroupRepository(now: () => DateTime.utc(2026, 8, 20));
    auth = phase3TeacherAuth();
    controller = TeacherLeaderboardController(
      groupRepository: groups,
      teacherId: 'teacher',
      fetchEntriesByUserIds: (ids) async => {
        for (final id in ids)
          if (id == 't1') id: _entry('t1', name: 'Ada Lovelace', xp: 50),
      },
      fetchGlobalPage: ({required period, startAfter}) async {
        return LeaderboardPage(
          entries: [
            _entry('stranger', name: 'Global Stranger', xp: 75),
            _entry('t1', name: 'Ada Lovelace', xp: 50),
            _entry('t2', name: 'Alan Turing', xp: 25),
            _entry('t3', name: 'Grace Hopper', xp: 0),
          ],
          nextCursor: null,
          hasMore: false,
        );
      },
    );
  });

  tearDown(() {
    groups.dispose();
    auth.dispose();
  });

  Future<void> pumpBoard(WidgetTester tester) async {
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);

    final router = GoRouter(
      initialLocation: AppRoutePaths.teacherLeaderboard,
      routes: [
        GoRoute(
          path: AppRoutePaths.teacherLeaderboard,
          builder: (context, state) =>
              TeacherLeaderboardScreen(controller: controller),
          routes: const [],
        ),
        GoRoute(
          path: '/teacher/students/:traineeId',
          builder: (context, state) => Text(
            'detail:${state.pathParameters['traineeId']}:${state.uri.queryParameters['groupId'] ?? ''}',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: auth),
          Provider<GroupRepository>.value(value: groups),
        ],
        child: FluentApp.router(routerConfig: router),
      ),
    );
    await controller.start();
    await tester.pump();
    await tester.pump();
  }

  testWidgets(
    'global stranger is visible but cannot open Teacher student detail',
    (tester) async {
      groups.seedGroup(activeGroup());
      groups.seedMembership(
        membership(
          groupId: 'group-1',
          teacherId: 'teacher',
          traineeId: 't1',
          traineeName: 'Ada Lovelace',
        ),
      );
      await pumpBoard(tester);

      expectNoUnboundedFlex(tester);
      expect(find.text('Global'), findsWidgets);
      expect(find.text('Global Stranger'), findsWidgets);
      expect(find.text('Ada Lovelace'), findsWidgets);

      await tester.tap(find.text('Global Stranger').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('detail:'), findsNothing);
      expect(find.text('Leaderboard'), findsWidgets);
    },
  );

  testWidgets('authorized classroom member opens Teacher student detail', (
    tester,
  ) async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 't1',
        traineeName: 'Ada Lovelace',
      ),
    );
    await pumpBoard(tester);

    await tester.tap(find.text('Ada Lovelace').first);
    await tester.pumpAndSettle();

    expect(find.text('detail:t1:group-1'), findsOneWidget);
  });

  testWidgets('group picker shows classroom names and empty state', (
    tester,
  ) async {
    await pumpBoard(tester);
    await tester.tap(find.text('Group'));
    await tester.pumpAndSettle();

    expect(
      find.text('No active classrooms yet. Create a group first.'),
      findsOneWidget,
    );
    expect(find.text('group-1'), findsNothing);

    groups.seedGroup(activeGroup(name: 'BSHM 4A'));
    await tester.pump();
    await tester.pump();

    expect(find.text('BSHM 4A'), findsWidgets);
    expect(find.text('group-1'), findsNothing);
  });

  testWidgets('My Students keeps a 0 XP approved member visible', (
    tester,
  ) async {
    groups.seedGroup(activeGroup());
    groups.seedMembership(
      membership(
        groupId: 'group-1',
        teacherId: 'teacher',
        traineeId: 'zero',
        traineeName: 'Zero XP',
      ),
    );
    await pumpBoard(tester);
    await tester.tap(find.text('My Students'));
    await tester.pumpAndSettle();

    expect(find.text('Zero XP'), findsWidgets);
  });
}
