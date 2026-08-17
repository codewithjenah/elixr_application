import 'package:elixr_application/data/models/practice_feedback.dart';
import 'package:elixr_application/data/models/training_prop.dart';
import 'package:elixr_application/features/practice/practice_readiness_state.dart';
import 'package:elixr_application/features/practice/practice_run_phase.dart';
import 'package:elixr_application/services/websocket_service.dart';
import 'package:fake_async/fake_async.dart';
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

    test('requestStartPractice with stable marks confirmation in flight', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();

      final result = run.requestStartPractice(readinessStable: true);
      expect(result, isTrue);
      expect(run.phase, PracticeRunPhase.readiness);
      expect(run.readinessConfirming, isTrue);
      expect(run.readinessFrozen, isFalse);
      run.dispose();
    });

    test('onConfirmReadinessAccepted freezes and enters countdown', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.requestStartPractice(readinessStable: true);

      final accepted = run.onConfirmReadinessAccepted();
      expect(accepted, isTrue);
      expect(run.phase, PracticeRunPhase.countdown);
      expect(run.readinessFrozen, isTrue);
      expect(run.readinessConfirmed, isTrue);
      run.dispose();
    });

    test('duplicate requestStartPractice returns false', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      expect(run.requestStartPractice(readinessStable: true), isTrue);
      expect(run.readinessConfirming, isTrue);

      // Second call: confirmation already in flight
      expect(run.requestStartPractice(readinessStable: true), isFalse);
      run.onConfirmReadinessAccepted();
      expect(run.phase, PracticeRunPhase.countdown);

      // Third call: phase is now countdown, not readiness
      expect(run.requestStartPractice(readinessStable: true), isFalse);
      expect(run.phase, PracticeRunPhase.countdown);
      run.dispose();
    });

    test('onConfirmReadinessRejected clears confirming without countdown', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.requestStartPractice(readinessStable: true);
      run.onConfirmReadinessRejected();
      expect(run.phase, PracticeRunPhase.readiness);
      expect(run.readinessConfirming, isFalse);
      expect(run.readinessFrozen, isFalse);
      run.dispose();
    });

    test('onActivationRejected returns to readiness from countdown', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.requestStartPractice(readinessStable: true);
      run.onConfirmReadinessAccepted();
      expect(run.phase, PracticeRunPhase.countdown);
      run.onActivationRejected();
      expect(run.phase, PracticeRunPhase.readiness);
      expect(run.readinessFrozen, isFalse);
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
      run.onConfirmReadinessAccepted();
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
      run.onConfirmReadinessAccepted();
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
      run.onConfirmReadinessAccepted();
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
      run.onConfirmReadinessAccepted();
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
      run.onConfirmReadinessAccepted();
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
      run.onConfirmReadinessAccepted();
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
      run.onConfirmReadinessAccepted();
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
      expect(feedback.readinessItems![0].status, ReadinessItemStatus.ready);
      expect(feedback.readinessItems![0].message, 'Camera is ready');
      expect(feedback.readinessItems![1].code, 'bottle_visible');
      expect(feedback.readinessItems![1].status, ReadinessItemStatus.waiting);
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
      expect(feedback.readinessItems![1].status, ReadinessItemStatus.error);
    });

    test('unknown item codes parse; unknown statuses map to unknown enum', () {
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
      // Unknown wire value → ReadinessItemStatus.unknown (forward compatible).
      expect(feedback.readinessItems![0].status, ReadinessItemStatus.unknown);
      expect(feedback.readinessItems![0].status.wireValue, 'unknown');
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

    test('parses calibration_scale and calibration_source when present', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Checking',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'session_state': 'readying',
        'calibration_scale': 1.2,
        'calibration_source': 'shoulders',
      });
      expect(feedback.calibrationScale, closeTo(1.2, 0.001));
      expect(feedback.calibrationSource, 'shoulders');
    });

    test('calibration fields absent remain null', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Checking',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'session_state': 'readying',
      });
      expect(feedback.calibrationScale, isNull);
      expect(feedback.calibrationSource, isNull);
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

    test('buildConfirmReadinessPayload uses confirm_readiness action', () {
      final payload = WebSocketService.buildConfirmReadinessPayload(
        sessionId: 'session-d',
        requestId: 'req-d',
      );
      expect(payload['action'], 'confirm_readiness');
      expect(payload['protocol_version'], 1);
      expect(payload['session_id'], 'session-d');
      expect(payload['request_id'], 'req-d');
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

  group('PracticeReadinessState', () {
    test('canStartPractice requires stable and no stale stream', () {
      const base = PracticeReadinessState(stable: true);
      expect(base.canStartPractice, isTrue);

      expect(
        const PracticeReadinessState(stable: false).canStartPractice,
        isFalse,
      );
      expect(
        const PracticeReadinessState(
          stable: true,
          streamStale: true,
        ).canStartPractice,
        isFalse,
      );
      expect(
        const PracticeReadinessState(
          stable: true,
          confirming: true,
        ).canStartPractice,
        isFalse,
      );
      expect(
        const PracticeReadinessState(
          stable: true,
          confirmed: true,
        ).canStartPractice,
        isFalse,
      );
    });

    test('frozen is true only when frozenSnapshot is non-null', () {
      expect(const PracticeReadinessState().frozen, isFalse);
      expect(const PracticeReadinessState(frozenSnapshot: []).frozen, isTrue);
    });

    test('displayItems returns frozenSnapshot when frozen, else items', () {
      const item = ReadinessItemView(
        code: 'camera_frame',
        status: ReadinessItemStatus.ready,
        message: 'OK',
      );
      const liveItem = ReadinessItemView(
        code: 'grip_landmarks_visible',
        status: ReadinessItemStatus.waiting,
        message: 'Wait',
      );
      const state = PracticeReadinessState(
        items: [liveItem],
        frozenSnapshot: [item],
      );
      expect(state.displayItems, [item]);

      const unfrozen = PracticeReadinessState(items: [liveItem]);
      expect(unfrozen.displayItems, [liveItem]);
    });

    test('readyCount counts only ready items', () {
      const items = [
        ReadinessItemView(
          code: 'camera_frame',
          status: ReadinessItemStatus.ready,
          message: 'OK',
        ),
        ReadinessItemView(
          code: 'bottle_detected',
          status: ReadinessItemStatus.waiting,
          message: 'Wait',
        ),
        ReadinessItemView(
          code: 'grip_landmarks_visible',
          status: ReadinessItemStatus.error,
          message: 'Error',
        ),
      ];
      const state = PracticeReadinessState(items: items);
      expect(state.readyCount, 1);
      expect(state.totalCount, 3);
    });

    test('copyWith clearFrozen removes frozenSnapshot', () {
      const frozen = PracticeReadinessState(frozenSnapshot: []);
      final cleared = frozen.copyWith(clearFrozen: true);
      expect(cleared.frozen, isFalse);
    });

    test('equality holds for identical instances', () {
      const a = PracticeReadinessState(stable: true, streamStale: false);
      const b = PracticeReadinessState(stable: true, streamStale: false);
      expect(a, equals(b));
    });
  });

  group('PracticeRunController readiness state (PracticeReadinessState)', () {
    test('readiness is empty before beginPreparing', () {
      final run = PracticeRunController();
      expect(run.readiness, PracticeReadinessState.empty);
      run.dispose();
    });

    test('applyReadinessFeedback updates readiness state', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();

      const item = ReadinessItemView(
        code: 'camera_frame',
        status: ReadinessItemStatus.ready,
        message: 'OK',
      );
      final applied = run.applyReadinessFeedback(
        items: [item],
        complete: true,
        stable: true,
        progress: 0.8,
      );

      expect(applied, isTrue);
      expect(run.readiness.stable, isTrue);
      expect(run.readiness.complete, isTrue);
      expect(run.readiness.stableProgress, closeTo(0.8, 0.001));
      expect(run.readiness.items, [item]);
      expect(run.readiness.streamStale, isFalse);
      run.dispose();
    });

    test('applyReadinessFeedback ignored when frozen', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.applyReadinessFeedback(
        items: const [],
        complete: true,
        stable: true,
        progress: 1.0,
      );
      run.requestStartPractice(readinessStable: true);
      run.onConfirmReadinessAccepted();
      expect(run.readiness.frozen, isTrue);

      final applied = run.applyReadinessFeedback(
        items: const [],
        complete: false,
        stable: false,
        progress: 0.0,
      );
      expect(applied, isFalse);
      expect(run.readiness.frozen, isTrue);
      run.dispose();
    });

    test('watchdog fires and sets streamStale after no fresh frames', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      // Trigger watchdog explicitly (no real Timer needed in tests).
      run.debugFireReadinessWatchdog();

      expect(run.readiness.streamStale, isTrue);
      expect(run.readiness.recoverableMessage, isNotEmpty);
      run.dispose();
    });

    test('fresh readiness frame resets streamStale', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.debugFireReadinessWatchdog();
      expect(run.readiness.streamStale, isTrue);

      run.applyReadinessFeedback(
        items: const [],
        complete: false,
        stable: false,
        progress: 0.0,
      );
      expect(run.readiness.streamStale, isFalse);
      run.dispose();
    });

    test(
      'onConfirmReadinessRejected with readiness_stale sets recoverableMessage',
      () {
        final run = PracticeRunController();
        run.beginPreparing(onTimeout: () {});
        run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
        run.enterReadiness();
        run.applyReadinessFeedback(
          items: const [],
          complete: true,
          stable: true,
          progress: 1.0,
        );
        run.requestStartPractice(readinessStable: true);

        run.onConfirmReadinessRejected(
          errorCode: 'readiness_stale',
          message: 'Snapshot expired.',
        );
        expect(run.readiness.confirming, isFalse);
        expect(run.readiness.recoverableMessage, 'Snapshot expired.');
        expect(run.phase, PracticeRunPhase.readiness);
        run.dispose();
      },
    );

    test(
      'onConfirmReadinessRejected with readiness_not_stable sets recoverableMessage',
      () {
        final run = PracticeRunController();
        run.beginPreparing(onTimeout: () {});
        run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
        run.enterReadiness();
        run.applyReadinessFeedback(
          items: const [],
          complete: true,
          stable: true,
          progress: 1.0,
        );
        run.requestStartPractice(readinessStable: true);

        run.onConfirmReadinessRejected(errorCode: 'readiness_not_stable');
        expect(run.readiness.confirming, isFalse);
        expect(run.readiness.recoverableMessage, isNotEmpty);
        run.dispose();
      },
    );

    test('onConfirmReadinessAccepted captures frozenSnapshot', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();

      const item = ReadinessItemView(
        code: 'camera_frame',
        status: ReadinessItemStatus.ready,
        message: 'OK',
      );
      run.applyReadinessFeedback(
        items: [item],
        complete: true,
        stable: true,
        progress: 1.0,
      );
      run.requestStartPractice(readinessStable: true);
      run.onConfirmReadinessAccepted();

      expect(run.readiness.frozen, isTrue);
      expect(run.readiness.frozenSnapshot, [item]);
      expect(run.phase, PracticeRunPhase.countdown);
      run.dispose();
    });

    test(
      'onActivationRejected clears frozenSnapshot and returns to readiness',
      () {
        final run = PracticeRunController();
        run.beginPreparing(onTimeout: () {});
        run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
        run.enterReadiness();
        run.applyReadinessFeedback(
          items: const [],
          complete: true,
          stable: true,
          progress: 1.0,
        );
        run.requestStartPractice(readinessStable: true);
        run.onConfirmReadinessAccepted();
        expect(run.phase, PracticeRunPhase.countdown);
        expect(run.readiness.frozen, isTrue);

        run.onActivationRejected();
        expect(run.phase, PracticeRunPhase.readiness);
        expect(run.readiness.frozen, isFalse);
        run.dispose();
      },
    );

    test('cancelToIdle resets readiness to empty', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.applyReadinessFeedback(
        items: const [],
        complete: true,
        stable: true,
        progress: 1.0,
      );
      run.cancelToIdle();
      expect(run.readiness, PracticeReadinessState.empty);
      run.dispose();
    });

    test('late applyReadinessFeedback during active phase is ignored', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.applyReadinessFeedback(
        items: const [],
        complete: true,
        stable: true,
        progress: 1.0,
      );
      run.requestStartPractice(readinessStable: true);
      run.onConfirmReadinessAccepted();
      run.enterActive();
      expect(run.phase, PracticeRunPhase.active);

      final applied = run.applyReadinessFeedback(
        items: const [],
        complete: false,
        stable: false,
        progress: 0.0,
      );
      expect(applied, isFalse);
      expect(run.phase, PracticeRunPhase.active);
      run.dispose();
    });

    test(
      'canStartPractice false when streamStale blocks requestStartPractice',
      () {
        final run = PracticeRunController();
        run.beginPreparing(onTimeout: () {});
        run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
        run.enterReadiness();
        run.applyReadinessFeedback(
          items: const [],
          complete: true,
          stable: true,
          progress: 1.0,
        );
        // Force stale stream.
        run.debugFireReadinessWatchdog();
        expect(run.readiness.streamStale, isTrue);

        final result = run.requestStartPractice(readinessStable: true);
        expect(result, isFalse);
        run.dispose();
      },
    );

    test('dispose cancels watchdog timer', () {
      final run = PracticeRunController();
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
      run.applyReadinessFeedback(
        items: const [],
        complete: false,
        stable: false,
        progress: 0.0,
      );
      expect(run.hasWatchdogTimer, isTrue);
      run.dispose();
      expect(run.hasWatchdogTimer, isFalse);
    });
  });

  group('PracticeRunController auto-start Ready beat', () {
    List<ReadinessItemView> readyItems() => const [
      ReadinessItemView(
        code: 'camera_frame',
        status: ReadinessItemStatus.ready,
        message: 'OK',
      ),
    ];

    void enterGuidedReadiness(PracticeRunController run) {
      run.beginPreparing(onTimeout: () {});
      run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
      run.enterReadiness();
    }

    test('stable readiness arms beat; after 800ms autoStartDue is true', () {
      fakeAsync((async) {
        final run = PracticeRunController();
        enterGuidedReadiness(run);
        run.applyReadinessFeedback(
          items: readyItems(),
          complete: true,
          stable: true,
          progress: 1.0,
        );
        expect(run.hasAutoStartTimer, isTrue);
        expect(run.autoStartDue, isFalse);

        async.elapse(const Duration(milliseconds: 799));
        expect(run.autoStartDue, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(run.autoStartDue, isTrue);
        expect(run.consumeAutoStartDue(), isTrue);
        expect(run.consumeAutoStartDue(), isFalse);
        expect(run.autoStartDue, isFalse);
        run.dispose();
      });
    });

    test('losing stability before beat completes cancels auto-start', () {
      fakeAsync((async) {
        final run = PracticeRunController();
        enterGuidedReadiness(run);
        run.applyReadinessFeedback(
          items: readyItems(),
          complete: true,
          stable: true,
          progress: 1.0,
        );
        expect(run.hasAutoStartTimer, isTrue);

        async.elapse(const Duration(milliseconds: 400));
        run.applyReadinessFeedback(
          items: readyItems(),
          complete: false,
          stable: false,
          progress: 0.2,
        );
        expect(run.hasAutoStartTimer, isFalse);
        expect(run.autoStartDue, isFalse);

        async.elapse(const Duration(milliseconds: 800));
        expect(run.autoStartDue, isFalse);
        expect(run.consumeAutoStartDue(), isFalse);
        run.dispose();
      });
    });

    test('soft reject re-arms Ready beat when still stable', () {
      fakeAsync((async) {
        final run = PracticeRunController();
        enterGuidedReadiness(run);
        run.applyReadinessFeedback(
          items: readyItems(),
          complete: true,
          stable: true,
          progress: 1.0,
        );
        async.elapse(PracticeRunController.defaultAutoStartReadyBeat);
        expect(run.consumeAutoStartDue(), isTrue);

        expect(run.requestStartPractice(readinessStable: true), isTrue);
        run.onConfirmReadinessRejected(
          errorCode: 'readiness_not_stable',
          message: 'Not stable',
        );
        expect(run.phase, PracticeRunPhase.readiness);
        expect(run.readiness.confirming, isFalse);
        // Prior feedback still reports stable, so auto-start re-arms.
        expect(run.hasAutoStartTimer, isTrue);

        async.elapse(PracticeRunController.defaultAutoStartReadyBeat);
        expect(run.autoStartDue, isTrue);
        expect(run.consumeAutoStartDue(), isTrue);
        run.dispose();
      });
    });

    test('cancelToIdle and dispose cancel pending Ready beat', () {
      fakeAsync((async) {
        final run = PracticeRunController();
        enterGuidedReadiness(run);
        run.applyReadinessFeedback(
          items: readyItems(),
          complete: true,
          stable: true,
          progress: 1.0,
        );
        expect(run.hasAutoStartTimer, isTrue);

        run.cancelToIdle();
        expect(run.hasAutoStartTimer, isFalse);
        expect(run.autoStartDue, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(run.autoStartDue, isFalse);

        enterGuidedReadiness(run);
        run.applyReadinessFeedback(
          items: readyItems(),
          complete: true,
          stable: true,
          progress: 1.0,
        );
        expect(run.hasAutoStartTimer, isTrue);
        run.dispose();
        expect(run.hasAutoStartTimer, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(run.autoStartDue, isFalse);
      });
    });

    test('stream stale during beat cancels auto-start', () {
      fakeAsync((async) {
        final run = PracticeRunController();
        enterGuidedReadiness(run);
        run.applyReadinessFeedback(
          items: readyItems(),
          complete: true,
          stable: true,
          progress: 1.0,
        );
        expect(run.hasAutoStartTimer, isTrue);

        run.debugFireReadinessWatchdog();
        expect(run.readiness.streamStale, isTrue);
        expect(run.hasAutoStartTimer, isFalse);
        expect(run.autoStartDue, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(run.autoStartDue, isFalse);
        run.dispose();
      });
    });
  });

  group('PracticeFeedback readiness progress clamping', () {
    test('readiness_stable_progress > 1 is clamped to 1', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Check',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'session_state': 'readying',
        'readiness_stable_progress': 1.5,
      });
      expect(feedback.readinessStableProgress, closeTo(1.0, 0.001));
    });

    test('readiness_stable_progress < 0 is clamped to 0', () {
      final feedback = PracticeFeedback.fromJson({
        'bottle_detected': false,
        'movement': 'Hand Stall',
        'score': 0,
        'feedback': 'Check',
        'feedback_type': 'positive',
        'posture_status': 'unknown',
        'session_state': 'readying',
        'readiness_stable_progress': -0.3,
      });
      expect(feedback.readinessStableProgress, closeTo(0.0, 0.001));
    });
  });

  group('WebSocketService session flags reset', () {
    test('beginPracticeAttempt resets sessionReadying to false', () {
      final ws = WebSocketService();
      // There is no direct setter, but we can verify via getter after a
      // fresh attempt.
      ws.beginPracticeAttempt();
      expect(ws.sessionReadying, isFalse);
      ws.dispose();
    });
  });
}
