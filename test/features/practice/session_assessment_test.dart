import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/features/practice/session_assessment.dart';
import 'package:flutter_test/flutter_test.dart';

PracticeFeedback _frame({
  String feedback = 'Keep steady',
  String feedbackType = 'warning',
  int score = 70,
  String? sessionState = 'active',
  String? errorCode,
}) {
  return PracticeFeedback(
    bottleDetected: true,
    movement: 'Normal Grip',
    score: score,
    feedback: feedback,
    feedbackType: feedbackType,
    postureStatus: 'ok',
    sessionState: sessionState,
    errorCode: errorCode,
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

void main() {
  group('SessionAssessmentAccumulator', () {
    test(
      'score 100 + heldSteady + positive final feedback yields no improvements',
      () {
        final accumulator = SessionAssessmentAccumulator();
        _recordFrames(
          accumulator,
          5,
          frame: _frame(
            feedback: 'Move your hand to the upper bottle neck.',
            feedbackType: 'warning',
          ),
        );
        _recordFrames(
          accumulator,
          20,
          frame: _frame(feedback: 'Great grip!', feedbackType: 'positive'),
        );

        final assessment = accumulator.buildAssessment(
          finalScore: 100,
          heldSteady: true,
          latestFeedback: _frame(
            feedback: 'Great grip!',
            feedbackType: 'positive',
            score: 100,
          ),
        );

        expect(assessment.improvements, isEmpty);
      },
    );

    test('one transient warning is excluded', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        1,
        frame: _frame(feedback: 'Lower your elbow'),
      );
      _recordFrames(accumulator, 10, frame: _frame(feedbackType: 'positive'));

      final assessment = accumulator.buildAssessment(
        finalScore: 85,
        heldSteady: false,
        latestFeedback: _frame(feedbackType: 'positive', score: 85),
      );

      expect(assessment.improvements, isEmpty);
    });

    test('recurring warning meeting thresholds is included', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(
        accumulator,
        4,
        frame: _frame(feedback: 'Wrap at least three fingers around the neck.'),
      );
      _recordFrames(accumulator, 16, frame: _frame(feedbackType: 'positive'));

      final assessment = accumulator.buildAssessment(
        finalScore: 88,
        heldSteady: false,
        latestFeedback: _frame(feedbackType: 'positive', score: 88),
      );

      expect(assessment.improvements, hasLength(1));
      expect(
        assessment.improvements.single.message,
        'Wrap at least three fingers around the neck.',
      );
      expect(assessment.improvements.single.occurrenceCount, 4);
      expect(
        assessment.improvements.single.occurrenceRatio,
        closeTo(0.2, 0.001),
      );
    });

    test(
      'positive and environment feedback are excluded from improvements',
      () {
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
          5,
          frame: _frame(feedback: 'Camera unavailable', feedbackType: 'error'),
        );
        _recordFrames(
          accumulator,
          2,
          frame: _frame(feedback: 'Lower your elbow'),
        );

        final assessment = accumulator.buildAssessment(
          finalScore: 75,
          heldSteady: false,
          latestFeedback: _frame(feedbackType: 'positive', score: 75),
        );

        expect(assessment.improvements, isEmpty);
        expect(assessment.positiveSampleCount, 10);
        expect(
          assessment.improvementMessages,
          isNot(contains('Keep the bottle visible in frame')),
        );
      },
    );

    test('only top 3 persistent issues are returned', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(accumulator, 6, frame: _frame(feedback: 'Issue A'));
      _recordFrames(accumulator, 5, frame: _frame(feedback: 'Issue B'));
      _recordFrames(accumulator, 4, frame: _frame(feedback: 'Issue C'));
      _recordFrames(accumulator, 3, frame: _frame(feedback: 'Issue D'));
      _recordFrames(accumulator, 2, frame: _frame(feedbackType: 'positive'));

      final assessment = accumulator.buildAssessment(
        finalScore: 70,
        heldSteady: false,
        latestFeedback: _frame(feedbackType: 'warning', score: 70),
      );

      expect(assessment.improvements, hasLength(3));
      expect(assessment.improvementMessages, ['Issue A', 'Issue B', 'Issue C']);
    });

    test('reset clears all accumulated assessment data', () {
      final accumulator = SessionAssessmentAccumulator();
      _recordFrames(accumulator, 5, frame: _frame(feedback: 'Issue A'));
      accumulator.reset();

      expect(accumulator.totalApplicableSamples, 0);
      expect(accumulator.positiveSampleCount, 0);

      final assessment = accumulator.buildAssessment(
        finalScore: 80,
        heldSteady: false,
      );
      expect(assessment.improvements, isEmpty);
      expect(assessment.totalApplicableSamples, 0);
    });
  });
}
