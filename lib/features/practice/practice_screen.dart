import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
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
import '../../data/models/session_assignment_context.dart';
import '../../data/models/training_prop.dart';
import '../../data/models/ws_protocol.dart';
import '../../services/auth_service.dart';
import '../../services/practice_music_service.dart';
import '../../services/practice_sfx_service.dart';
import '../../services/session_service.dart';
import '../../services/settings_service.dart';
import '../../services/tutorial_progress_service.dart';
import '../../services/websocket_service.dart';
import 'practice_feedback_controller.dart';
import 'practice_game_widgets.dart';
import 'practice_run_phase.dart';
import 'session_summary_sheet.dart';
import 'widgets/readiness_checklist_panel.dart';
import 'widgets/training_action_area.dart';
import 'widgets/training_camera_workspace.dart';
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
  });

  final String movement;
  final String difficulty;
  final TrainingProp prop;

  /// Trusted official assignment identity from `/assigned-practice/:id`.
  /// Ordinary catalog practice leaves this null.
  final SessionAssignmentContext? assignmentContext;

  static const cameraAspectWidth = 640.0;
  static const cameraAspectHeight = 480.0;

  static double panelWidthForContent(double contentWidth) {
    return math.min(
      AppSpacing.practicePanelMaxWidth,
      math.max(AppSpacing.practicePanelMinWidth, contentWidth * 0.28),
    );
  }

  @visibleForTesting
  static Size desktopCameraSize({
    required double contentWidth,
    required double workspaceHeight,
  }) {
    final panelWidth = panelWidthForContent(contentWidth);
    final availableCameraWidth =
        contentWidth - panelWidth - AppSpacing.practiceCameraPanelGap;
    final cameraWidth = math.min(
      availableCameraWidth,
      workspaceHeight * cameraAspectWidth / cameraAspectHeight,
    );
    final cameraHeight = cameraWidth * cameraAspectHeight / cameraAspectWidth;
    return Size(cameraWidth, cameraHeight);
  }

  @visibleForTesting
  static Size stackedCameraSize(double contentWidth) {
    return Size(
      contentWidth,
      contentWidth * cameraAspectHeight / cameraAspectWidth,
    );
  }

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen>
    with SingleTickerProviderStateMixin {
  late final String _movement = widget.movement;
  late final String _difficulty = widget.difficulty;
  late final TrainingProp _prop = widget.prop;

  final _ws = WebSocketService();
  final _music = PracticeMusicService();
  final _sfx = PracticeSfxService();
  final _run = PracticeRunController();
  final _feedback = PracticeFeedbackController();
  final _comboNotifier = ValueNotifier<ComboState>(const ComboState());
  final _scorePopupNotifier = ValueNotifier<ScorePopupState>(
    const ScorePopupState(),
  );

  StreamSubscription<PracticeFeedback>? _feedbackSub;
  StreamSubscription<PreviewFrame>? _previewSub;
  final ValueNotifier<Uint8List?> _frameBytes = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<RubricAssessment?> _assessmentNotifier =
      ValueNotifier<RubricAssessment?>(null);
  final ValueNotifier<double> _holdProgressNotifier = ValueNotifier<double>(0);
  bool _connecting = false;
  String? _sessionError;
  bool _isShowingSummary = false;
  bool _movementConfirmedShowing = false;
  bool _commandInFlight = false;
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
    _connect();
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
    _music.dispose();
    _sfx.dispose();
    _ws.removeListener(_onWsStateChanged);
    _run.removeListener(_onRunChanged);
    _run.dispose();
    _ws.dispose();
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
    if (!mounted) return;
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
    if (!mounted) return;
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
    if (!mounted) return;

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
    if (_commandInFlight) return;
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
    setState(() => _connecting = true);
    await _ws.connect();
    if (mounted) setState(() => _connecting = false);
  }

  Future<void> _startSession() async {
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
          _clearFrame();
        });
      }
    } catch (error) {
      if (!mounted) return;
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
    _clearFrame();
    _assessmentNotifier.value = null;
    _holdProgressNotifier.value = 0;
    _comboNotifier.value = const ComboState();
    _scorePopupNotifier.value = const ScorePopupState();
    _lastPulsedTotal = null;
    _movementConfirmedShowing = false;
  }

  Future<void> _cancelPreActive() async {
    await _stopWebSocketSession();
    _run.cancelToIdle();
    await _music.stop();
    await _sfx.stop();
    _clearSessionState();
    if (mounted) setState(() {});
  }

  Future<void> _stopSession({bool heldSteady = false}) async {
    if (_isShowingSummary) return;

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
      if (mounted) _goPracticeExit(catalog: true);
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
        if (mounted) router.go(_practiceExitLocation(catalog: true));
        return;
      }
    }

    if (userId == null) {
      _run.cancelToIdle();
      _clearSessionState();
      if (mounted) setState(() {});
      if (mounted) router.go(_practiceExitLocation(catalog: true));
      return;
    }

    // Assessment V2 requires a rubric to persist. A session that ended before
    // any assessment frame arrived saves an explicit all-zero rubric rather
    // than fabricating criterion scores.
    final summaryRubric = _feedback.latestFeedback?.assessment ?? _emptyRubric;
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
      if (!mounted) return;
      if (preference == null) {
        saveEvidence = await _askEvidenceConsent() ?? false;
        await sessionService.setSessionEvidenceEnabled(
          userId: userId,
          enabled: saveEvidence,
        );
        if (!mounted) return;
      } else {
        saveEvidence = preference;
      }
    }
    _isShowingSummary = true;
    if (mounted) setState(() {});
    try {
      unawaited(_playCongratsBestEffort(sfxVolume));
      if (!mounted) return;
      final nextStep = widget.assignmentContext == null
          ? nextEnabledPracticeAfter(_movement, _prop)
          : null;
      final result = await SessionSummarySheet.show(
        context,
        movement: _movement,
        durationSeconds: summaryDuration,
        assessment: sessionAssessment,
        nextMovement: nextStep?.movement,
        nextProp: nextStep?.prop,
        evidenceJpegBytes: evidence,
        onSave: (existingSessionId) => sessionService.saveCompletedSession(
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
        ),
      );

      if (!mounted) return;

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

      if (result == SessionSummaryResult.saved) {
        unawaited(tutorialProgress.completeFirstSessionGuidance());
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
              onPressed: () => Navigator.of(context).pop(false),
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
              onPressed: () => Navigator.of(context).pop(true),
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

  bool get _isAssignedPractice => widget.assignmentContext != null;

  String _practiceExitLocation({required bool catalog}) {
    if (_isAssignedPractice) return AppRoutePaths.assignedMovements;
    return catalog ? AppRoutePaths.movements : AppRoutePaths.dashboard;
  }

  void _goPracticeExit({required bool catalog}) {
    context.go(_practiceExitLocation(catalog: catalog));
  }

  void _onBack() {
    if (_isShowingSummary) return;
    if (_run.isPreparingCamera || _run.isReadiness || _run.isCountdown) {
      _cancelPreActive();
      return;
    }
    if (_hasSessionData || _run.isTrainingActive) {
      _stopSession();
    } else {
      _goPracticeExit(catalog: true);
    }
  }

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
                  title: _movement,
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
                          final workspace = isDesktop
                              ? _buildDesktopWorkspace(
                                  contentWidth: contentWidth,
                                  workspaceHeight:
                                      workspaceConstraints.maxHeight,
                                  camera: camera,
                                  panel: panel,
                                )
                              : _buildStackedWorkspace(
                                  contentWidth: contentWidth,
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
      errorMessage: _ws.errorMessage,
      sessionError: _sessionError ?? _run.errorMessage,
      onRetry: _connect,
      countdownActive: _run.isCountdown,
      onCountdownComplete: _beginSessionAfterCountdown,
      overlayFeedback: isTrainingActive ? _feedback.latestFeedback : null,
      overlays: Stack(
        fit: StackFit.expand,
        children: [
          if (isTrainingActive)
            ValueListenableBuilder<double>(
              valueListenable: _holdProgressNotifier,
              builder: (context, holdProgress, _) {
                if (holdProgress <= 0 || holdProgress >= 1) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppSpacing.lg,
                  child: Center(child: _HoldIndicator(progress: holdProgress)),
                );
              },
            ),
          Positioned(
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: ValueListenableBuilder<ComboState>(
              valueListenable: _comboNotifier,
              builder: (context, comboState, _) {
                return ComboBadge(
                  combo: isTrainingActive ? comboState.combo : 0,
                );
              },
            ),
          ),
          Positioned.fill(
            child: Center(
              child: ValueListenableBuilder<ScorePopupState>(
                valueListenable: _scorePopupNotifier,
                builder: (context, popupState, _) {
                  return ScorePopup(
                    trigger: popupState.trigger,
                    delta: popupState.delta,
                  );
                },
              ),
            ),
          ),
        ],
      ),
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
          : SessionMetricTiles(
              elapsedDisplay: _formatDuration(_run.elapsedSeconds),
              rubricChild: isTrainingActive
                  ? ValueListenableBuilder<RubricAssessment?>(
                      valueListenable: _assessmentNotifier,
                      builder: (context, assessment, _) {
                        return ScaleTransition(
                          scale: _scorePulse,
                          child: Text(
                            assessment != null
                                ? '${assessment.total} / ${RubricScale.maxTotal}'
                                : '—',
                            style: AppTheme.headingMedium.copyWith(
                              fontSize: 22,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        );
                      },
                    )
                  : Text(
                      '—',
                      style: AppTheme.headingMedium.copyWith(
                        fontSize: 22,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
              performanceBar: isTrainingActive
                  ? ValueListenableBuilder<RubricAssessment?>(
                      valueListenable: _assessmentNotifier,
                      builder: (context, assessment, _) =>
                          TrainingPerformanceBar(total: assessment?.total),
                    )
                  : const TrainingPerformanceBar(total: null),
              rubricBreakdown: isTrainingActive
                  ? ValueListenableBuilder<RubricAssessment?>(
                      valueListenable: _assessmentNotifier,
                      builder: (context, assessment, _) =>
                          RubricCriteriaTiles(assessment: assessment),
                    )
                  : const RubricCriteriaTiles(assessment: null),
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
      actionArea: isReadiness
          ? _buildReadinessActionArea()
          : TrainingActionArea(
              kind: actionKind,
              startLabel: 'Start Camera Setup',
              onPressed: switch (actionKind) {
                TrainingActionKind.finish => () => _stopSession(),
                TrainingActionKind.cancel => _cancelPreActive,
                TrainingActionKind.retry || TrainingActionKind.start =>
                  _ws.isConnected ? _startSession : _connect,
              },
              isLoading: _connecting || _commandInFlight,
            ),
    );
  }

  Widget _buildDesktopWorkspace({
    required double contentWidth,
    required double workspaceHeight,
    required Widget camera,
    required Widget panel,
  }) {
    final panelWidth = PracticeScreen.panelWidthForContent(contentWidth);
    final cameraSize = PracticeScreen.desktopCameraSize(
      contentWidth: contentWidth,
      workspaceHeight: workspaceHeight,
    );

    return Align(
      alignment: Alignment.topCenter,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: cameraSize.width,
            height: cameraSize.height,
            child: camera,
          ),
          SizedBox(width: AppSpacing.practiceCameraPanelGap),
          SizedBox(width: panelWidth, height: cameraSize.height, child: panel),
        ],
      ),
    );
  }

  Widget _buildStackedWorkspace({
    required double contentWidth,
    required Widget camera,
    required Widget panel,
  }) {
    final cameraSize = PracticeScreen.stackedCameraSize(contentWidth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: cameraSize.width,
          height: cameraSize.height,
          child: camera,
        ),
        SizedBox(height: AppSpacing.practiceCameraPanelGap),
        panel,
      ],
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
          onPressed: _cancelPreActive,
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

class _HoldIndicator extends StatelessWidget {
  const _HoldIndicator({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: const Color(0xE6101018),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: ProgressRing(
              value: progress * 100,
              strokeWidth: 3,
              activeColor: AppColors.success,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Hold steady…',
            style: AppTheme.body.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
