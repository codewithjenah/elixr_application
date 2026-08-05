import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
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

  group('PracticeRunController guided-practice readiness gate', () {
    test(
      'first JPEG arms preview; enterReadiness goes to readiness not countdown',
      () {
        final run = PracticeRunController();
        run.beginPreparing(onTimeout: () {});
        expect(run.phase, PracticeRunPhase.preparingCamera);

        final armed = run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
        expect(armed, isTrue);
        expect(run.phase, PracticeRunPhase.preparingCamera);

        run.enterReadiness();
        expect(run.phase, PracticeRunPhase.readiness);
        expect(run.isReadiness, isTrue);
        expect(run.isCameraSessionLive, isTrue);
        run.dispose();
      },
    );

    test('requestStartPractice without stable returns false', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      expect(run.phase, PracticeRunPhase.readiness);

      final result = run.requestStartPractice(readinessStable: false);
      expect(result, isFalse);
      expect(run.phase, PracticeRunPhase.readiness);
      expect(run.readinessFrozen, isFalse);
      run.dispose();
    });

    test('requestStartPractice with stable freezes and enters countdown', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();

      final result = run.requestStartPractice(readinessStable: true);
      expect(result, isTrue);
      expect(run.phase, PracticeRunPhase.countdown);
      expect(run.readinessFrozen, isTrue);
      run.dispose();
    });

    test('duplicate requestStartPractice returns false', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      expect(run.requestStartPractice(readinessStable: true), isTrue);
      expect(run.phase, PracticeRunPhase.countdown);

      // Second call: already frozen
      expect(run.requestStartPractice(readinessStable: true), isFalse);
      // Third call: phase is now countdown, not readiness
      expect(run.requestStartPractice(readinessStable: true), isFalse);
      expect(run.phase, PracticeRunPhase.countdown);
      run.dispose();
    });

    test('applyReadinessUpdate accepted during readiness phase', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();

      final applied = run.applyReadinessUpdate(readinessStable: true);
      expect(applied, isTrue);
      expect(run.readinessStable, isTrue);
      run.dispose();
    });

    test('ordinary readiness loss after freeze does not leave countdown', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.requestStartPractice(readinessStable: true);
      expect(run.phase, PracticeRunPhase.countdown);

      // Readiness becomes false after freeze — must be ignored (frozen guard).
      final applied = run.applyReadinessUpdate(readinessStable: false);
      expect(applied, isFalse);
      expect(run.phase, PracticeRunPhase.countdown);
      run.dispose();
    });

    test('late applyReadinessUpdate during countdown is ignored', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.requestStartPractice(readinessStable: true);
      expect(run.phase, PracticeRunPhase.countdown);

      final applied = run.applyReadinessUpdate(readinessStable: false);
      expect(applied, isFalse);
      expect(run.phase, PracticeRunPhase.countdown);
      run.dispose();
    });

    test('late applyReadinessUpdate during active phase is ignored', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.requestStartPractice(readinessStable: true);
      run.enterActive();
      expect(run.phase, PracticeRunPhase.active);

      final applied = run.applyReadinessUpdate(readinessStable: false);
      expect(applied, isFalse);
      expect(run.phase, PracticeRunPhase.active);
      run.dispose();
    });

    test('fatal error during readiness enters error', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      expect(run.phase, PracticeRunPhase.readiness);

      final result = run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: 'Camera lost',
      );
      expect(result, isFalse);
      expect(run.phase, PracticeRunPhase.error);
      expect(run.errorMessage, 'Camera lost');
      run.dispose();
    });

    test('fatal error during countdown enters error', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.requestStartPractice(readinessStable: true);
      expect(run.phase, PracticeRunPhase.countdown);

      run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: 'Fatal during countdown',
      );
      expect(run.phase, PracticeRunPhase.error);
      expect(run.errorMessage, 'Fatal during countdown');
      run.dispose();
    });

    test('lifecycleGeneration increments on each beginPreparing', () {
      final run = PracticeRunController();
      final gen0 = run.lifecycleGeneration;

      run.beginPreparing(onTimeout: () {});
      expect(run.lifecycleGeneration, gen0 + 1);

      run.cancelToIdle();
      run.beginPreparing(onTimeout: () {});
      expect(run.lifecycleGeneration, gen0 + 2);

      run.dispose();
    });

    test('cancelToIdle clears readinessFrozen and readinessStable', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.applyReadinessUpdate(readinessStable: true);
      run.requestStartPractice(readinessStable: true);
      expect(run.readinessFrozen, isTrue);

      run.cancelToIdle();
      expect(run.phase, PracticeRunPhase.idle);
      expect(run.readinessFrozen, isFalse);
      expect(run.readinessStable, isNull);
      run.dispose();
    });

    test('beginPreparing clears readiness freeze and stable state', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.requestStartPractice(readinessStable: true);
      expect(run.readinessFrozen, isTrue);

      run.cancelToIdle();
      run.beginPreparing(onTimeout: () {});
      expect(run.readinessFrozen, isFalse);
      expect(run.readinessStable, isNull);
      run.dispose();
    });

    test('enterCountdown from readiness+frozen (guided path) works', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      // Manually freeze without requestStartPractice (internal path test).
      run.requestStartPractice(readinessStable: true);
      expect(run.phase, PracticeRunPhase.countdown);
      run.enterActive();
      expect(run.phase, PracticeRunPhase.active);
      run.dispose();
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

    test('parses shaker prop and defaults legacy feedback to bottle', () {
      final shaker = PracticeFeedback.fromJson({
        'prop_type': 'shaker',
        'bottle_detected': true,
        'bottle_count': 1,
        'movement': 'Hand Stall',
        'score': 80,
        'feedback': 'Good',
        'feedback_type': 'positive',
        'posture_status': 'stable',
      });
      final legacy = PracticeFeedback.fromJson({
        'bottle_detected': true,
        'movement': 'Hand Stall',
        'score': 80,
        'feedback': 'Good',
        'feedback_type': 'positive',
        'posture_status': 'stable',
      });

      expect(shaker.propType, TrainingProp.shaker);
      expect(shaker.bottleCount, 1);
      expect(legacy.propType, TrainingProp.bottle);
    });
  });

  group('PracticeFeedback readiness fields', () {
    test('parses readiness_items when present', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Checking readiness…',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'session_state': 'readying',
        'readiness_complete': false,
        'readiness_stable': false,
        'readiness_stable_progress': 0.4,
        'readiness_items': [
          {
            'code': 'camera_ready',
            'status': 'ready',
            'message': 'Camera is ready',
          },
          {
            'code': 'bottle_visible',
            'status': 'waiting',
            'message': 'Hold bottle up',
          },
        ],
      });

      expect(feedback.isReadying, isTrue);
      expect(feedback.readinessComplete, isFalse);
      expect(feedback.readinessStable, isFalse);
      expect(feedback.readinessStableProgress, closeTo(0.4, 0.001));
      expect(feedback.readinessItems, hasLength(2));
      expect(feedback.readinessItems![0].code, 'camera_ready');
      expect(feedback.readinessItems![0].status, 'ready');
      expect(feedback.readinessItems![0].message, 'Camera is ready');
      expect(feedback.readinessItems![1].code, 'bottle_visible');
      expect(feedback.readinessItems![1].status, 'waiting');
    });

    test('readiness_items absent returns null safely', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Preparing…',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'session_state': 'preparing',
      });

      expect(feedback.readinessItems, isNull);
      expect(feedback.readinessComplete, isNull);
      expect(feedback.readinessStable, isNull);
      expect(feedback.readinessStableProgress, isNull);
      expect(feedback.isReadying, isFalse);
    });

    test('malformed readiness_items entries are skipped gracefully', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Check',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'session_state': 'readying',
        'readiness_items': [
          {'code': 'good_item', 'status': 'ready', 'message': 'OK'},
          'not_a_map',
          {'code': 'missing_status', 'message': 'No status field'},
          {'code': 123, 'status': 'ready', 'message': 'Bad code type'},
          {'code': 'another_good', 'status': 'error', 'message': 'Failed'},
        ],
      });

      // Only valid entries parsed; malformed ones skipped.
      expect(feedback.readinessItems, hasLength(2));
      expect(feedback.readinessItems![0].code, 'good_item');
      expect(feedback.readinessItems![1].code, 'another_good');
      expect(feedback.readinessItems![1].status, 'error');
    });

    test('unknown item codes and statuses are preserved as-is', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Check',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'session_state': 'readying',
        'readiness_items': [
          {
            'code': 'future_unknown_check',
            'status': 'future_status',
            'message': 'Some future message',
          },
        ],
      });

      expect(feedback.readinessItems, hasLength(1));
      expect(feedback.readinessItems![0].code, 'future_unknown_check');
      expect(feedback.readinessItems![0].status, 'future_status');
    });

    test('non-list readiness_items returns null', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Check',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'readiness_items': 'not_a_list',
      });
      expect(feedback.readinessItems, isNull);
    });

    test('readiness_stable true and complete true are parsed', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': true,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Ready!',
        'feedback_type': 'positive',
        'posture_status': 'stable',
        'session_state': 'readying',
        'readiness_complete': true,
        'readiness_stable': true,
        'readiness_stable_progress': 1.0,
        'readiness_items': [],
      });

      expect(feedback.readinessComplete, isTrue);
      expect(feedback.readinessStable, isTrue);
      expect(feedback.readinessStableProgress, closeTo(1.0, 0.001));
      expect(feedback.readinessItems, isEmpty);
    });

    test('semanticEquals includes readiness fields', () {
      final a = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Checking',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'session_state': 'readying',
        'readiness_stable': false,
        'readiness_items': [
          {'code': 'x', 'status': 'waiting', 'message': 'Wait'},
        ],
      });
      final b = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Checking',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'session_state': 'readying',
        'readiness_stable': true, // different
        'readiness_items': [
          {'code': 'x', 'status': 'waiting', 'message': 'Wait'},
        ],
      });
      expect(a.semanticEquals(b), isFalse);
      expect(a.semanticEquals(a), isTrue);
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
      expect(payload['prop_type'], 'bottle');
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
        prop: TrainingProp.shaker,
        sessionId: 'session-c',
        requestId: 'req-c',
      );
      expect(payload['action'], 'start');
      expect(payload['protocol_version'], 1);
      expect(payload['prop_type'], 'shaker');
    });
  });

  group('fresh practice attempt identity', () {
    test('beginPracticeAttempt always allocates a new session id', () {
      final ws = WebSocketService();
      final first = ws.beginPracticeAttempt();
      final second = ws.beginPracticeAttempt();
      expect(second, isNot(first));
      expect(ws.currentSessionId, second);
      ws.dispose();
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
