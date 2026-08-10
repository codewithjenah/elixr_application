import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_border_frame.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/leaderboard_period.dart';
import 'package:elixr_application/features/leaderboard/leaderboard_presentation.dart';
import 'package:elixr_application/features/leaderboard/leaderboard_screen.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_header.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_identity.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_podium.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_podium_card.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_rank_row.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_rankings_section.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry entry({
  required String id,
  required String name,
  required int xp,
  int sessions = 8,
  double average = 86,
  int best = 95,
  int dailyXp = 0,
  int dailySessions = 0,
  double dailyAverage = 0,
  int dailyBest = 0,
  int monthlyXp = 0,
  int monthlySessions = 0,
  double monthlyAverage = 0,
  int monthlyBest = 0,
  String? profilePictureUrl,
  String? equippedBorderId,
}) {
  return LeaderboardEntry(
    userId: id,
    displayName: name,
    totalXp: xp,
    sessionsCompleted: sessions,
    scoreSum: average * sessions,
    averageScore: average,
    bestScore: best,
    dailyXp: dailyXp,
    dailySessionsCompleted: dailySessions,
    dailyScoreSum: dailyAverage * dailySessions,
    dailyAverageScore: dailyAverage,
    dailyBestScore: dailyBest,
    monthlyXp: monthlyXp,
    monthlySessionsCompleted: monthlySessions,
    monthlyScoreSum: monthlyAverage * monthlySessions,
    monthlyAverageScore: monthlyAverage,
    monthlyBestScore: monthlyBest,
    profilePictureUrl: profilePictureUrl,
    equippedBorderId: equippedBorderId,
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
  group('LeaderboardInitialsAvatar', () {
    testWidgets('uses network image when profile URL is present', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          LeaderboardInitialsAvatar(
            initials: 'AB',
            accent: const Color(0xFFB8C0CC),
            size: 40,
            profilePictureUrl: 'https://example.com/avatar.jpg',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
    });

    testWidgets('shows initials when profile URL is absent', (tester) async {
      await tester.pumpWidget(
        wrap(
          const LeaderboardInitialsAvatar(
            initials: 'AB',
            accent: Color(0xFFB8C0CC),
            size: 40,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AB'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('falls back to initials when network image fails', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          LeaderboardInitialsAvatar(
            initials: 'AB',
            accent: const Color(0xFFB8C0CC),
            size: 40,
            profilePictureUrl: 'https://example.com/missing.jpg',
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(find.text('AB'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('defaults animateBorder to false for dense-list consumers', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const LeaderboardInitialsAvatar(
            initials: 'AB',
            accent: Color(0xFFB8C0CC),
            size: 40,
            equippedBorderId: 'starter_glow',
          ),
        ),
      );
      await tester.pump();

      final avatar = tester.widget<LeaderboardInitialsAvatar>(
        find.byType(LeaderboardInitialsAvatar),
      );
      expect(avatar.animateBorder, isFalse);
      final frameState = tester.state<ProfileBorderFrameState>(
        find.byType(ProfileBorderFrame),
      );
      expect(frameState.debugIsAnimating, isFalse);
    });
  });

  group('LeaderboardHeader', () {
    testWidgets(
      'shows dynamic subtitle and switches period from one selector',
      (tester) async {
        await setSurface(tester, const Size(1200, 300));
        LeaderboardPeriod? selected;
        await tester.pumpWidget(
          wrap(
            LeaderboardHeader(
              period: LeaderboardPeriod.allTime,
              onPeriodChanged: (value) => selected = value,
              onRefresh: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('All-time rankings by total XP.'), findsOneWidget);
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('This month'), findsOneWidget);
        expect(find.text('All time'), findsOneWidget);
        expect(find.text('All Time'), findsNothing);

        await tester.tap(find.text('Today'));
        expect(selected, LeaderboardPeriod.today);
      },
    );

    testWidgets('period buttons support keyboard activation', (tester) async {
      await setSurface(tester, const Size(1200, 300));
      LeaderboardPeriod? selected;
      await tester.pumpWidget(
        wrap(
          LeaderboardHeader(
            period: LeaderboardPeriod.allTime,
            onPeriodChanged: (value) => selected = value,
            onRefresh: () {},
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(selected, LeaderboardPeriod.today);
    });

    testWidgets('reflows selector below title at narrow widths', (
      tester,
    ) async {
      await setSurface(tester, const Size(390, 260));
      await tester.pumpWidget(
        wrap(
          LeaderboardHeader(
            period: LeaderboardPeriod.thisMonth,
            onPeriodChanged: (_) {},
            onRefresh: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Rankings based on XP earned this month.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('LeaderboardPodium', () {
    testWidgets('current user fallback uses in-memory profile URL', (
      tester,
    ) async {
      await setSurface(tester, const Size(1000, 600));
      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: [entry(id: 'me', name: 'Current', xp: 300)],
            currentUserId: 'me',
            currentUserProfilePictureUrl: 'https://example.com/me.jpg',
            variant: LeaderboardPodiumVariant.full,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
    });

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

      expect(find.text('All-time top 3'), findsOneWidget);
      expect(find.text('Gold Player'), findsOneWidget);
      expect(find.text('Silver Player'), findsOneWidget);
      expect(find.text('Bronze Player'), findsOneWidget);

      final gold = tester.getCenter(find.text('Gold Player'));
      final silver = tester.getCenter(find.text('Silver Player'));
      final bronze = tester.getCenter(find.text('Bronze Player'));
      expect(silver.dx, lessThan(gold.dx));
      expect(gold.dx, lessThan(bronze.dx));

      final cardSizes = List.generate(
        3,
        (index) => tester.getSize(find.byType(LeaderboardPodiumCard).at(index)),
      );
      expect(cardSizes.map((size) => size.height).toSet(), hasLength(1));
      expect(cardSizes.map((size) => size.width).toSet(), hasLength(1));
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
      expect(
        tester.getSize(find.byType(LeaderboardPodiumCard)).width,
        lessThan(500),
      );
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
      expect(find.text('★ Top 1'), findsOneWidget);
    });

    testWidgets('podium cards use Top labels for ranks 1 through 3', (
      tester,
    ) async {
      await setSurface(tester, const Size(1200, 800));
      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: [
              entry(id: '1', name: 'Gold Player', xp: 300),
              entry(id: '2', name: 'Silver Player', xp: 275),
              entry(id: '3', name: 'Bronze Player', xp: 250),
            ],
            currentUserId: null,
            variant: LeaderboardPodiumVariant.full,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('★ Top 1'), findsOneWidget);
      expect(find.text('Top 2'), findsOneWidget);
      expect(find.text('Top 3'), findsOneWidget);
      expect(find.text('#1'), findsNothing);
      expect(find.text('#2'), findsNothing);
      expect(find.text('#3'), findsNothing);
    });

    testWidgets('compact variant omits the Top 3 title', (tester) async {
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
      expect(find.text('All-time top 3'), findsNothing);
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

    testWidgets(
      'legendary frames and YOU badge fit full and compact card heights',
      (tester) async {
        addTearDown(() async {
          await tester.binding.setSurfaceSize(null);
        });
        final podium = [
          entry(
            id: '1',
            name: 'Legendary Champion',
            xp: 300,
            equippedBorderId: 'tin_specialist',
          ),
          entry(
            id: '2',
            name: 'Legendary Second',
            xp: 275,
            equippedBorderId: 'tin_specialist',
          ),
          entry(
            id: '3',
            name: 'Legendary Third',
            xp: 250,
            equippedBorderId: 'tin_specialist',
          ),
        ];

        for (final scenario in const [
          (
            size: Size(1480, 700),
            variant: LeaderboardPodiumVariant.full,
            expectedHeight: LeaderboardPodiumLayout.fullCardHeight,
          ),
          (
            size: Size(760, 700),
            variant: LeaderboardPodiumVariant.compact,
            expectedHeight: LeaderboardPodiumLayout.compactCardHeight,
          ),
          (
            size: Size(390, 1000),
            variant: LeaderboardPodiumVariant.full,
            expectedHeight: LeaderboardPodiumLayout.fullCardHeight,
          ),
        ]) {
          await tester.binding.setSurfaceSize(scenario.size);
          await tester.pumpWidget(
            wrap(
              SingleChildScrollView(
                child: LeaderboardPodium(
                  podium: podium,
                  currentUserId: '1',
                  variant: scenario.variant,
                ),
              ),
            ),
          );
          await tester.pump();

          final cardSizes = tester.getSize(
            find.byType(LeaderboardPodiumCard).first,
          );
          expect(cardSizes.height, scenario.expectedHeight);
          expect(find.text('YOU'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason:
                'Unexpected overflow for ${scenario.variant.name} at '
                '${scenario.size.width}px',
          );
        }
      },
    );

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

    testWidgets('long name keeps fixed geometry and exposes full tooltip', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await setSurface(tester, const Size(1200, 800));
      const longName =
          'A Player Name Long Enough To Require A Desktop Tooltip Without '
          'Changing The Card';
      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: [
              entry(id: '1', name: longName, xp: 300),
              entry(id: '2', name: 'Short', xp: 275),
              entry(id: '3', name: 'Also short', xp: 250),
            ],
            currentUserId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final sizes = List.generate(
        3,
        (index) => tester.getSize(find.byType(LeaderboardPodiumCard).at(index)),
      );
      expect(sizes.map((size) => size.height).toSet(), hasLength(1));
      final nameTooltip = find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == longName,
      );
      expect(nameTooltip, findsOneWidget);
      expect(
        find.descendant(
          of: nameTooltip,
          matching: find.byType(FocusableActionDetector),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(longName))),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('selected period XP is shown instead of lifetime XP', (
      tester,
    ) async {
      await setSurface(tester, const Size(900, 500));
      await tester.pumpWidget(
        wrap(
          LeaderboardPodium(
            podium: [
              entry(
                id: '1',
                name: 'Period player',
                xp: 900,
                dailyXp: 25,
                dailySessions: 1,
                dailyAverage: 80,
                dailyBest: 80,
              ),
            ],
            currentUserId: null,
            period: LeaderboardPeriod.today,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("Today's top 3"), findsOneWidget);
      expect(find.text('XP today'), findsOneWidget);
      expect(find.text('25 XP'), findsOneWidget);
      expect(find.text('900 XP'), findsNothing);
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
      expect(find.text('Level'), findsNothing);
      expect(find.textContaining('Lv. '), findsOneWidget);
      expect(find.text('Sessions'), findsOneWidget);
      expect(find.text('Avg score'), findsOneWidget);
      expect(find.text('Best score'), findsOneWidget);
      expect(find.text('Total XP'), findsOneWidget);
      expect(find.text('Fourth'), findsOneWidget);
      expect(find.text('#4'), findsOneWidget);
    });

    testWidgets(
      'profile URL flows through podium and rank rows without overflow',
      (tester) async {
        await setSurface(tester, const Size(1200, 800));
        final rowEntry = entry(
          id: '4',
          name: 'Fourth',
          xp: 180,
          profilePictureUrl: 'https://example.com/avatar.jpg',
        );
        await tester.pumpWidget(
          wrap(
            Column(
              children: [
                LeaderboardPodium(
                  podium: [
                    entry(
                      id: '1',
                      name: 'Gold',
                      xp: 300,
                      profilePictureUrl: 'https://example.com/gold.jpg',
                    ),
                  ],
                  currentUserId: null,
                  variant: LeaderboardPodiumVariant.full,
                ),
                LeaderboardRankRow(
                  rank: 4,
                  entry: rowEntry,
                  isCurrentUser: false,
                ),
              ],
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(Image), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

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
      expect(find.text('Best score'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('medium width hides Best score column', (tester) async {
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
      expect(find.text('Best score'), findsNothing);
    });

    testWidgets('animates equipped borders in podium and rank rows', (
      tester,
    ) async {
      await setSurface(tester, const Size(1200, 800));
      final bordered = entry(
        id: '4',
        name: 'Fourth',
        xp: 180,
        equippedBorderId: 'starter_glow',
      );

      await tester.pumpWidget(
        wrap(
          Column(
            children: [
              LeaderboardPodiumCard(
                rank: 1,
                entry: entry(
                  id: '1',
                  name: 'Gold',
                  xp: 300,
                  equippedBorderId: 'starter_glow',
                ),
                isCurrentUser: false,
              ),
              LeaderboardRankRow(
                rank: 4,
                entry: bordered,
                isCurrentUser: false,
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      final avatars = tester
          .widgetList<LeaderboardInitialsAvatar>(
            find.byType(LeaderboardInitialsAvatar),
          )
          .toList();
      expect(avatars, hasLength(2));
      expect(avatars[0].animateBorder, isTrue);
      expect(avatars[1].animateBorder, isTrue);

      final frames = tester
          .stateList<ProfileBorderFrameState>(find.byType(ProfileBorderFrame))
          .toList();
      expect(frames, hasLength(2));
      expect(frames[0].debugIsAnimating, isTrue);
      expect(frames[1].debugIsAnimating, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('compact rank row animates an equipped cosmetic border', (
      tester,
    ) async {
      await setSurface(tester, const Size(400, 300));
      await tester.pumpWidget(
        wrap(
          LeaderboardRankRow(
            rank: 4,
            entry: entry(
              id: '4',
              name: 'Fourth',
              xp: 180,
              equippedBorderId: 'starter_glow',
            ),
            isCurrentUser: false,
          ),
        ),
      );
      await tester.pump();

      final avatar = tester.widget<LeaderboardInitialsAvatar>(
        find.byType(LeaderboardInitialsAvatar),
      );
      expect(avatar.animateBorder, isTrue);
      final frameState = tester.state<ProfileBorderFrameState>(
        find.byType(ProfileBorderFrame),
      );
      expect(frameState.debugIsAnimating, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rank row without equipped border still renders safely', (
      tester,
    ) async {
      await setSurface(tester, const Size(1200, 800));
      await tester.pumpWidget(
        wrap(
          LeaderboardRankRow(
            rank: 4,
            entry: entry(id: '4', name: 'Fourth', xp: 180),
            isCurrentUser: false,
          ),
        ),
      );
      await tester.pump();

      final avatar = tester.widget<LeaderboardInitialsAvatar>(
        find.byType(LeaderboardInitialsAvatar),
      );
      expect(avatar.animateBorder, isTrue);
      expect(avatar.equippedBorderId, isNull);

      final frameState = tester.state<ProfileBorderFrameState>(
        find.byType(ProfileBorderFrame),
      );
      expect(frameState.debugIsAnimating, isFalse);
      expect(find.text('FO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('table uses selected period metrics and dynamic XP heading', (
      tester,
    ) async {
      await setSurface(tester, const Size(1200, 600));
      final rowEntry = entry(
        id: '4',
        name: 'Monthly player',
        xp: 950,
        sessions: 38,
        average: 88,
        best: 99,
        monthlyXp: 125,
        monthlySessions: 5,
        monthlyAverage: 82,
        monthlyBest: 91,
      );
      await tester.pumpWidget(
        wrap(
          LeaderboardRankingsSection(
            rows: [(rank: 4, entry: rowEntry)],
            currentUserId: null,
            period: LeaderboardPeriod.thisMonth,
            footer: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('XP this month'), findsOneWidget);
      expect(find.text('125 XP'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('82'), findsOneWidget);
      expect(find.text('91'), findsOneWidget);
      expect(find.text('950 XP'), findsNothing);
      expect(find.text('38'), findsNothing);
    });

    testWidgets('long row name exposes full tooltip without overflow', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await setSurface(tester, const Size(720, 400));
      const longName =
          'Extremely Long Leaderboard Player Name Kept Available To Hover';
      await tester.pumpWidget(
        wrap(
          LeaderboardRankRow(
            rank: 4,
            entry: entry(id: '4', name: longName, xp: 180),
            isCurrentUser: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final nameTooltip = find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == longName,
      );
      expect(nameTooltip, findsOneWidget);
      expect(
        find.descendant(
          of: nameTooltip,
          matching: find.byType(FocusableActionDetector),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(longName))),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('interactive row supports keyboard activation', (tester) async {
      await setSurface(tester, const Size(900, 400));
      var activations = 0;
      await tester.pumpWidget(
        wrap(
          LeaderboardRankRow(
            rank: 4,
            entry: entry(id: '4', name: 'Keyboard player', xp: 180),
            isCurrentUser: false,
            onTap: () => activations++,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(activations, 1);
    });
  });

  group('responsive leaderboard composition', () {
    testWidgets('target desktop and narrow widths render without overflow', (
      tester,
    ) async {
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });
      final podium = [
        entry(
          id: '1',
          name: 'A very long champion name that should remain one line',
          xp: 300,
        ),
        entry(id: '2', name: 'Second player', xp: 275),
        entry(id: '3', name: 'Third player', xp: 250),
      ];
      final rowEntry = entry(
        id: '4',
        name: 'A long fourth-place player name for responsive testing',
        xp: 200,
      );

      for (final size in const [
        Size(1024, 768),
        Size(1366, 768),
        Size(1920, 1080),
        Size(390, 844),
      ]) {
        await tester.binding.setSurfaceSize(size);
        final horizontal = LeaderboardScreenLayout.horizontalPaddingFor(
          size.width,
        );
        await tester.pumpWidget(
          wrap(
            SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: LeaderboardScreenLayout.maxContentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LeaderboardHeader(
                          period: LeaderboardPeriod.allTime,
                          onPeriodChanged: (_) {},
                          onRefresh: () {},
                        ),
                        const SizedBox(height: 24),
                        LeaderboardPodium(podium: podium, currentUserId: null),
                        const SizedBox(height: 24),
                        LeaderboardRankingsSection(
                          rows: [(rank: 4, entry: rowEntry)],
                          currentUserId: null,
                          footer: const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          tester.takeException(),
          isNull,
          reason: 'Unexpected layout exception at ${size.width}×${size.height}',
        );
      }
    });

    test('content width and padding stay bounded for Windows targets', () {
      expect(
        LeaderboardScreenLayout.maxContentWidth,
        inInclusiveRange(1440, 1520),
      );
      expect(LeaderboardScreenLayout.horizontalPaddingFor(1024), 20);
      expect(LeaderboardScreenLayout.horizontalPaddingFor(1366), 28);
      expect(LeaderboardScreenLayout.horizontalPaddingFor(1920), 36);
      expect(LeaderboardScreenLayout.horizontalPaddingFor(390), 16);
    });
  });

  group('presentation partition still holds for UI inputs', () {
    test(
      'profilePictureUrlFor prefers entry URL then current user fallback',
      () {
        final row = entry(id: 'me', name: 'Me', xp: 100);
        expect(
          LeaderboardPresentation.profilePictureUrlFor(
            entry: row,
            isCurrentUser: true,
            currentUserProfilePictureUrl: 'https://example.com/me.jpg',
          ),
          'https://example.com/me.jpg',
        );

        final mirrored = entry(
          id: 'me',
          name: 'Me',
          xp: 100,
          profilePictureUrl: 'https://example.com/mirrored.jpg',
        );
        expect(
          LeaderboardPresentation.profilePictureUrlFor(
            entry: mirrored,
            isCurrentUser: true,
            currentUserProfilePictureUrl: 'https://example.com/me.jpg',
          ),
          'https://example.com/mirrored.jpg',
        );
      },
    );

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
