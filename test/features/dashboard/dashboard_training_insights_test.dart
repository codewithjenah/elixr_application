import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/dashboard/widgets/dashboard_training_insights.dart';
import 'package:elixr_application/features/training/training_view.dart';
import 'package:elixr_core/utils/comparable_rubric_progress.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Session _v2(String name, int score, int day) => Session(
  userId: 'trainee',
  movementName: name,
  difficulty: 'Easy',
  rubric: RubricAssessment(
    technique: score.clamp(0, 3),
    stability: (score - 3).clamp(0, 3),
    completion: (score - 6).clamp(0, 3),
    propPositioning: (score - 9).clamp(0, 3),
  ),
  assessmentVersion: 2,
  durationSeconds: 60,
  createdAt: DateTime.utc(2026, 1, day).toIso8601String(),
);

Session _legacy(String name, int score, int day) => Session(
  userId: 'trainee',
  movementName: name,
  difficulty: 'Medium',
  legacyScore: score,
  durationSeconds: 60,
  createdAt: DateTime.utc(2026, 1, day).toIso8601String(),
);

Widget _host(List<Session> sessions, {double width = 900}) => FluentApp(
  theme: AppTheme.dark,
  home: ScaffoldPage(
    content: SingleChildScrollView(
      child: SizedBox(
        width: width,
        child: DashboardTrainingInsights(
          sessions: sessions,
          sessionsThisWeek: 2,
          currentStreak: 2,
          weeklyComparison: const ComparableRubricComparison(
            currentAverage: 9,
            comparisonAverage: 8,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('trend selection only includes V2 rubric sessions chronologically', () {
    final selected = DashboardTrainingInsights.rubricTrendSessions([
      _legacy('Legacy', 90, 3),
      _v2('Later', 10, 4),
      _v2('Earlier', 7, 2),
    ]);

    expect(selected.map((session) => session.movementName), [
      'Earlier',
      'Later',
    ]);
    expect(selected.every((session) => session.isRubricAssessed), isTrue);
  });

  testWidgets('renders a V2 chart while keeping legacy scores separate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([_legacy('Legacy', 92, 3), _v2('V2 A', 8, 1), _v2('V2 B', 10, 2)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Performance Trend'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('92 / 100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one V2 session does not render a misleading chart', (
    tester,
  ) async {
    await tester.pumpWidget(_host([_v2('First attempt', 8, 1)]));
    await tester.pumpAndSettle();

    expect(find.byType(LineChart), findsNothing);
    expect(
      find.textContaining('Complete one more scored practice session'),
      findsOneWidget,
    );
  });

  testWidgets('does not render insights with no session history', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const []));
    await tester.pumpAndSettle();

    expect(find.text('TRAINING INSIGHTS'), findsNothing);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('recent sessions are newest first and preserve score scales', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host([
        _v2('Older V2', 7, 1),
        _legacy('Newest legacy', 84, 3),
        _v2('Middle V2', 9, 2),
      ]),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Newest legacy')).dy,
      lessThan(tester.getTopLeft(find.text('Middle V2')).dy),
    );
    expect(find.text('84 / 100'), findsOneWidget);
    expect(find.text('9 / 12'), findsOneWidget);
  });

  testWidgets('wide and stacked layouts render without overflow', (
    tester,
  ) async {
    final sessions = [_v2('A', 8, 1), _v2('B', 9, 2), _legacy('C', 88, 3)];
    for (final width in [1440.0, 1100.0, 800.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(_host(sessions, width: width));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(find.text('Recent Sessions'), findsOneWidget);
    }
    addTearDown(() => tester.binding.setSurfaceSize(null));
  });

  testWidgets('uses existing progress and history locations', (tester) async {
    final locations = <String>[];
    final router = GoRouter(
      initialLocation: '/dashboard',
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => _host([_v2('A', 8, 1), _v2('B', 9, 2)]),
        ),
        GoRoute(
          path: AppRoutePaths.progress,
          builder: (_, state) {
            locations.add(state.uri.toString());
            return const Text('Progress');
          },
        ),
        GoRoute(
          path: AppRoutePaths.training,
          builder: (_, state) {
            locations.add(state.uri.toString());
            return const Text('History');
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      FluentApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View Progress'));
    await tester.pumpAndSettle();
    expect(locations.last, AppRoutePaths.progress);
    router.go('/dashboard');
    await tester.pumpAndSettle();
    await tester.tap(find.text('View history'));
    await tester.pumpAndSettle();
    expect(locations.last, trainingLocation(view: TrainingView.history));
  });
}
