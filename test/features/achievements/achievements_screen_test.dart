import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/achievement.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/user_cosmetics.dart';
import 'package:elixr_application/data/models/profile_border.dart';
import 'package:elixr_application/features/achievements/widgets/achievement_card.dart';
import 'package:elixr_application/features/achievements/widgets/profile_border_picker.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_identity.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
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

Widget wrap(Widget child, {Brightness brightness = Brightness.dark}) {
  return FluentApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    home: ScaffoldPage(content: child),
  );
}

Future<void> setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Future<void> expectNoOverflow(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

AchievementViewData _claimableView() {
  return buildAllAchievementViewData(
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
  ).firstWhere((v) => v.state == AchievementState.claimable);
}

AchievementViewData _claimedView() {
  return buildAchievementViewData(
    definition: achievementById('first_steps')!,
    sessions: const [],
    leaderboardEntry: null,
    claimedAchievementIds: {'first_steps'},
  );
}

AchievementViewData _lockedView() {
  return buildAchievementViewData(
    definition: achievementById('century_club')!,
    sessions: const [],
    leaderboardEntry: null,
    claimedAchievementIds: const {},
  );
}

Matrix4 _cardTransform(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byType(AchievementCard),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return container.transform ?? Matrix4.identity();
}

Icon _previewIcon(WidgetTester tester, IconData iconData) {
  return tester.widget<Icon>(find.byIcon(iconData));
}

AchievementViewData _achievementViewForBorder(String achievementId) {
  return buildAchievementViewData(
    definition: achievementById(achievementId)!,
    sessions: achievementId == 'first_steps'
        ? [
            const Session(
              userId: 'u1',
              movementName: 'Hand Stall',
              difficulty: 'Easy',
              score: 70,
              durationSeconds: 60,
            ),
          ]
        : const [],
    leaderboardEntry: _entry(),
    claimedAchievementIds: achievementId == 'first_steps'
        ? const {'first_steps'}
        : const {},
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
      wrap(
        SizedBox(
          width: 420,
          height: 200,
          child: ListView(
            children: [
              for (final view in views.take(3))
                SizedBox(
                  height: 168,
                  child: AchievementCard(
                    view: view,
                    claiming: false,
                    onClaim: () {},
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    await expectNoOverflow(tester);
    expect(find.text('Claim'), findsOneWidget);
    expect(find.text('First Steps'), findsOneWidget);
    expect(find.text('Getting Started'), findsOneWidget);
  });

  testWidgets('AchievementCard renders without overflow at compact size', (
    tester,
  ) async {
    final view = _claimableView();

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 420,
          height: 168,
          child: AchievementCard(view: view, claiming: false, onClaim: () {}),
        ),
      ),
    );

    await expectNoOverflow(tester);
  });

  testWidgets('hovering a claimable AchievementCard changes visual state', (
    tester,
  ) async {
    final view = _claimableView();

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 420,
          height: 168,
          child: AchievementCard(view: view, claiming: false, onClaim: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = _cardTransform(tester).getTranslation();
    final center = tester.getCenter(find.byType(MouseRegion).first);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    await tester.pump(const Duration(milliseconds: 200));

    final after = _cardTransform(tester).getTranslation();
    expect(after.y, lessThan(before.y));
  });

  testWidgets('tapping a claimable card invokes onClaim exactly once', (
    tester,
  ) async {
    final view = _claimableView();
    var claimCount = 0;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 420,
          height: 168,
          child: AchievementCard(
            view: view,
            claiming: false,
            onClaim: () => claimCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AchievementCard));
    await tester.pumpAndSettle();

    expect(claimCount, 1);
  });

  testWidgets('tapping Claim button invokes onClaim exactly once', (
    tester,
  ) async {
    final view = _claimableView();
    var claimCount = 0;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 420,
          height: 168,
          child: AchievementCard(
            view: view,
            claiming: false,
            onClaim: () => claimCount++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Claim'));
    await tester.pumpAndSettle();

    expect(claimCount, 1);
  });

  testWidgets('locked and claimed cards do not invoke onClaim', (tester) async {
    var claimCount = 0;

    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            SizedBox(
              height: 168,
              width: 420,
              child: AchievementCard(
                view: _lockedView(),
                claiming: false,
                onClaim: () => claimCount++,
              ),
            ),
            SizedBox(
              height: 168,
              width: 420,
              child: AchievementCard(
                view: _claimedView(),
                claiming: false,
                onClaim: () => claimCount++,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(AchievementCard).first);
    await tester.tap(find.byType(AchievementCard).last);
    await tester.pumpAndSettle();

    expect(claimCount, 0);
    expect(find.text('Claim'), findsNothing);
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

    await setSurface(tester, const Size(1200, 900));

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 1100,
          height: 400,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 380,
              mainAxisExtent: 168,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 4,
            itemBuilder: (context, index) {
              return AchievementCard(
                view: views[index],
                claiming: false,
                onClaim: () {},
              );
            },
          ),
        ),
      ),
    );

    await expectNoOverflow(tester);
    expect(find.byType(AchievementCard), findsNWidgets(4));
    expect(find.text('Claim'), findsWidgets);
  });

  testWidgets('claimed state hides claim button', (tester) async {
    final claimed = _claimedView();

    await tester.pumpWidget(
      wrap(
        SizedBox(
          height: 168,
          width: 420,
          child: AchievementCard(
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
    await setSurface(tester, const Size(1000, 800));

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 900,
          height: 600,
          child: ProfileBorderPicker(
            unlockedBorderIds: const {'starter_glow'},
            equippedBorderId: null,
            busyBorderId: null,
            onEquip: (_) {},
            onUnequip: () {},
          ),
        ),
      ),
    );

    await expectNoOverflow(tester);
    expect(find.text('Equip'), findsOneWidget);
    expect(find.text('Locked'), findsWidgets);
  });

  testWidgets('unlocked border card can be equipped by clicking the card', (
    tester,
  ) async {
    String? equippedId;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 360,
          height: 220,
          child: ProfileBorderPicker(
            unlockedBorderIds: const {'starter_glow'},
            equippedBorderId: null,
            busyBorderId: null,
            onEquip: (id) => equippedId = id,
            onUnequip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final starterCard = find.ancestor(
      of: find.text('Starter Glow'),
      matching: find.byType(FocusableActionDetector),
    );
    expect(starterCard, findsOneWidget);

    await tester.tap(starterCard);
    await tester.pumpAndSettle();

    expect(equippedId, 'starter_glow');
  });

  testWidgets('clicking Equip button invokes onEquip exactly once', (
    tester,
  ) async {
    var equipCount = 0;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 360,
          height: 220,
          child: ProfileBorderPicker(
            unlockedBorderIds: const {'starter_glow'},
            equippedBorderId: null,
            busyBorderId: null,
            onEquip: (_) => equipCount++,
            onUnequip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Equip'));
    await tester.pumpAndSettle();

    expect(equipCount, 1);
  });

  testWidgets('locked border cards never invoke onEquip', (tester) async {
    var equipCount = 0;

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 900,
          height: 600,
          child: ProfileBorderPicker(
            unlockedBorderIds: const {'starter_glow'},
            equippedBorderId: null,
            busyBorderId: null,
            onEquip: (_) => equipCount++,
            onUnequip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lockedCards = find.text('Locked');
    expect(lockedCards, findsWidgets);

    for (var i = 0; i < tester.widgetList(lockedCards).length; i++) {
      await tester.tap(lockedCards.at(i));
    }
    await tester.pumpAndSettle();

    expect(equipCount, 0);
  });

  testWidgets('equipped borders display the Equipped state', (tester) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 360,
          height: 220,
          child: ProfileBorderPicker(
            unlockedBorderIds: const {'starter_glow'},
            equippedBorderId: 'starter_glow',
            busyBorderId: null,
            onEquip: (_) {},
            onUnequip: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Equipped'), findsOneWidget);
    expect(find.text('Equip'), findsNothing);
  });

  testWidgets('ProfileBorderPicker renders without overflow at narrow size', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 340,
          height: 800,
          child: ProfileBorderPicker(
            unlockedBorderIds: const {'starter_glow'},
            equippedBorderId: null,
            busyBorderId: null,
            onEquip: (_) {},
            onUnequip: () {},
          ),
        ),
      ),
    );

    await expectNoOverflow(tester);
  });

  testWidgets('ProfileBorderPicker renders without overflow at wide size', (
    tester,
  ) async {
    await setSurface(tester, const Size(1200, 900));

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 1100,
          height: 500,
          child: ProfileBorderPicker(
            unlockedBorderIds: const {'starter_glow', 'cyan_orbit'},
            equippedBorderId: 'starter_glow',
            busyBorderId: null,
            onEquip: (_) {},
            onUnequip: () {},
          ),
        ),
      ),
    );

    await expectNoOverflow(tester);
    expect(find.byType(FocusableActionDetector), findsWidgets);
  });

  testWidgets('ProfileAvatarWidget with and without cosmetic border', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const Row(
          children: [
            ProfileAvatarWidget(initials: 'AL', radius: 20),
            ProfileAvatarWidget(
              initials: 'AL',
              radius: 20,
              equippedBorderId: 'starter_glow',
            ),
          ],
        ),
      ),
    );

    expect(find.byType(ProfileAvatarWidget), findsNWidgets(2));
  });

  testWidgets('leaderboard avatar keeps highlight while showing border', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const LeaderboardInitialsAvatar(
          initials: 'AL',
          accent: Color(0xFFFFC107),
          size: 40,
          equippedBorderId: 'gold_mastery',
          highlightRing: true,
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

  testWidgets(
    'dark theme unlocked achievement trophy avoids border accent foreground',
    (tester) async {
      final view = _achievementViewForBorder('first_steps');
      final borderAccent = Color(
        profileBorderById('starter_glow')!.primaryColorValue,
      );

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 420,
            height: 168,
            child: AchievementCard(view: view, claiming: false, onClaim: () {}),
          ),
        ),
      );

      final trophy = _previewIcon(tester, FluentIcons.trophy2);
      expect(trophy.color, AppColors.textPrimary);
      expect(trophy.color, isNot(equals(borderAccent)));
      expect(trophy.size, 20);
    },
  );

  testWidgets('light theme achievement trophy uses primary text foreground', (
    tester,
  ) async {
    final view = _achievementViewForBorder('first_steps');
    final borderAccent = Color(
      profileBorderById('starter_glow')!.primaryColorValue,
    );

    await tester.pumpWidget(
      wrap(
        brightness: Brightness.light,
        SizedBox(
          width: 420,
          height: 168,
          child: AchievementCard(view: view, claiming: false, onClaim: () {}),
        ),
      ),
    );

    final trophy = _previewIcon(tester, FluentIcons.trophy2);
    expect(trophy.color, AppColors.textPrimaryLight);
    expect(trophy.color, isNot(equals(borderAccent)));
  });

  testWidgets(
    'dark theme unlocked border contact icon avoids border accent foreground',
    (tester) async {
      final borderAccent = Color(
        profileBorderById('cyan_orbit')!.primaryColorValue,
      );

      await tester.pumpWidget(
        wrap(
          SizedBox(
            width: 360,
            height: 220,
            child: ProfileBorderPicker(
              unlockedBorderIds: const {'cyan_orbit'},
              equippedBorderId: null,
              busyBorderId: null,
              onEquip: (_) {},
              onUnequip: () {},
            ),
          ),
        ),
      );

      final contacts = tester.widgetList<Icon>(
        find.byIcon(FluentIcons.contact),
      );
      expect(contacts, isNotEmpty);
      final contact = contacts.first;
      expect(contact.color, AppColors.textPrimary);
      expect(contact.color, isNot(equals(borderAccent)));
      expect(contact.size, 22);
    },
  );

  testWidgets('light theme border contact icon uses primary text foreground', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        brightness: Brightness.light,
        SizedBox(
          width: 360,
          height: 220,
          child: ProfileBorderPicker(
            unlockedBorderIds: const {'starter_glow'},
            equippedBorderId: null,
            busyBorderId: null,
            onEquip: (_) {},
            onUnequip: () {},
          ),
        ),
      ),
    );

    final contact = _previewIcon(tester, FluentIcons.contact);
    expect(contact.color, AppColors.textPrimaryLight);
  });

  testWidgets('locked preview icons use muted secondary foreground', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            SizedBox(
              width: 420,
              height: 168,
              child: AchievementCard(
                view: _lockedView(),
                claiming: false,
                onClaim: () {},
              ),
            ),
            SizedBox(
              width: 360,
              height: 220,
              child: ProfileBorderPicker(
                unlockedBorderIds: const {'starter_glow'},
                equippedBorderId: null,
                busyBorderId: null,
                onEquip: (_) {},
                onUnequip: () {},
              ),
            ),
          ],
        ),
      ),
    );

    final lockedTrophy = _previewIcon(tester, FluentIcons.trophy2);
    expect(lockedTrophy.color, AppColors.textSecondary);

    final locks = tester.widgetList<Icon>(find.byIcon(FluentIcons.lock));
    expect(locks, isNotEmpty);
    for (final lock in locks) {
      expect(lock.color, AppColors.textSecondary);
    }
  });
}
