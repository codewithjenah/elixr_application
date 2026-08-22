import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/assessment_mode.dart';
import '../../data/models/assessment_spec.dart';
import '../../data/models/classroom_exceptions.dart';
import '../../data/models/group_assignment.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/rubric_assessment.dart';
import '../../data/models/training_prop.dart';
import '../../data/models/ws_protocol.dart';
import '../../data/repositories/classroom_assignment_repository.dart';
import '../../services/settings_service.dart';
import '../../services/websocket_service.dart';
import '../practice/practice_readiness_state.dart';
import '../practice/practice_run_phase.dart';
import '../teacher/movements/teacher_movement_builder_draft.dart';

/// Trainee template-scored assignment session.
///
/// Uses the frozen assignment AssessmentSpec and writes at most one
/// `template_score` attempt after backend-confirmed completion.
class TemplateScoredPracticeController extends ChangeNotifier {
  TemplateScoredPracticeController({
    required this.assignment,
    required this.traineeId,
    required this.assignmentRepository,
    WebSocketService? websocket,
    Future<String?> Function()? loadCameraDeviceId,
    int? Function()? pendingLegacyCameraIndex,
  }) : _ownsWebSocket = websocket == null,
       _ws = websocket ?? WebSocketService(),
       _loadCameraDeviceId = loadCameraDeviceId,
       _pendingLegacyCameraIndex = pendingLegacyCameraIndex {
    _ws.addListener(_onWebSocketChanged);
    _run.addListener(_notifyIfActive);
    _feedbackSub = _ws.feedbackStream.listen(_onFeedback);
    _previewSub = _ws.previewStream.listen(_onPreviewFrame);
  }

  final GroupAssignment assignment;
  final String traineeId;
  final ClassroomAssignmentRepository assignmentRepository;
  final WebSocketService _ws;
  final bool _ownsWebSocket;
  final PracticeRunController _run = PracticeRunController();

  Future<String?> Function()? _loadCameraDeviceId;
  int? Function()? _pendingLegacyCameraIndex;

  StreamSubscription<PracticeFeedback>? _feedbackSub;
  StreamSubscription<PreviewFrame>? _previewSub;

  bool _connecting = false;
  bool _commandInFlight = false;
  bool _disposed = false;
  bool _hasLiveSession = false;
  bool _beginReadinessSent = false;
  bool _holdConfirmed = false;
  bool _resultPersisted = false;
  bool _resultSaved = false;
  Future<void>? _persistFuture;
  Future<void>? _stopFuture;
  String? _errorMessage;
  String? _saveErrorMessage;
  PracticeFeedback? _latestFeedback;
  Uint8List? _previewFrame;
  double _holdProgress = 0;
  RubricAssessment? _assessment;
  int _completedDurationSeconds = 0;

  WebSocketService get websocket => _ws;
  PracticeRunPhase get phase => _run.phase;
  PracticeReadinessState get readiness => _run.readiness;
  PracticeFeedback? get latestFeedback => _latestFeedback;
  Uint8List? get previewFrame => _previewFrame;
  String? get errorMessage => _errorMessage;
  String? get saveErrorMessage => _saveErrorMessage;
  bool get connecting => _connecting;
  bool get holdConfirmed => _holdConfirmed;
  bool get resultSaved => _resultSaved;
  bool get resultPersisted => _resultPersisted;
  double get holdProgress => _holdProgress;
  RubricAssessment? get assessment => _assessment;
  WebSocketConnectionState get connectionState => _ws.connectionState;
  bool get isConnected => _ws.isConnected;
  AssessmentSpec? get frozenSpec => assignment.assessmentSpec;
  String get lateralityLabel => assignment.assessmentSpec == null
      ? 'Either wrist'
      : lateralityTeacherLabel(assignment.assessmentSpec!.laterality);
  bool get canStartPractice =>
      _run.isReadiness &&
      _run.readiness.canStartPractice &&
      !_commandInFlight &&
      !_disposed;

  String? get localValidationError {
    if (!assignment.isActive) {
      return 'This assignment has been archived.';
    }
    if (assignment.assessmentMode != AssessmentMode.templateScored) {
      return 'This assignment is not a template-scored classroom run.';
    }
    final spec = assignment.assessmentSpec;
    if (spec == null || !spec.isCanonicalWristStallV1) {
      return 'This template assignment is missing a valid AssessmentSpec.';
    }
    if (assignment.allowedProp != TrainingProp.bottle) {
      return 'This template assignment is not a Bottle Wrist Stall.';
    }
    return null;
  }

  void attachSettings(SettingsService settings) {
    _loadCameraDeviceId ??= settings.loadSelectedCameraDeviceId;
    _pendingLegacyCameraIndex ??= () => settings.pendingLegacyCameraIndex;
  }

