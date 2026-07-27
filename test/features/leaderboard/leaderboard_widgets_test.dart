import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/features/leaderboard/leaderboard_presentation.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_podium.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_podium_card.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_rank_row.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_rankings_section.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry entry({
  required String id,
  required String name,
  required int xp,
  int sessions = 8,
  double average = 86,
  int best = 95,
}) {
  return LeaderboardEntry(
    userId: id,
    displayName: name,
    totalXp: xp,
    sessionsCompleted: sessions,
    scoreSum: average * sessions,
    averageScore: average,
    bestScore: best,
  );
}

Widget wrap(Widget child) {
  return FluentApp(
    theme: AppTheme.dark,
    home: ScaffoldPage(content: child),
  );
}

Future<void> setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

void main() {
  group('LeaderboardPodium', () {
    testWidgets('wide layout orders cards 2nd, 1st, 3rd', (tester) async {
      await setSurface(tester, const Size(1200, 800));
      final podium = [
        entry(id: '1', name: 'Gold Player', xp: 300),
        entry(id: '2', name: 'Silver Player', xp: 275),
        entry(id: '3', name: 'Bronze Player', xp: 250),
      ];

      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: podium,
            currentUserId: null,
            variant: LeaderboardPodiumVariant.full,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Top Performers'), findsOneWidget);
      expect(find.text('Gold Player'), findsOneWidget);
      expect(find.text('Silver Player'), findsOneWidget);
      expect(find.text('Bronze Player'), findsOneWidget);

      final gold = tester.getCenter(find.text('Gold Player'));
      final silver = tester.getCenter(find.text('Silver Player'));
      final bronze = tester.getCenter(find.text('Bronze Player'));
      expect(silver.dx, lessThan(gold.dx));
      expect(gold.dx, lessThan(bronze.dx));
    });

    testWidgets('supports one and two player podiums', (tester) async {
      await setSurface(tester, const Size(1000, 600));

      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: [entry(id: '1', name: 'Only One', xp: 100)],
            currentUserId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Only One'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: [
              entry(id: '1', name: 'First', xp: 200),
              entry(id: '2', name: 'Second', xp: 150),
            ],
            currentUserId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('current user shows YOU without replacing medal rank', (
      tester,
    ) async {
      await setSurface(tester, const Size(1000, 600));
      final podium = [
        entry(id: 'me', name: 'Current', xp: 300),
        entry(id: '2', name: 'Silver', xp: 275),
        entry(id: '3', name: 'Bronze', xp: 250),
      ];

      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: podium,
            currentUserId: 'me',
            variant: LeaderboardPodiumVariant.full,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOU'), findsOneWidget);
      expect(find.textContaining('#1'), findsWidgets);
    });

    testWidgets('compact variant omits Top Performers title', (tester) async {
      await setSurface(tester, const Size(800, 400));
      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: [entry(id: '1', name: 'Ada', xp: 100)],
            currentUserId: null,
            variant: LeaderboardPodiumVariant.compact,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Top Performers'), findsNothing);
      expect(find.text('Ada'), findsOneWidget);
    });

    testWidgets('YOU badge does not change podium card height', (tester) async {
      await setSurface(tester, const Size(1000, 600));
      final podium = [
        entry(id: '1', name: 'Same Name', xp: 300),
        entry(id: '2', name: 'Other Name', xp: 275),
        entry(id: '3', name: 'Third Name', xp: 250),
      ];

      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: podium,
            currentUserId: null,
            variant: LeaderboardPodiumVariant.full,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final withoutYou = tester.getSize(
        find.byType(LeaderboardPodiumCard).at(1),
      );

      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: podium,
            currentUserId: '1',
            variant: LeaderboardPodiumVariant.full,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final withYou = tester.getSize(find.byType(LeaderboardPodiumCard).at(1));

      expect(withYou.height, withoutYou.height);
      expect(find.text('YOU'), findsOneWidget);
    });

    testWidgets('narrow width stacks without overflow', (tester) async {
      await setSurface(tester, const Size(390, 844));
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: LeaderboardPodium(
              podium: [
                entry(
                  id: '1',
                  name: 'Very Long Player Name That Should Ellipsize',
                  xp: 999999,
                ),
                entry(id: '2', name: 'Another Long Name Here', xp: 888888),
                entry(id: '3', name: 'Third Long Name Player', xp: 777777),
              ],
              currentUserId: '2',
              variant: LeaderboardPodiumVariant.full,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('LeaderboardRankRow', () {
    testWidgets('wide layout shows labeled metric columns', (tester) async {
      await setSurface(tester, const Size(1200, 800));
      final rowEntry = entry(id: '4', name: 'Fourth', xp: 180);
      await tester.pumpWidget(
        wrap(
          LeaderboardRankingsSection(
            rows: [(rank: 4, entry: rowEntry)],
            currentUserId: null,
            footer: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rankings'), findsOneWidget);
      expect(find.text('Rank'), findsOneWidget);
      expect(find.text('Player'), findsOneWidget);
      expect(find.text('Level'), findsOneWidget);
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('Avg Score'), findsOneWidget);
      expect(find.text('Best Score'), findsOneWidget);
      expect(find.text('Total XP'), findsOneWidget);
      expect(find.text('Fourth'), findsOneWidget);
    });

    testWidgets('narrow layout uses labeled secondary metrics line', (
      tester,
    ) async {
      await setSurface(tester, const Size(400, 300));
      final rowEntry = entry(
        id: '4',
        name: 'Fourth',
        xp: 180,
        sessions: 8,
        average: 86,
      );
      await tester.pumpWidget(
        wrap(LeaderboardRankRow(rank: 4, entry: rowEntry, isCurrentUser: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('YOU'), findsOneWidget);
      expect(find.textContaining('Lv. '), findsOneWidget);
      expect(find.textContaining('sessions'), findsOneWidget);
      expect(find.textContaining('avg'), findsOneWidget);
      expect(find.text('Best Score'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('medium width hides Best Score column', (tester) async {
      await setSurface(tester, const Size(800, 600));
      final rowEntry = entry(id: '4', name: 'Fourth', xp: 180);
      await tester.pumpWidget(
        wrap(
          LeaderboardRankingsSection(
            rows: [(rank: 4, entry: rowEntry)],
            currentUserId: null,
            footer: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('Best Score'), findsNothing);
    });
  });

  group('presentation partition still holds for UI inputs', () {
    test('display order helper remains 2-1-3', () {
      final podium = LeaderboardPresentation.podiumOf([
        entry(id: '1', name: 'A', xp: 3),
        entry(id: '2', name: 'B', xp: 2),
        entry(id: '3', name: 'C', xp: 1),
      ]);
      final display = LeaderboardPresentation.podiumDisplayOrder(podium);
      expect(display.map((s) => s.rank), [2, 1, 3]);
    });
  });
}
