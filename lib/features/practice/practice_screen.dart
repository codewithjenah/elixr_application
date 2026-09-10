import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/constants/music_tracks.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/rubric_assessment.dart';
import '../../data/models/class_challenge.dart';
import '../../data/models/class_challenge_session_context.dart';
import '../../data/models/session_assignment_context.dart';
import '../../data/models/training_prop.dart';
import '../../data/models/ws_protocol.dart';
import '../../services/auth_service.dart';
import '../../services/practice_music_service.dart';
import '../../services/practice_sfx_service.dart';
import '../../services/session_service.dart';
import '../../services/settings_service.dart';
import '../../services/startup_diagnostics.dart';
import '../../services/tutorial_progress_service.dart';
import '../../services/websocket_service.dart';
import '../learning/movement_lesson_content.dart';
import '../learning/movement_tutorial_dialog.dart';
import '../settings/settings_screen.dart';
import '../settings/settings_section.dart';
import 'camera_recovery_presentation.dart';
import 'practice_feedback_controller.dart';
import 'practice_game_widgets.dart';
import 'practice_run_phase.dart';
import 'session_summary_sheet.dart';
import 'training_quit_guard.dart';
import 'widgets/readiness_checklist_panel.dart';
import 'widgets/training_action_area.dart';
import 'widgets/training_arena_layout.dart';
import 'widgets/training_camera_workspace.dart';
import 'widgets/training_live_hud.dart';
import 'widgets/training_performance.dart';
import 'widgets/training_session_header.dart';
import 'widgets/training_session_panel.dart';
import 'widgets/training_status_row.dart';

/// Rubric used when a scored session ends with no assessment frame observed.
const _emptyRubric = RubricAssessment(
  technique: 0,
  stability: 0,
  completion: 0,
  propPositioning: 0,
);

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    required this.movement,
    required this.difficulty,
    this.prop = TrainingProp.bottle,
    this.assignmentContext,
    this.challengeContext,
    this.onChallengeComplete,
    this.challengeReturnLocation,
    this.previousChallengeBest,
    @visibleForTesting this.websocketService,
  });

  final String movement;
  final String difficulty;
  final TrainingProp prop;

  /// Trusted official assignment identity from `/assigned-practice/:id`.
  /// Ordinary catalog practice leaves this null.
  final SessionAssignmentContext? assignmentContext;

  final ClassChallengeSessionContext? challengeContext;
  final Future<ClassChallengeCompletionReceipt> Function(String sessionId)?
  onChallengeComplete;
  final String? challengeReturnLocation;
  final int? previousChallengeBest;

  /// Test injection. Production constructs [WebSocketService] in [createState].
  @visibleForTesting
  final WebSocketService? websocketService;

  static const cameraAspectWidth = TrainingArenaLayout.cameraAspectWidth;
  static const cameraAspectHeight = TrainingArenaLayout.cameraAspectHeight;

  static double panelWidthForContent(double contentWidth) {
    return TrainingArenaLayout.panelWidthForContent(contentWidth);
  }

  @visibleForTesting
  static Size desktopCameraSize({
    required double contentWidth,
    required double workspaceHeight,
  }) {
    return TrainingArenaLayout.desktopCameraSize(
      contentWidth: contentWidth,
      workspaceHeight: workspaceHeight,
    );
  }

  @visibleForTesting
  static Size stackedCameraSize(double contentWidth) {
    return TrainingArenaLayout.stackedCameraSize(contentWidth);
  }

  @override
  State<PracticeScreen> createState() => PracticeScreenState();
}

class ClassChallengeCompletionReceipt {
  const ClassChallengeCompletionReceipt({required this.bestResult, this.rank});
  final ClassChallengeLeaderboardEntry bestResult;
  final int? rank;
}

