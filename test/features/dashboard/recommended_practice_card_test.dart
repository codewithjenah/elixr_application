import 'package:elixr_application/core/constants/movements.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/movement.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_hero.dart';
import 'package:elixr_application/features/dashboard/widgets/recommended_practice_card.dart';
import 'package:elixr_application/features/progress/training_recommendation.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

TrainingRecommendation _recommendationFor(List<Session> sessions) {
  return buildTrainingRecommendation(
    sessions: sessions,
    movements: movementCatalog,
  );
}

Session _session({
  required String movementName,
  int score = 70,
  String? createdAt,
}) {
  return Session(
    userId: 'user-1',
    movementName: movementName,
    difficulty: 'Easy',
    score: score,
    durationSeconds: 60,
    createdAt: createdAt,
  );
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecommendedPracticeCard', () {
    testWidgets('shows loading state', (tester) async {
      await _setSurface(tester, const Size(900, 600));

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: const ScaffoldPage(
            content: RecommendedPracticeCard(
              recommendation: null,
              loading: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ProgressRing), findsOneWidget);
      expect(find.text("COACH'S FOCUS"), findsNothing);
    });

    testWidgets('new user state recommends first Easy movement', (
      tester,
    ) async {
      await _setSurface(tester, const Size(900, 600));
      final recommendation = _recommendationFor(const []);

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: ScaffoldPage(
            content: RecommendedPracticeCard(
              recommendation: recommendation,
              loading: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("COACH'S FOCUS"), findsOneWidget);
      expect(find.text('Normal Grip'), findsOneWidget);
      expect(find.text('Not practiced'), findsOneWidget);
      expect(
        find.text('You have not practiced this movement yet.'),
        findsOneWidget,
      );
      expect(find.text('Practice this'), findsOneWidget);
    });

    testWidgets('recommended practiced movement shows recent average', (
      tester,
    ) async {
      await _setSurface(tester, const Size(900, 600));
      const movements = <Movement>[
        Movement(
          name: 'Mastered A',
          difficulty: 'Easy',
          description: 'A',
          requiresHandsDetection: true,
          enabled: true,
        ),
        Movement(
          name: 'Weak Move',
          difficulty: 'Easy',
          description: 'B',
          requiresHandsDetection: true,
          enabled: true,
        ),
      ];
      final recommendation = buildTrainingRecommendation(
        sessions: [
          for (var i = 1; i <= 3; i++)
            _session(
              movementName: 'Mastered A',
              score: 90,
              createdAt: DateTime(2026, 1, i).toUtc().toIso8601String(),
            ),
          _session(
            movementName: 'Weak Move',
            score: 64,
            createdAt: DateTime(2026, 2, 1).toUtc().toIso8601String(),
          ),
        ],
        movements: movements,
      );

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: ScaffoldPage(
            content: RecommendedPracticeCard(
              recommendation: recommendation,
              loading: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Weak Move'), findsOneWidget);
      expect(find.textContaining('Recent: 64'), findsOneWidget);
    });

    testWidgets('Practice this navigates with encoded query parameters', (
      tester,
    ) async {
      await _setSurface(tester, const Size(900, 600));
      final navigated = <String>[];
      final recommendation = _recommendationFor(const []);

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => ScaffoldPage(
              content: RecommendedPracticeCard(
                recommendation: recommendation,
                loading: false,
              ),
            ),
          ),
          GoRoute(
            path: '/practice',
            builder: (context, state) {
              navigated.add(state.uri.toString());
              return const ScaffoldPage(
                content: Center(child: Text('Practice')),
              );
            },
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

      await tester.tap(find.text('Practice this'));
      await tester.pumpAndSettle();

      expect(navigated, hasLength(1));
      expect(
        navigated.single,
        '/practice?movement=Normal%20Grip&difficulty=Easy',
      );
    });

    testWidgets('narrow width does not overflow', (tester) async {
      await _setSurface(tester, const Size(360, 700));
      final recommendation = _recommendationFor(const []);

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.dark,
          home: ScaffoldPage(
            content: SingleChildScrollView(
              child: SizedBox(
                width: 360,
                child: RecommendedPracticeCard(
                  recommendation: recommendation,
                  loading: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Practice this'), findsOneWidget);
    });
  });

  group('DashboardHero CTAs', () {
    testWidgets('primary and secondary actions navigate to different routes', (
      tester,
    ) async {
      await _setSurface(tester, const Size(1100, 800));
      final navigated = <String>[];
      final recommendation = _recommendationFor(const []);

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => ScaffoldPage(
              content: DashboardHero(
                firstName: 'Ada',
                greeting: 'Good Morning',
                sessionCount: 3,
                recommendation: recommendation,
              ),
            ),
          ),
          GoRoute(
            path: '/practice',
            builder: (context, state) {
              navigated.add(state.uri.toString());
              return const ScaffoldPage(content: Text('Practice'));
            },
          ),
          GoRoute(
            path: '/movements',
            builder: (context, state) {
              navigated.add(state.uri.toString());
              return const ScaffoldPage(content: Text('Movements'));
            },
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

      expect(find.text('Practice Normal Grip'), findsOneWidget);
      expect(find.text('Explore Movements'), findsOneWidget);

      await tester.tap(find.text('Practice Normal Grip'));
      await tester.pumpAndSettle();
      expect(
        navigated.single,
        '/practice?movement=Normal%20Grip&difficulty=Easy',
      );

      router.go('/dashboard');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Explore Movements'));
      await tester.pumpAndSettle();
      expect(navigated.last, '/movements');
      expect(navigated.first, isNot(equals(navigated.last)));
    });

    test('practiceRouteFor encodes movement and falls back', () {
      final recommendation = _recommendationFor(const []);
      expect(
        DashboardHero.practiceRouteFor(recommendation),
        '/practice?movement=Normal%20Grip&difficulty=Easy',
      );
      expect(DashboardHero.practiceRouteFor(null), '/movements');
    });
  });
}
