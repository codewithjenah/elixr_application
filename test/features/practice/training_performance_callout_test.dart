import 'package:elixr_application/data/models/assessment_score_display.dart';
import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/practice_feedback_controller.dart';
import 'package:elixr_application/features/practice/practice_game_widgets.dart';
import 'package:elixr_application/features/practice/widgets/training_performance.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

RubricAssessment _rubric(int total) {
  final scores = <int>[0, 0, 0, 0];
  var remaining = total;
  for (var i = 0; i < scores.length && remaining > 0; i++) {
    scores[i] = remaining >= 3 ? 3 : remaining;
    remaining -= scores[i];
  }
  return RubricAssessment(
    technique: scores[0],
    stability: scores[1],
    completion: scores[2],
    propPositioning: scores[3],
  );
}

PracticeFeedback _feedback({int? total}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Hand Stall',
    assessment: total == null ? null : _rubric(total),
    feedback: 'Hold steady',
    feedbackType: 'positive',
    postureStatus: 'stable',
    propType: TrainingProp.bottle,
    sessionState: 'active',
  );
}

void main() {
  test('callout copy is derived from PerformanceLevel only', () {
    expect(
      performanceCalloutCopy(PerformanceLevel.mastered)?.headline,
      'PERFECT!',
    );
    expect(
      performanceCalloutCopy(PerformanceLevel.proficient)?.headline,
      'GREAT!',
    );
    expect(
      performanceCalloutCopy(PerformanceLevel.competent)?.headline,
      'GOOD!',
    );
    expect(
      performanceCalloutCopy(PerformanceLevel.developing)?.headline,
      'KEEP GOING',
    );
    expect(
      performanceCalloutCopy(PerformanceLevel.beginning)?.headline,
      'STAY FOCUSED',
    );
    expect(performanceCalloutCopy(null), isNull);
    expect(
      performanceCalloutCopy(PerformanceLevel.mastered)?.detail,
      AssessmentScoreDisplay.performanceLabel(PerformanceLevel.mastered),
    );
  });

  test('PERFECT is only produced for Mastered assessments', () {
    const mastered = RubricAssessment(
      technique: 3,
      stability: 3,
      completion: 3,
      propPositioning: 3,
    );
    const proficient = RubricAssessment(
      technique: 3,
      stability: 3,
      completion: 3,
      propPositioning: 2,
    );
    expect(mastered.performanceLevel, PerformanceLevel.mastered);
    expect(
      performanceCalloutCopy(mastered.performanceLevel)?.headline,
      'PERFECT!',
    );
    expect(proficient.performanceLevel, isNot(PerformanceLevel.mastered));
    expect(
      performanceCalloutCopy(proficient.performanceLevel)?.headline,
      isNot('PERFECT!'),
    );
  });

  test('controller triggers callouts on level transitions only', () {
    final controller = PracticeFeedbackController();

    final none = controller.applyActiveFeedback(_feedback());
    expect(none.calloutChanged, isFalse);
    expect(controller.calloutState.level, isNull);

    final beginning = controller.applyActiveFeedback(_feedback(total: 2));
    expect(beginning.calloutChanged, isTrue);
    expect(controller.calloutState.level, PerformanceLevel.beginning);
    expect(controller.calloutState.trigger, 1);

    final sameLevel = controller.applyActiveFeedback(_feedback(total: 3));
    expect(sameLevel.calloutChanged, isFalse);
    expect(controller.calloutState.trigger, 1);

    final identical = controller.applyActiveFeedback(_feedback(total: 3));
    expect(identical.calloutChanged, isFalse);
    expect(identical.assessmentChanged, isFalse);

    final proficient = controller.applyActiveFeedback(_feedback(total: 11));
    expect(proficient.calloutChanged, isTrue);
    expect(controller.calloutState.level, PerformanceLevel.proficient);
    expect(controller.calloutState.trigger, 2);

    final mastered = controller.applyActiveFeedback(_feedback(total: 12));
    expect(mastered.calloutChanged, isTrue);
    expect(controller.calloutState.level, PerformanceLevel.mastered);
    expect(controller.calloutState.total, 12);
  });

  testWidgets('Mastered assessment can present PERFECT', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: ScaffoldPage(
          content: PerformanceCallout(
            trigger: 1,
            level: PerformanceLevel.mastered,
            total: 12,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('PERFECT!'), findsOneWidget);
    expect(find.textContaining('Mastered'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('training-performance-callout')),
      findsOneWidget,
    );
  });

  testWidgets('lower levels present matching labels without PERFECT', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: ScaffoldPage(
          content: PerformanceCallout(
            trigger: 1,
            level: PerformanceLevel.proficient,
            total: 11,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('GREAT!'), findsOneWidget);
    expect(find.text('PERFECT!'), findsNothing);
  });

  testWidgets('null assessment does not fabricate a performance result', (
    tester,
  ) async {
    await tester.pumpWidget(
      const FluentApp(
        home: ScaffoldPage(
          content: PerformanceCallout(trigger: 0, level: null),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('PERFECT!'), findsNothing);
    expect(find.text('GREAT!'), findsNothing);
    expect(find.text('GOOD!'), findsNothing);
    expect(
      find.byKey(const ValueKey('training-performance-callout')),
      findsNothing,
    );
  });
}
