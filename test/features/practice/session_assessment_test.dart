import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/session_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeFeedback _frame({
  String feedback = 'Keep steady',
  String feedbackType = 'warning',
  int score = 70,
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
    score: score,
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
  int finalScore = 80,
  bool heldSteady = false,
  PracticeFeedback? latestFeedback,
}) {
  return accumulator.buildAssessment(
    movement: movement,
    prop: prop,
    finalScore: finalScore,
    heldSteady: heldSteady,
    latestFeedback: latestFeedback,
  );
}

void main() {
  group('SessionAssessmentAccumulator', () {
    test(
      'confirmed score-100 session retains persistent technique improvements',
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
          finalScore: 100,
          heldSteady: true,
          latestFeedback: _frame(
            feedback: 'Hand stall locked in.',
            feedbackType: 'positive',
            feedbackCode: 'hand_stall_locked',
            feedbackCategory: 'technique',
            score: 100,
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

      final assessment = _build(accumulator, finalScore: 85);
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

      final assessment = _build(accumulator, finalScore: 88);
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

      final assessment = _build(accumulator, finalScore: 75);
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

      final assessment = _build(accumulator, finalScore: 75);
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

      final assessment = _build(accumulator, finalScore: 75);
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

    test('no strength inferred from missing warning code', () {
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
      expect(
        assessment.coaching.strengths.any(
          (s) => s.message.toLowerCase().contains('upright'),
        ),
        isFalse,
      );
    });

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

      final assessment = _build(accumulator, finalScore: 70);
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

      final assessment = _build(accumulator, finalScore: 70);
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
      expect(recommendation.reason, 'Focus: Keep the bottle upright');
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
        'Focus: Keep the cocktail shaker upright',
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
        finalScore: 80,
        heldSteady: false,
        totalApplicableSamples: 0,
        positiveSampleCount: 0,
        positiveRatio: 0,
        improvements: [],
      );
      expect(assessment.coaching.isEmpty, isTrue);
      expect(assessment.coaching.recommendation, isNull);
      expect(assessment.improvementMessages, isEmpty);
    });
  });
}
