import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/rubric_assessment.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/coaching/coaching_config.dart';
import 'package:elixr_application/features/practice/session_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

const _defaultRubric = RubricAssessment(
  technique: 2,
  stability: 2,
  completion: 2,
  propPositioning: 2,
);

const _perfectRubric = RubricAssessment(
  technique: 3,
  stability: 3,
  completion: 3,
  propPositioning: 3,
);

PracticeFeedback _frame({
  String feedback = 'Keep steady',
  String feedbackType = 'warning',
  RubricAssessment? assessment,
  String? sessionState = 'active',
  String? errorCode,
  String? feedbackCode,
  String? feedbackCategory,
  double holdProgress = 0,
  int holdDurationMs = 0,
  int holdTargetMs = 0,
  bool holdConfirmed = false,
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Hand Stall',
    assessment: assessment,
    feedback: feedback,
    feedbackType: feedbackType,
    postureStatus: feedbackType == 'positive' ? 'stable' : 'unstable',
    sessionState: sessionState,
    errorCode: errorCode,
    feedbackCode: feedbackCode,
    feedbackCategory: feedbackCategory,
    holdProgress: holdProgress,
    holdDurationMs: holdDurationMs,
    holdTargetMs: holdTargetMs,
    holdConfirmed: holdConfirmed,
  );
}

void _recordFrames(
  SessionAssessmentAccumulator accumulator,
  int count, {
  required PracticeFeedback frame,
}) {
  for (var i = 0; i < count; i++) {
    accumulator.record(frame);
  }
}

SessionAssessment _build(
  SessionAssessmentAccumulator accumulator, {
  String movement = 'Hand Stall',
  TrainingProp prop = TrainingProp.bottle,
  RubricAssessment rubric = _defaultRubric,
  bool heldSteady = false,
  PracticeFeedback? latestFeedback,
}) {
  return accumulator.buildAssessment(
    movement: movement,
    prop: prop,
    rubric: rubric,
    heldSteady: heldSteady,
    latestFeedback: latestFeedback,
  );
}

