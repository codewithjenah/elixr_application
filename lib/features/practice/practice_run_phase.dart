import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/practice_feedback.dart';
import 'practice_readiness_state.dart';

/// Explicit practice-run lifecycle. Distinct from WebSocket connected /
/// session prepared / frame ready.
enum PracticeRunPhase {
  idle,
  preparingCamera,

  /// Pre-practice readiness gate (Guided Practice only). Camera is live and the
  /// backend is running readiness checks. Checklist items arrive via feedback
  /// frames until auto-start (after a Ready beat) calls
  /// [PracticeRunController.requestStartPractice], freezes the state, and
  /// transitions to countdown.
  readiness,

  countdown,
  active,
  completed,
  error,
}

/// Duration after which a missing readiness feedback frame marks the stream stale.
const _kReadinessFreshnessWindow = Duration(seconds: 2);

/// Owns prepare → first-frame → countdown → active timing for Practice screens.
///
/// Does not own WebSocket, music, scoring UI, or hold validation — callers
/// gate those on [phase] / [isTrainingActive].
class PracticeRunController extends ChangeNotifier {
  PracticeRunController({
    this.preparationTimeout = const Duration(seconds: 20),
    this.autoStartReadyBeat = defaultAutoStartReadyBeat,
  });

  /// Brief hold after [PracticeReadinessState.canStartPractice] so the Ready
  /// checklist state is visible before auto-confirm.
  static const defaultAutoStartReadyBeat = Duration(milliseconds: 800);

  final Duration preparationTimeout;

  /// Delay between stable readiness and [autoStartDue] for guided auto-start.
  final Duration autoStartReadyBeat;

  PracticeRunPhase _phase = PracticeRunPhase.idle;
  int _elapsedSeconds = 0;
  String? _errorMessage;
  bool _firstPreviewReceived = false;
  Timer? _elapsedTimer;
  Timer? _prepTimeout;
  Timer? _watchdogTimer;
  Timer? _autoStartTimer;
  bool _autoStartDue = false;
  VoidCallback? _onPreparationTimeout;

  /// Incremented on each [beginPreparing] call. Callers may snapshot this
  /// value to detect stale callbacks from a previous preparation attempt.
  int _lifecycleGeneration = 0;

  /// Immutable readiness gate state. Updated by [applyReadinessFeedback].
  PracticeReadinessState _readiness = PracticeReadinessState.empty;

  PracticeRunPhase get phase => _phase;
  int get elapsedSeconds => _elapsedSeconds;
  String? get errorMessage => _errorMessage;

  /// Incremented on each [beginPreparing]. Snapshot to detect stale messages.
  int get lifecycleGeneration => _lifecycleGeneration;

  /// Current readiness gate state (items, stable, frozen, stale, etc.).
  PracticeReadinessState get readiness => _readiness;

  // ── Backward-compatible readiness getters ────────────────────────────────

  /// True when the Ready beat completed and the screen should auto-confirm.
  bool get autoStartDue => _autoStartDue;

  /// True after [requestStartPractice] freezes the readiness checklist.
  bool get readinessFrozen => _readiness.frozen;

  /// True while a [confirm_readiness] command is in flight.
  bool get readinessConfirming => _readiness.confirming;

  /// True after the backend accepted [confirm_readiness].
  bool get readinessConfirmed => _readiness.confirmed;

  /// Last readiness-stable state received via [applyReadinessFeedback].
  /// Null before any readiness feedback has been applied.
  bool? get readinessStable =>
      _readiness.items.isEmpty && !_readiness.stable ? null : _readiness.stable;

  // ── Phase helpers ─────────────────────────────────────────────────────────

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

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void beginPreparing({required VoidCallback onTimeout}) {
    _stopElapsedTimer();
    _cancelPrepTimeout();
    _cancelWatchdog();
    _cancelAutoStartBeat(clearDue: true);
    _phase = PracticeRunPhase.preparingCamera;
    _elapsedSeconds = 0;
    _errorMessage = null;
    _firstPreviewReceived = false;
    _readiness = PracticeReadinessState.empty;
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
  /// should play countdown SFX, then call [enterCountdown] or [enterReadiness].
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
    if (_firstPreviewReceived) return false;

    _firstPreviewReceived = true;
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
    if (!_firstPreviewReceived) return;
    _phase = PracticeRunPhase.readiness;
    notifyListeners();
  }

