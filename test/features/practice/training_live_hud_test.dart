import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/features/practice/practice_feedback_controller.dart';
import 'package:elixr_application/features/practice/widgets/training_live_hud.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeFeedback _coaching({
  required String feedbackType,
  required String postureStatus,
  String? feedbackCategory,
  String? feedbackCode,
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Hand Stall',
    feedback: 'Live coaching message.',
    feedbackType: feedbackType,
    postureStatus: postureStatus,
    feedbackCategory: feedbackCategory,
    feedbackCode: feedbackCode,
  );
}

void main() {
  testWidgets('scored HUD exposes each coaching verdict with a distinct cue', (
    tester,
  ) async {
    final assessment = ValueNotifier<RubricAssessment?>(null);
    final hold = ValueNotifier(0.0);
    final combo = ValueNotifier(const ComboState());
    final score = ValueNotifier(const ScorePopupState());
    final callout = ValueNotifier(const PerformanceCalloutState());
    addTearDown(assessment.dispose);
    addTearDown(hold.dispose);
    addTearDown(combo.dispose);
    addTearDown(score.dispose);
    addTearDown(callout.dispose);

    Widget build(PracticeFeedback coaching) => FluentApp(
      theme: AppTheme.highContrastDark,
      home: ScaffoldPage(
        content: SizedBox(
          width: 640,
          height: 480,
          child: TrainingLiveHud(
            assessmentListenable: assessment,
            holdListenable: hold,
            comboListenable: combo,
            scorePopupListenable: score,
            calloutListenable: callout,
            coaching: coaching,
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      build(_coaching(feedbackType: 'positive', postureStatus: 'stable')),
    );
    expect(find.text('Correct'), findsOneWidget);
    expect(find.byIcon(FluentIcons.status_circle_checkmark), findsOneWidget);

    await tester.pumpWidget(
      build(_coaching(feedbackType: 'warning', postureStatus: 'unstable')),
    );
    expect(find.text('Wrong'), findsOneWidget);
    expect(find.byIcon(FluentIcons.warning), findsOneWidget);

    await tester.pumpWidget(
      build(
        _coaching(
          feedbackType: 'error',
          postureStatus: 'unknown',
          feedbackCategory: 'visibility',
          feedbackCode: 'hands_not_visible',
        ),
      ),
    );
    expect(find.text("Can't determine"), findsOneWidget);
    expect(find.byIcon(FluentIcons.info_solid), findsOneWidget);
    expect(
      find.text('Keep your hands, prop, and upper body clearly visible.'),
      findsOneWidget,
    );
    expect(find.text('Wrong'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('HUD does not render a timer', (tester) async {
    final assessment = ValueNotifier<RubricAssessment?>(null);
    final hold = ValueNotifier(0.0);
    final combo = ValueNotifier(const ComboState());
    final score = ValueNotifier(const ScorePopupState());
    final callout = ValueNotifier(const PerformanceCalloutState());
    addTearDown(assessment.dispose);
    addTearDown(hold.dispose);
    addTearDown(combo.dispose);
    addTearDown(score.dispose);
    addTearDown(callout.dispose);

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: SizedBox(
            width: 640,
            height: 480,
            child: TrainingLiveHud(
              assessmentListenable: assessment,
              holdListenable: hold,
              comboListenable: combo,
              scorePopupListenable: score,
              calloutListenable: callout,
            ),
          ),
        ),
      ),
    );

    expect(find.text('TIME LEFT'), findsNothing);
    expect(find.text('TIME LEFT · HURRY'), findsNothing);
    expect(find.text('00:09'), findsNothing);
    expect(find.text('RUBRIC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('motion cue badge follows backend cue and hides when cleared', (
    tester,
  ) async {
    final assessment = ValueNotifier<RubricAssessment?>(null);
    final hold = ValueNotifier(0.0);
    final combo = ValueNotifier(const ComboState());
    final score = ValueNotifier(const ScorePopupState());
    final callout = ValueNotifier(const PerformanceCalloutState());
    final cue = ValueNotifier<MotionCue?>(null);
    for (final n in [assessment, hold, combo, score, callout, cue]) {
      addTearDown(n.dispose);
    }

    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: SizedBox(
            width: 640,
            height: 480,
            child: TrainingLiveHud(
              assessmentListenable: assessment,
              holdListenable: hold,
              comboListenable: combo,
              scorePopupListenable: score,
              calloutListenable: callout,
              motionCueListenable: cue,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(MotionCueBadge), findsNothing);

    cue.value = const MotionCue(kind: MotionEventKind.airborne, sequence: 1);
    await tester.pumpAndSettle();
    expect(find.text('AIRBORNE'), findsOneWidget);

    cue.value = const MotionCue(kind: MotionEventKind.flip, sequence: 2);
    await tester.pumpAndSettle();
    expect(find.text('FLIP DETECTED'), findsOneWidget);
    expect(find.text('AIRBORNE'), findsNothing);

    cue.value = null;
    await tester.pumpAndSettle();
    expect(find.byType(MotionCueBadge), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('PracticeFeedback motion_event parsing', () {
    Map<String, dynamic> base() => {
      'bottle_detected': true,
      'movement': 'Hand Stall',
      'feedback': 'ok',
      'feedback_type': 'positive',
      'posture_status': 'stable',
    };

    test('absent fields parse as null', () {
      final f = PracticeFeedback.fromJson(base());
      expect(f.motionEvent, isNull);
      expect(MotionCue.fromFeedback(f), isNull);
    });

    test('valid fields parse into a cue', () {
      final f = PracticeFeedback.fromJson({
        ...base(),
        'motion_event': 'caught',
        'motion_event_confidence': 0.72,
        'motion_event_sequence': 4,
      });
      expect(f.motionEvent, MotionEventKind.caught);
      expect(f.motionEventConfidence, 0.72);
      expect(
        MotionCue.fromFeedback(f),
        const MotionCue(kind: MotionEventKind.caught, sequence: 4),
      );
    });

    test('unknown or malformed values are ignored', () {
      final f = PracticeFeedback.fromJson({
        ...base(),
        'motion_event': 'spin',
        'motion_event_confidence': 'high',
        'motion_event_sequence': '4',
      });
      expect(f.motionEvent, isNull);
      expect(f.motionEventConfidence, isNull);
      expect(f.motionEventSequence, isNull);
    });
  });
}