  Future<void> connect() async {
    if (_disposed || _ws.isConnected || _connecting) return;
    _connecting = true;
    _notify();
    await _ws.connect();
    if (_disposed) return;
    if (!_ws.isConnected) {
      _errorMessage =
          _ws.errorMessage ??
          'Unable to connect to the backend. Is it running?';
    }
    _connecting = false;
    _notify();
  }

  Future<void> startSession() async {
    if (_disposed) return;
    if (_commandInFlight) return;
    final validation = localValidationError;
    if (validation != null) {
      _errorMessage = validation;
      _notify();
      return;
    }
    if (_run.phase != PracticeRunPhase.idle &&
        _run.phase != PracticeRunPhase.error &&
        _run.phase != PracticeRunPhase.completed) {
      return;
    }

    if (!_ws.isConnected) {
      await connect();
      if (_disposed || !_ws.isConnected) return;
    }

    _errorMessage = null;
    _saveErrorMessage = null;
    _latestFeedback = null;
    _previewFrame = null;
    _holdProgress = 0;
    _assessment = null;
    _holdConfirmed = false;
    _resultPersisted = false;
    _resultSaved = false;
    _persistFuture = null;
    _beginReadinessSent = false;
    _stopFuture = null;
    _completedDurationSeconds = 0;
    _ws.beginPracticeAttempt();
    _hasLiveSession = true;
    _run.beginPreparing(onTimeout: _onPreparationTimeout);
    _notify();

    final cameraDeviceId = await (_loadCameraDeviceId ?? () async => null)();
    if (_disposed || !_run.isPreparingCamera) return;

    _commandInFlight = true;
    try {
      final ack = await _ws.sendPrepare(
        movement: kTemplateAssessmentMovement,
        difficulty: kTemplateAssessmentDifficulty,
        prop: TrainingProp.bottle,
        cameraDeviceId: cameraDeviceId,
        legacyCameraIndex: cameraDeviceId == null
            ? _pendingLegacyCameraIndex?.call()
            : null,
        allowSubmissionRecording: false,
        sessionPurpose: WebSocketSessionPurpose.templateScored,
        assessmentSpec: assignment.assessmentSpec,
      );
      if (_disposed || !_run.isPreparingCamera) return;
      if (!ack.accepted) {
        _failPrepare(
          ack.message ??
              _friendlyErrorCode(ack.errorCode) ??
              'Camera preparation was rejected.',
        );
      }
    } catch (error) {
      if (_disposed) return;
      _failPrepare(_prepareFailureMessage(error));
    } finally {
      _commandInFlight = false;
    }
  }

  Future<void> confirmReadiness() async {
    if (_disposed || _commandInFlight || !canStartPractice) {
      return;
    }
    if (!_run.requestStartPractice(readinessStable: true)) return;
    _notify();

    _commandInFlight = true;
    try {
      final ack = await _ws.sendConfirmReadiness();
      if (_disposed) return;
      if (!ack.accepted) {
        final code = ack.errorCode;
        if (code == 'readiness_not_stable' || code == 'readiness_stale') {
          _run.onConfirmReadinessRejected(
            errorCode: code,
            message: ack.message,
          );
          _notify();
          return;
        }
        _failPrepare(
          ack.message ??
              _friendlyErrorCode(code) ??
              'Readiness confirmation was rejected.',
        );
        return;
      }
      _run.onConfirmReadinessAccepted();
      _notify();
    } catch (error) {
      if (_disposed) return;
      _run.onConfirmReadinessRejected();
      _errorMessage = error is CommandTimeoutException
          ? 'Readiness confirmation timed out. Check the backend and try again.'
          : 'Readiness confirmation failed. Check the backend and try again.';
      _notify();
    } finally {
      _commandInFlight = false;
    }
  }

  Future<void> activateAfterCountdown() async {
    if (_disposed || _commandInFlight || !_run.isCountdown) return;
    if (!_ws.isConnected) {
      _run.cancelToIdle();
      await connect();
      return;
    }

    _commandInFlight = true;
    try {
      final ack = await _ws.sendActivate();
      if (_disposed || !_run.isCountdown) return;
      if (!ack.accepted) {
        if (ack.errorCode == 'readiness_not_confirmed') {
          _run.onActivationRejected();
          _errorMessage =
              ack.message ??
              'Readiness must be confirmed before practice can start.';
          _notify();
          return;
        }
        _failPrepare(
          ack.message ??
              _friendlyErrorCode(ack.errorCode) ??
              'Session activation was rejected.',
        );
        return;
      }
      _run.enterActive();
      _notify();
    } catch (error) {
      if (_disposed) return;
      _failPrepare(
        error is CommandTimeoutException
            ? 'Session activation timed out. Try starting again.'
            : 'Session activation failed. Try starting again.',
      );
    } finally {
      _commandInFlight = false;
    }
  }

