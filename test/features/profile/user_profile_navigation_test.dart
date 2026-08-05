import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/leaderboard_award_plan.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/models/profile_visit.dart';
import 'package:elixr_application/data/models/public_profile.dart';
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
  _FakePublicProfileRepository({this.root});

  PublicProfile? root;

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
  Future<List<String>> fetchClaimedAchievementIds(String userId) async =>
      const [];
}

class _FakeProfileVisitRepository extends ProfileVisitRepository {
  @override
  Future<void> upsertVisit({
    required String profileOwnerId,
    required String viewerId,
  }) async {}

  @override
  Future<List<ProfileVisitDisplay>> fetchVisitors({
    required String profileOwnerId,
    int limit = 20,
  }) async => const [];
}

class _SeededProfileController extends UserProfileController {
  _SeededProfileController({
    required super.userId,
    required super.currentUserId,
    required ProfileLoadState seedState,
    LeaderboardEntry? entry,
    PublicProfile? root,
    int? rank,
  }) : super(
         initialEntry: entry,
         initialRank: rank,
         leaderboardRepository: _FakeLeaderboardRepository([?entry]),
         publicProfileRepository: _FakePublicProfileRepository(root: root),
         profileVisitRepository: _FakeProfileVisitRepository(),
       ) {
    loadState = seedState;
    profileRoot = root;
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
}
