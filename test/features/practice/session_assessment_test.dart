import 'package:elixr_application/data/models/practice_feedback.dart';
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
  int finalScore = 80,
  bool heldSteady = false,
  PracticeFeedback? latestFeedback,
}) {
  return accumulator.buildAssessment(
    movement: movement,
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
            feedbackCode: 'bottle_not_upright',
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
        expect(assessment.improvements.single.code, 'bottle_not_upright');
        expect(assessment.coaching.strengths, isNotEmpty);
        expect(
          assessment.coaching.strengths.any((s) => s.code == 'hold_confirmed'),
          isTrue,
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
          feedbackCode: 'bottle_not_upright',
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
      expect(assessment.improvements.single.code, 'bottle_not_upright');
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

    test('positive Hand Stall code produces a strength', () {
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
          feedbackCode: 'bottle_not_upright',
          feedbackCategory: 'technique',
        ),
      );

      final assessment = _build(accumulator);
      expect(
        assessment.coaching.strengths.any((s) => s.code == 'hand_stall_locked'),
        isTrue,
      );
      expect(
        assessment.coaching.strengths
            .where((s) => s.evidenceKind == 'positiveCode')
            .single
            .sampleCount,
        12,
      );
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

    test('confirmed hold at target produces only one hold strength', () {
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
      final holdStrengths = assessment.coaching.strengths
          .where((s) => s.code.startsWith('hold_'))
          .toList();
      expect(holdStrengths, hasLength(1));
      expect(holdStrengths.single.message, 'Hold confirmed');
      expect(holdStrengths.single.evidenceKind, 'holdConfirmed');
    });

    test('confirmed exceptional duration produces one combined strength', () {
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
      final holdStrengths = assessment.coaching.strengths
          .where((s) => s.code.startsWith('hold_'))
          .toList();
      expect(holdStrengths, hasLength(1));
      expect(holdStrengths.single.evidenceKind, 'holdExceptionalDuration');
      expect(holdStrengths.single.message, contains('best hold'));
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
          feedbackCode: 'bottle_not_upright',
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
        heldSteady: false,
      );
      final recommendation = assessment.coaching.recommendation;
      expect(recommendation, isNotNull);
      expect(recommendation!.movementName, 'Hand Stall');
      expect(recommendation.reason.toLowerCase(), contains('upright'));
    });

    test('coaching improvements reuse the same list as assessment', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        4,
        frame: _frame(
          feedback: 'Keep the bottle upright on your palm.',
          feedbackCode: 'bottle_not_upright',
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
  });
}
