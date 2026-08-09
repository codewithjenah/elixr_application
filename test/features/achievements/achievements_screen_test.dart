import 'dart:async';

import 'package:elixr_application/core/constants/app_colors.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/achievement.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/models/user.dart';
import 'package:elixr_application/data/models/user_cosmetics.dart';
import 'package:elixr_application/data/models/profile_border.dart';
import 'package:elixr_application/data/repositories/achievement_repository.dart';
import 'package:elixr_application/data/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/data/repositories/session_repository.dart';
import 'package:elixr_application/features/achievements/achievements_screen.dart';
import 'package:elixr_application/features/achievements/widgets/achievement_card.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_identity.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:firebase_core/firebase_core.dart';
// Test-only Firebase bootstrap; not part of app dependencies.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _testUserId = 'u1';

const _sampleSession = Session(
  userId: _testUserId,
  movementName: 'Hand Stall',
  difficulty: 'Easy',
  score: 70,
  durationSeconds: 60,
);

class _StubAuthRepository implements AuthRepositoryBase {
  _StubAuthRepository(this._user);

  final User _user;

  @override
  Future<void> clearCurrentUser() async {}

  @override
  Future<PendingEmailChangeRecoveryResult> checkAndRecoverPendingEmailChange({
    required String originalUid,
    required String pendingEmail,
    required String recoveryPassword,
    String? originalEmail,
  }) async => PendingEmailChangeRecoveryResult.pending();

  @override
  Future<bool> isCurrentEmailVerified() async => true;

  @override
  Future<User> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<User?> loadPersistedUser() async => _user;

  @override
  Future<User> register({
    required String firstName,
    String? middleName,
    required String lastName,
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> requestCurrentEmailVerification() async {}

  @override
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<User?> refreshAuthenticatedUser() async => _user;

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<User> updateProfileDetails({
    required String userId,
    required String firstName,
    String? middleName,
    required String lastName,
    ProfilePictureUpdate? profilePictureUpdate,
  }) async => _user;

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async => _user;
}

class _NoopPublicProfileRepository extends PublicProfileRepository {}

class _FakeAchievementRepository extends AchievementRepository {
  _FakeAchievementRepository(this._claimedIdsStream);

  final Stream<Set<String>> _claimedIdsStream;

  @override
  Stream<Set<String>> watchClaimedAchievementIds(String userId) =>
      _claimedIdsStream;
}

class _FakeLeaderboardRepository extends LeaderboardRepository {
  _FakeLeaderboardRepository(this._entry);

  final LeaderboardEntry? _entry;

  @override
  Stream<LeaderboardEntry?> watchPlayer(String userId) => Stream.value(_entry);
}

class _FakeSessionRepository extends SessionRepository {
  _FakeSessionRepository(this._sessions);

  final List<Session> _sessions;

  @override
  Future<List<Session>> getSessionsForUser(String userId) async => _sessions;
}

User _testUser() {
  return const User(
    id: _testUserId,
    firstName: 'Test',
    lastName: 'User',
    email: 'user@example.com',
  );
}

Map<String, int> _expectedFilterCounts({
  required List<Session> sessions,
  required Set<String> claimedIds,
}) {
  final views = buildAllAchievementViewData(
    sessions: sessions,
    leaderboardEntry: _entry(),
    claimedAchievementIds: claimedIds,
  );
  return {
    'all': views.length,
    'claimable': views
        .where((v) => v.state == AchievementState.claimable)
        .length,
    'inProgress': views
        .where((v) => v.state == AchievementState.inProgress)
        .length,
    'claimed': views.where((v) => v.state == AchievementState.claimed).length,
    'locked': views.where((v) => v.state == AchievementState.locked).length,
  };
}

Future<void> settleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openAchievementFilterMenu(WidgetTester tester) async {
  await tester.tap(
    find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString().startsWith('ComboBox<'),
    ),
  );
  await settleUi(tester);
}

Future<void> _selectAchievementFilter(WidgetTester tester, String label) async {
  await _openAchievementFilterMenu(tester);
  final options = find.text(label).hitTestable();
  await tester.tap(options.last);
  await settleUi(tester);
}

Future<void> _pumpAchievementsScreen(
  WidgetTester tester, {
  required Widget screen,
  Size surfaceSize = const Size(1200, 900),
}) async {
  await setSurface(tester, surfaceSize);
  await tester.pumpWidget(screen);
  await settleUi(tester);
}

Widget _wrapAchievementsScreen({
  required AuthService authService,
  required List<Session> sessions,
  Set<String> claimedIds = const {},
  Stream<Set<String>>? claimedIdsStream,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: authService),
      Provider<PublicProfileRepository>.value(
        value: _NoopPublicProfileRepository(),
      ),
    ],
    child: FluentApp(
      theme: AppTheme.dark,
      home: AchievementsScreen(
        achievementRepository: _FakeAchievementRepository(
          claimedIdsStream ?? Stream.value(claimedIds),
        ),
        leaderboardRepository: _FakeLeaderboardRepository(_entry()),
        sessionRepository: _FakeSessionRepository(sessions),
      ),
    ),
  );
}

