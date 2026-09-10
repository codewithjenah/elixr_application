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
            elapsedDisplay: '00:10',
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
}
