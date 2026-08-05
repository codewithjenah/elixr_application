import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/achievement.dart';
import 'package:elixr_application/data/models/leaderboard_award_plan.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/profile_visit.dart';
import 'package:elixr_application/data/models/public_profile.dart';
import 'package:elixr_application/data/models/public_profile_summary.dart';
import 'package:elixr_application/data/models/user.dart';
import 'package:elixr_application/data/repositories/auth_repository.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/data/repositories/profile_visit_repository.dart';
import 'package:elixr_application/data/repositories/public_profile_repository.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_leaderboard.dart';
import 'package:elixr_application/features/leaderboard/leaderboard_list_controller.dart';
import 'package:elixr_application/features/leaderboard/leaderboard_screen.dart';
import 'package:elixr_application/features/profile/profile_route_args.dart';
import 'package:elixr_application/features/profile/user_profile_controller.dart';
import 'package:elixr_application/features/profile/user_profile_screen.dart';
import 'package:elixr_application/services/auth_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

User _authUser() {
  return const User(
    id: 'viewer',
    firstName: 'Viewer',
    lastName: 'User',
    email: 'viewer@example.com',
  );
}

LeaderboardEntry _entry(String id, String name, int xp) {
  return LeaderboardEntry(
    userId: id,
    displayName: name,
    totalXp: xp,
    sessionsCompleted: 3,
    scoreSum: 240,
    averageScore: 80,
    bestScore: 90,
  );
}

AuthService _testAuth() {
  return AuthService(
    repository: _NavFakeAuthRepository(),
    awaitInitialAuthState: () async {},
  )..seedAuthenticatedUser(_authUser());
}

class _NavFakeAuthRepository implements AuthRepositoryBase {
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
  Future<User?> loadPersistedUser() async => null;

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
  Future<EmailChangeRequestResult> requestEmailChange({
    required String newEmail,
    required String currentPassword,
  }) async => EmailChangeRequestResult.unchanged;

  @override
  Future<void> requestCurrentEmailVerification() async {}

  @override
  Future<User?> refreshAuthenticatedUser() async => null;

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
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<User> updateProfilePicture({
    required String userId,
    required ProfilePictureUpdate profilePictureUpdate,
  }) async {
    throw UnimplementedError();
  }
}

class _FakeLeaderboardRepository extends LeaderboardRepository {
  _FakeLeaderboardRepository(this.topPlayers);

  final List<LeaderboardEntry> topPlayers;

  @override
  Stream<List<LeaderboardEntry>> watchTopPlayers({int limit = 10}) {
    return Stream.value(topPlayers.take(limit).toList(growable: false));
  }

