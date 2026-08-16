import 'package:elixr_core/elixr_core.dart';
import 'package:elixr_teacher/features/ranking/roster_ranking_controller.dart';
import 'package:elixr_teacher/features/ranking/roster_ranking_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('loads sorted roster rows and empty state', () async {
    final repository = InMemoryRosterLeaderboardRepository(
      rosterRows: {
        'teacher': const [
          RosterLeaderboardEntry(
            userId: 'b',
            displayName: 'B',
            totalXp: 0,
            sessionsCompleted: 0,
            bestScore: 0,
            rosterRank: 0,
          ),
          RosterLeaderboardEntry(
            userId: 'a',
            displayName: 'A',
            totalXp: 100,
            sessionsCompleted: 4,
            bestScore: 12,
            rosterRank: 0,
          ),
        ],
      },
    );
    final controller = RosterRankingController(
      repository: repository,
      teacherId: 'teacher',
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.state, RosterRankingState.ready);
    expect(controller.entries.first.userId, 'a');
    expect(controller.entries.last.totalXp, 0);

    final empty = RosterRankingController(
      repository: InMemoryRosterLeaderboardRepository(),
      teacherId: 'teacher',
    );
    addTearDown(empty.dispose);
    await empty.load();
    expect(empty.state, RosterRankingState.empty);
  });

  testWidgets('ranking row opens the shared student route', (tester) async {
    final controller = RosterRankingController(
      repository: InMemoryRosterLeaderboardRepository(
        rosterRows: {
          'teacher': const [
            RosterLeaderboardEntry(
              userId: 'trainee',
              displayName: 'Ada Lovelace',
              totalXp: 75,
              sessionsCompleted: 3,
              bestScore: 10,
              rosterRank: 0,
            ),
          ],
        },
      ),
      teacherId: 'teacher',
    );
    addTearDown(controller.dispose);
    final router = GoRouter(
      initialLocation: '/ranking',
      routes: [
        GoRoute(
          path: '/ranking',
          builder: (_, _) => RosterRankingScreen(controller: controller),
        ),
        GoRoute(
          path: '/students/:id',
          builder: (_, state) => Text('Student ${state.pathParameters['id']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('#1  Ada Lovelace'), findsOneWidget);
    expect(find.text('75 lifetime XP · 3 sessions'), findsOneWidget);

    await tester.tap(find.byKey(const Key('roster_rank_trainee')));
    await tester.pumpAndSettle();
    expect(find.text('Student trainee'), findsOneWidget);
  });
}
