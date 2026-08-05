import 'dart:async';

import 'package:flutter/foundation.dart';

/// Explicit practice-run lifecycle. Distinct from WebSocket connected /
/// session prepared / frame ready.
enum PracticeRunPhase {
  idle,
  preparingCamera,

  /// Pre-practice readiness gate (Guided Practice only). Camera is live and the
  /// backend is running readiness checks. Checklist items arrive via feedback
  /// frames until [PracticeRunController.requestStartPractice] freezes the
  /// state and transitions to countdown.
  readiness,

  countdown,
  active,
  completed,
  error,
}

/// Owns prepare → first-frame → countdown → active timing for Practice screens.
///
/// Does not own WebSocket, music, scoring UI, or hold validation — callers
/// gate those on [phase] / [isTrainingActive].
class PracticeRunController extends ChangeNotifier {
  PracticeRunController({
    this.preparationTimeout = const Duration(seconds: 20),
  });

  final Duration preparationTimeout;

  PracticeRunPhase _phase = PracticeRunPhase.idle;
  int _elapsedSeconds = 0;
  String? _errorMessage;
  bool _countdownTriggered = false;
  Timer? _elapsedTimer;
  Timer? _prepTimeout;
  VoidCallback? _onPreparationTimeout;

  /// Incremented on each [beginPreparing] call. Callers may snapshot this
  /// value to detect stale callbacks from a previous preparation attempt.
  int _lifecycleGeneration = 0;

  /// True after [requestStartPractice] accepts and freezes the readiness state.
  bool _readinessFrozen = false;

  /// Last readiness-stable value received via [applyReadinessUpdate].
  bool? _readinessStable;

  PracticeRunPhase get phase => _phase;
  int get elapsedSeconds => _elapsedSeconds;
  String? get errorMessage => _errorMessage;

  /// Incremented on each [beginPreparing]. Snapshot to detect stale messages.
  int get lifecycleGeneration => _lifecycleGeneration;

  /// True after [requestStartPractice] freezes the readiness checklist.
  bool get readinessFrozen => _readinessFrozen;

  /// Last readiness-stable state received while in the readiness phase.
  bool? get readinessStable => _readinessStable;

  /// Camera session is live (preview, readiness gate, countdown, or training).
  bool get isCameraSessionLive =>
      _phase == PracticeRunPhase.preparingCamera ||
      _phase == PracticeRunPhase.readiness ||
      _phase == PracticeRunPhase.countdown ||
      _phase == PracticeRunPhase.active;

  /// Scoring, combo, hold, and elapsed timer are allowed.
  bool get isTrainingActive => _phase == PracticeRunPhase.active;

  bool get isPreparingCamera => _phase == PracticeRunPhase.preparingCamera;
  bool get isReadiness => _phase == PracticeRunPhase.readiness;
  bool get isCountdown => _phase == PracticeRunPhase.countdown;
  bool get isError => _phase == PracticeRunPhase.error;

  /// Finish Session / session summary only after training has started.
  bool get shouldShowSummaryOnStop => _phase == PracticeRunPhase.active;

  void beginPreparing({required VoidCallback onTimeout}) {
    _stopElapsedTimer();
    _cancelPrepTimeout();
    _phase = PracticeRunPhase.preparingCamera;
    _elapsedSeconds = 0;
    _errorMessage = null;
    _countdownTriggered = false;
    _readinessFrozen = false;
    _readinessStable = null;
    _lifecycleGeneration++;
    _onPreparationTimeout = onTimeout;
    _prepTimeout = Timer(preparationTimeout, _handlePrepTimeout);
    notifyListeners();
  }

  void _handlePrepTimeout() {
    _prepTimeout = null;
    if (_phase != PracticeRunPhase.preparingCamera) return;
    _enterError(
      'The camera did not provide a usable frame. '
      'Check the selected camera and try again.',
    );
    _onPreparationTimeout?.call();
  }

  /// Handle an inbound feedback frame during preparation.
  ///
  /// Returns true exactly once when the first usable JPEG arrives. The caller
  /// should play countdown SFX, then call [enterCountdown].
  bool onPreviewFeedback({
    required bool hasJpegFrame,
    required bool isFatal,
    String? fatalMessage,
  }) {
    if (isFatal) {
      _enterError(fatalMessage ?? 'Session error');
      return false;
    }

    if (_phase != PracticeRunPhase.preparingCamera) return false;
    if (!hasJpegFrame) return false;
    if (_countdownTriggered) return false;

    _countdownTriggered = true;
    _cancelPrepTimeout();
    notifyListeners();
    return true;
  }