class PracticeScreenState extends State<PracticeScreen>
    with SingleTickerProviderStateMixin {
  late final String _movement = widget.movement;
  late final String _difficulty = widget.difficulty;
  late final TrainingProp _prop = widget.prop;

  late final WebSocketService _ws;
  late final bool _ownsWebSocket;
  final _music = PracticeMusicService();
  final _sfx = PracticeSfxService();
  final _run = PracticeRunController();
  final _feedback = PracticeFeedbackController();
  final _comboNotifier = ValueNotifier<ComboState>(const ComboState());
  final _scorePopupNotifier = ValueNotifier<ScorePopupState>(
    const ScorePopupState(),
  );
  final _calloutNotifier = ValueNotifier<PerformanceCalloutState>(
    const PerformanceCalloutState(),
  );

  StreamSubscription<PracticeFeedback>? _feedbackSub;
  StreamSubscription<PreviewFrame>? _previewSub;
  final ValueNotifier<Uint8List?> _frameBytes = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<RubricAssessment?> _assessmentNotifier =
      ValueNotifier<RubricAssessment?>(null);
  final ValueNotifier<double> _holdProgressNotifier = ValueNotifier<double>(0);
  bool _connecting = false;
  String? _sessionError;
  String? _sessionErrorCode;
  bool _isShowingSummary = false;
  bool _movementConfirmedShowing = false;
  bool _commandInFlight = false;
  bool _leaving = false;
  bool _quitDialogOpen = false;
  bool _stopInFlight = false;
  Uint8List? _confirmedEvidenceJpegBytes;

  late final AnimationController _scorePulseController;
  late final Animation<double> _scorePulse;
  int? _lastPulsedTotal;

  static const _maxContentWidth = AppSpacing.practiceMaxContentWidth;
  static const _desktopBreakpoint = AppSpacing.practiceDesktopBreakpoint;
  static const _compactBreakpoint = AppSpacing.practiceCompactBreakpoint;

  @override
  void initState() {
    super.initState();
    _ownsWebSocket = widget.websocketService == null;
    _ws = widget.websocketService ?? WebSocketService();
    _scorePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scorePulse =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12), weight: 50),
          TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 50),
        ]).animate(
          CurvedAnimation(parent: _scorePulseController, curve: Curves.easeOut),
        );
    _ws.addListener(_onWsStateChanged);
    _run.addListener(_onRunChanged);
    _feedbackSub = _ws.feedbackStream.listen(_onFeedback);
    _previewSub = _ws.previewStream.listen(_onPreviewFrame);
    if (widget.websocketService == null || !_ws.isConnected) {
      _connect();
    }
    _sfx.preload();
  }

  @override
  void dispose() {
    _feedbackSub?.cancel();
    _previewSub?.cancel();
    _scorePulseController.dispose();
    _frameBytes.dispose();
    _assessmentNotifier.dispose();
    _holdProgressNotifier.dispose();
    _comboNotifier.dispose();
    _scorePopupNotifier.dispose();
    _calloutNotifier.dispose();
    _music.dispose();
    _sfx.dispose();
    _ws.removeListener(_onWsStateChanged);
    _run.removeListener(_onRunChanged);
    _run.dispose();
    if (_ownsWebSocket) {
      _ws.dispose();
    }
    super.dispose();
  }

  void _onWsStateChanged() {
    if (_ws.connectionState == WebSocketConnectionState.disconnected ||
        _ws.connectionState == WebSocketConnectionState.error) {
      _music.stop();
      _sfx.stop();
      _frameBytes.value = null;
      _assessmentNotifier.value = null;
      _holdProgressNotifier.value = 0;
      if (mounted) {
        final wasCalibrating =
            _run.isPreparingCamera || _run.isReadiness || _run.isCountdown;
        if (wasCalibrating || _run.isTrainingActive) {
          _run.onPreviewFeedback(
            hasJpegFrame: false,
            isFatal: true,
            fatalMessage:
                _ws.errorMessage ??
                'Connection lost. Reconnect and begin calibration again.',
          );
        }
        setState(() {
          _feedback.latestFeedback = null;
          if (wasCalibrating) {
            _sessionError =
                _ws.errorMessage ??
                'Connection lost. Reconnect and begin calibration again.';
          }
        });
      }
      return;
    }
    if (mounted) setState(() {});
  }

  void _onRunChanged() {
    if (!mounted || _leaving) return;
    setState(() {});
    if (_run.consumeAutoStartDue()) {
      _onStartPractice();
    }
  }

  void _publishFrame(Uint8List? bytes) {
    if (bytes != null) {
      _frameBytes.value = bytes;
    }
  }

  void _clearFrame() {
    _frameBytes.value = null;
  }

  Future<void> _stopWebSocketSession() async {
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

  void _onPreviewFrame(PreviewFrame frame) {
    if (!mounted || _leaving) return;
    if (!frame.hasJpeg) return;

    _publishFrame(frame.jpegBytes);

    if (_run.isPreparingCamera) {
      if (_sessionError != null) {
        setState(() => _sessionError = null);
      }
      final firstFrame = _run.onPreviewFeedback(
        hasJpegFrame: true,
        isFatal: false,
      );
      if (firstFrame) {
        _run.enterReadiness();
        unawaited(_beginReadiness());
      }
      return;
    }

    if (_sessionError != null &&
        (_run.isReadiness || _run.isCountdown || _run.isTrainingActive)) {
      setState(() => _sessionError = null);
    }
  }

  void _onFeedback(PracticeFeedback feedback) {
    if (!mounted || _leaving) return;

    if (feedback.isSessionFatal) {
      _music.stop();
      _sfx.stop();
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: feedback.feedback,
      );
      unawaited(_stopWebSocketSession());
      _clearFrame();
      _assessmentNotifier.value = null;
      _holdProgressNotifier.value = 0;
      setState(() {
        _sessionError = feedback.feedback;
        _sessionErrorCode = feedback.errorCode;
        _feedback.latestFeedback = null;
      });
      return;
    }

    // Preparing: store frame; first JPEG enters the readiness gate.
    if (_run.isPreparingCamera) {
      _publishFrame(feedback.frameJpegBytes);
      final hadError = _sessionError != null;
      if (hadError) {
        setState(() => _sessionError = null);
      }
      final firstFrame = _run.onPreviewFeedback(
        hasJpegFrame: feedback.frameJpegBytes != null,
        isFatal: false,
      );
      if (firstFrame) {
        _run.enterReadiness();
        unawaited(_beginReadiness());
      }
      return;
    }

    // Readiness gate: update checklist and progress; ignore late frames once frozen.
    if (_run.isReadiness) {
      _publishFrame(feedback.frameJpegBytes);
      if (_sessionError != null) {
        setState(() => _sessionError = null);
      }
      if (!_run.readinessFrozen) {
        final items = feedback.readinessItems ?? const [];
        final progress = feedback.readinessStableProgress ?? 0.0;
        final stable = feedback.readinessStable ?? false;
        final complete = feedback.readinessComplete ?? false;
        _run.applyReadinessFeedback(
          items: items,
          complete: complete,
          stable: stable,
          progress: progress,
        );
      }
      return;
    }

    // Countdown: keep refreshing preview frames only.
    if (_run.isCountdown) {
      _publishFrame(feedback.frameJpegBytes);
      if (_sessionError != null) {
        setState(() => _sessionError = null);
      }
      return;
    }

    // Only active training updates score UI / combo / history / hold.
    if (!_run.isTrainingActive) return;

    // Capture before any async stop/camera teardown. The backend only emits
    // this optional payload on the confirming frame.
    _confirmedEvidenceJpegBytes ??= feedback.evidenceJpegBytes;

    final result = _feedback.applyActiveFeedback(feedback);

    _publishFrame(feedback.frameJpegBytes);
    _assessmentNotifier.value = feedback.assessment;
    _holdProgressNotifier.value = feedback.holdProgress;

    if (result.comboChanged) {
      _comboNotifier.value = result.comboState;
    }
    if (result.scorePopupChanged) {
      _scorePopupNotifier.value = result.scorePopupState;
    }
    if (result.calloutChanged) {
      _calloutNotifier.value = result.calloutState;
    }

    if (result.needsChromeRebuild || _sessionError != null) {
      setState(() {
        _sessionError = null;
      });
    }

    if (result.holdConfirmed) {
      unawaited(_onMovementConfirmed());
    }

    final total = feedback.assessment?.total;
    if (result.assessmentChanged &&
        total != null &&
        _lastPulsedTotal != total) {
      _lastPulsedTotal = total;
      _scorePulseController.forward(from: 0);
    }
  }

  /// Send begin_readiness after entering the readiness phase.
  ///
  /// Captures the lifecycle generation before the await to guard against
  /// stale callbacks from a cancelled/restarted session.
  Future<void> _beginReadiness() async {
    final gen = _run.lifecycleGeneration;
    try {
      final ack = await _ws.sendBeginReadiness();
      if (!mounted) return;
      if (_run.lifecycleGeneration != gen) return;
      if (!ack.accepted) {
        final message =
            ack.message ?? ack.errorCode ?? 'Readiness check was rejected.';
        _run.onPreviewFeedback(
          hasJpegFrame: false,
          isFatal: true,
          fatalMessage: message,
        );
        unawaited(_stopWebSocketSession());
        setState(() {
          _sessionError = message;
          _clearFrame();
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (_run.lifecycleGeneration != gen) return;
      final message = error is CommandTimeoutException
          ? 'Readiness check timed out. Check the backend and try again.'
          : 'Readiness check failed. Check the backend and try again.';
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: message,
      );
      unawaited(_stopWebSocketSession());
      setState(() {
        _sessionError = message;
        _clearFrame();
      });
    }
  }

  /// Auto-start entry after the Ready beat (or shared confirm path).
  void _onStartPractice() {
    if (_leaving || _commandInFlight) return;
    final stable = _run.readiness.stable || (_run.readinessStable == true);
    if (!_run.requestStartPractice(readinessStable: stable)) return;
    setState(() {});
    unawaited(_confirmReadinessAndCountdown());
  }

  /// Send confirm_readiness; enter countdown only after backend acceptance.
  Future<void> _confirmReadinessAndCountdown() async {
    final gen = _run.lifecycleGeneration;
    _commandInFlight = true;
    try {
      final ack = await _ws.sendConfirmReadiness();
      if (!mounted) return;
      if (_run.lifecycleGeneration != gen) return;

      if (!ack.accepted) {
        final code = ack.errorCode;
        // readiness_not_stable and readiness_stale are recoverable: stay in
        // readiness and let the user try again once stable.
        if (code == 'readiness_not_stable' || code == 'readiness_stale') {
          _run.onConfirmReadinessRejected(
            errorCode: code,
            message: ack.message,
          );
          setState(() {});
          return;
        }
        _run.onConfirmReadinessRejected(errorCode: code, message: ack.message);
        final message =
            ack.message ??
            ack.errorCode ??
            'Readiness confirmation was rejected.';
        _run.onPreviewFeedback(
          hasJpegFrame: false,
          isFatal: true,
          fatalMessage: message,
        );
        unawaited(_stopWebSocketSession());
        setState(() {
          _sessionError = message;
          _clearFrame();
        });
        return;
      }

      if (!_run.onConfirmReadinessAccepted()) return;
      unawaited(
        context.read<TutorialProgressService>().markCameraSetupComplete(),
      );
      setState(() {});
      unawaited(_startGuidedCountdownOverlay());
    } catch (error) {
      if (!mounted) return;
      if (_run.lifecycleGeneration != gen) return;
      _run.onConfirmReadinessRejected();
      final message = error is CommandTimeoutException
          ? 'Readiness confirmation timed out. Check the backend and try again.'
          : 'Readiness confirmation failed. Check the backend and try again.';
      setState(() {
        _sessionError = message;
      });
    } finally {
      _commandInFlight = false;
      if (mounted) setState(() {});
    }
  }

  /// Play the countdown SFX after requestStartPractice enters countdown.
  ///
  /// The [GameCountdownOverlay] is already mounted because [_run.isCountdown]
  /// became true. When the overlay animation completes it calls
  /// [_beginSessionAfterCountdown] via [onCountdownComplete].
  Future<void> _startGuidedCountdownOverlay() async {
    final settings = context.read<SettingsService>();
    await _sfx.setVolume(settings.soundEnabled ? settings.musicVolume : 0.0);
    await _sfx.playCountdown();
    // SFX completes; the overlay drives the rest via onCountdownComplete.
  }

  Future<void> _onMovementConfirmed() async {
    if (_movementConfirmedShowing) return;
    _movementConfirmedShowing = true;

    _run.markCompleted();
    if (mounted) setState(() {});

    // One completion dialog for beginners (skip separate victory screen).
    await _stopSession(heldSteady: true);
    _movementConfirmedShowing = false;
    _confirmedEvidenceJpegBytes = null;
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      await _ws.connect();
    } catch (error, stackTrace) {
      debugPrint('Practice connection failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _sessionError = 'Camera service unavailable.');
      }
    } finally {
      _connecting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _resetInterruptedAttempt() async {
    _commandInFlight = false;
    _run.cancelToIdle();
    await _stopWebSocketSession();
    await _music.stop();
    await _sfx.stop();
    if (!mounted) return;
    setState(_clearSessionState);
  }

  Future<void> _retrySession() async {
    if (_leaving || _connecting) return;
    await _resetInterruptedAttempt();
    if (!mounted || _leaving) return;
    await _connect();
    if (!mounted || !_ws.isConnected) return;
    await _startSession();
  }

  Future<void> _chooseCamera() async {
    await _resetInterruptedAttempt();
    if (!mounted || _leaving) return;
    await SettingsScreen.show(
      context,
      initialSection: SettingsSection.practice,
    );
  }

  Future<void> _startSession() async {
    if (_leaving) return;
    if (!_ws.isConnected) {
      _connect();
      return;
    }
    if (_commandInFlight) return;
    if (_run.phase != PracticeRunPhase.idle &&
        _run.phase != PracticeRunPhase.error) {
      return;
    }

    _clearSessionState();
    _ws.beginPracticeAttempt();
    _run.beginPreparing(onTimeout: _onPreparationTimeout);
    setState(() {});

    final cameraDeviceId = await context
        .read<SettingsService>()
        .loadSelectedCameraDeviceId();
    if (!mounted) return;
    if (!_run.isPreparingCamera) return;

    _ws.startupDiagnostics.annotate(
      sessionMode: 'guided',
      movement: _movement,
      camera: cameraDiagnosticIdentity(
        deviceId: cameraDeviceId,
        identityStable:
            cameraDeviceId != null && !cameraDeviceId.startsWith('opencv:'),
      ),
    );

    final settings = context.read<SettingsService>();
    _commandInFlight = true;
    try {
      final ack = await _ws.sendPrepare(
        movement: _movement,
        difficulty: _difficulty,
        prop: _prop,
        cameraDeviceId: cameraDeviceId,
        legacyCameraIndex: cameraDeviceId == null
            ? settings.pendingLegacyCameraIndex
            : null,
      );
      if (!mounted) return;
      if (!_run.isPreparingCamera) return;

      if (!ack.accepted) {
        final message =
            ack.message ?? ack.errorCode ?? 'Camera preparation was rejected.';
        _run.onPreviewFeedback(
          hasJpegFrame: false,
          isFatal: true,
          fatalMessage: message,
        );
        unawaited(_stopWebSocketSession());
        setState(() {
          _sessionError = message;
          _sessionErrorCode = ack.errorCode;
          _clearFrame();
        });
      }
    } catch (error) {
      if (!mounted) return;
      if (!_run.isPreparingCamera) return;
      final message = error is CommandTimeoutException
          ? 'Camera preparation timed out. Check the backend and try again.'
          : 'Camera preparation failed. Check the backend and try again.';
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: message,
      );
      unawaited(_stopWebSocketSession());
      setState(() {
        _sessionError = message;
        _sessionErrorCode = error is CommandTimeoutException
            ? 'prepare_timeout'
            : null;
        _clearFrame();
      });
    } finally {
      _commandInFlight = false;
    }
  }

  void _onPreparationTimeout() {
    if (!mounted) return;
    unawaited(_stopWebSocketSession());
    unawaited(_music.stop());
    unawaited(_sfx.stop());
    setState(() {
      _sessionError = _run.errorMessage;
      _sessionErrorCode = 'prepare_timeout';
      _clearFrame();
    });
  }

  Future<void> _beginSessionAfterCountdown() async {
    if (!mounted) return;
    if (!_run.isCountdown) return;
    if (_commandInFlight) return;
    if (!_ws.isConnected) {
      _run.cancelToIdle();
      _connect();
      return;
    }

    _commandInFlight = true;
    try {
      final ack = await _ws.sendActivate();
      if (!mounted) return;
      if (!_run.isCountdown) return;

      if (!ack.accepted) {
        if (ack.errorCode == 'readiness_not_confirmed') {
          _run.onActivationRejected();
          setState(() {
            _sessionError =
                ack.message ??
                'Readiness must be confirmed before practice can start.';
          });
          return;
        }
        final message =
            ack.message ?? ack.errorCode ?? 'Session activation was rejected.';
        _run.onPreviewFeedback(
          hasJpegFrame: false,
          isFatal: true,
          fatalMessage: message,
        );
        unawaited(_stopWebSocketSession());
        setState(() {
          _sessionError = message;
          _sessionErrorCode = ack.errorCode;
          _clearFrame();
        });
        return;
      }

      _run.enterActive();
      _sfx.stop();
      final settings = context.read<SettingsService>();
      final volume = settings.soundEnabled ? settings.musicVolume : 0.0;
      await _music.setVolume(volume);
      _music.start(resolveTrack(settings.selectedMusicTrackId));
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      final message = error is CommandTimeoutException
          ? 'Session activation timed out. Try starting again.'
          : 'Session activation failed. Try starting again.';
      _run.onPreviewFeedback(
        hasJpegFrame: false,
        isFatal: true,
        fatalMessage: message,
      );
      unawaited(_stopWebSocketSession());
      setState(() {
        _sessionError = message;
        _sessionErrorCode = error is CommandTimeoutException
            ? 'command_timeout'
            : null;
        _clearFrame();
      });
    } finally {
      _commandInFlight = false;
    }
  }

  bool get _hasSessionData =>
      _run.elapsedSeconds > 0 ||
      _feedback.feedbackHistory.isNotEmpty ||
      _feedback.latestFeedback != null;

  void _clearSessionState() {
    _feedback.reset();
    _sessionError = null;
    _sessionErrorCode = null;
    _clearFrame();
    _assessmentNotifier.value = null;
    _holdProgressNotifier.value = 0;
    _comboNotifier.value = const ComboState();
    _scorePopupNotifier.value = const ScorePopupState();
    _calloutNotifier.value = const PerformanceCalloutState();
    _lastPulsedTotal = null;
    _movementConfirmedShowing = false;
  }

  Future<void> _cancelPreActive() async {
    _run.cancelToIdle();
    await _stopWebSocketSession();
    unawaited(_music.stop());
    unawaited(_sfx.stop());
    _commandInFlight = false;
    _clearSessionState();
    if (mounted) setState(() {});
  }

  Future<void> _stopSession({bool heldSteady = false}) async {
    if (_isShowingSummary || _leaving || _stopInFlight || _quitDialogOpen) {
      return;
    }
    _stopInFlight = true;
    try {
      // Cancel during prepare/readiness/countdown/error: no summary.
      if (_run.isPreparingCamera ||
          _run.isReadiness ||
          _run.isCountdown ||
          _run.isError) {
        await _cancelPreActive();
        return;
      }

      final wasTraining =
          _run.isTrainingActive || _run.phase == PracticeRunPhase.completed;
      if (!wasTraining) {
        await _cancelPreActive();
        if (_leaving || !mounted) return;
        _goPracticeExit(catalog: true);
        return;
      }

      final router = GoRouter.of(context);
      final sessionService = context.read<SessionService>();
      final authUser = context.read<AuthService>().currentUser;
      final userId = authUser?.id;
      final displayName = authUser?.fullName ?? 'Trainee';
      final settings = context.read<SettingsService>();
      final tutorialProgress = context.read<TutorialProgressService>();
      final sfxVolume = settings.soundEnabled ? settings.musicVolume : 0.0;

      await _stopWebSocketSession();
      if (_leaving || !mounted) return;
      if (_run.phase == PracticeRunPhase.active) {
        _run.markCompleted();
      }
      unawaited(_music.stop());
      // Do not await _sfx.stop() here. playCongrats() already stops then
      // plays on the same AudioPlayer; a parallel stop can race and mute it.

      if (!_hasSessionData && _run.elapsedSeconds == 0) {
        // Still show summary for an activated session with zero elapsed when
        // there was at least a feedback snapshot; otherwise return to catalog.
        if (_feedback.latestFeedback == null &&
            _feedback.feedbackHistory.isEmpty) {
          _run.cancelToIdle();
          _clearSessionState();
          if (mounted && !_leaving) {
            router.go(_practiceExitLocation(catalog: true));
          }
          return;
        }
      }

      if (userId == null) {
        _run.cancelToIdle();
        _clearSessionState();
        if (mounted && !_leaving) setState(() {});
        if (mounted && !_leaving) {
          router.go(_practiceExitLocation(catalog: true));
        }
        return;
      }

      // Assessment V2 requires a rubric to persist. A session that ended before
      // any assessment frame arrived saves an explicit all-zero rubric rather
      // than fabricating criterion scores.
      final summaryRubric =
          _feedback.latestFeedback?.assessment ?? _emptyRubric;
      final summaryDuration = _run.elapsedSeconds;
      final sessionAssessment = _feedback.buildSessionAssessment(
        movement: _movement,
        prop: _prop,
        rubric: summaryRubric,
        heldSteady: heldSteady,
      );
      var saveEvidence = false;
      final evidence = _confirmedEvidenceJpegBytes;
      if (heldSteady && evidence != null) {
        final preference = await sessionService.sessionEvidenceEnabled(userId);
        if (_leaving || !mounted) return;
        if (preference == null) {
          saveEvidence = await _askEvidenceConsent() ?? false;
          if (_leaving || !mounted) return;
          await sessionService.setSessionEvidenceEnabled(
            userId: userId,
            enabled: saveEvidence,
          );
          if (_leaving || !mounted) return;
        } else {
          saveEvidence = preference;
        }
      }
      if (_leaving) return;
      _isShowingSummary = true;
      if (mounted) setState(() {});
      try {
        unawaited(_playCongratsBestEffort(sfxVolume));
        if (!mounted || _leaving) return;
        final nextStep = widget.assignmentContext == null
            ? nextEnabledPracticeAfter(_movement, _prop)
            : null;
        // Reserve before the first write. The sheet retains this identifier on
        // every retry, including when the first atomic write committed but the
        // client received an ambiguous transport failure.
        final reservedSessionId = sessionService.reserveSessionId();
        ClassChallengeCompletionReceipt? challengeReceipt;
        final result = await SessionSummarySheet.show(
          context,
          movement: _movement,
          durationSeconds: summaryDuration,
          assessment: sessionAssessment,
          nextMovement: nextStep?.movement,
          nextProp: nextStep?.prop,
          evidenceJpegBytes: evidence,
          initialSessionId: reservedSessionId,
          showSavedAcknowledgment: true,
          onSave: (existingSessionId) async {
            final sessionId = await sessionService.saveCompletedSession(
              existingSessionId: existingSessionId,
              userId: userId,
              displayName: displayName,
              profilePictureUrl: authUser?.profilePictureUrl,
              movementName: _movement,
              difficulty: _difficulty,
              prop: _prop,
              rubric: summaryRubric,
              durationSeconds: summaryDuration,
              sessionImprovements: sessionAssessment.improvementFeedbacks,
              evidenceJpegBytes: evidence,
              saveEvidence: saveEvidence,
              assignmentContext: widget.assignmentContext,
              challengeContext: widget.challengeContext,
            );
            final complete = widget.onChallengeComplete;
            if (complete != null) challengeReceipt = await complete(sessionId);
            return sessionId;
          },
        );

        if (!mounted || _leaving) return;

        if (result == SessionSummaryResult.tryAgain) {
          await _sfx.stop();
          _clearSessionState();
          _run.cancelToIdle();
          setState(() {});
          await _startSession();
          return;
        }

        if (result == SessionSummaryResult.next && nextStep != null) {
          // Session was already persisted by the summary primary action.
          unawaited(tutorialProgress.completeFirstSessionGuidance());
          // Don't block navigation on SFX teardown.
          unawaited(_sfx.stop());
          _clearSessionState();
          _run.cancelToIdle();
          final encoded = Uri.encodeComponent(nextStep.movement.name);
          router.go(
            '/practice?movement=$encoded'
            '&difficulty=${nextStep.movement.difficulty}'
            '&prop=${nextStep.prop.protocolValue}',
          );
          return;
        }

        // End congrats before leaving practice. Do NOT stop again in finally —
        // Try Again starts preparation on the same player and a finally stop
        // would silence it immediately.
        await _sfx.stop();
        if (_leaving || !mounted) return;

        if (result == SessionSummaryResult.saved) {
          unawaited(tutorialProgress.completeFirstSessionGuidance());
          final receipt = challengeReceipt;
          if (receipt != null && mounted && !_leaving) {
            await _showChallengeResult(
              score: summaryRubric.total,
              receipt: receipt,
            );
          }
        }

        _clearSessionState();
        _run.cancelToIdle();
        setState(() {});

        router.go(
          result == SessionSummaryResult.saved
              ? _practiceExitLocation(catalog: false)
              : _practiceExitLocation(catalog: true),
        );
      } finally {
        _isShowingSummary = false;
      }
    } finally {
      _stopInFlight = false;
    }
  }

  Future<void> _showChallengeResult({
    required int score,
    required ClassChallengeCompletionReceipt receipt,
  }) {
    final previous = widget.previousChallengeBest;
    final isNewBest = previous == null || score > previous;
    return showDialog<void>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(isNewBest ? 'New personal best!' : 'Challenge complete'),
        content: Text(
          'Final score: $score/12\n'
          '${previous == null ? 'Previous best: —' : 'Previous best: $previous/12'}\n'
          'Current class rank: ${receipt.rank == null ? '—' : '#${receipt.rank}'}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('View Class Leaderboard'),
          ),
        ],
      ),
    );
  }

  Future<void> _playCongratsBestEffort(double volume) async {
    try {
      await _sfx.setVolume(volume);
      await _sfx.playCongrats();
    } catch (error, stackTrace) {
      debugPrint('Congrats SFX failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<bool?> _askEvidenceConsent() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 500),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(FluentIcons.camera, size: 19),
            ),
            const SizedBox(width: AppSpacing.md),
            const Expanded(child: Text('Save your confirmed movement?')),
          ],
        ),
        content: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: context.elixBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.elixBorder),
          ),
          child: const Text(
            'We captured one annotated image from the exact frame that '
            'confirmed your movement. It is private to your account, never '
            'shared to profiles or leaderboards, and can be deleted anytime '
            'in Settings → Privacy.',
            style: TextStyle(fontSize: 15, height: 1.45),
          ),
        ),
        actions: [
          SizedBox(
            width: 198,
            height: 56,
            child: Button(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text(
                'Save without image',
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox(
            width: 198,
            height: 56,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context, rootNavigator: true).pop(true),
              child: const Text(
                'Enable & save image',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _instructionForMovement(String movement) {
    for (final m in movementCatalog) {
      if (m.name == movement) return m.description;
    }
    return 'Follow the on-screen guidance for this movement.';
  }

  String _practiceExitLocation({required bool catalog}) {
    final challengeLocation = widget.challengeReturnLocation;
    if (challengeLocation != null) return challengeLocation;
    final assignment = widget.assignmentContext;
    if (assignment != null) {
      return AppRoutePaths.assignmentDetail(assignment.assignmentId);
    }
    return catalog ? AppRoutePaths.movements : AppRoutePaths.dashboard;
  }

  void _goPracticeExit({required bool catalog}) {
    context.go(_practiceExitLocation(catalog: catalog));
  }

  bool get _shouldConfirmAbandon =>
      trainingShouldConfirmAbandon(runPhase: _run.phase);

  Future<void> _abandonAndLeave() async {
    if (_leaving || _isShowingSummary || _stopInFlight) return;
    _leaving = true;
    final router = GoRouter.of(context);
    final location = _practiceExitLocation(catalog: true);
    final feedbackSub = _feedbackSub;
    final previewSub = _previewSub;
    _feedbackSub = null;
    _previewSub = null;
    unawaited(feedbackSub?.cancel() ?? Future<void>.value());
    unawaited(previewSub?.cancel() ?? Future<void>.value());
    _ws.removeListener(_onWsStateChanged);
    _run.removeListener(_onRunChanged);
    await _stopWebSocketSession();
    _run.cancelToIdle();
    unawaited(_music.stop());
    unawaited(_sfx.stop());
    _commandInFlight = false;
    _clearSessionState();
    router.go(location);
  }

  Future<void> _confirmAbandonThen(Future<void> Function() onConfirmed) async {
    if (_leaving || _isShowingSummary || _quitDialogOpen || _stopInFlight) {
      return;
    }
    _quitDialogOpen = true;
    try {
      final confirmed = await showTrainingQuitDialog(
        context,
        copy: TrainingQuitCopy.practice,
      );
      if (confirmed && mounted && !_leaving && !_stopInFlight) {
        await onConfirmed();
      }
    } finally {
      _quitDialogOpen = false;
    }
  }

  Future<void> _onCancelPressed() async {
    if (_leaving || _quitDialogOpen || _stopInFlight) return;
    if (!_shouldConfirmAbandon) {
      await _cancelPreActive();
      return;
    }
    await _confirmAbandonThen(_cancelPreActive);
  }

  Future<void> _onBack() async {
    if (_isShowingSummary || _leaving || _stopInFlight) return;
    if (!_shouldConfirmAbandon) {
      _goPracticeExit(catalog: true);
      return;
    }
    await _confirmAbandonThen(_abandonAndLeave);
  }

  @visibleForTesting
  PracticeRunController get debugRun => _run;

  @visibleForTesting
  WebSocketService get debugWebSocket => _ws;

  TrainingActionKind _actionKind() {
    return switch (_run.phase) {
      PracticeRunPhase.active => TrainingActionKind.finish,
      PracticeRunPhase.preparingCamera ||
      PracticeRunPhase.readiness ||
      PracticeRunPhase.countdown => TrainingActionKind.cancel,
      PracticeRunPhase.error => TrainingActionKind.retry,
      PracticeRunPhase.idle ||
      PracticeRunPhase.completed => TrainingActionKind.start,
    };
  }

  TrainingSessionPhase _panelPhase() {
    return switch (_run.phase) {
      PracticeRunPhase.idle => TrainingSessionPhase.ready,
      PracticeRunPhase.preparingCamera => TrainingSessionPhase.preparingCamera,
      PracticeRunPhase.readiness => TrainingSessionPhase.readiness,
      PracticeRunPhase.countdown => TrainingSessionPhase.getReady,
      PracticeRunPhase.active => TrainingSessionPhase.inProgress,
      PracticeRunPhase.completed => TrainingSessionPhase.completed,
      PracticeRunPhase.error => TrainingSessionPhase.cameraError,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isTrainingActive = _run.isTrainingActive;
    final isCameraLive = _run.isCameraSessionLive;
    final hasConnectionError =
        _ws.connectionState == WebSocketConnectionState.error;

    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: SizedBox.expand(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm + 2,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = math.min(
                  constraints.maxWidth,
                  _maxContentWidth,
                );
                final isDesktop = contentWidth >= _desktopBreakpoint;
                final isCompact =
                    contentWidth >= _compactBreakpoint && !isDesktop;

                final header = TrainingSessionHeader(
                  onBack: _onBack,
                  title: widget.challengeContext == null
                      ? _movement
                      : 'Class Challenge · $_movement',
                  statusPill: _difficulty,
                  statusPillColor: trainingDifficultyColor(_difficulty),
                  instruction: _instructionForMovement(_movement),
                  connectionState: _ws.connectionState,
                  connecting: _connecting,
                  wideLayout: isDesktop || isCompact,
                );
                final camera = _buildCamera(
                  isTrainingActive: isTrainingActive,
                  isCameraLive: isCameraLive,
                );
                final panel = _buildPanel(
                  isTrainingActive: isTrainingActive,
                  hasConnectionError: hasConnectionError,
                  expandVertically: isDesktop,
                );

                final body = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, workspaceConstraints) {
                          final workspace = TrainingArenaWorkspace(
                            desktop: isDesktop,
                            contentWidth: contentWidth,
                            workspaceHeight: workspaceConstraints.maxHeight,
                            camera: camera,
                            panel: panel,
                          );

                          if (isDesktop) {
                            return workspace;
                          }

                          return SingleChildScrollView(child: workspace);
                        },
                      ),
                    ),
                  ],
                );

                if (constraints.maxWidth <= _maxContentWidth) {
                  return body;
                }

                return Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(width: _maxContentWidth, child: body),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCamera({
    required bool isTrainingActive,
    required bool isCameraLive,
  }) {
    return TrainingCameraWorkspace(
      frameListenable: _frameBytes,
      mirrored: context.watch<SettingsService>().cameraMirrored,
      connectionState: _ws.connectionState,
      connecting: _connecting,
      isSessionActive: isCameraLive && !_run.isPreparingCamera,
      isPreparingCamera: _run.isPreparingCamera,
      accentBorder:
          _run.isPreparingCamera || _run.isReadiness || _run.isCountdown,
      readyAura: _run.isReadiness && _run.readiness.stable,
      idleTitle: 'Training Arena',
      idleSubtitle: 'Press Start Camera Setup when you are ready.',
      idleCaption: 'Keep your upper body, hands, and bottle visible.',
      errorMessage: _ws.errorMessage,
      sessionError: _sessionError ?? _run.errorMessage,
      recoveryPresentation:
          (_sessionError ?? _run.errorMessage) != null ||
              _ws.connectionState == WebSocketConnectionState.error
          ? CameraRecoveryPresentation.fromFailure(
              errorCode: _sessionErrorCode,
              diagnosticMessage:
                  _sessionError ?? _run.errorMessage ?? _ws.errorMessage,
              connectionFailed:
                  _ws.connectionState == WebSocketConnectionState.error,
            )
          : null,
      onRetry: _retrySession,
      onChooseCamera: _chooseCamera,
      onOpenSetupHelp: () => showCameraRecoverySetupHelp(context),
      countdownActive: _run.isCountdown,
      onCountdownComplete: _beginSessionAfterCountdown,
      overlayFeedback: isTrainingActive ? null : _feedback.latestFeedback,
      overlays: isTrainingActive
          ? TrainingLiveHud(
              elapsedDisplay: _formatDuration(_run.elapsedSeconds),
              assessmentListenable: _assessmentNotifier,
              holdListenable: _holdProgressNotifier,
              comboListenable: _comboNotifier,
              scorePopupListenable: _scorePopupNotifier,
              calloutListenable: _calloutNotifier,
              coaching: _feedback.latestFeedback,
            )
          : null,
    );
  }

  Widget _buildPanel({
    required bool isTrainingActive,
    required bool hasConnectionError,
    required bool expandVertically,
  }) {
    final actionKind = _actionKind();
    final isReadiness = _run.isReadiness;
    final readiness = _run.readiness;
    final isCalibrating =
        _run.isPreparingCamera || _run.isReadiness || _run.isCountdown;

    return TrainingSessionPanel(
      phase: _panelPhase(),
      expandVertically: expandVertically,
      rankBadge: isTrainingActive
          ? ValueListenableBuilder<RubricAssessment?>(
              valueListenable: _assessmentNotifier,
              builder: (context, assessment, _) =>
                  RankBadge(level: assessment?.performanceLevel),
            )
          : null,
      metrics: isCalibrating
          ? TrainingStageIndicator(
              cameraActive: _run.isPreparingCamera,
              cameraDone:
                  !_run.isPreparingCamera &&
                  (_run.isReadiness || _run.isCountdown),
              setupActive: _run.isReadiness,
              setupDone: _run.isCountdown,
              practiceActive: _run.isCountdown,
            )
          : isTrainingActive
          ? SessionMetricTiles(
              elapsedDisplay: _formatDuration(_run.elapsedSeconds),
              rubricChild: ValueListenableBuilder<RubricAssessment?>(
                valueListenable: _assessmentNotifier,
                builder: (context, assessment, _) {
                  return ScaleTransition(
                    scale: _scorePulse,
                    child: Text(
                      assessment != null
                          ? '${assessment.total} / ${RubricScale.maxTotal}'
                          : '—',
                      style: AppTheme.sectionTitle(
                        context,
                        color: AppColors.primary,
                      ).copyWith(fontWeight: FontWeight.w800),
                    ),
                  );
                },
              ),
              performanceBar: ValueListenableBuilder<RubricAssessment?>(
                valueListenable: _assessmentNotifier,
                builder: (context, assessment, _) =>
                    TrainingPerformanceBar(total: assessment?.total),
              ),
              rubricBreakdown: ValueListenableBuilder<RubricAssessment?>(
                valueListenable: _assessmentNotifier,
                builder: (context, assessment, _) =>
                    RubricCriteriaTiles(assessment: assessment),
              ),
            )
          : const TrainingReadyBrief(
              title: 'Ready to train',
              body:
                  'Start Camera Setup to prepare the camera, complete the setup check, then begin scored practice.',
            ),
      statusContent: (isReadiness || (_run.isCountdown && readiness.frozen))
          ? ReadinessChecklistPanel(
              items: readiness.displayItems,
              progress: readiness.stableProgress,
              stable: readiness.stable,
              complete: readiness.complete,
              frozen: readiness.frozen,
              streamStale: readiness.streamStale,
              recoverableMessage: readiness.recoverableMessage,
              readyCount: readiness.readyCount,
            )
          : TrainingStatusRow(
              detection: resolveDetectionStatus(
                sessionActive: isTrainingActive,
                bottleDetected: _feedback.latestFeedback?.bottleDetected,
              ),
              propLabel: _prop.displayLabel,
              postureLabel: postureDisplayLabel(
                isTrainingActive
                    ? _feedback.latestFeedback?.postureStatus
                    : null,
              ),
            ),
      supportingContent: ValueListenableBuilder<ComboState>(
        valueListenable: _comboNotifier,
        builder: (context, comboState, _) {
          return Column(
            children: [
              SessionSetupRow(
                icon: FluentIcons.play_solid,
                label: 'Movement',
                value: _movement,
              ),
              SessionSetupRow(
                icon: FluentIcons.speed_high,
                label: 'Difficulty',
                value: _difficulty,
              ),
              SessionSetupRow(
                icon: FluentIcons.diet_plan_notebook,
                label: 'Prop',
                value: _prop.displayLabel,
              ),
              if (comboState.bestCombo > 1)
                SessionSetupRow(
                  icon: FluentIcons.lightning_bolt,
                  label: 'Best combo',
                  value: 'x${comboState.bestCombo}',
                ),
            ],
          );
        },
      ),
      compactStatusNote: (_sessionError ?? _run.errorMessage) != null
          ? Text(
              _sessionError ?? _run.errorMessage!,
              style: AppTheme.bodySecondary.copyWith(color: AppColors.error),
            )
          : (hasConnectionError
                ? Text(
                    _ws.errorMessage ??
                        'Camera setup is unavailable. Check that ELIXR is running, then try again.',
                    style: AppTheme.bodySecondary.copyWith(
                      color: AppColors.error,
                    ),
                  )
                : null),
      onViewTutorial: () => _showTutorial(isSessionActive: isTrainingActive),
      actionArea: isReadiness
          ? _buildReadinessActionArea()
          : TrainingActionArea(
              kind: actionKind,
              startLabel: 'Start Camera Setup',
              onPressed: switch (actionKind) {
                TrainingActionKind.finish => () => _stopSession(),
                TrainingActionKind.cancel => _onCancelPressed,
                TrainingActionKind.retry || TrainingActionKind.start =>
                  _ws.isConnected ? _startSession : _connect,
              },
              isLoading:
                  actionKind == TrainingActionKind.cancel ||
                      actionKind == TrainingActionKind.finish
                  ? false
                  : (_connecting || _commandInFlight),
            ),
    );
  }

  void _showTutorial({required bool isSessionActive}) {
    final movement = movementCatalog
        .where((item) => item.name == _movement)
        .firstOrNull;
    if (movement == null) return;

    showDialog<void>(
      context: context,
      builder: (context) => MovementTutorialDialog(
        movement: movement,
        prop: _prop,
        lesson: MovementLesson.forMovement(movement),
        sessionActive: isSessionActive,
      ),
    );
  }

  /// Action area shown during the readiness gate: status + Cancel (auto-start).
  Widget _buildReadinessActionArea() {
    final readiness = _run.readiness;
    final starting =
        readiness.confirming ||
        _commandInFlight ||
        (readiness.canStartPractice && _run.isReadiness);
    final statusText = starting ? 'Starting\u2026' : 'Hold steady\u2026';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            statusText,
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        HyperlinkButton(
          onPressed: _onCancelPressed,
          child: Text(
            'Cancel',
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
