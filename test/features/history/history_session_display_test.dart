import 'dart:convert';
import 'dart:typed_data';

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
  String? evidenceStoragePath,
  String? evidenceKind,
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
    evidenceStoragePath: evidenceStoragePath,
    evidenceKind: evidenceKind,
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

/// 1x1 PNG so Image.memory can decode without Firebase Storage.
final Uint8List _onePixelPng = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

Widget _wrap(Widget child, {double width = 900}) {
  return FluentApp(
    theme: AppTheme.dark,
    home: ScaffoldPage(
      content: SingleChildScrollView(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

Future<void> _pumpDetails(
  WidgetTester tester, {
  required Session session,
  double width = 900,
  Future<Uint8List?> Function(String path)? loadEvidence,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _wrap(
      HistorySessionDetails(
        session: session,
        loading: false,
        feedbacks: const [],
        loadEvidence: loadEvidence,
      ),
      width: width,
    ),
  );
  await tester.pumpAndSettle();
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
      await _pumpDetails(tester, session: _rubricSession());

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
      expect(find.text('No confirmed movement image'), findsOneWidget);
    });

    testWidgets('legacy session shows the legacy score read-out', (
      tester,
    ) async {
      await _pumpDetails(tester, session: _legacySession());

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

      await _pumpDetails(tester, session: session);

      expect(find.text('No score recorded'), findsOneWidget);
      expect(find.textContaining('/ 12'), findsNothing);
      expect(find.textContaining('/100'), findsNothing);
      expect(find.text('No confirmed movement image'), findsOneWidget);
    });

    testWidgets('wide layout shows criteria and a capped still, not 4:3', (
      tester,
    ) async {
      await _pumpDetails(
        tester,
        width: 900,
        session: _rubricSession(
          evidenceStoragePath: 'users/history-user/session_evidence/s1.jpg',
          evidenceKind: 'hold_confirmed',
        ),
        loadEvidence: (_) async => _onePixelPng,
      );

      expect(find.text('Correct Technique'), findsOneWidget);
      expect(find.text('Confirmed movement image'), findsOneWidget);
      expect(find.text('Click to enlarge'), findsOneWidget);
      expect(find.byKey(const Key('history-evidence-preview')), findsOneWidget);
      expect(find.byType(AspectRatio), findsNothing);
    });

    testWidgets('narrow layout keeps a height-capped still without 4:3', (
      tester,
    ) async {
      await _pumpDetails(
        tester,
        width: 400,
        session: _rubricSession(
          evidenceStoragePath: 'users/history-user/session_evidence/s1.jpg',
          evidenceKind: 'hold_confirmed',
        ),
        loadEvidence: (_) async => _onePixelPng,
      );

      expect(find.text('Confirmed movement image'), findsOneWidget);
      expect(find.byKey(const Key('history-evidence-preview')), findsOneWidget);
      expect(find.byType(AspectRatio), findsNothing);
    });

    testWidgets('enlarging the still uses a 4:3 dialog only', (tester) async {
      await _pumpDetails(
        tester,
        width: 900,
        session: _rubricSession(
          evidenceStoragePath: 'users/history-user/session_evidence/s1.jpg',
          evidenceKind: 'hold_confirmed',
        ),
        loadEvidence: (_) async => _onePixelPng,
      );

      expect(find.byType(AspectRatio), findsNothing);
      await tester.tap(find.byKey(const Key('history-evidence-preview')));
      await tester.pumpAndSettle();

      expect(find.byType(AspectRatio), findsOneWidget);
      expect(find.text('Click to enlarge'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AspectRatio), findsNothing);
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
