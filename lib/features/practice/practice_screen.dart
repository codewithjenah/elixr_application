import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/practice_feedback.dart';
import '../../data/models/training_prop.dart';
import '../../data/models/ws_protocol.dart';
import '../../services/auth_service.dart';
import '../../services/practice_music_service.dart';
import '../../services/practice_sfx_service.dart';
import '../../services/session_service.dart';
import '../../services/settings_service.dart';
import '../../services/websocket_service.dart';
import 'practice_feedback_controller.dart';
import 'practice_game_widgets.dart';
import 'practice_run_phase.dart';
import 'session_summary_sheet.dart';
import 'widgets/training_action_area.dart';
import 'widgets/training_camera_workspace.dart';
import 'widgets/training_performance.dart';
import 'widgets/training_session_header.dart';
import 'widgets/training_session_panel.dart';
import 'widgets/training_status_row.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    required this.movement,
    required this.difficulty,
    this.prop = TrainingProp.bottle,
  });

  final String movement;
  final String difficulty;
  final TrainingProp prop;

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
  final ValueNotifier<Uint8List?> _frameBytes = ValueNotifier<Uint8List?>(null);
  final ValueNotifier<int?> _scoreNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<double> _holdProgressNotifier = ValueNotifier<double>(0);
  bool _connecting = false;
  String? _sessionError;
  bool _isShowingSummary = false;
  bool _movementConfirmedShowing = false;
  bool _commandInFlight = false;

  late final AnimationController _scorePulseController;
  late final Animation<double> _scorePulse;
  int? _lastPulsedScore;

  static const _wideBreakpoint = 1100.0;
  static const _panelWidth = 370.0;

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
    _connect();
    _sfx.preload();
  }

  @override
  void dispose() {
    _feedbackSub?.cancel();
    _scorePulseController.dispose();
    _frameBytes.dispose();
    _scoreNotifier.dispose();
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
      _scoreNotifier.value = null;
      _holdProgressNotifier.value = 0;
      if (mounted) {
        setState(() {
          _feedback.latestFeedback = null;
        });
      }
      return;
    }
    if (mounted) setState(() {});
  }

  void _onRunChanged() {
    if (mounted) setState(() {});
  }

  void _publishFrame(Uint8List? bytes) {
    if (bytes != null) {
      _frameBytes.value = bytes;
    }
  }

  void _clearFrame() {
    _frameBytes.value = null;
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
      unawaited(_ws.sendStop());
      _clearFrame();
      _scoreNotifier.value = null;
      _holdProgressNotifier.value = 0;
      setState(() {
        _sessionError = feedback.feedback;
        _feedback.latestFeedback = null;
      });
      return;
    }

    // Preparing: store frame; first JPEG starts countdown once.
    if (_run.isPreparingCamera) {
      _publishFrame(feedback.frameJpegBytes);
      final hadError = _sessionError != null;
      if (hadError) {
        setState(() => _sessionError = null);
      }
      final startCountdown = _run.onPreviewFeedback(
        hasJpegFrame: feedback.frameJpegBytes != null,
        isFatal: false,
      );
      if (startCountdown) {
        unawaited(_startCountdownOverlay());
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

    final result = _feedback.applyActiveFeedback(feedback);

    _publishFrame(feedback.frameJpegBytes);
    _scoreNotifier.value = feedback.score;
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

    if (result.scoreChanged && _lastPulsedScore != feedback.score) {
      _lastPulsedScore = feedback.score;
      _scorePulseController.forward(from: 0);
    }
  }

  Future<void> _startCountdownOverlay() async {
    await _sfx.playCountdown();
    if (!mounted || !_run.isPreparingCamera) return;
    if (!_run.countdownTriggered) return;
    _run.enterCountdown();
  }

  Future<void> _onMovementConfirmed() async {
    if (_movementConfirmedShowing) return;
    _movementConfirmedShowing = true;

    unawaited(_ws.sendStop());
    _run.markCompleted();
    await _music.stop();
    if (mounted) setState(() {});

    // One completion dialog for beginners (skip separate victory screen).
    await _stopSession(heldSteady: true);
    _movementConfirmedShowing = false;
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
        unawaited(_ws.sendStop());
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
      unawaited(_ws.sendStop());
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
    unawaited(_ws.sendStop());
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
        final message =
            ack.message ?? ack.errorCode ?? 'Session activation was rejected.';
        _run.onPreviewFeedback(
          hasJpegFrame: false,
          isFatal: true,
          fatalMessage: message,
        );
        unawaited(_ws.sendStop());
        setState(() {
          _sessionError = message;
          _clearFrame();
        });
        return;
      }

      _run.enterActive();
      _sfx.stop();
      _music.start();
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
      unawaited(_ws.sendStop());
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
    _scoreNotifier.value = null;
    _holdProgressNotifier.value = 0;
    _comboNotifier.value = const ComboState();
    _scorePopupNotifier.value = const ScorePopupState();
    _lastPulsedScore = null;
    _movementConfirmedShowing = false;
  }

  Future<void> _cancelPreActive() async {
    unawaited(_ws.sendStop());
    _run.cancelToIdle();
    await _music.stop();
    await _sfx.stop();
    _clearSessionState();
    if (mounted) setState(() {});
  }

  Future<void> _stopSession({bool heldSteady = false}) async {
    if (_isShowingSummary) return;

    // Cancel during prepare/countdown/error: no summary.
    if (_run.isPreparingCamera || _run.isCountdown || _run.isError) {
      await _cancelPreActive();
      return;
    }

    final wasTraining =
        _run.isTrainingActive || _run.phase == PracticeRunPhase.completed;
    if (!wasTraining) {
      await _cancelPreActive();
      if (mounted) context.go('/movements');
      return;
    }

    final router = GoRouter.of(context);
    final sessionService = context.read<SessionService>();
    final authUser = context.read<AuthService>().currentUser;
    final userId = authUser?.id;
    final displayName = authUser?.fullName ?? 'Trainee';

    unawaited(_ws.sendStop());
    if (_run.phase == PracticeRunPhase.active) {
      _run.markCompleted();
    }
    await _music.stop();
    await _sfx.stop();

    if (!_hasSessionData && _run.elapsedSeconds == 0) {
      // Still show summary for an activated session with zero elapsed when
      // there was at least a score snapshot; otherwise return to catalog.
      if (_feedback.latestFeedback == null &&
          _feedback.feedbackHistory.isEmpty) {
        _run.cancelToIdle();
        _clearSessionState();
        if (mounted) router.go('/movements');
        return;
      }
    }

    if (userId == null) {
      _run.cancelToIdle();
      _clearSessionState();
      if (mounted) setState(() {});
      if (mounted) router.go('/movements');
      return;
    }

    final summaryScore = _feedback.latestFeedback?.score ?? 0;
    final summaryDuration = _run.elapsedSeconds;
    final summaryFeedbacks = List<PracticeFeedback>.unmodifiable(
      _feedback.feedbackHistory.reversed.toList(),
    );

    _isShowingSummary = true;
    try {
      // Play congrats when the Session Complete dialog appears.
      await _sfx.playCongrats();
      if (!mounted) return;
      final result = await SessionSummarySheet.show(
        context,
        movement: _movement,
        score: summaryScore,
        durationSeconds: summaryDuration,
        feedbacks: summaryFeedbacks,
        heldSteady: heldSteady,
        onSave: () => sessionService.saveCompletedSession(
          userId: userId,
          displayName: displayName,
          profilePictureUrl: authUser?.profilePictureUrl,
          movementName: _movement,
          difficulty: _difficulty,
          prop: _prop,
          score: summaryScore,
          durationSeconds: summaryDuration,
          feedbackHistory: summaryFeedbacks.reversed.toList(),
        ),
      );

      if (!mounted) return;

      // End congrats before the next action. Do NOT stop again in finally —
      // Try Again starts preparation on the same player and a finally stop
      // would silence it immediately.
      await _sfx.stop();

      if (result == SessionSummaryResult.tryAgain) {
        _clearSessionState();
        _run.cancelToIdle();
        setState(() {});
        await _startSession();
        return;
      }

      _clearSessionState();
      _run.cancelToIdle();
      setState(() {});

      router.go(
        result == SessionSummaryResult.saved ? '/dashboard' : '/movements',
      );
    } finally {
      _isShowingSummary = false;
    }
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

  void _onBack() {
    if (_isShowingSummary) return;
    if (_run.isPreparingCamera || _run.isCountdown) {
      _cancelPreActive();
      return;
    }
    if (_hasSessionData || _run.isTrainingActive) {
      _stopSession();
    } else {
      context.go('/movements');
    }
  }

  TrainingActionKind _actionKind() {
    return switch (_run.phase) {
      PracticeRunPhase.active => TrainingActionKind.finish,
      PracticeRunPhase.preparingCamera ||
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

    return ScaffoldPage(
      content: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _wideBreakpoint;
              final header = TrainingSessionHeader(
                onBack: _onBack,
                title: _movement,
                statusPill: _difficulty.toUpperCase(),
                statusPillColor: trainingDifficultyColor(_difficulty),
                instruction: _instructionForMovement(_movement),
                connectionState: _ws.connectionState,
                connecting: _connecting,
                wideLayout: wide,
              );
              final camera = _buildCamera(
                isTrainingActive: isTrainingActive,
                isCameraLive: isCameraLive,
              );
              final panel = _buildPanel(
                isTrainingActive: isTrainingActive,
                hasConnectionError: hasConnectionError,
              );

              if (wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: camera),
                          const SizedBox(width: AppSpacing.lg),
                          SizedBox(width: _panelWidth, child: panel),
                        ],
                      ),
                    ),
                  ],
                );
              }

              final cameraHeight = math.max(
                280.0,
                constraints.maxHeight * 0.42,
              );
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    SizedBox(height: cameraHeight, child: camera),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(height: 360, child: panel),
                  ],
                ),
              );
            },
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
  }) {
    final actionKind = _actionKind();

    return TrainingSessionPanel(
      phase: _panelPhase(),
      rankBadge: isTrainingActive
          ? ValueListenableBuilder<int?>(
              valueListenable: _scoreNotifier,
              builder: (context, score, _) => RankBadge(score: score),
            )
          : null,
      metrics: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MetricCell(
                  label: 'Elapsed',
                  child: Text(
                    _formatDuration(_run.elapsedSeconds),
                    style: AppTheme.headingMedium.copyWith(
                      letterSpacing: 1.2,
                      color: context.elixTextPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _MetricCell(
                  label: 'Score',
                  emphasize: true,
                  child: isTrainingActive
                      ? ValueListenableBuilder<int?>(
                          valueListenable: _scoreNotifier,
                          builder: (context, score, _) {
                            return ScaleTransition(
                              scale: _scorePulse,
                              child: Text(
                                score != null ? '$score' : '—',
                                style: AppTheme.headingMedium.copyWith(
                                  fontSize: 28,
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
                            fontSize: 28,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (isTrainingActive)
            ValueListenableBuilder<int?>(
              valueListenable: _scoreNotifier,
              builder: (context, score, _) =>
                  TrainingPerformanceBar(score: score),
            )
          else
            const TrainingPerformanceBar(score: null),
        ],
      ),
      statusContent: TrainingStatusRow(
        detection: resolveDetectionStatus(
          sessionActive: isTrainingActive,
          bottleDetected: _feedback.latestFeedback?.bottleDetected,
        ),
        propLabel: _prop.displayLabel,
        postureLabel: postureDisplayLabel(
          isTrainingActive ? _feedback.latestFeedback?.postureStatus : null,
        ),
      ),
      supportingContent: ValueListenableBuilder<ComboState>(
        valueListenable: _comboNotifier,
        builder: (context, comboState, _) {
          return Column(
            children: [
              _InfoRow(label: 'Movement', value: _movement),
              const SizedBox(height: AppSpacing.sm),
              _InfoRow(label: 'Difficulty', value: _difficulty),
              const SizedBox(height: AppSpacing.sm),
              _InfoRow(label: 'Prop', value: _prop.displayLabel),
              if (comboState.bestCombo > 1) ...[
                const SizedBox(height: AppSpacing.sm),
                _InfoRow(
                  label: 'Best Combo',
                  value: 'x${comboState.bestCombo}',
                ),
              ],
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
                        'Backend offline. Start the Python server first.',
                    style: AppTheme.bodySecondary.copyWith(
                      color: AppColors.error,
                    ),
                  )
                : null),
      actionArea: TrainingActionArea(
        kind: actionKind,
        startLabel: 'Start Session',
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
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.label,
    required this.child,
    this.emphasize = false,
  });

  final String label;
  final Widget child;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTheme.caption.copyWith(
            color: emphasize
                ? AppColors.primarySoft
                : context.elixTextSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTheme.bodySecondary.copyWith(
            color: context.elixTextSecondary,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style: AppTheme.body.copyWith(
              fontWeight: FontWeight.w600,
              color: context.elixTextPrimary,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
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