  Future<void> stopPractice() async {
    await _ensureStopped();
    if (_disposed) return;
    if (_run.phase != PracticeRunPhase.completed) {
      _run.cancelToIdle();
    }
    _previewFrame = null;
    _notify();
  }

  Future<void> closePractice() async {
    await _ensureStopped();
    if (_disposed) return;
    _run.cancelToIdle();
    _latestFeedback = null;
    _previewFrame = null;
    _holdProgress = 0;
    _assessment = null;
    _holdConfirmed = false;
    _errorMessage = null;
    _notify();
  }

  Future<void> tryAgain() async {
    await closePractice();
    if (_disposed) return;
    await startSession();
  }

  Future<void> retrySave() async {
    if (_disposed || !_holdConfirmed || _resultSaved) return;
    final rubric = _assessment;
    if (rubric == null) return;
    _saveErrorMessage = null;
    _notify();
    await _persistResult(rubric);
  }

  void _onPreviewFrame(PreviewFrame frame) {
    if (_disposed || !frame.hasJpeg) return;
    _previewFrame = frame.jpegBytes;
    _enterReadinessIfFirstFrame(hasJpeg: true);
    _notify();
  }

  void _onFeedback(PracticeFeedback feedback) {
    if (_disposed) return;

    if (feedback.isSessionFatal) {
      _errorMessage = feedback.feedback;
      _latestFeedback = null;
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: feedback.feedback,
      );
      unawaited(_ensureStopped());
      _previewFrame = null;
      _notify();
      return;
    }

    if (_run.isPreparingCamera) {
      if (feedback.frameJpegBytes != null) {
        _previewFrame = feedback.frameJpegBytes;
      }
      _enterReadinessIfFirstFrame(hasJpeg: feedback.frameJpegBytes != null);
      _notify();
      return;
    }

    if (_run.isReadiness) {
      if (feedback.frameJpegBytes != null) {
        _previewFrame = feedback.frameJpegBytes;
      }
      if (!_run.readinessFrozen) {
        _run.applyReadinessFeedback(
          items: feedback.readinessItems ?? const [],
          complete: feedback.readinessComplete ?? false,
          stable: feedback.readinessStable ?? false,
          progress: feedback.readinessStableProgress ?? 0,
        );
      }
      _latestFeedback = feedback;
      _notify();
      return;
    }

    if (_run.isCountdown) {
      if (feedback.frameJpegBytes != null) {
        _previewFrame = feedback.frameJpegBytes;
      }
      _notify();
      return;
    }

    if (!_run.isTrainingActive) return;

