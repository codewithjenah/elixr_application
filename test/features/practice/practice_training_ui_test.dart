import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:elixr_application/features/practice/widgets/readiness_checklist_panel.dart';
import 'package:elixr_application/features/practice/widgets/training_action_area.dart';
import 'package:elixr_application/features/practice/widgets/training_connection_badge.dart';
import 'package:elixr_application/features/practice/widgets/training_performance.dart';
import 'package:elixr_application/features/practice/widgets/training_session_header.dart';
import 'package:elixr_application/features/practice/widgets/training_session_panel.dart';
import 'package:elixr_application/features/practice/widgets/training_status_row.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

bool _searchingForTest = true;

Widget _wrap(Widget child, {Brightness brightness = Brightness.dark}) {
  return FluentApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    home: ScaffoldPage(content: child),
  );
}

void main() {
  group('Training dashboard widgets', () {
    testWidgets('ready phase renders session shell and primary action', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 640,
            child: TrainingSessionPanel(
              phase: TrainingSessionPhase.ready,
              expandVertically: false,
              metrics: SessionMetricTiles(
                elapsedDisplay: '00:00',
                rubricChild: const Text('—'),
                performanceBar: const TrainingPerformanceBar(total: null),
                rubricBreakdown: const RubricCriteriaTiles(assessment: null),
              ),
              statusContent: const TrainingStatusRow(
                detection: TrainingDetectionStatus.inactive,
              ),
              supportingContent: SessionSetupRow(
                icon: FluentIcons.play_solid,
                label: 'Movement',
                value: 'Hand Stall',
              ),
              actionArea: TrainingActionArea(
                kind: TrainingActionKind.start,
                startLabel: 'Begin Calibration',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('practice-session-panel')),
        findsOneWidget,
      );
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('Waiting for assessment'), findsOneWidget);
      expect(find.text('Correct Technique'), findsOneWidget);
      expect(find.text('%'), findsNothing);
      expect(
        find.byKey(const ValueKey('practice-primary-action')),
        findsOneWidget,
      );
      expect(find.text('Begin Calibration'), findsOneWidget);
    });

    testWidgets('in-progress phase renders rubric metric and rank area', (
      tester,
    ) async {
      const rubric = RubricAssessment(
        technique: 3,
        stability: 2,
        completion: 3,
        propPositioning: 2,
      );
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 640,
            child: TrainingSessionPanel(
              phase: TrainingSessionPhase.inProgress,
              expandVertically: false,
              rankBadge: RankBadge(level: rubric.performanceLevel),
              metrics: SessionMetricTiles(
                elapsedDisplay: '01:12',
                rubricChild: const Text('10 / 12'),
                performanceBar: const TrainingPerformanceBar(total: 10),
                rubricBreakdown: const RubricCriteriaTiles(assessment: rubric),
              ),
              statusContent: const TrainingStatusRow(
                detection: TrainingDetectionStatus.detected,
                propLabel: 'Bottle',
              ),
              supportingContent: SessionSetupRow(
                icon: FluentIcons.play_solid,
                label: 'Movement',
                value: 'Hand Stall',
              ),
              actionArea: TrainingActionArea(
                kind: TrainingActionKind.finish,
                startLabel: 'Begin Calibration',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('In Progress'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-score-metric')),
        findsOneWidget,
      );
      expect(find.text('10 / 12'), findsWidgets);
      expect(find.text('Proficient'), findsOneWidget);
      expect(find.text('Pro'), findsOneWidget);
      expect(find.text('3 / 3'), findsNWidgets(2));
      expect(find.text('2 / 3'), findsNWidgets(2));
    });

    testWidgets('readiness phase renders checklist in status surface', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 720,
            child: TrainingSessionPanel(
              phase: TrainingSessionPhase.readiness,
              expandVertically: false,
              metrics: const TrainingStageIndicator(
                cameraActive: false,
                cameraDone: true,
                setupActive: true,
                setupDone: false,
                practiceActive: false,
              ),
              statusContent: ReadinessChecklistPanel(
                items: const [
                  ReadinessItemView(
                    code: 'bottle_detected',
                    status: ReadinessItemStatus.ready,
                    message: 'Bottle visible',
                  ),
                  ReadinessItemView(
                    code: 'grip_landmarks_visible',
                    status: ReadinessItemStatus.waiting,
                    message: 'Hands visible',
                  ),
                ],
                progress: 0.4,
                stable: false,
                complete: false,
              ),
              supportingContent: SessionSetupRow(
                icon: FluentIcons.play_solid,
                label: 'Movement',
                value: 'Hand Stall',
              ),
              actionArea: TrainingActionArea(
                kind: TrainingActionKind.start,
                startLabel: 'Start Practice',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('session-status-surface')),
        findsOneWidget,
      );
      expect(find.text('Setup status'), findsOneWidget);
      expect(find.text('Bottle'), findsOneWidget);
      expect(find.text('Start Practice'), findsOneWidget);
    });

    testWidgets('connection error phase renders retry action', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 560,
            child: TrainingSessionPanel(
              phase: TrainingSessionPhase.cameraError,
              expandVertically: false,
              metrics: SessionMetricTiles(
                elapsedDisplay: '00:00',
                rubricChild: const Text('—'),
                performanceBar: const TrainingPerformanceBar(total: null),
              ),
              statusContent: const TrainingStatusRow(
                detection: TrainingDetectionStatus.inactive,
              ),
              compactStatusNote: const Text('Backend offline.'),
              actionArea: TrainingActionArea(
                kind: TrainingActionKind.retry,
                startLabel: 'Begin Calibration',
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Camera Error'), findsOneWidget);
      expect(find.text('Backend offline.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('narrow header and long movement names do not overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() async {
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 360,
            child: TrainingSessionHeader(
              onBack: () {},
              title: 'Extended Movement Name That Should Ellipsize Safely',
              statusPill: 'Medium',
              statusPillColor: trainingDifficultyColor('medium'),
              instruction: 'Follow the on-screen guidance.',
              connectionState: WebSocketConnectionState.connected,
              wideLayout: false,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('practice-training-header')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('detection labels remain correct', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const TrainingStatusRow(
            detection: TrainingDetectionStatus.searching,
            propLabel: 'Bottle',
            postureLabel: 'Posture stable',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Searching for bottle'), findsOneWidget);
      expect(find.text('Posture stable'), findsOneWidget);
    });

    testWidgets('searching pulse toggles without ticker errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return Column(
                children: [
                  TrainingStatusRow(
                    detection: _searchingForTest
                        ? TrainingDetectionStatus.searching
                        : TrainingDetectionStatus.detected,
                    propLabel: 'Bottle',
                  ),
                  Button(
                    onPressed: () =>
                        setState(() => _searchingForTest = !_searchingForTest),
                    child: const Text('Toggle'),
                  ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Toggle'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('light and dark themes build without exceptions', (
      tester,
    ) async {
      for (final brightness in [Brightness.dark, Brightness.light]) {
        await tester.pumpWidget(
          _wrap(
            Column(
              children: [
                TrainingConnectionBadge(
                  state: WebSocketConnectionState.connected,
                ),
                const TrainingPerformanceBar(total: null),
                TrainingSessionHeader(
                  onBack: () {},
                  title: 'Hand Stall',
                  statusPill: 'Easy',
                  instruction: 'Hold steady.',
                  connectionState: WebSocketConnectionState.connected,
                  wideLayout: true,
                ),
              ],
            ),
            brightness: brightness,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });
  });
}
