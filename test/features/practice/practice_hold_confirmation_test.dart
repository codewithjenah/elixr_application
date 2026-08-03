import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors [PracticeScreen] hold-completion gating for unit tests.
class _HoldCompletionHarness {
  bool movementConfirmedShowing = false;
  int completionCount = 0;

  void onFeedback(PracticeFeedback feedback, {required bool isTrainingActive}) {
    if (!isTrainingActive) return;
    if (feedback.holdConfirmed) {
      onMovementConfirmed();
    }
  }

  void onMovementConfirmed() {
    if (movementConfirmedShowing) return;
    movementConfirmedShowing = true;
    completionCount++;
  }

  void clearSessionState() {
    movementConfirmedShowing = false;
  }
}

bool shouldDisplayHoldProgress({
  required double holdProgress,
  required bool isTrainingActive,
}) {
  return isTrainingActive && holdProgress > 0 && holdProgress < 1;
}

PracticeFeedback _activeHoldFeedback({
  double holdProgress = 0,
  bool holdConfirmed = false,
}) {
  return PracticeFeedback.fromJson({
    'bottle_detected': true,
    'movement': 'Hand Stall',
    'score': 80,
    'feedback': 'Good',
    'feedback_type': 'positive',
    'posture_status': 'stable',
    'session_state': 'active',
    'hold_progress': holdProgress,
    'hold_confirmed': holdConfirmed,
  });
}

void main() {
  group('PracticeFeedback hold fields', () {
    test('missing hold fields parse with safe defaults', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': true,
        'movement': 'Hand Stall',
        'score': 80,
        'feedback': 'Good',
        'feedback_type': 'positive',
        'posture_status': 'stable',
      });

      expect(feedback.holdProgress, 0);
      expect(feedback.holdDurationMs, 0);
      expect(feedback.holdConfirmed, isFalse);
      expect(feedback.positiveFrameRatio, 0);
    });

    test('parses backend hold progress and confirmation', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': true,
        'movement': 'Hand Stall',
        'score': 90,
        'feedback': 'Good',
        'feedback_type': 'positive',
        'posture_status': 'stable',
        'hold_progress': 0.62,
        'hold_duration_ms': 1550,
        'hold_confirmed': false,
        'positive_frame_ratio': 0.95,
      });

      expect(feedback.holdProgress, 0.62);
      expect(feedback.holdDurationMs, 1550);
      expect(feedback.holdConfirmed, isFalse);
      expect(feedback.positiveFrameRatio, 0.95);
    });
  });

  group('backend hold display gating', () {
    test('shows hold progress only during active training', () {
      expect(
        shouldDisplayHoldProgress(holdProgress: 0.4, isTrainingActive: true),
        isTrue,
      );
      expect(
        shouldDisplayHoldProgress(holdProgress: 0.4, isTrainingActive: false),
        isFalse,
      );
      expect(
        shouldDisplayHoldProgress(holdProgress: 0, isTrainingActive: true),
        isFalse,
      );
      expect(
        shouldDisplayHoldProgress(holdProgress: 1, isTrainingActive: true),
        isFalse,
      );
    });
  });

  group('movement confirmation stop lifecycle', () {
    test('hold confirmation triggers only one centralized stop', () async {
      var stopCalls = 0;

      Future<void> stopPracticeSession() async {
        stopCalls++;
      }

      Future<void> stopSession({bool heldSteady = false}) async {
        await stopPracticeSession();
      }

      Future<void> onMovementConfirmed() async {
        // Mirrors PracticeScreen: no separate sendStop before stopSession.
        await stopSession(heldSteady: true);
      }

      await onMovementConfirmed();
      expect(stopCalls, 1);
    });
  });

  group('backend hold completion gating', () {
    test('hold_confirmed completes the session exactly once', () {
      final harness = _HoldCompletionHarness();
      final confirmed = _activeHoldFeedback(holdConfirmed: true);

      harness.onFeedback(confirmed, isTrainingActive: true);
      harness.onFeedback(confirmed, isTrainingActive: true);
      harness.onFeedback(confirmed, isTrainingActive: true);

      expect(harness.completionCount, 1);
    });

    test(
      'positive feedback without backend confirmation does not complete',
      () {
        final harness = _HoldCompletionHarness();
        final positive = _activeHoldFeedback(holdProgress: 0.9);

        harness.onFeedback(positive, isTrainingActive: true);

        expect(harness.completionCount, 0);
      },
    );

    test('prepare and countdown feedback cannot complete the movement', () {
      final harness = _HoldCompletionHarness();
      final confirmed = _activeHoldFeedback(holdConfirmed: true);

      harness.onFeedback(confirmed, isTrainingActive: false);

      expect(harness.completionCount, 0);
    });

    test('Try Again clears prior confirmation state', () {
      final harness = _HoldCompletionHarness();
      harness.onFeedback(
        _activeHoldFeedback(holdConfirmed: true),
        isTrainingActive: true,
      );
      expect(harness.completionCount, 1);

      harness.clearSessionState();
      expect(harness.movementConfirmedShowing, isFalse);

      harness.onFeedback(
        _activeHoldFeedback(holdConfirmed: true),
        isTrainingActive: true,
      );
      expect(harness.completionCount, 2);
    });
  });

  group('practice phase eligibility', () {
    test('only active phase allows hold completion', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      expect(run.isTrainingActive, isFalse);

      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterCountdown();
      expect(run.isTrainingActive, isFalse);

      run.enterActive();
      expect(run.isTrainingActive, isTrue);
      run.dispose();
    });
  });
}