void main() {
  group('SessionAssessmentAccumulator', () {
    test(
      'confirmed 12/12 session retains persistent technique improvements',
      () {
        final accumulator = SessionAssessmentAccumulator();
        _recordFrames(
          accumulator,
          5,
          frame: _frame(
            feedback: 'Keep the bottle upright on your palm.',
            feedbackCode: 'prop_not_upright',
            feedbackCategory: 'technique',
          ),
        );
        _recordFrames(
          accumulator,
          20,
          frame: _frame(
            feedback: 'Hand stall locked in.',
            feedbackType: 'positive',
            feedbackCode: 'hand_stall_locked',
            feedbackCategory: 'technique',
          ),
        );

        final assessment = _build(
          accumulator,
          rubric: _perfectRubric,
          heldSteady: true,
          latestFeedback: _frame(
            feedback: 'Hand stall locked in.',
            feedbackType: 'positive',
            feedbackCode: 'hand_stall_locked',
            feedbackCategory: 'technique',
            assessment: _perfectRubric,
          ),
        );

        expect(assessment.improvements, hasLength(1));
        expect(assessment.improvements.single.code, 'prop_not_upright');
        expect(assessment.coaching.strengths, hasLength(1));
        expect(
          assessment.coaching.strengths.single.code,
          SessionAssessmentAccumulator.handStallConfirmedCode,
        );
        expect(
          assessment.coaching.strengths.single.message,
          SessionAssessmentAccumulator.handStallConfirmedStrengthMessage,
        );
        expect(
          assessment.coaching.strengths.any(
            (s) => s.code == 'hand_stall_locked',
          ),
          isFalse,
        );
      },
    );

    test('one transient warning is excluded', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        1,
        frame: _frame(
          feedback: 'Lower your elbow',
          feedbackCode: 'legacy_elbow',
          feedbackCategory: 'technique',
        ),
      );
      _recordFrames(
        accumulator,
        10,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator);
      expect(assessment.improvements, isEmpty);
    });

    test('recurring technique warning meeting thresholds is included', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Keep the bottle upright on your palm.',
          feedbackCode: 'prop_not_upright',
          feedbackCategory: 'technique',
        ),
      );
      _recordFrames(
        accumulator,
        16,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator);
      expect(assessment.improvements, hasLength(1));
      expect(assessment.improvements.single.code, 'prop_not_upright');
      expect(assessment.improvements.single.sampleCount, 4);
      expect(assessment.improvements.single.sampleRatio, closeTo(0.2, 0.001));
      expect(assessment.improvements.single.occurrenceCount, 4);
    });

    test('visibility and environment categories are excluded', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        10,
        frame: _frame(
          feedbackType: 'positive',
          feedback: 'Hand stall locked in.',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );
      _recordFrames(
        accumulator,
        8,
        frame: _frame(
          feedback: 'Keep your hand fully visible.',
          feedbackCode: 'hand_not_fully_visible',
          feedbackCategory: 'visibility',
        ),
      );
      _recordFrames(
        accumulator,
        8,
        frame: _frame(
          feedback: 'Bottle not detected. Keep the bottle visible.',
          feedbackCode: 'prop_not_detected',
          feedbackCategory: 'environment',
          feedbackType: 'error',
        ),
      );

      final assessment = _build(accumulator);
      expect(assessment.improvements, isEmpty);
      expect(assessment.positiveSampleCount, 10);
    });

    test('unknown non-null category is excluded safely', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        10,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );
      _recordFrames(
        accumulator,
        8,
        frame: _frame(
          feedback: 'Mysterious future category message.',
          feedbackCode: 'future_code',
          feedbackCategory: 'calibration',
        ),
      );

      final assessment = _build(accumulator);
      expect(assessment.improvements, isEmpty);
      expect(assessment.totalApplicableSamples, 10);
    });

    test('technique category is included', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Keep the bottle upright on your palm.',
          feedbackCode: 'prop_not_upright',
          feedbackCategory: 'technique',
        ),
      );
      _recordFrames(
        accumulator,
        10,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator);
      expect(assessment.improvements.single.code, 'prop_not_upright');
    });

    test('legacy phrase-based environment exclusion still works', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        10,
        frame: _frame(feedbackType: 'positive', feedback: 'Nice form'),
      );
      _recordFrames(
        accumulator,
        5,
        frame: _frame(feedback: 'Keep the bottle visible in frame'),
      );
      _recordFrames(
        accumulator,
        4,
        frame: _frame(feedback: 'Wrap fingers around the neck.'),
      );

      final assessment = _build(accumulator);
      expect(assessment.improvements, hasLength(1));
      expect(
        assessment.improvementMessages,
        isNot(contains('Keep the bottle visible in frame')),
      );
    });

    test('unconfirmed Hand Stall form strength uses supportive wording', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        12,
        frame: _frame(
          feedback: 'Hand stall locked in.',
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Keep the bottle upright on your palm.',
          feedbackCode: 'prop_not_upright',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator, heldSteady: false);
      final formStrength = assessment.coaching.strengths.singleWhere(
        (s) => s.code == 'hand_stall_locked',
      );
      expect(
        formStrength.message,
        SessionAssessmentAccumulator.handStallFormStrengthMessage,
      );
      expect(formStrength.message.toLowerCase(), isNot(contains('confirmed')));
      expect(formStrength.sampleCount, 12);
    });

    test(
      'locked positive code uses profile form strength not raw feedback',
      () {
        final accumulator = SessionAssessmentAccumulator();
        _recordFrames(
          accumulator,
          20,
          frame: _frame(
            feedback: 'Hand stall locked in.',
            feedbackType: 'positive',
            feedbackCode: 'hand_stall_locked',
            feedbackCategory: 'technique',
          ),
        );

        final assessment = _build(accumulator, heldSteady: false);
        final formStrength = assessment.coaching.strengths.singleWhere(
          (s) => s.code == 'hand_stall_locked',
        );
        expect(formStrength.message, formStrengthMessageFor('Hand Stall'));
        expect(formStrength.message, isNot(contains('Hand stall locked in')));
      },
    );

    test('only top 3 persistent issues are returned', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        6,
        frame: _frame(feedback: 'Issue A', feedbackCategory: 'technique'),
      );
      _recordFrames(
        accumulator,
        5,
        frame: _frame(feedback: 'Issue B', feedbackCategory: 'technique'),
      );
      _recordFrames(
        accumulator,
        4,
        frame: _frame(feedback: 'Issue C', feedbackCategory: 'technique'),
      );
      _recordFrames(
        accumulator,
        3,
        frame: _frame(feedback: 'Issue D', feedbackCategory: 'technique'),
      );
      _recordFrames(
        accumulator,
        2,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator);
      expect(assessment.improvements, hasLength(3));
      expect(assessment.improvementMessages, ['Issue A', 'Issue B', 'Issue C']);
    });

    test('dominant warning outranks a less frequent error', () {
      final accumulator = SessionAssessmentAccumulator();
      // Total applicable = 20. Warning 8/20 = 0.40, error 4/20 = 0.20.
      _recordFrames(
        accumulator,
        8,
        frame: _frame(
          feedback: 'Keep the bottle upright on your palm.',
          feedbackCode: 'prop_not_upright',
          feedbackCategory: 'technique',
          feedbackType: 'warning',
        ),
      );
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Open your palm and extend your fingers.',
          feedbackCode: 'palm_not_open',
          feedbackCategory: 'technique',
          feedbackType: 'error',
        ),
      );
      _recordFrames(
        accumulator,
        8,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator);
      expect(assessment.improvements.first.code, 'prop_not_upright');
      expect(assessment.improvements.first.feedbackType, 'warning');
      expect(assessment.improvements[1].code, 'palm_not_open');
      expect(assessment.improvements[1].feedbackType, 'error');
    });

    test('ratio ties use sample count then severity then code', () {
      final accumulator = SessionAssessmentAccumulator();
      // Force equal ratios by using the same counts for two codes, then a
      // third with equal ratio but lower severity for the severity tie-break.
      // Total = 20. A and B both 4/20 = 0.20.
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Hold the bottle steady on your open palm.',
          feedbackCode: 'prop_not_steady',
          feedbackCategory: 'technique',
          feedbackType: 'warning',
        ),
      );
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Keep the bottle upright on your palm.',
          feedbackCode: 'prop_not_upright',
          feedbackCategory: 'technique',
          feedbackType: 'warning',
        ),
      );
      _recordFrames(
        accumulator,
        12,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator);
      // Equal ratio and count → severity equal → alphabetical code order.
      expect(assessment.improvements.map((i) => i.code).toList(), [
        'prop_not_steady',
        'prop_not_upright',
      ]);
    });

    test('ratio and count ties use severity as later tie-breaker', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Warning issue',
          feedbackCode: 'code_a',
          feedbackCategory: 'technique',
          feedbackType: 'warning',
        ),
      );
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Error issue',
          feedbackCode: 'code_b',
          feedbackCategory: 'technique',
          feedbackType: 'error',
        ),
      );
      _recordFrames(
        accumulator,
        12,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator);
      expect(assessment.improvements.first.feedbackType, 'error');
      expect(assessment.improvements.first.code, 'code_b');
    });

    test('reset clears all accumulated coaching state', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        5,
        frame: _frame(
          feedback: 'Issue A',
          feedbackCategory: 'technique',
          holdDurationMs: 1200,
          holdProgress: 0.5,
          holdTargetMs: 2500,
        ),
      );
      accumulator.reset();

      expect(accumulator.totalApplicableSamples, 0);
      expect(accumulator.positiveSampleCount, 0);
      expect(accumulator.maxHoldDurationMs, 0);
      expect(accumulator.maxHoldProgress, 0);
      expect(accumulator.holdTargetMs, 0);

      final assessment = _build(accumulator);
      expect(assessment.improvements, isEmpty);
      expect(assessment.coaching.strengths, isEmpty);
    });

    test('confirmed Hand Stall emits exactly one success strength', () {
      final accumulator = SessionAssessmentAccumulator();
      accumulator.record(
        _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
          holdProgress: 1.0,
          holdDurationMs: 2500,
          holdTargetMs: 2500,
          holdConfirmed: true,
        ),
      );
      _recordFrames(
        accumulator,
        5,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
          holdProgress: 1.0,
          holdDurationMs: 2500,
          holdTargetMs: 2500,
        ),
      );

      final assessment = _build(accumulator, heldSteady: true);
      expect(assessment.coaching.strengths, hasLength(1));
      expect(
        assessment.coaching.strengths.single.message,
        SessionAssessmentAccumulator.handStallConfirmedStrengthMessage,
      );
      expect(
        assessment.coaching.strengths.single.evidenceKind,
        'holdConfirmed',
      );
      expect(
        assessment.coaching.strengths.any((s) => s.code == 'hand_stall_locked'),
        isFalse,
      );
      expect(
        assessment.coaching.strengths.any((s) => s.code == 'hold_confirmed'),
        isFalse,
      );
      expect(
        assessment.coaching.strengths.any(
          (s) => s.evidenceKind == 'holdExceptionalDuration',
        ),
        isFalse,
      );
    });

    test('synthetic duration above target does not claim exceptional hold', () {
      final accumulator = SessionAssessmentAccumulator();
      accumulator.record(
        _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
          holdProgress: 1.0,
          holdDurationMs: 3200,
          holdTargetMs: 2500,
        ),
      );

      final assessment = _build(accumulator, heldSteady: true);
      expect(assessment.coaching.strengths, hasLength(1));
      expect(
        assessment.coaching.strengths.single.evidenceKind,
        'holdConfirmed',
      );
      expect(
        assessment.coaching.strengths.single.message.toLowerCase(),
        isNot(contains('best hold')),
      );
      expect(
        assessment.coaching.strengths.any(
          (s) => s.evidenceKind == 'holdExceptionalDuration',
        ),
        isFalse,
      );
    });

    test('unconfirmed short attempt produces no hold strength', () {
      final accumulator = SessionAssessmentAccumulator();
      accumulator.record(
        _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
          holdProgress: 0.2,
          holdDurationMs: 400,
          holdTargetMs: 2500,
        ),
      );

      final assessment = _build(accumulator, heldSteady: false);
      expect(
        assessment.coaching.strengths.where((s) => s.code.startsWith('hold_')),
        isEmpty,
      );
    });

    test('unconfirmed progress at least 0.40 produces progress strength', () {
      final accumulator = SessionAssessmentAccumulator();
      accumulator.record(
        _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
          holdProgress: 0.82,
          holdDurationMs: 900,
          holdTargetMs: 2500,
        ),
      );

      final assessment = _build(accumulator, heldSteady: false);
      final hold = assessment.coaching.strengths.singleWhere(
        (s) => s.code.startsWith('hold_'),
      );
      expect(hold.evidenceKind, 'holdPartialProgress');
      expect(hold.message, contains('82%'));
      expect(hold.message.toLowerCase(), isNot(contains('mistakes')));
      expect(hold.message.toLowerCase(), isNot(contains(' times')));
    });

    test(
      'unconfirmed form evidence may coexist with partial hold evidence',
      () {
        final accumulator = SessionAssessmentAccumulator();
        _recordFrames(
          accumulator,
          12,
          frame: _frame(
            feedback: 'Hand stall locked in.',
            feedbackType: 'positive',
            feedbackCode: 'hand_stall_locked',
            feedbackCategory: 'technique',
            holdProgress: 0.5,
            holdDurationMs: 1200,
            holdTargetMs: 2500,
          ),
        );

        final assessment = _build(accumulator, heldSteady: false);
        expect(assessment.coaching.strengths.length, lessThanOrEqualTo(3));
        expect(
          assessment.coaching.strengths.any(
            (s) => s.code == 'hand_stall_locked',
          ),
          isTrue,
        );
        expect(
          assessment.coaching.strengths.any(
            (s) => s.evidenceKind == 'holdPartialProgress',
          ),
          isTrue,
        );
        expect(
          assessment.coaching.strengths.any(
            (s) => s.message.toLowerCase().contains('confirmed'),
          ),
          isFalse,
        );
      },
    );

    test('duration-only fallback requires at least 1000 ms', () {
      final accumulator = SessionAssessmentAccumulator();
      accumulator.record(
        _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
          holdProgress: 0.1,
          holdDurationMs: 1000,
          holdTargetMs: 0,
        ),
      );

      final assessment = _build(accumulator, heldSteady: false);
      expect(
        assessment.coaching.strengths.single.evidenceKind,
        'holdPartialDuration',
      );
    });

    test('conflicting nonzero hold targets keep the first value', () {
      final accumulator = SessionAssessmentAccumulator();
      accumulator.record(_frame(holdTargetMs: 2500, feedbackType: 'positive'));
      accumulator.record(_frame(holdTargetMs: 3000, feedbackType: 'positive'));

      expect(accumulator.holdTargetMs, 2500);
      expect(accumulator.holdTargetHadConflict, isTrue);
      final assessment = _build(accumulator);
      expect(assessment.holdTargetMs, 2500);
    });

    test('production build includes one recommendation for movement', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Keep the bottle upright on your palm.',
          feedbackCode: 'prop_not_upright',
          feedbackCategory: 'technique',
        ),
      );
      _recordFrames(
        accumulator,
        10,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(
        accumulator,
        movement: 'Hand Stall',
        prop: TrainingProp.bottle,
        heldSteady: false,
      );
      final recommendation = assessment.coaching.recommendation;
      expect(recommendation, isNotNull);
      expect(recommendation!.movementName, 'Hand Stall');
      expect(
        recommendation.reason,
        'Focus: Keep the bottle upright. Then keep the bottle upright '
        'over the open palm long enough to complete a confirmed hold.',
      );
    });

    test('shaker prop produces cocktail-shaker recommendation wording', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Keep the cocktail shaker upright on your palm.',
          feedbackCode: 'prop_not_upright',
          feedbackCategory: 'technique',
        ),
      );
      _recordFrames(
        accumulator,
        10,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(
        accumulator,
        prop: TrainingProp.shaker,
        heldSteady: false,
      );
      expect(
        assessment.coaching.recommendation!.reason,
        'Focus: Keep the cocktail shaker upright. Then keep the cocktail '
        'shaker upright over the open palm long enough to complete a '
        'confirmed hold.',
      );
      expect(
        assessment.coaching.recommendation!.reason.toLowerCase(),
        isNot(contains('bottle')),
      );
    });

    test('coaching improvements reuse the same list as assessment', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Keep the bottle upright on your palm.',
          feedbackCode: 'prop_not_upright',
          feedbackCategory: 'technique',
        ),
      );
      _recordFrames(
        accumulator,
        10,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator);
      expect(
        identical(assessment.improvements, assessment.coaching.improvements),
        isTrue,
      );
    });

    test('empty coaching fabricates no recommendation', () {
      const assessment = SessionAssessment(
        rubric: _defaultRubric,
        heldSteady: false,
        totalApplicableSamples: 0,
        positiveSampleCount: 0,
        positiveRatio: 0,
        improvements: [],
      );
      expect(assessment.coaching.isEmpty, isTrue);
      expect(assessment.coaching.recommendation, isNull);
      expect(assessment.coaching.cleanSessionMessage, isNull);
      expect(assessment.improvementMessages, isEmpty);
    });

    test('production assessment populates movement cleanSessionMessage', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        12,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'shoulder_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(
        accumulator,
        movement: 'Shoulder Stall',
        heldSteady: true,
        rubric: _perfectRubric,
      );

      expect(
        assessment.coaching.cleanSessionMessage,
        cleanSessionMessageFor('Shoulder Stall'),
      );
      expect(assessment.coaching.cleanSessionMessage, contains('shoulder'));
    });

    test(
      'Normal Grip confirmed session uses config-driven success strength',
      () {
        final accumulator = SessionAssessmentAccumulator();
        _recordFrames(
          accumulator,
          4,
          frame: _frame(
            feedback: 'Move your hand to the upper bottle neck.',
            feedbackCode: 'hand_not_at_neck',
            feedbackCategory: 'technique',
          ),
        );
        _recordFrames(
          accumulator,
          12,
          frame: _frame(
            feedback: 'Bottle held securely with a full overhand neck grip.',
            feedbackType: 'positive',
            feedbackCode: 'normal_grip_locked',
            feedbackCategory: 'technique',
            assessment: _perfectRubric,
            holdConfirmed: true,
            holdProgress: 1,
            holdDurationMs: 2500,
            holdTargetMs: 2500,
          ),
        );

        final assessment = _build(
          accumulator,
          movement: 'Normal Grip',
          rubric: _perfectRubric,
          heldSteady: true,
        );

        expect(
          assessment.coaching.strengths.any(
            (s) => s.code == 'normal_grip_confirmed',
          ),
          isTrue,
        );
        expect(
          assessment.coaching.strengths.any(
            (s) => s.message == 'Secure overhand neck grip maintained',
          ),
          isTrue,
        );
        expect(
          assessment.coaching.strengths.any(
            (s) => s.code == 'normal_grip_locked',
          ),
          isFalse,
        );
        expect(assessment.coaching.recommendation?.movementName, 'Normal Grip');
      },
    );

    group('Phase C per-movement aggregation', () {
      const cases =
          <
            ({
              String movement,
              String successCode,
              String issueCode,
              String issueMessage,
            })
          >[
            (
              movement: 'Normal Grip',
              successCode: 'normal_grip_locked',
              issueCode: 'overhand_grip_required',
              issueMessage: 'Rotate your wrist into an overhand grip.',
            ),
            (
              movement: "Bartender's Grip",
              successCode: 'bartender_grip_locked',
              issueCode: 'bartender_pinch_required',
              issueMessage:
                  'Secure the neck between your thumb and index finger.',
            ),
            (
              movement: 'Reverse Grip',
              successCode: 'reverse_grip_locked',
              issueCode: 'underhand_grip_required',
              issueMessage: 'Rotate your wrist into a reverse grip.',
            ),
            (
              movement: 'Claw Grip',
              successCode: 'claw_grip_locked',
              issueCode: 'claw_fingers_not_curled',
              issueMessage: 'Curl your fingers downward around the upper neck.',
            ),
            (
              movement: 'Hand Stall',
              successCode: 'hand_stall_locked',
              issueCode: 'prop_not_upright',
              issueMessage: 'Keep the bottle upright on your palm.',
            ),
            (
              movement: 'One Finger Stall',
              successCode: 'one_finger_stall_locked',
              issueCode: 'index_finger_not_extended',
              issueMessage: 'Extend one index finger straight.',
            ),
            (
              movement: 'Forearm Stall',
              successCode: 'forearm_stall_locked',
              issueCode: 'prop_not_positioned_on_target',
              issueMessage: 'Align the bottle over the stall point.',
            ),
            (
              movement: 'Elbow Stall',
              successCode: 'elbow_stall_locked',
              issueCode: 'prop_not_positioned_on_target',
              issueMessage: 'Align the bottle over the stall point.',
            ),
            (
              movement: 'Reverse Forearm Stall',
              successCode: 'reverse_forearm_stall_locked',
              issueCode: 'prop_not_on_reverse_forearm',
              issueMessage: 'Balance the bottle on your reverse forearm.',
            ),
            (
              movement: 'Shoulder Stall',
              successCode: 'shoulder_stall_locked',
              issueCode: 'prop_not_on_shoulder',
              issueMessage: 'Balance the bottle steadily on either shoulder.',
            ),
            (
              movement: 'Double Hand Stall',
              successCode: 'double_hand_stall_locked',
              issueCode: 'bottles_not_one_per_palm',
              issueMessage: 'Position one bottle directly above each palm.',
            ),
            (
              movement: 'Bottle in a tin',
              successCode: 'bottle_in_tin_locked',
              issueCode: 'shaker_not_horizontal',
              issueMessage: 'Hold the cocktail shaker horizontally.',
            ),
          ];

      for (final c in cases) {
        test(
          '${c.movement} aggregates success and dominant technique issue',
          () {
            final accumulator = SessionAssessmentAccumulator();
            _recordFrames(
              accumulator,
              5,
              frame: _frame(
                feedback: c.issueMessage,
                feedbackCode: c.issueCode,
                feedbackCategory: 'technique',
                holdTargetMs: 2500,
              ),
            );
            _recordFrames(
              accumulator,
              12,
              frame: _frame(
                feedback: '${c.movement} locked in.',
                feedbackType: 'positive',
                feedbackCode: c.successCode,
                feedbackCategory: 'technique',
                holdTargetMs: 2500,
              ),
            );

            final assessment = _build(
              accumulator,
              movement: c.movement,
              heldSteady: false,
            );

            expect(assessment.coaching.improvements, isNotEmpty);
            expect(assessment.coaching.improvements.first.code, c.issueCode);
            expect(
              assessment.coaching.improvements.length,
              lessThanOrEqualTo(3),
            );
            expect(assessment.coaching.strengths.length, lessThanOrEqualTo(3));
            expect(
              assessment.coaching.strengths
                  .where(
                    (s) =>
                        s.evidenceKind.startsWith('hold') ||
                        s.code.contains('confirmed') ||
                        s.evidenceKind == 'holdConfirmed' ||
                        s.evidenceKind == 'holdPartialProgress' ||
                        s.evidenceKind == 'holdPartialDuration' ||
                        s.evidenceKind == 'holdExceptionalDuration',
                  )
                  .length,
              lessThanOrEqualTo(1),
            );
            expect(
              assessment.coaching.strengths.any(
                (s) =>
                    s.code == c.successCode ||
                    s.message.contains('Correct ${c.movement} form'),
              ),
              isTrue,
            );
            expect(
              assessment.coaching.recommendation?.movementName,
              c.movement,
            );
            expect(
              assessment.coaching.recommendation?.reason.toLowerCase(),
              isNot(contains('mistakes')),
            );
            expect(
              assessment.coaching.recommendation?.reason.toLowerCase(),
              isNot(contains('hold broke')),
            );
            expect(
              identical(
                assessment.improvements,
                assessment.coaching.improvements,
              ),
              isTrue,
            );
          },
        );
      }
    });

    test('null category uses legacy phrase fallback for environment', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        5,
        frame: _frame(
          feedback: 'Bottle not detected. Keep the bottle visible.',
          feedbackCode: null,
          feedbackCategory: null,
        ),
      );
      _recordFrames(
        accumulator,
        10,
        frame: _frame(
          feedbackType: 'positive',
          feedbackCode: 'hand_stall_locked',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator);
      expect(
        assessment.improvements.any(
          (i) => i.message.toLowerCase().contains('not detected'),
        ),
        isFalse,
      );
    });

    test(
      'generic Hold confirmed fallback when success code never observed',
      () {
        final accumulator = SessionAssessmentAccumulator();
        _recordFrames(
          accumulator,
          8,
          frame: _frame(
            feedback: 'Keep the bottle upright on your palm.',
            feedbackCode: 'prop_not_upright',
            feedbackCategory: 'technique',
            holdTargetMs: 2500,
          ),
        );
        // Confirm hold without ever observing the movement success code.
        accumulator.record(
          _frame(
            feedback: 'Keep refining technique.',
            feedbackType: 'warning',
            feedbackCode: 'prop_not_steady',
            feedbackCategory: 'technique',
            holdConfirmed: true,
            holdProgress: 1,
            holdDurationMs: 2500,
            holdTargetMs: 2500,
            assessment: _perfectRubric,
          ),
        );

        final assessment = _build(
          accumulator,
          heldSteady: true,
          rubric: _perfectRubric,
        );
        expect(
          assessment.coaching.strengths.any(
            (s) => s.code == 'hold_confirmed' && s.message == 'Hold confirmed',
          ),
          isTrue,
        );
        expect(
          assessment.coaching.strengths
              .where(
                (s) =>
                    s.evidenceKind == 'holdConfirmed' ||
                    s.evidenceKind == 'holdExceptionalDuration' ||
                    s.evidenceKind == 'holdPartialProgress' ||
                    s.evidenceKind == 'holdPartialDuration',
              )
              .length,
          1,
        );
      },
    );
  });
}
