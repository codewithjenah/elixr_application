import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PracticeRunController timing', () {
    test('elapsed stays 00:00 before first frame and during countdown', () {
      final run = PracticeRunController(
        preparationTimeout: const Duration(seconds: 10),
      );

      run.beginPreparing(onTimeout: () {});
      expect(run.phase, PracticeRunPhase.preparingCamera);
      expect(run.elapsedSeconds, 0);

      // Simulated wall-clock wait before first frame.
      run.debugElapseSeconds(3);
      expect(run.elapsedSeconds, 0);

      final armed = run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      expect(armed, isTrue);
      expect(run.phase, PracticeRunPhase.preparingCamera);
      expect(run.elapsedSeconds, 0);

      run.enterCountdown();
      expect(run.phase, PracticeRunPhase.countdown);

      run.debugElapseSeconds(4);
      expect(run.elapsedSeconds, 0);
      expect(run.phase, PracticeRunPhase.countdown);

      run.dispose();
    });

    test('first JPEG arms countdown exactly once', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});

      expect(run.onPreviewFeedback(hasJpegFrame: true, isFatal: false), isTrue);
      expect(
        run.onPreviewFeedback(hasJpegFrame: true, isFatal: false),
        isFalse,
      );
      expect(run.countdownTriggered, isTrue);

      run.enterCountdown();
      expect(run.phase, PracticeRunPhase.countdown);
      run.dispose();
    });

    test('timer starts only after enterActive', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterCountdown();
      expect(run.elapsedSeconds, 0);

      run.enterActive();
      expect(run.phase, PracticeRunPhase.active);
      expect(run.elapsedSeconds, 0);
      expect(run.hasElapsedTimer, isTrue);

      run.debugElapseSeconds(3);
      expect(run.elapsedSeconds, 3);

      run.dispose();
    });

    test('preparation timeout keeps elapsed at zero', () {
      final run = PracticeRunController(
        preparationTimeout: const Duration(seconds: 8),
      );
      var timedOut = false;
      run.beginPreparing(onTimeout: () => timedOut = true);
      expect(run.hasPrepTimeout, isTrue);

      run.debugFirePreparationTimeout();
      expect(timedOut, isTrue);
      expect(run.phase, PracticeRunPhase.error);
      expect(run.elapsedSeconds, 0);
      expect(
        run.errorMessage,
        contains('camera did not provide a usable frame'),
      );
      run.dispose();
    });

    test('fatal preparation error cancels lifecycle', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      final started = run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: 'Camera unavailable',
      );
      expect(started, isFalse);
      expect(run.phase, PracticeRunPhase.error);
      expect(run.elapsedSeconds, 0);
      expect(run.errorMessage, 'Camera unavailable');
      run.dispose();
    });

    test('cancel during preparation does not leave active state', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      expect(run.shouldShowSummaryOnStop, isFalse);
      run.cancelToIdle();
      expect(run.phase, PracticeRunPhase.idle);
      expect(run.elapsedSeconds, 0);
      expect(run.shouldShowSummaryOnStop, isFalse);
      run.dispose();
    });

    test('cancel during countdown does not show summary eligibility', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterCountdown();
      expect(run.shouldShowSummaryOnStop, isFalse);
      run.cancelToIdle();
      expect(run.phase, PracticeRunPhase.idle);
      expect(run.elapsedSeconds, 0);
      run.dispose();
    });

    test('Try Again style reset returns to full preparation flow', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterCountdown();
      run.enterActive();
      run.debugElapseSeconds(2);
      expect(run.elapsedSeconds, 2);

      run.markCompleted();
      run.cancelToIdle();
      expect(run.phase, PracticeRunPhase.idle);
      expect(run.elapsedSeconds, 0);
      expect(run.countdownTriggered, isFalse);

      run.beginPreparing(onTimeout: () {});
      expect(run.phase, PracticeRunPhase.preparingCamera);
      expect(run.hasPrepTimeout, isTrue);
      run.dispose();
    });

    test('dispose cancels elapsed and preparation timers', () {
      final run = PracticeRunController(
        preparationTimeout: const Duration(seconds: 10),
      );
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterCountdown();
      run.enterActive();
      expect(run.hasElapsedTimer, isTrue);

      run.dispose();
      expect(run.hasElapsedTimer, isFalse);
      expect(run.hasPrepTimeout, isFalse);

      // Phase is still active but timers are gone; debug tick must no-op
      // once we force phase via cancel — after dispose, do not notify.
      expect(run.elapsedSeconds, 0);
    });
  });

  group('PracticeFeedback lifecycle fields', () {
    test('parses optional camera_ready and session_state', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 70,
        'feedback': 'Preparing camera…',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'frame_jpeg_base64': null,
        'camera_ready': true,
        'session_state': 'preparing',
      });

      expect(feedback.cameraReady, isTrue);
      expect(feedback.sessionState, 'preparing');
      expect(feedback.isPreparing, isTrue);
      expect(feedback.isSessionEvaluating, isFalse);
    });

    test('defaults missing lifecycle fields to null', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': true,
        'movement': 'Hand Stall',
        'score': 80,
        'feedback': 'Good',
        'feedback_type': 'positive',
        'posture_status': 'stable',
      });

      expect(feedback.cameraReady, isNull);
      expect(feedback.sessionState, isNull);
    });
  });

  group('WebSocket prepare/activate payloads', () {
    test('buildPreparePayload uses prepare action', () {
      final payload = WebSocketService.buildPreparePayload(
        movement: 'Normal Grip',
        difficulty: 'Easy',
        cameraDeviceId: 'dev-b',
        sessionId: 'session-a',
        requestId: 'req-a',
      );
      expect(payload['action'], 'prepare');
      expect(payload['protocol_version'], 1);
      expect(payload['session_id'], 'session-a');
      expect(payload['request_id'], 'req-a');
      expect(payload['movement'], 'Normal Grip');
      expect(payload['camera_device_id'], 'dev-b');
      expect(payload['bottle_detection_enabled'], isTrue);
    });

    test('buildActivatePayload uses activate action', () {
      final payload = WebSocketService.buildActivatePayload(
        sessionId: 'session-b',
        requestId: 'req-b',
      );
      expect(payload['action'], 'activate');
      expect(payload['protocol_version'], 1);
      expect(payload['session_id'], 'session-b');
      expect(payload['request_id'], 'req-b');
    });

    test('legacy start payload remains available', () {
      final payload = WebSocketService.buildStartPayload(
        movement: 'Hand Stall',
        difficulty: 'Medium',
        sessionId: 'session-c',
        requestId: 'req-c',
      );
      expect(payload['action'], 'start');
      expect(payload['protocol_version'], 1);
    });
  });

  group('preview feedback gating helpers', () {
    test('isTrainingActive gates combo/history/hold eligibility', () {
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