  @override
  Future<LeaderboardSyncResult> syncCurrentUserLeaderboard({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {
    return LeaderboardSyncResult.empty;
  }

  @override
  Stream<LeaderboardEntry?> watchPlayer(String userId) {
    final match = topPlayers.where((e) => e.userId == userId);
    return Stream.value(match.isEmpty ? null : match.first);
  }

  @override
  Future<int?> computeRankForUser(String userId) async => 1;
}

class _FakePublicProfileRepository extends PublicProfileRepository {
  _FakePublicProfileRepository({
    this.root,
    this.summary,
    this.claimedAchievementIds = const [],
  });

  PublicProfile? root;
  PublicProfileSummary? summary;
  List<String> claimedAchievementIds;
  int fetchSessionsPageCalls = 0;
  int getSummaryCalls = 0;
  int fetchClaimedAchievementIdsCalls = 0;

  @override
  Stream<PublicProfile?> watchProfileRoot(String userId) {
    return Stream.value(root);
  }

  @override
  Future<void> ensurePublicProfile({
    required String userId,
    required String displayName,
    String? profilePictureUrl,
  }) async {}

  @override
  Future<PublicProfileSummary?> getSummary(String userId) async {
    getSummaryCalls++;
    return summary;
  }

  @override
  Future<List<String>> fetchClaimedAchievementIds(String userId) async {
    fetchClaimedAchievementIdsCalls++;
    return claimedAchievementIds;
  }

  @override
  Future<PublicProfileSessionPage> fetchSessionsPage({
    required String userId,
    int limit = 20,
    PublicProfileSessionCursor? startAfter,
  }) async {
    fetchSessionsPageCalls++;
    fail('fetchSessionsPage should not be called from Player Profile');
  }
}

class _FakeProfileVisitRepository extends ProfileVisitRepository {
  List<ProfileVisitDisplay> visitors = const [];

  @override
  Future<void> upsertVisit({
    required String profileOwnerId,
    required String viewerId,
  }) async {}

  @override
  Future<List<ProfileVisitDisplay>> fetchVisitors({
    required String profileOwnerId,
    int limit = 20,
  }) async => visitors;
}

ProfileVisitDisplay _visitor({
  required String viewerId,
  required String displayName,
  String ownerId = 'viewer',
}) {
  return ProfileVisitDisplay(
    visit: ProfileVisit(
      profileOwnerId: ownerId,
      viewerId: viewerId,
      lastViewedAt: DateTime.utc(2026, 8, 1, 10).toIso8601String(),
    ),
    displayName: displayName,
  );
}

class _SeededProfileController extends UserProfileController {
  _SeededProfileController({
    required super.userId,
    required super.currentUserId,
    required ProfileLoadState seedState,
    LeaderboardEntry? entry,
    PublicProfile? root,
    int? rank,
    PublicProfileSummary? summary,
    List<AchievementDefinition>? claimedAchievements,
    ProfileVisitorsState visitorsState = ProfileVisitorsState.empty,
    List<ProfileVisitDisplay> visitors = const [],
  }) : super(
         initialEntry: entry,
         initialRank: rank,
         leaderboardRepository: _FakeLeaderboardRepository([?entry]),
         publicProfileRepository: _FakePublicProfileRepository(root: root),
         profileVisitRepository: _FakeProfileVisitRepository(),
       ) {
    loadState = seedState;
    profileRoot = root;
    this.summary = summary;
    this.claimedAchievements = claimedAchievements ?? const [];
    this.visitorsState = visitorsState;
    this.visitors = visitors;
  }

  @override
  Future<void> initialize({
    required String displayName,
    String? profilePictureUrl,
  }) async {}
}

Future<void> _setSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

Finder _backButton() {
  return find.byIcon(FluentIcons.back);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('profile navigation from leaderboard and dashboard', () {
    testWidgets('leaderboard player tap pushes profile with route args', (
      tester,
    ) async {
      await _setSurface(tester);
      ProfileRouteArgs? receivedArgs;
      String? receivedUserId;
      final entries = [
        _entry('p1', 'Alice', 300),
        _entry('p2', 'Bob', 200),
        _entry('p3', 'Cara', 100),
      ];
      final controller = LeaderboardListController(
        fetchPage: ({startAfter}) async =>
            LeaderboardPage(entries: entries, nextCursor: null, hasMore: false),
      );
      final auth = _testAuth();

      final router = GoRouter(
        initialLocation: '/leaderboard',
        routes: [
          GoRoute(
            path: '/leaderboard',
            builder: (context, state) => LeaderboardScreen(
              repository: _FakeLeaderboardRepository(entries),
              controller: controller,
            ),
          ),
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) {
              receivedUserId = state.pathParameters['userId'];
              receivedArgs = state.extra is ProfileRouteArgs
                  ? state.extra! as ProfileRouteArgs
                  : null;
              return const ScaffoldPage(content: Text('Profile page'));
            },
          ),
          GoRoute(
            path: '/dashboard',
            builder: (context, state) =>
                const ScaffoldPage(content: Text('Dashboard page')),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.canPop(), isFalse);
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(receivedUserId, 'p1');
      expect(receivedArgs, isNotNull);
      expect(receivedArgs!.entry?.userId, 'p1');
      expect(receivedArgs!.rank, 1);
      expect(router.canPop(), isTrue);
      expect(router.state.uri.path, '/profile/p1');
    });

    testWidgets('dashboard player tap pushes profile with route args', (
      tester,
    ) async {
      await _setSurface(tester);
      ProfileRouteArgs? receivedArgs;
      final entries = [
        _entry('p1', 'Alice', 300),
        _entry('p2', 'Bob', 200),
        _entry('p3', 'Cara', 100),
      ];
      final auth = _testAuth();

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => ScaffoldPage(
              content: DashboardLeaderboard(
                currentUserId: 'viewer',
                displayName: 'Viewer User',
                repository: _FakeLeaderboardRepository(entries),
              ),
            ),
          ),
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) {
              receivedArgs = state.extra is ProfileRouteArgs
                  ? state.extra! as ProfileRouteArgs
                  : null;
              return ScaffoldPage(
                content: Text('Profile ${state.pathParameters['userId']}'),
              );
            },
          ),
          GoRoute(
            path: '/leaderboard',
            builder: (context, state) =>
                const ScaffoldPage(content: Text('Full leaderboard')),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.canPop(), isFalse);
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/profile/p1');
      expect(router.canPop(), isTrue);
      expect(receivedArgs?.entry?.userId, 'p1');
      expect(receivedArgs?.rank, 1);
    });

    testWidgets('View Full Leaderboard still uses go replacement', (
      tester,
    ) async {
      await _setSurface(tester);
      final auth = _testAuth();
      final entries = [
        _entry('p1', 'Alice', 300),
        _entry('p2', 'Bob', 200),
        _entry('p3', 'Cara', 100),
      ];
      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => ScaffoldPage(
              content: DashboardLeaderboard(
                currentUserId: 'viewer',
                displayName: 'Viewer User',
                repository: _FakeLeaderboardRepository(entries),
              ),
            ),
          ),
          GoRoute(
            path: '/leaderboard',
            builder: (context, state) =>
                const ScaffoldPage(content: Text('Full leaderboard')),
          ),
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) =>
                const ScaffoldPage(content: Text('Profile')),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('View Full Leaderboard'));
      await tester.pumpAndSettle();

