import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/coaching/session_recommendation.dart';
import 'package:elixr_application/features/practice/practice_feedback_controller.dart';
import 'package:elixr_application/features/practice/session_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeFeedback _frame({
  String feedback = 'Keep the bottle upright on your palm.',
  String feedbackType = 'warning',
  String? feedbackCode = 'prop_not_upright',
  String? feedbackCategory = 'technique',
  int holdTargetMs = 2500,
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Hand Stall',
    score: 70,
    feedback: feedback,
    feedbackType: feedbackType,
    postureStatus: feedbackType == 'positive' ? 'stable' : 'unstable',
    sessionState: 'active',
    feedbackCode: feedbackCode,
    feedbackCategory: feedbackCategory,
    holdTargetMs: holdTargetMs,
  );
}

void main() {
  group('buildSessionRecommendation', () {
    test('dominant technique issue drives focus', () {
      final recommendation = buildSessionRecommendation(
        movement: 'Hand Stall',
        prop: TrainingProp.bottle,
        heldSteady: false,
        finalScore: 70,
        positiveRatio: 0.5,
        totalApplicableSamples: 20,
        improvements: [
          SessionImprovement(
            message: 'Keep the bottle upright on your palm.',
            occurrenceCount: 5,
            occurrenceRatio: 0.25,
            feedbackType: 'warning',
            representativeFeedback: _frame(),
            code: 'prop_not_upright',
          ),
        ],
        maxHoldDurationMs: 800,
        maxHoldProgress: 0.3,
        holdTargetMs: 2500,
      );

      expect(recommendation.movementName, 'Hand Stall');
      expect(recommendation.reason, 'Focus: Keep the bottle upright');
      expect(recommendation.targetUsesHoldMs, isTrue);
      expect(recommendation.targetLabel, contains('2.5'));
    });

    test('shaker Hand Stall uses cocktail-shaker wording', () {
      final recommendation = buildSessionRecommendation(
        movement: 'Hand Stall',
        prop: TrainingProp.shaker,
        heldSteady: false,
        finalScore: 70,
        positiveRatio: 0.5,
        totalApplicableSamples: 20,
        improvements: [
          SessionImprovement(
            message: 'Keep the cocktail shaker upright on your palm.',
            occurrenceCount: 5,
            occurrenceRatio: 0.25,
            feedbackType: 'warning',
            representativeFeedback: _frame(
              feedback: 'Keep the cocktail shaker upright on your palm.',
            ),
            code: 'prop_not_upright',
          ),
        ],
        maxHoldDurationMs: 800,
        maxHoldProgress: 0.3,
        holdTargetMs: 2500,
      );

      expect(recommendation.movementName, 'Hand Stall');
      expect(recommendation.reason, 'Focus: Keep the cocktail shaker upright');
      expect(recommendation.reason.toLowerCase(), isNot(contains('bottle')));
    });

    test('missing target produces nonnumeric confirmed-hold wording', () {
      final recommendation = buildSessionRecommendation(
        movement: 'Hand Stall',
        prop: TrainingProp.bottle,
        heldSteady: false,
        finalScore: 60,
        positiveRatio: 0.4,
        totalApplicableSamples: 10,
        improvements: const [],
        maxHoldDurationMs: 0,
        maxHoldProgress: 0,
        holdTargetMs: 0,
      );

      expect(recommendation.targetLabel, 'Complete one confirmed hold');
      expect(recommendation.targetUsesHoldMs, isFalse);
      expect(recommendation.movementName, 'Hand Stall');
    });

    test('no issue produces generic same-movement recommendation', () {
      final recommendation = buildSessionRecommendation(
        movement: 'Hand Stall',
        prop: TrainingProp.bottle,
        heldSteady: true,
        finalScore: 90,
        positiveRatio: 0.85,
        totalApplicableSamples: 30,
        improvements: const [],
        maxHoldDurationMs: 2500,
        maxHoldProgress: 1,
        holdTargetMs: 2500,
      );

      expect(recommendation.movementName, 'Hand Stall');
      expect(recommendation.reason.toLowerCase(), contains('hand stall'));
      expect(recommendation.movementName, isNot(equals('Normal Grip')));
    });

    test('low data produces neutral same-movement fallback', () {
      final recommendation = buildSessionRecommendation(
        movement: 'Hand Stall',
        prop: TrainingProp.bottle,
        heldSteady: false,
        finalScore: 70,
        positiveRatio: 0,
        totalApplicableSamples: 0,
        improvements: const [],
        maxHoldDurationMs: 0,
        maxHoldProgress: 0,
        holdTargetMs: 0,
      );

      expect(recommendation.movementName, 'Hand Stall');
      expect(recommendation.reason.toLowerCase(), contains('gather'));
    });

    test('output is deterministic', () {
      SessionRecommendation build() => buildSessionRecommendation(
        movement: 'Hand Stall',
        prop: TrainingProp.bottle,
        heldSteady: false,
        finalScore: 72,
        positiveRatio: 0.55,
        totalApplicableSamples: 20,
        improvements: [
          SessionImprovement(
            message: 'Keep the bottle upright on your palm.',
            occurrenceCount: 5,
            occurrenceRatio: 0.25,
            feedbackType: 'warning',
            representativeFeedback: _frame(),
            code: 'prop_not_upright',
          ),
        ],
        maxHoldDurationMs: 900,
        maxHoldProgress: 0.35,
        holdTargetMs: 2500,
      );

      final first = build();
      final second = build();
      expect(first.movementName, second.movementName);
      expect(first.reason, second.reason);
      expect(first.targetLabel, second.targetLabel);
      expect(
        first.recommendedDurationSeconds,
        second.recommendedDurationSeconds,
      );
    });

    test('Normal Grip uses config focus copy and duration', () {
      final recommendation = buildSessionRecommendation(
        movement: 'Normal Grip',
        prop: TrainingProp.bottle,
        heldSteady: false,
        finalScore: 65,
        positiveRatio: 0.4,
        totalApplicableSamples: 20,
        improvements: [
          SessionImprovement(
            message: 'Rotate your wrist into an overhand grip.',
            occurrenceCount: 5,
            occurrenceRatio: 0.25,
            feedbackType: 'warning',
            representativeFeedback: _frame(
              feedback: 'Rotate your wrist into an overhand grip.',
              feedbackCode: 'overhand_grip_required',
            ),
            code: 'overhand_grip_required',
          ),
        ],
        maxHoldDurationMs: 500,
        maxHoldProgress: 0.2,
        holdTargetMs: 2500,
      );

      expect(recommendation.movementName, 'Normal Grip');
      expect(
        recommendation.reason,
        'Focus: Rotate your wrist into an overhand grip',
      );
      expect(recommendation.recommendedDurationSeconds, 120);
    });

    test('Bottle in a tin recommendation stays same-movement', () {
      final recommendation = buildSessionRecommendation(
        movement: 'Bottle in a tin',
        prop: TrainingProp.bottleAndShaker,
        heldSteady: false,
        finalScore: 55,
        positiveRatio: 0.3,
        totalApplicableSamples: 20,
        improvements: [
          SessionImprovement(
            message: 'Hold the cocktail shaker horizontally.',
            occurrenceCount: 6,
            occurrenceRatio: 0.3,
            feedbackType: 'warning',
            representativeFeedback: _frame(
              feedback: 'Hold the cocktail shaker horizontally.',
              feedbackCode: 'shaker_not_horizontal',
            ),
            code: 'shaker_not_horizontal',
          ),
        ],
        maxHoldDurationMs: 400,
        maxHoldProgress: 0.15,
        holdTargetMs: 2500,
      );

      expect(recommendation.movementName, 'Bottle in a tin');
      expect(
        recommendation.reason,
        'Focus: Hold the cocktail shaker horizontally',
      );
      expect(recommendation.recommendedDurationSeconds, 180);
    });

    test('Double Hand Stall recommendation stays same-movement', () {
      final recommendation = buildSessionRecommendation(
        movement: 'Double Hand Stall',
        prop: TrainingProp.bottle,
        heldSteady: false,
        finalScore: 60,
        positiveRatio: 0.35,
        totalApplicableSamples: 20,
        improvements: [
          SessionImprovement(
            message: 'Position one bottle directly above each palm.',
            occurrenceCount: 6,
            occurrenceRatio: 0.3,
            feedbackType: 'warning',
            representativeFeedback: _frame(
              feedback: 'Position one bottle directly above each palm.',
              feedbackCode: 'bottles_not_one_per_palm',
            ),
            code: 'bottles_not_one_per_palm',
          ),
        ],
        maxHoldDurationMs: 500,
        maxHoldProgress: 0.2,
        holdTargetMs: 2500,
      );

      expect(recommendation.movementName, 'Double Hand Stall');
      expect(
        recommendation.reason,
        'Focus: Position one bottle directly above each palm',
      );
      expect(recommendation.movementName, isNot(equals('Hand Stall')));
    });

    test('bottle-only Normal Grip never recommends another movement', () {
      final recommendation = buildSessionRecommendation(
        movement: 'Normal Grip',
        prop: TrainingProp.bottle,
        heldSteady: true,
        finalScore: 90,
        positiveRatio: 0.9,
        totalApplicableSamples: 30,
        improvements: const [],
        maxHoldDurationMs: 2500,
        maxHoldProgress: 1,
        holdTargetMs: 2500,
      );
      expect(recommendation.movementName, 'Normal Grip');
      expect(recommendation.reason.toLowerCase(), contains('normal grip'));
    });

    test('every enabled movement recommends itself only', () {
      const movements = [
        'Normal Grip',
        "Bartender's Grip",
        'Reverse Grip',
        'Claw Grip',
        'Hand Stall',
        'One Finger Stall',
        'Forearm Stall',
        'Elbow Stall',
        'Reverse Forearm Stall',
        'Shoulder Stall',
        'Double Hand Stall',
        'Bottle in a tin',
      ];
      for (final movement in movements) {
        final recommendation = buildSessionRecommendation(
          movement: movement,
          prop: TrainingProp.bottle,
          heldSteady: false,
          finalScore: 70,
          positiveRatio: 0.5,
          totalApplicableSamples: 10,
          improvements: const [],
          maxHoldDurationMs: 0,
          maxHoldProgress: 0,
          holdTargetMs: 2500,
        );
        expect(recommendation.movementName, movement);
        for (final other in movements) {
          if (other == movement) continue;
          expect(
            recommendation.movementName,
            isNot(equals(other)),
            reason: '$movement must not recommend $other',
          );
        }
      }
    });
  });

  group('PracticeFeedbackController movement plumbing', () {
    test(
      'selected movement and prop propagate into coaching recommendation',
      () {
        final controller = PracticeFeedbackController();
        for (var i = 0; i < 4; i++) {
          controller.applyActiveFeedback(
            _frame(
              feedback: 'Keep the cocktail shaker upright on your palm.',
              feedbackCode: 'prop_not_upright',
            ),
          );
        }
        for (var i = 0; i < 10; i++) {
          controller.applyActiveFeedback(
            _frame(
              feedback: 'Hand stall locked in.',
              feedbackType: 'positive',
              feedbackCode: 'hand_stall_locked',
            ),
          );
        }

        final assessment = controller.buildSessionAssessment(
          movement: 'Hand Stall',
          prop: TrainingProp.shaker,
          finalScore: 78,
          heldSteady: false,
        );

        expect(assessment.coaching.recommendation, isNotNull);
        expect(assessment.coaching.recommendation!.movementName, 'Hand Stall');
        expect(
          assessment.coaching.recommendation!.reason,
          'Focus: Keep the cocktail shaker upright',
        );
        expect(
          assessment.coaching.recommendation!.reason.toLowerCase(),
          isNot(contains('bottle')),
        );
      },
    );
  });
}