LeaderboardEntry _entry({String? border}) {
  return LeaderboardEntry(
    userId: _testUserId,
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

Future<void> _ensureFirebaseInitialized() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  await Firebase.initializeApp();
}

Future<void> expectNoOverflow(WidgetTester tester) async {
  await settleUi(tester);
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AchievementsScreen filter dropdown', () {
    late AuthService authService;

    setUpAll(() async {
      await _ensureFirebaseInitialized();
    });

    setUp(() {
      authService = AuthService(
        repository: _StubAuthRepository(_testUser()),
        leaderboardRepository: null,
      );
      authService.seedAuthenticatedUser(_testUser());
    });

    tearDown(() {
      authService.dispose();
    });

    testWidgets('collapsed dropdown shows the selected filter and count', (
      tester,
    ) async {
      final counts = _expectedFilterCounts(
        sessions: const [_sampleSession],
        claimedIds: const {},
      );

      await _pumpAchievementsScreen(
        tester,
        screen: _wrapAchievementsScreen(
          authService: authService,
          sessions: const [_sampleSession],
        ),
      );

      expect(find.text('All achievements'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString().startsWith('ComboBox<'),
          ),
          matching: find.text('${counts['all']}'),
        ),
        findsOneWidget,
      );
      await expectNoOverflow(tester);
    });

    testWidgets('opening the dropdown shows all five filter options', (
      tester,
    ) async {
      final counts = _expectedFilterCounts(
        sessions: const [_sampleSession],
        claimedIds: const {},
      );

      await _pumpAchievementsScreen(
        tester,
        screen: _wrapAchievementsScreen(
          authService: authService,
          sessions: const [_sampleSession],
        ),
      );

      await _openAchievementFilterMenu(tester);

      expect(find.text('All achievements'), findsWidgets);
      expect(find.text('Claimable'), findsWidgets);
      expect(find.text('In progress'), findsWidgets);
      expect(find.text('Claimed'), findsWidgets);
      expect(find.text('Locked'), findsWidgets);
      expect(find.text('${counts['all']}'), findsWidgets);
      expect(find.text('${counts['claimable']}'), findsWidgets);
      expect(find.text('${counts['inProgress']}'), findsWidgets);
      expect(find.text('${counts['claimed']}'), findsWidgets);
      expect(find.text('${counts['locked']}'), findsWidgets);
    });

    testWidgets('selecting Claimed shows only claimed achievement cards', (
      tester,
    ) async {
      await _pumpAchievementsScreen(
        tester,
        screen: _wrapAchievementsScreen(
          authService: authService,
          sessions: const [],
          claimedIds: const {'first_steps'},
        ),
      );

      await _selectAchievementFilter(tester, 'Claimed');

      expect(find.text('First Steps'), findsOneWidget);
      expect(find.text('Century Club'), findsNothing);
      expect(find.text('Claimed'), findsWidgets);
      expect(find.text('Claim'), findsNothing);
    });

    testWidgets('selecting Locked shows only locked achievement cards', (
      tester,
    ) async {
      final lockedCount = _expectedFilterCounts(
        sessions: const [],
        claimedIds: const {},
      )['locked']!;

      await _pumpAchievementsScreen(
        tester,
        screen: _wrapAchievementsScreen(
          authService: authService,
          sessions: const [],
          claimedIds: const {},
        ),
      );

      await _selectAchievementFilter(tester, 'Locked');

      expect(find.byType(AchievementCard), findsNWidgets(lockedCount));
      expect(find.text('Claim'), findsNothing);
      expect(find.text('Locked'), findsWidgets);
    });

    testWidgets('zero-result filter shows the existing empty-filter state', (
      tester,
    ) async {
      await _pumpAchievementsScreen(
        tester,
        screen: _wrapAchievementsScreen(
          authService: authService,
          sessions: const [],
          claimedIds: const {},
        ),
      );

      await _selectAchievementFilter(tester, 'Claimed');

      expect(
        find.text(
          'No claimed achievements yet. Complete and claim your first one.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('selection remains active when claim stream updates', (
      tester,
    ) async {
      final claimedController = StreamController<Set<String>>.broadcast();
      addTearDown(claimedController.close);

      await _pumpAchievementsScreen(
        tester,
        screen: _wrapAchievementsScreen(
          authService: authService,
          sessions: const [_sampleSession],
          claimedIdsStream: claimedController.stream,
        ),
      );

      await _selectAchievementFilter(tester, 'Claimable');

      expect(find.text('First Steps'), findsOneWidget);
      expect(find.text('Claim'), findsOneWidget);

      claimedController.add({'first_steps'});
      await settleUi(tester);

      expect(
        find.text('No claimable achievements right now. Keep practicing!'),
        findsOneWidget,
      );
      expect(find.text('Claimable'), findsOneWidget);
    });

    testWidgets('narrow layout renders without overflow', (tester) async {
      await _pumpAchievementsScreen(
        tester,
        surfaceSize: const Size(420, 900),
        screen: _wrapAchievementsScreen(
          authService: authService,
          sessions: const [_sampleSession],
        ),
      );
      await expectNoOverflow(tester);
      expect(find.text('All achievements'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString().startsWith('ComboBox<'),
        ),
        findsOneWidget,
      );
    });
  });

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
                  height: 200,
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
          height: 200,
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
          height: 200,
          child: AchievementCard(view: view, claiming: false, onClaim: () {}),
        ),
      ),
    );
    await settleUi(tester);

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
          height: 200,
          child: AchievementCard(
            view: view,
            claiming: false,
            onClaim: () => claimCount++,
          ),
        ),
      ),
    );
    await settleUi(tester);

    await tester.tap(find.byType(AchievementCard));
    await settleUi(tester);

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
          height: 200,
          child: AchievementCard(
            view: view,
            claiming: false,
            onClaim: () => claimCount++,
          ),
        ),
      ),
    );
    await settleUi(tester);

    await tester.tap(find.text('Claim'));
    await settleUi(tester);

    expect(claimCount, 1);
  });

  testWidgets('locked and claimed cards do not invoke onClaim', (tester) async {
    var claimCount = 0;

    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            SizedBox(
              height: 200,
              width: 420,
              child: AchievementCard(
                view: _lockedView(),
                claiming: false,
                onClaim: () => claimCount++,
              ),
            ),
            SizedBox(
              height: 200,
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
    await settleUi(tester);

    await tester.tap(find.byType(AchievementCard).first);
    await tester.tap(find.byType(AchievementCard).last);
    await settleUi(tester);

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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisExtent: 200,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
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
          height: 200,
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

  testWidgets('achievement cards still show reward frame information', (
    tester,
  ) async {
    final view = _claimableView();

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 420,
          height: 200,
          child: AchievementCard(view: view, claiming: false, onClaim: () {}),
        ),
      ),
    );

    expect(find.text('Claim'), findsOneWidget);
    expect(find.byType(AchievementCard), findsOneWidget);
    // Reward border preview remains on the card.
    expect(find.textContaining('Starter'), findsWidgets);
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
            height: 200,
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
          height: 200,
          child: AchievementCard(view: view, claiming: false, onClaim: () {}),
        ),
      ),
    );

    final trophy = _previewIcon(tester, FluentIcons.trophy2);
    expect(trophy.color, AppColors.textPrimaryLight);
    expect(trophy.color, isNot(equals(borderAccent)));
  });

  testWidgets('locked preview icons use muted secondary foreground', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 420,
          height: 200,
          child: AchievementCard(
            view: _lockedView(),
            claiming: false,
            onClaim: () {},
          ),
        ),
      ),
    );

    final lockedTrophy = _previewIcon(tester, FluentIcons.trophy2);
    expect(lockedTrophy.color, AppColors.textSecondary);
  });
}