      expect(router.state.uri.path, '/leaderboard');
      expect(router.canPop(), isFalse);
    });
  });

  group('profile back navigation', () {
    testWidgets('back pops to originating page when stack can pop', (
      tester,
    ) async {
      await _setSurface(tester);
      final auth = _testAuth();
      final entry = _entry('p1', 'Alice', 300);
      final profileController = _SeededProfileController(
        userId: 'p1',
        currentUserId: 'viewer',
        seedState: ProfileLoadState.loaded,
        entry: entry,
        root: PublicProfile(
          userId: 'p1',
          displayName: 'Alice',
          visibility: ProfileVisibility.public,
        ),
        rank: 1,
      );

      final router = GoRouter(
        initialLocation: '/leaderboard',
        routes: [
          GoRoute(
            path: '/leaderboard',
            builder: (context, state) =>
                const ScaffoldPage(content: Text('Leaderboard home')),
          ),
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) => UserProfileScreen(
              userId: state.pathParameters['userId']!,
              controller: profileController,
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      router.push('/profile/p1');
      await tester.pumpAndSettle();
      expect(find.text('Player Profile'), findsOneWidget);

      await tester.tap(_backButton());
      await tester.pumpAndSettle();

      expect(find.text('Leaderboard home'), findsOneWidget);
      expect(router.state.uri.path, '/leaderboard');
    });

    testWidgets('directly opened profile falls back to /leaderboard', (
      tester,
    ) async {
      await _setSurface(tester);
      final auth = _testAuth();
      final profileController = _SeededProfileController(
        userId: 'p1',
        currentUserId: 'viewer',
        seedState: ProfileLoadState.loaded,
        entry: _entry('p1', 'Alice', 300),
        root: PublicProfile(
          userId: 'p1',
          displayName: 'Alice',
          visibility: ProfileVisibility.public,
        ),
      );

      final router = GoRouter(
        initialLocation: '/profile/p1',
        routes: [
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) => UserProfileScreen(
              userId: state.pathParameters['userId']!,
              controller: profileController,
            ),
          ),
          GoRoute(
            path: '/leaderboard',
            builder: (context, state) =>
                const ScaffoldPage(content: Text('Leaderboard fallback')),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(router.canPop(), isFalse);
      await tester.tap(_backButton());
      await tester.pumpAndSettle();

      expect(find.text('Leaderboard fallback'), findsOneWidget);
      expect(router.state.uri.path, '/leaderboard');
    });

    testWidgets('not-found Go Back uses shared back handler fallback', (
      tester,
    ) async {
      await _setSurface(tester);
      final auth = _testAuth();
      final profileController = _SeededProfileController(
        userId: 'missing',
        currentUserId: 'viewer',
        seedState: ProfileLoadState.notFound,
      );

      final router = GoRouter(
        initialLocation: '/profile/missing',
        routes: [
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) => UserProfileScreen(
              userId: state.pathParameters['userId']!,
              controller: profileController,
            ),
          ),
          GoRoute(
            path: '/leaderboard',
            builder: (context, state) =>
                const ScaffoldPage(content: Text('Leaderboard fallback')),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Player not found.'), findsOneWidget);
      await tester.tap(find.text('Go Back'));
      await tester.pumpAndSettle();

      expect(find.text('Leaderboard fallback'), findsOneWidget);
    });
  });

  group('profile page-level back button visibility', () {
    Future<void> pumpProfile(
      WidgetTester tester, {
      required ProfileLoadState state,
      PublicProfile? root,
      LeaderboardEntry? entry,
      String? currentUserId,
      bool settle = true,
    }) async {
      await _setSurface(tester);
      final auth = _testAuth();
      final controller = _SeededProfileController(
        userId: 'p1',
        currentUserId: currentUserId ?? 'viewer',
        seedState: state,
        entry: entry ?? _entry('p1', 'Alice', 300),
        root: root,
        rank: 1,
      );

      final router = GoRouter(
        initialLocation: '/profile/p1',
        routes: [
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) =>
                UserProfileScreen(userId: 'p1', controller: controller),
          ),
          GoRoute(
            path: '/leaderboard',
            builder: (context, state) =>
                const ScaffoldPage(content: Text('Leaderboard')),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }

    testWidgets('visible while loading', (tester) async {
      await pumpProfile(tester, state: ProfileLoadState.loading, settle: false);
      expect(_backButton(), findsOneWidget);
      expect(find.text('Player Profile'), findsOneWidget);
    });

    testWidgets('visible when loaded', (tester) async {
      await pumpProfile(
        tester,
        state: ProfileLoadState.loaded,
        root: PublicProfile(
          userId: 'p1',
          displayName: 'Alice',
          visibility: ProfileVisibility.public,
        ),
      );
      expect(_backButton(), findsOneWidget);
    });

    testWidgets('visible for private profile', (tester) async {
      await pumpProfile(
        tester,
        state: ProfileLoadState.loaded,
        root: PublicProfile(
          userId: 'p1',
          displayName: 'Alice',
          visibility: ProfileVisibility.private,
        ),
      );
      expect(_backButton(), findsOneWidget);
      expect(find.text('This profile is private'), findsOneWidget);
    });

    testWidgets('visible on error', (tester) async {
      await pumpProfile(tester, state: ProfileLoadState.error);
      expect(_backButton(), findsOneWidget);
      expect(find.text('Could not load this profile.'), findsOneWidget);
    });

    testWidgets('visible when not found', (tester) async {
      await pumpProfile(tester, state: ProfileLoadState.notFound);
      expect(_backButton(), findsOneWidget);
      expect(find.text('Player not found.'), findsOneWidget);
    });
  });

  group('practice history removed from player profile', () {
    Future<void> pumpLoadedProfile(
      WidgetTester tester, {
      required String userId,
      required String currentUserId,
      PublicProfileSummary? summary,
      List<AchievementDefinition>? claimedAchievements,
    }) async {
      await _setSurface(tester);
      final auth = _testAuth();
      final controller = _SeededProfileController(
        userId: userId,
        currentUserId: currentUserId,
        seedState: ProfileLoadState.loaded,
        entry: _entry(userId, 'Alice', 300),
        root: PublicProfile(
          userId: userId,
          displayName: 'Alice',
          visibility: ProfileVisibility.public,
        ),
        summary:
            summary ??
            const PublicProfileSummary(
              totalDurationSeconds: 120,
              completedMovementNames: ['Hand Stall', 'Around the World'],
            ),
        claimedAchievements:
            claimedAchievements ??
            achievementCatalog.where((a) => a.id == 'first_steps').toList(),
        rank: 1,
      );

      final router = GoRouter(
        initialLocation: '/profile/$userId',
        routes: [
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) => UserProfileScreen(
              userId: state.pathParameters['userId']!,
              controller: controller,
            ),
          ),
          GoRoute(
            path: '/leaderboard',
            builder: (context, state) =>
                const ScaffoldPage(content: Text('Leaderboard')),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('public profile does not show Practice History heading', (
      tester,
    ) async {
      await pumpLoadedProfile(tester, userId: 'p1', currentUserId: 'viewer');
      expect(find.text('Practice History'), findsNothing);
      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('Completed Movements'), findsOneWidget);
      expect(find.text('Hand Stall'), findsOneWidget);
      expect(find.text('First Steps'), findsOneWidget);
    });

    testWidgets('owner profile does not show Practice History heading', (
      tester,
    ) async {
      await pumpLoadedProfile(
        tester,
        userId: 'viewer',
        currentUserId: 'viewer',
      );
      expect(find.text('Practice History'), findsNothing);
      expect(find.text('Achievements'), findsOneWidget);
      expect(find.text('Completed Movements'), findsOneWidget);
      expect(find.text('Profile Visitors'), findsOneWidget);
    });

    test('controller does not request fetchSessionsPage', () async {
      final publicRepo = _FakePublicProfileRepository(
        root: PublicProfile(
          userId: 'p1',
          displayName: 'Alice',
          visibility: ProfileVisibility.public,
        ),
        summary: const PublicProfileSummary(
          totalDurationSeconds: 60,
          completedMovementNames: ['Hand Stall'],
        ),
        claimedAchievementIds: const ['first_steps'],
      );
      final controller = UserProfileController(
        userId: 'p1',
        currentUserId: 'viewer',
        initialEntry: _entry('p1', 'Alice', 300),
        initialRank: 1,
        leaderboardRepository: _FakeLeaderboardRepository([
          _entry('p1', 'Alice', 300),
        ]),
        publicProfileRepository: publicRepo,
        profileVisitRepository: _FakeProfileVisitRepository(),
      );

      await controller.initialize(displayName: 'Viewer User');
      await Future<void>.delayed(Duration.zero);

      expect(publicRepo.fetchSessionsPageCalls, 0);
      expect(publicRepo.getSummaryCalls, greaterThan(0));
      expect(publicRepo.fetchClaimedAchievementIdsCalls, greaterThan(0));
      expect(controller.summary?.completedMovementNames, ['Hand Stall']);
      expect(controller.claimedAchievements.map((a) => a.id), ['first_steps']);
      controller.dispose();
    });
  });

  group('profile visitor navigation', () {
    Future<({GoRouter router, _SeededProfileController controller})>
    pumpOwnerProfile(
      WidgetTester tester, {
      required List<ProfileVisitDisplay> visitors,
      ProfileVisitorsState visitorsState = ProfileVisitorsState.loaded,
      bool settle = true,
    }) async {
      await _setSurface(tester);
      final auth = _testAuth();
      final ownerController = _SeededProfileController(
        userId: 'viewer',
        currentUserId: 'viewer',
        seedState: ProfileLoadState.loaded,
        entry: _entry('viewer', 'Viewer User', 100),
        root: PublicProfile(
          userId: 'viewer',
          displayName: 'Viewer User',
          visibility: ProfileVisibility.public,
        ),
        summary: const PublicProfileSummary(
          totalDurationSeconds: 30,
          completedMovementNames: ['Hand Stall'],
        ),
        visitorsState: visitorsState,
        visitors: visitors,
        rank: 2,
      );

      final router = GoRouter(
        initialLocation: '/profile/viewer',
        routes: [
          GoRoute(
            path: '/profile/:userId',
            builder: (context, state) {
              final userId = state.pathParameters['userId']!;
              if (userId == 'viewer') {
                return UserProfileScreen(
                  userId: userId,
                  controller: ownerController,
                );
              }
              return UserProfileScreen(
                userId: userId,
                controller: _SeededProfileController(
                  userId: userId,
                  currentUserId: 'viewer',
                  seedState: ProfileLoadState.loaded,
                  entry: _entry(userId, 'Opened Visitor', 50),
                  root: PublicProfile(
                    userId: userId,
                    displayName: 'Opened Visitor',
                    visibility: ProfileVisibility.public,
                  ),
                ),
              );
            },
          ),
          GoRoute(
            path: '/leaderboard',
            builder: (context, state) =>
                const ScaffoldPage(content: Text('Leaderboard')),
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthService>.value(
          value: auth,
          child: FluentApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
      return (router: router, controller: ownerController);
    }

    Future<void> tapVisitorRow(
      WidgetTester tester,
      String semanticLabel,
    ) async {
      final row = find.bySemanticsLabel(semanticLabel);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
    }

    testWidgets('seeded visitors render and open by viewerId', (tester) async {
      final visitors = [
        _visitor(viewerId: 'alice-id', displayName: 'Alice Visitor'),
        _visitor(viewerId: 'bob-id', displayName: 'Player'),
      ];
      final env = await pumpOwnerProfile(tester, visitors: visitors);

      expect(find.text('Alice Visitor'), findsOneWidget);
      expect(find.text('Player'), findsOneWidget);
      expect(find.byIcon(FluentIcons.chevron_right), findsNWidgets(2));
      expect(
        find.bySemanticsLabel("View Alice Visitor's profile"),
        findsOneWidget,
      );

      await tapVisitorRow(tester, "View Alice Visitor's profile");

      expect(env.router.state.uri.path, '/profile/alice-id');
      expect(env.router.canPop(), isTrue);
      expect(find.text('Opened Visitor'), findsOneWidget);

      await tester.tap(_backButton());
      await tester.pumpAndSettle();

      expect(env.router.state.uri.path, '/profile/viewer');
      expect(find.text('Alice Visitor'), findsOneWidget);
      expect(find.text('Profile Visitors'), findsOneWidget);
    });

    testWidgets('fallback display name still navigates by viewerId', (
      tester,
    ) async {
      final env = await pumpOwnerProfile(
        tester,
        visitors: [_visitor(viewerId: 'fallback-id', displayName: 'Player')],
      );

      await tapVisitorRow(tester, "View Player's profile");

      expect(env.router.state.uri.path, '/profile/fallback-id');
      expect(env.router.canPop(), isTrue);
    });

    testWidgets('empty visitor state has no tappable rows', (tester) async {
      await pumpOwnerProfile(
        tester,
        visitors: const [],
        visitorsState: ProfileVisitorsState.empty,
      );

      expect(find.text('No profile visitors yet.'), findsOneWidget);
      expect(find.byIcon(FluentIcons.chevron_right), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r"^View .+\'s profile$")),
        findsNothing,
      );
    });

    testWidgets('loading visitor state has no tappable rows', (tester) async {
      await pumpOwnerProfile(
        tester,
        visitors: const [],
        visitorsState: ProfileVisitorsState.loading,
        settle: false,
      );

      expect(find.byType(ProgressRing), findsWidgets);
      expect(find.byIcon(FluentIcons.chevron_right), findsNothing);
    });

    testWidgets('error visitor state has no tappable rows', (tester) async {
      await pumpOwnerProfile(
        tester,
        visitors: const [],
        visitorsState: ProfileVisitorsState.error,
      );

      expect(find.text('Could not load profile visitors.'), findsOneWidget);
      expect(find.byIcon(FluentIcons.chevron_right), findsNothing);
    });
  });
}
