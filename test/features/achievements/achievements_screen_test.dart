import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/achievement.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/user_cosmetics.dart';
import 'package:elixr_application/features/achievements/widgets/achievement_card.dart';
import 'package:elixr_application/features/achievements/widgets/profile_border_picker.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_identity.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

LeaderboardEntry _entry({String? border}) {
  return LeaderboardEntry(
    userId: 'u1',
    displayName: 'Ada',
    totalXp: 25,
    sessionsCompleted: 1,
    scoreSum: 80,
    averageScore: 80,
    bestScore: 80,
    equippedBorderId: border,
  );
}

void main() {
  testWidgets('narrow achievements cards show claimable button', (
    tester,
  ) async {
    final views = buildAllAchievementViewData(
      sessions: [
        const Session(
          userId: 'u1',
          movementName: 'Hand Stall',
          difficulty: 'Easy',
          score: 70,
          durationSeconds: 60,
        ),
      ],
      leaderboardEntry: _entry(),
      claimedAchievementIds: const {},
    );

    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SizedBox(
            width: 420,
            child: ListView(
              children: [
                for (final view in views.take(3))
                  AchievementCard(view: view, claiming: false, onClaim: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Claim'), findsOneWidget);
    expect(find.text('First Steps'), findsOneWidget);
    expect(find.text('Getting Started'), findsOneWidget);
  });

  testWidgets('wide layout can host multiple claim cards', (tester) async {
    final views = buildAllAchievementViewData(
      sessions: List.generate(
        10,
        (_) => const Session(
          userId: 'u1',
          movementName: 'Hand Stall',
          difficulty: 'Easy',
          score: 70,
          durationSeconds: 60,
        ),
      ),
      leaderboardEntry: _entry(),
      claimedAchievementIds: const {},
    );

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SizedBox(
            width: 1100,
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              children: [
                for (final view in views.take(4))
                  AchievementCard(view: view, claiming: false, onClaim: () {}),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AchievementCard), findsNWidgets(4));
    expect(find.text('Claim'), findsWidgets);
  });

  testWidgets('claimed state hides claim button', (tester) async {
    final claimed = buildAchievementViewData(
      definition: achievementById('first_steps')!,
      sessions: const [],
      leaderboardEntry: null,
      claimedAchievementIds: {'first_steps'},
    );

    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: AchievementCard(
            view: claimed,
            claiming: false,
            onClaim: () {},
          ),
        ),
      ),
    );

    expect(find.text('Claimed'), findsWidgets);
    expect(find.text('Claim'), findsNothing);
  });

  testWidgets('locked border cannot equip; unlocked can', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: SizedBox(
            width: 900,
            child: SingleChildScrollView(
              child: ProfileBorderPicker(
                unlockedBorderIds: const {'starter_glow'},
                equippedBorderId: null,
                busyBorderId: null,
                onEquip: (_) {},
                onUnequip: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Equip'), findsOneWidget);
    expect(find.text('Locked'), findsWidgets);
  });

  testWidgets('ProfileAvatarWidget with and without cosmetic border', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: Row(
            children: const [
              ProfileAvatarWidget(initials: 'AL', radius: 20),
              ProfileAvatarWidget(
                initials: 'AL',
                radius: 20,
                equippedBorderId: 'starter_glow',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(ProfileAvatarWidget), findsNWidgets(2));
  });

  testWidgets('leaderboard avatar keeps highlight while showing border', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        home: ScaffoldPage(
          content: LeaderboardInitialsAvatar(
            initials: 'AL',
            accent: const Color(0xFFFFC107),
            size: 40,
            equippedBorderId: 'gold_mastery',
            highlightRing: true,
          ),
        ),
      ),
    );

    expect(find.byType(LeaderboardInitialsAvatar), findsOneWidget);
    expect(find.text('AL'), findsOneWidget);
  });

  test('user cosmetics parse unlocked borders', () {
    final cosmetics = UserCosmetics.tryFromMap({
      'user_id': 'u1',
      'unlocked_border_ids': ['starter_glow', 'cyan_orbit'],
      'last_achievement_claim_id': 'u1_sharp_pour',
    });
    expect(cosmetics, isNotNull);
    expect(cosmetics!.isUnlocked('starter_glow'), isTrue);
    expect(cosmetics.isUnlocked('gold_mastery'), isFalse);
  });
}