  /// Transition to countdown.
  ///
  /// Accepted from two sources:
  /// - Free Practice: preparingCamera + [countdownTriggered] (first JPEG seen).
  /// - Guided: readiness + frozen snapshot (after auto-start confirm).
  void enterCountdown() {
    final fromFreePractice =
        _phase == PracticeRunPhase.preparingCamera && _firstPreviewReceived;
    final fromGuidedReadiness =
        _phase == PracticeRunPhase.readiness && _readiness.frozen;
    if (!fromFreePractice && !fromGuidedReadiness) return;
    _cancelWatchdog();
    _cancelAutoStartBeat(clearDue: true);
    _phase = PracticeRunPhase.countdown;
    notifyListeners();
  }

  // ── Readiness gate ────────────────────────────────────────────────────────

  /// Apply a readiness feedback frame from the backend.
  ///
  /// Updates [readiness] only while phase == readiness && !frozen.
  /// Resets stream stale and restarts the 2-second freshness watchdog.
  /// Arms or cancels the auto-start Ready beat based on [canStartPractice].
  ///
  /// Returns true if the state was updated and listeners were notified.
  bool applyReadinessFeedback({
    required List<ReadinessItemView> items,
    required bool complete,
    required bool stable,
    required double progress,
  }) {
    if (_phase != PracticeRunPhase.readiness || _readiness.frozen) return false;
    _readiness = _readiness.copyWith(
      items: items,
      complete: complete,
      stable: stable,
      stableProgress: progress.clamp(0.0, 1.0),
      streamStale: false,
      clearRecoverable: stable, // clear recoverable message once stable again
    );
    _restartWatchdog();
    _syncAutoStartBeat();
    notifyListeners();
    return true;
  }

  /// Apply a readiness update received from the backend (legacy / compat path).
  ///
  /// Prefer [applyReadinessFeedback] for new call sites. This method updates
  /// only the stable flag on [readiness] and keeps existing item/progress data.
  ///
  /// Returns true if the update was accepted and listeners were notified.
  bool applyReadinessUpdate({bool? readinessStable}) {
    if (_phase != PracticeRunPhase.readiness || _readiness.frozen) return false;
    if (readinessStable != null) {
      _readiness = _readiness.copyWith(stable: readinessStable);
    }
    _syncAutoStartBeat();
    notifyListeners();
    return true;
  }

