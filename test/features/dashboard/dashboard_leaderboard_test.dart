import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/leaderboard_award_plan.dart';
import 'package:elixr_application/data/models/leaderboard_entry.dart';
import 'package:elixr_application/data/repositories/leaderboard_repository.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_leaderboard.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_identity.dart';
import 'package:elixr_application/features/leaderboard/widgets/leaderboard_podium.dart';
import 'package:elixr_application/features/profile/profile_route_args.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

LeaderboardEntry _entry(String id, String name, int xp, {int bestScore = 90}) {
  return LeaderboardEntry(
    userId: id,
    displayName: name,
    totalXp: xp,
    sessionsCompleted: xp ~/ 25,
    scoreSum: bestScore.toDouble(),
    averageScore: bestScore.toDouble(),
    bestScore: bestScore,
  );
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
}

Future<void> _setSurface(
  WidgetTester tester, {
  Size size = const Size(1100, 900),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final entries = [
    _entry('p1', 'Alice', 300, bestScore: 100),
    _entry('p2', 'Bob', 200, bestScore: 88),
    _entry('p3', 'Cara', 100, bestScore: 75),
  ];

  testWidgets('renders Top 3 snapshot without LeaderboardPodium', (
    tester,
  ) async {
    await _setSurface(tester);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: DashboardLeaderboard(
            currentUserId: 'viewer',
            displayName: 'Viewer User',
            repository: _FakeLeaderboardRepository(entries),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LeaderboardPodium), findsNothing);
    expect(find.text('Top Players'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cara'), findsOneWidget);
    expect(find.text('View leaderboard'), findsOneWidget);
    expect(find.textContaining('Best '), findsNothing);
  });

  testWidgets('YOU badge shows for current user in Top 3', (tester) async {
    await _setSurface(tester);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: DashboardLeaderboard(
            currentUserId: 'p2',
            displayName: 'Bob',
            repository: _FakeLeaderboardRepository(entries),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LeaderboardYouBadge), findsOneWidget);
    expect(find.text('YOU'), findsOneWidget);
  });

  testWidgets('player tap opens profile route', (tester) async {
    await _setSurface(tester);
    ProfileRouteArgs? receivedArgs;

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
      FluentApp.router(
        theme: AppTheme.dark,
        routeInformationParser: router.routeInformationParser,
        routerDelegate: router.routerDelegate,
        routeInformationProvider: router.routeInformationProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(router.state.uri.path, '/profile/p1');
    expect(receivedArgs?.entry?.userId, 'p1');
    expect(receivedArgs?.rank, 1);
  });

  testWidgets('View leaderboard goes to /leaderboard', (tester) async {
    await _setSurface(tester);

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
      ],
    );

    await tester.pumpWidget(
      FluentApp.router(
        theme: AppTheme.dark,
        routeInformationParser: router.routeInformationParser,
        routerDelegate: router.routerDelegate,
        routeInformationProvider: router.routeInformationProvider,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View leaderboard'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/leaderboard');
  });

  testWidgets('narrow width does not overflow', (tester) async {
    await _setSurface(tester, size: const Size(420, 900));

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: SizedBox(
              width: 360,
              child: DashboardLeaderboard(
                currentUserId: 'p1',
                displayName: 'Alice',
                repository: _FakeLeaderboardRepository(entries),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(LeaderboardPodium), findsNothing);
    expect(find.text('Alice'), findsOneWidget);
  });
}