  /// Guided-practice path: transition preparingCamera → readiness after first JPEG.
  ///
  /// Free Practice uses [enterCountdown] directly from preparingCamera instead.
  /// Only valid from preparingCamera with [countdownTriggered] set (first JPEG seen).
  void enterReadiness() {
    if (_phase != PracticeRunPhase.preparingCamera) return;
    if (!_countdownTriggered) return;
    _phase = PracticeRunPhase.readiness;
    notifyListeners();
  }

  /// Transition to countdown.
  ///
  /// Accepted from two sources:
  /// - Free Practice: preparingCamera + [countdownTriggered] (first JPEG seen).
  /// - Guided: readiness + [readinessFrozen] (after [requestStartPractice]).
  void enterCountdown() {
    final fromFreePractice =
        _phase == PracticeRunPhase.preparingCamera && _countdownTriggered;
    final fromGuidedReadiness =
        _phase == PracticeRunPhase.readiness && _readinessFrozen;
    if (!fromFreePractice && !fromGuidedReadiness) return;
    _phase = PracticeRunPhase.countdown;
    notifyListeners();
  }

  /// Request to start practice from the readiness gate (Guided Practice).
  ///
  /// Returns false without changing state when:
  /// - [readinessStable] is false (backend not yet confirmed stable).
  /// - [readinessFrozen] is already true (duplicate tap guard).
  /// - Phase is not [PracticeRunPhase.readiness].
  ///
  /// On success: freezes the readiness checklist snapshot, transitions to
  /// countdown, and returns true.
  bool requestStartPractice({required bool readinessStable}) {
    if (!readinessStable) return false;
    if (_readinessFrozen) return false;
    if (_phase != PracticeRunPhase.readiness) return false;
    _readinessFrozen = true;
    _phase = PracticeRunPhase.countdown;
    notifyListeners();
    return true;
  }

  /// Apply a readiness update received from the backend.
  ///
  /// Returns true if the update was accepted and listeners were notified.
  /// Returns false (no-op) when phase is not [PracticeRunPhase.readiness] or
  /// the checklist is already frozen — this guards against late backend frames
  /// during countdown or active phases demoting the lifecycle.
  bool applyReadinessUpdate({bool? readinessStable}) {
    if (_phase != PracticeRunPhase.readiness || _readinessFrozen) return false;
    if (readinessStable != null) _readinessStable = readinessStable;
    notifyListeners();
    return true;
  }

  /// Transition countdown → active and start the elapsed timer from 00:00.
  void enterActive() {
    if (_phase != PracticeRunPhase.countdown) return;
    _cancelPrepTimeout();
    _phase = PracticeRunPhase.active;
    _elapsedSeconds = 0;
    _startElapsedTimer();
    notifyListeners();
  }

  void markCompleted() {
    _stopElapsedTimer();
    _cancelPrepTimeout();
    _phase = PracticeRunPhase.completed;
    notifyListeners();
  }

  /// Cancel prepare/readiness/countdown/error back to idle. Elapsed resets to zero.
  void cancelToIdle() {
    _stopElapsedTimer();
    _cancelPrepTimeout();
    _phase = PracticeRunPhase.idle;
    _elapsedSeconds = 0;
    _errorMessage = null;
    _countdownTriggered = false;
    _readinessFrozen = false;
    _readinessStable = null;
    notifyListeners();
  }

  void _enterError(String message) {
    _stopElapsedTimer();
    _cancelPrepTimeout();
    _phase = PracticeRunPhase.error;
    _errorMessage = message;
    // Keep elapsed at whatever it was; preparation failures stay at 0.
    notifyListeners();
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_phase != PracticeRunPhase.active) return;
      _elapsedSeconds++;
      notifyListeners();
    });
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  void _cancelPrepTimeout() {
    _prepTimeout?.cancel();
    _prepTimeout = null;
  }

  bool get countdownTriggered => _countdownTriggered;

  @visibleForTesting
  bool get hasElapsedTimer => _elapsedTimer != null;

  @visibleForTesting
  bool get hasPrepTimeout => _prepTimeout != null;

  /// Test helper: advance the elapsed counter as if Timer.periodic fired.
  @visibleForTesting
  void debugElapseSeconds(int seconds) {
    for (var i = 0; i < seconds; i++) {
      if (_phase != PracticeRunPhase.active) return;
      _elapsedSeconds++;
    }
    notifyListeners();
  }

  /// Test helper: fire the preparation timeout callback immediately.
  @visibleForTesting
  void debugFirePreparationTimeout() => _handlePrepTimeout();

  @override
  void dispose() {
    _stopElapsedTimer();
    _cancelPrepTimeout();
    super.dispose();
  }
}