    if (feedback.frameJpegBytes != null) {
      _previewFrame = feedback.frameJpegBytes;
    }
    _latestFeedback = feedback;
    _holdProgress = feedback.holdProgress;
    _assessment = feedback.assessment;
    if (feedback.holdConfirmed && feedback.assessment != null) {
      _holdConfirmed = true;
      _completedDurationSeconds = feedback.holdDurationMs <= 0
          ? 0
          : feedback.holdDurationMs ~/ 1000;
      _run.markCompleted();
      unawaited(_persistResult(feedback.assessment!));
      unawaited(_ensureStopped());
    }
    _notify();
  }

  Future<void> _persistResult(RubricAssessment rubric) {
    if (_persistFuture != null) return _persistFuture!;
    if (_resultPersisted) return Future.value();
    _resultPersisted = true;
    _persistFuture = _persistBody(rubric);
    return _persistFuture!;
  }

  Future<void> _persistBody(RubricAssessment rubric) async {
    try {
      await assignmentRepository.createTemplateScoreAttempt(
        traineeId: traineeId,
        assignment: assignment,
        rubric: rubric,
        durationSeconds: _completedDurationSeconds,
        completedAt: DateTime.now().toUtc(),
      );
      if (_disposed) return;
      _resultSaved = true;
      _saveErrorMessage = null;
    } on ClassroomException catch (error) {
      if (_disposed) return;
      _resultPersisted = false;
      _persistFuture = null;
      _resultSaved = false;
      _saveErrorMessage =
          error.message ??
          'Could not save the classroom result. The score was not recorded.';
    } catch (_) {
      if (_disposed) return;
      _resultPersisted = false;
      _persistFuture = null;
      _resultSaved = false;
      _saveErrorMessage =
          'Could not save the classroom result. The score was not recorded.';
    }
    _notify();
  }

  void _enterReadinessIfFirstFrame({required bool hasJpeg}) {
    if (!_run.isPreparingCamera) return;
    final first = _run.onPreviewFeedback(hasJpegFrame: hasJpeg, isFatal: false);
    if (!first || _beginReadinessSent) return;
    _run.enterReadiness();
    _beginReadinessSent = true;
    unawaited(_beginReadiness());
  }

  Future<void> _beginReadiness() async {
    final generation = _run.lifecycleGeneration;
    try {
      final ack = await _ws.sendBeginReadiness();
      if (_disposed || _run.lifecycleGeneration != generation) return;
      if (!ack.accepted) {
        _failPrepare(
          ack.message ??
              _friendlyErrorCode(ack.errorCode) ??
              'Readiness check was rejected.',
        );
      }
    } catch (error) {
      if (_disposed || _run.lifecycleGeneration != generation) return;
      _failPrepare(
        error is CommandTimeoutException
            ? 'Readiness check timed out. Check the backend and try again.'
            : 'Readiness check failed. Check the backend and try again.',
      );
    }
  }

  void _onWebSocketChanged() {
    if (_disposed) return;
    if (_ws.connectionState != WebSocketConnectionState.disconnected &&
        _ws.connectionState != WebSocketConnectionState.error) {
      _notify();
      return;
    }
    final inSession =
        _run.isPreparingCamera ||
        _run.isReadiness ||
        _run.isCountdown ||
        _run.isTrainingActive;
    if (!inSession) {
      _notify();
      return;
    }
    _errorMessage =
        _ws.errorMessage ??
        'Lost connection to the backend. Check that it is running and try again.';
    _run.onPreviewFeedback(
      hasJpegFrame: false,
      isFatal: true,
      fatalMessage: _errorMessage,
    );
    unawaited(_ensureStopped());
    _previewFrame = null;
    _notify();
  }

  void _onPreparationTimeout() {
    if (_disposed) return;
    _errorMessage = _run.errorMessage;
    unawaited(_ensureStopped());
    _previewFrame = null;
    _notify();
  }

  void _failPrepare(String message) {
    _errorMessage = message;
    _run.onPreviewFeedback(
      hasJpegFrame: false,
      isFatal: true,
      fatalMessage: message,
    );
    unawaited(_ensureStopped());
    _previewFrame = null;
    _notify();
  }

  Future<void> _ensureStopped() {
    if (_stopFuture != null) return _stopFuture!;
    if (!_hasLiveSession) return Future.value();
    _hasLiveSession = false;
    _stopFuture = _stopBody();
    return _stopFuture!;
  }

  Future<void> _stopBody() async {
    try {
      await _ws.stopPracticeSession();
    } on CommandTimeoutException {
      // Expected when the backend is slow or unavailable.
    } on CommandAckMismatchException {
      // Stop ack did not match; session identity was already cleared.
    } on CommandDisconnectedException {
      // Expected during navigation or dispose.
    }
  }

  String _prepareFailureMessage(Object error) {
    if (error is CommandTimeoutException) {
      return 'Camera preparation timed out. Check the backend and try again.';
    }
    if (error is CommandDisconnectedException) {
      return 'Lost connection to the backend during camera preparation. Check the backend and try again.';
    }
    if (error is CommandAckMismatchException) {
      return 'Camera preparation was out of sync with the backend. Try starting again.';
    }
    return 'Camera preparation failed. Check the backend and try again.';
  }

  String? _friendlyErrorCode(String? code) {
    return switch (code) {
      'unsupported_template' => 'This template is not supported.',
      'camera_unavailable' =>
        'The selected camera is unavailable. Choose another camera in Settings.',
      'backend_unavailable' =>
        'Unable to reach the local ELIXR backend. Is it running?',
      'command_timeout' => 'The backend did not respond in time. Try again.',
      'ack_action_mismatch' || 'ack_session_mismatch' =>
        'The backend response did not match this assignment. Try starting again.',
      _ => null,
    };
  }

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @visibleForTesting
  void debugForceActive() {
    _hasLiveSession = true;
    _errorMessage = null;
    _run.beginPreparing(onTimeout: () {});
    _run.onPreviewFeedback(hasJpegFrame: true, isFatal: false);
    _run.enterReadiness();
    _run.applyReadinessFeedback(
      items: const [],
      complete: true,
      stable: true,
      progress: 1,
    );
    _run.requestStartPractice(readinessStable: true);
    _run.onConfirmReadinessAccepted();
    _run.enterActive();
    _notify();
  }

  @visibleForTesting
  void debugApplyFeedback(PracticeFeedback feedback) => _onFeedback(feedback);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _feedbackSub?.cancel();
    _previewSub?.cancel();
    _ws.removeListener(_onWebSocketChanged);
    _run.removeListener(_notifyIfActive);
    unawaited(_ensureStopped());
    _previewFrame = null;
    _run.dispose();
    if (_ownsWebSocket) {
      _ws.dispose();
    }
    super.dispose();
  }
}