  void _restartWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(_kReadinessFreshnessWindow, _onWatchdogExpired);
  }

  void _onWatchdogExpired() {
    _watchdogTimer = null;
    if (_phase != PracticeRunPhase.readiness || _readiness.frozen) return;
    _readiness = _readiness.copyWith(
      streamStale: true,
      recoverableMessage: 'Waiting for a fresh camera reading\u2026',
    );
    _syncAutoStartBeat();
    notifyListeners();
  }

  void _cancelWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// Consume a one-shot auto-start signal after the Ready beat completes.
  ///
  /// Returns true once; subsequent calls return false until a new beat fires.
  bool consumeAutoStartDue() {
    if (!_autoStartDue) return false;
    _autoStartDue = false;
    return true;
  }

  /// Arm or cancel the Ready beat based on current readiness eligibility.
  void _syncAutoStartBeat() {
    final eligible =
        _phase == PracticeRunPhase.readiness && _readiness.canStartPractice;
    if (!eligible) {
      _cancelAutoStartBeat(clearDue: true);
      return;
    }
    if (_autoStartDue || _autoStartTimer != null) return;
    _autoStartTimer = Timer(autoStartReadyBeat, _onAutoStartBeatComplete);
  }

  void _onAutoStartBeatComplete() {
    _autoStartTimer = null;
    if (_phase != PracticeRunPhase.readiness) return;
    if (!_readiness.canStartPractice) return;
    _autoStartDue = true;
    notifyListeners();
  }

  void _cancelAutoStartBeat({required bool clearDue}) {
    _autoStartTimer?.cancel();
    _autoStartTimer = null;
    if (clearDue) {
      _autoStartDue = false;
    }
  }

  /// Request to start practice from the readiness gate (Guided Practice).
  ///
  /// Called by the screen after [consumeAutoStartDue] (or tests). Returns
  /// false without changing state when:
  /// - [readiness.canStartPractice] is false (not stable, stream stale, or
  ///   already confirming/confirmed). The legacy [readinessStable] param is
  ///   accepted for backward compatibility but [readiness.stable] takes
  ///   precedence when it has been set via [applyReadinessFeedback].
  /// - Phase is not [PracticeRunPhase.readiness].
  ///
  /// On success: marks confirmation in flight and cancels the Ready beat.
  bool requestStartPractice({required bool readinessStable}) {
    if (_phase != PracticeRunPhase.readiness) return false;
    // Compat: accept caller-supplied stable when readiness hasn't been updated
    // via applyReadinessFeedback (e.g. older test paths).
    final isStable = _readiness.stable || readinessStable;
    if (!isStable) return false;
    if (_readiness.streamStale) return false;
    if (_readiness.confirming || _readiness.frozen || _readiness.confirmed) {
      return false;
    }
    _cancelAutoStartBeat(clearDue: true);
    _readiness = _readiness.copyWith(confirming: true, clearRecoverable: true);
    notifyListeners();
    return true;
  }

  /// Backend accepted [confirm_readiness]. Freezes checklist and enters countdown.
  bool onConfirmReadinessAccepted() {
    if (!_readiness.confirming || _phase != PracticeRunPhase.readiness) {
      return false;
    }
    _readiness = _readiness.copyWith(
      confirming: false,
      confirmed: true,
      frozenSnapshot: List.unmodifiable(_readiness.items),
    );
    _cancelWatchdog();
    _cancelAutoStartBeat(clearDue: true);
    _phase = PracticeRunPhase.countdown;
    notifyListeners();
    return true;
  }

  /// Backend rejected [confirm_readiness].
  ///
  /// For [readiness_not_stable] and [readiness_stale] errors the rejection is
  /// recoverable: clears confirming, sets [recoverableMessage], and stays in
  /// readiness. Other error codes are also recoverable (the session is not
  /// fatal) but do not set a specific message. Soft rejects re-arm auto-start
  /// when stable feedback returns.
  void onConfirmReadinessRejected({String? errorCode, String? message}) {
    if (!_readiness.confirming) return;
    String? recoverable;
    if (errorCode == 'readiness_not_stable' || errorCode == 'readiness_stale') {
      recoverable =
          message ??
          'Readiness is no longer stable. Keep required inputs visible.';
    }
    _readiness = _readiness.copyWith(
      confirming: false,
      recoverableMessage: recoverable,
      clearRecoverable: recoverable == null,
    );
    _syncAutoStartBeat();
    notifyListeners();
  }

  /// Activation rejected after countdown (e.g. readiness_not_confirmed).
  ///
  /// Returns to readiness phase and clears the frozen snapshot so auto-start
  /// can attempt confirmation again.
  void onActivationRejected() {
    _readiness = _readiness.copyWith(
      confirming: false,
      confirmed: false,
      clearFrozen: true,
    );
    if (_phase == PracticeRunPhase.countdown) {
      _phase = PracticeRunPhase.readiness;
    }
    _syncAutoStartBeat();
    notifyListeners();
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
    _cancelAutoStartBeat(clearDue: true);
    _phase = PracticeRunPhase.completed;
    notifyListeners();
  }

  /// Cancel prepare/readiness/countdown/error back to idle. Elapsed resets to zero.
  void cancelToIdle() {
    _stopElapsedTimer();
    _cancelPrepTimeout();
    _cancelWatchdog();
    _cancelAutoStartBeat(clearDue: true);
    _phase = PracticeRunPhase.idle;
    _elapsedSeconds = 0;
    _errorMessage = null;
    _firstPreviewReceived = false;
    _readiness = PracticeReadinessState.empty;
    notifyListeners();
  }

  void _enterError(String message) {
    _stopElapsedTimer();
    _cancelPrepTimeout();
    _cancelWatchdog();
    _cancelAutoStartBeat(clearDue: true);
    _phase = PracticeRunPhase.error;
    _errorMessage = message;
    _readiness = PracticeReadinessState.empty;
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

  /// True after the first usable JPEG was received during [preparingCamera].
  bool get countdownTriggered => _firstPreviewReceived;

  /// True after the first usable JPEG was received during [preparingCamera].
  bool get firstPreviewReceived => _firstPreviewReceived;

  @visibleForTesting
  bool get hasElapsedTimer => _elapsedTimer != null;

  @visibleForTesting
  bool get hasPrepTimeout => _prepTimeout != null;

  @visibleForTesting
  bool get hasWatchdogTimer => _watchdogTimer != null;

  @visibleForTesting
  bool get hasAutoStartTimer => _autoStartTimer != null;

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

  /// Test helper: fire the readiness freshness watchdog immediately.
  @visibleForTesting
  void debugFireReadinessWatchdog() => _onWatchdogExpired();

  /// Test helper: fire the auto-start Ready beat immediately.
  @visibleForTesting
  void debugFireAutoStartBeat() => _onAutoStartBeatComplete();

  @override
  void dispose() {
    _stopElapsedTimer();
    _cancelPrepTimeout();
    _cancelWatchdog();
    _cancelAutoStartBeat(clearDue: true);
    super.dispose();
  }
}
