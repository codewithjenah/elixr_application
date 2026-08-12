import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/features/history/history_format.dart';
import 'package:elixr_application/features/history/widgets/history_session_details.dart';
import 'package:elixr_application/features/history/widgets/history_summary_section.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _userId = 'history-user';

Session _rubricSession({
  int technique = 3,
  int stability = 2,
  int completion = 3,
  int propPositioning = 2,
  String movementName = 'Hand Stall',
}) {
  return Session(
    userId: _userId,
    movementName: movementName,
    difficulty: 'Medium',
    rubric: RubricAssessment(
      technique: technique,
      stability: stability,
      completion: completion,
      propPositioning: propPositioning,
    ),
    assessmentVersion: 2,
    durationSeconds: 90,
    createdAt: '2026-08-02T10:00:00.000',
  );
}

Session _legacySession({int legacyScore = 84}) {
  return Session(
    userId: _userId,
    movementName: 'Hand Stall',
    difficulty: 'Medium',
    legacyScore: legacyScore,
    durationSeconds: 90,
    createdAt: '2026-08-02T10:00:00.000',
  );
}

Widget _wrap(Widget child) {
  return FluentApp(
    theme: AppTheme.dark,
    home: ScaffoldPage(
      content: SingleChildScrollView(child: SizedBox(width: 900, child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('history rubric formatting', () {
    test('rubric helpers report the 0..12 scale', () {
      expect(rubricTotalLabel(10), '10 / 12');
      expect(rubricAverageLabel(8.25), '8.3 / 12');
      expect(rubricPerformanceLevel(10), PerformanceLevel.proficient);
      expect(rubricPerformanceLevel(12), PerformanceLevel.mastered);
      expect(rubricPerformanceLevel(0), PerformanceLevel.beginning);
    });

    test('legacy helpers stay on the 0..100 scale', () {
      expect(legacyScoreLabel(84), 'Legacy Score: 84/100');
      expect(scoreQualityLabel(84), 'Excellent');
      expect(scoreQualityLabel(60), 'Developing');
      expect(scoreQualityLabel(10), 'Needs Practice');
    });
  });

  group('HistorySessionDetails', () {
    testWidgets('Assessment V2 session shows the four criteria', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HistorySessionDetails(
            session: _rubricSession(),
            loading: false,
            feedbacks: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Performance'), findsOneWidget);
      expect(find.text('Proficient'), findsOneWidget);
      expect(find.text('Rubric Total'), findsOneWidget);
      expect(find.text('10 / 12'), findsOneWidget);

      expect(find.text('Correct Technique'), findsOneWidget);
      expect(find.text('Stability / Control'), findsOneWidget);
      expect(find.text('Hold / Completion'), findsOneWidget);
      expect(find.text('Prop Positioning'), findsOneWidget);
      expect(find.text('3 / 3'), findsNWidgets(2));
      expect(find.text('2 / 3'), findsNWidgets(2));

      expect(find.textContaining('Legacy Score'), findsNothing);
    });

    testWidgets('legacy session shows the legacy score read-out', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          HistorySessionDetails(
            session: _legacySession(),
            loading: false,
            feedbacks: const [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Legacy Score: 84/100'), findsOneWidget);
      expect(find.text('Correct Technique'), findsNothing);
      expect(find.text('Rubric Total'), findsNothing);
      expect(find.textContaining('/ 12'), findsNothing);
    });

    testWidgets('session without any assessment does not invent a result', (
      tester,
    ) async {
      const session = Session(
        userId: _userId,
        movementName: 'Hand Stall',
        difficulty: 'Medium',
        durationSeconds: 60,
      );

      await tester.pumpWidget(
        _wrap(
          const HistorySessionDetails(
            session: session,
            loading: false,
            feedbacks: [],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No score recorded'), findsOneWidget);
      expect(find.textContaining('/ 12'), findsNothing);
      expect(find.textContaining('/100'), findsNothing);
    });
  });

  group('HistorySummarySection', () {
    testWidgets('rubric cohort shows rubric average and best', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const HistorySummarySection(
            totalSessions: 3,
            rubricSessionCount: 3,
            averageRubricTotal: 9.5,
            bestRubricTotal: 11,
            legacySessionCount: 0,
            averageLegacyScore: null,
            bestLegacyScore: null,
            totalDurationSeconds: 300,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Average Rubric'), findsOneWidget);
      expect(find.text('9.5 / 12'), findsOneWidget);
      expect(find.text('Best Rubric'), findsOneWidget);
      expect(find.text('11 / 12'), findsOneWidget);
      expect(find.text('Average Score'), findsNothing);
      expect(find.text('Best Score'), findsNothing);
    });

    testWidgets('legacy-only cohort keeps the 0..100 labels', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const HistorySummarySection(
            totalSessions: 2,
            rubricSessionCount: 0,
            averageRubricTotal: null,
            bestRubricTotal: null,
            legacySessionCount: 2,
            averageLegacyScore: 84,
            bestLegacyScore: 90,
            totalDurationSeconds: 200,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Average Score'), findsOneWidget);
      expect(find.text('84'), findsOneWidget);
      expect(find.text('Best Score'), findsOneWidget);
      expect(find.text('90'), findsOneWidget);
      expect(find.text('Average Rubric'), findsNothing);
      expect(find.textContaining('/ 12'), findsNothing);
    });

    testWidgets('mixed cohorts report legacy sessions separately', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const HistorySummarySection(
            totalSessions: 5,
            rubricSessionCount: 3,
            averageRubricTotal: 9,
            bestRubricTotal: 11,
            legacySessionCount: 2,
            averageLegacyScore: 70,
            bestLegacyScore: 80,
            totalDurationSeconds: 400,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Average Rubric'), findsOneWidget);
      expect(find.text('9.0 / 12'), findsOneWidget);
      expect(
        find.text('2 legacy sessions scored 0–100 • average 70/100'),
        findsOneWidget,
      );
    });
  });
}
