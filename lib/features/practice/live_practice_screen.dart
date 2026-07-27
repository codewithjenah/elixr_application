import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/practice_feedback.dart';
import '../../services/practice_music_service.dart';
import '../../services/practice_sfx_service.dart';
import '../../services/settings_service.dart';
import '../../services/websocket_service.dart';
import 'practice_run_phase.dart';
import 'widgets/training_action_area.dart';
import 'widgets/training_camera_workspace.dart';
import 'widgets/training_session_header.dart';
import 'widgets/training_session_panel.dart';
import 'widgets/training_status_row.dart';

/// Free-form live practice: camera streams with detection overlays but the
/// user is not locked to a movement and no scoring/feedback is shown.
class LivePracticeScreen extends StatefulWidget {
  const LivePracticeScreen({super.key});

  @override
  State<LivePracticeScreen> createState() => _LivePracticeScreenState();
}

class _LivePracticeScreenState extends State<LivePracticeScreen> {
  final _ws = WebSocketService();
  final _music = PracticeMusicService();
  final _sfx = PracticeSfxService();
  final _run = PracticeRunController();

  StreamSubscription<PracticeFeedback>? _feedbackSub;
  Uint8List? _currentFrame;
  bool _bottleDetected = false;
  bool _connecting = false;
  String? _sessionError;
  bool _leaving = false;

  static const _wideBreakpoint = 1100.0;
  static const _panelWidth = 370.0;

  @override
  void initState() {
    super.initState();
    _ws.addListener(_onWsStateChanged);
    _run.addListener(_onRunChanged);
    _feedbackSub = _ws.feedbackStream.listen(_onFeedback);
    _connect();
    _sfx.preload();
  }

  @override
  void dispose() {
    _feedbackSub?.cancel();
    _music.dispose();
    _sfx.dispose();
    _ws.removeListener(_onWsStateChanged);
    _run.removeListener(_onRunChanged);
    _run.dispose();
    _ws.dispose();
    super.dispose();
  }

  void _onWsStateChanged() {
    if (mounted) setState(() {});
  }

  void _onRunChanged() {
    if (mounted) setState(() {});
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
      _ws.sendStop();
      setState(() {
        _sessionError = feedback.feedback;
        _currentFrame = null;
      });
      return;
    }

    if (_run.isPreparingCamera) {
      setState(() {
        _sessionError = null;
        if (feedback.frameJpegBytes != null) {
          _currentFrame = feedback.frameJpegBytes;
        }
      });
      final startCountdown = _run.onPreviewFeedback(
        hasJpegFrame: feedback.frameJpegBytes != null,
        isFatal: false,
      );
      if (startCountdown) {
        unawaited(_startCountdownOverlay());
      }
      return;
    }

    if (_run.isCountdown) {
      setState(() {
        _sessionError = null;
        if (feedback.frameJpegBytes != null) {
          _currentFrame = feedback.frameJpegBytes;
        }
      });
      return;
    }

    if (!_run.isTrainingActive) return;

    setState(() {
      _sessionError = null;
      _bottleDetected = feedback.bottleDetected;
      if (feedback.frameJpegBytes != null) {
        _currentFrame = feedback.frameJpegBytes;
      }
    });
  }

  Future<void> _startCountdownOverlay() async {
    await _sfx.playCountdown();
    if (!mounted || !_run.isPreparingCamera) return;
    if (!_run.countdownTriggered) return;
    _run.enterCountdown();
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
    if (_run.phase != PracticeRunPhase.idle &&
        _run.phase != PracticeRunPhase.error) {
      return;
    }

    _sessionError = null;
    _currentFrame = null;
    _bottleDetected = false;
    _run.beginPreparing(onTimeout: _onPreparationTimeout);
    setState(() {});

    final cameraIndex =
        await context.read<SettingsService>().loadSelectedCameraIndex();
    if (!mounted) return;
    if (!_run.isPreparingCamera) return;

    // A generic movement keeps the vision pipeline (camera + detection
    // overlays) running; the user practices freely and nothing is scored.
    _ws.sendPrepare(
      movement: 'Normal Grip',
      difficulty: 'Easy',
      cameraIndex: cameraIndex,
    );
  }

  void _onPreparationTimeout() {
    if (!mounted) return;
    _ws.sendStop();
    unawaited(_music.stop());
    unawaited(_sfx.stop());
    setState(() {
      _sessionError = _run.errorMessage;
      _currentFrame = null;
    });
  }

  Future<void> _beginSessionAfterCountdown() async {
    if (!mounted) return;
    if (!_run.isCountdown) return;
    if (!_ws.isConnected) {
      _run.cancelToIdle();
      _connect();
      return;
    }

    _ws.sendActivate();
    _run.enterActive();
    _sfx.stop();
    _music.start();
    if (mounted) setState(() {});
  }

  Future<void> _cancelPreActive() async {
    _ws.sendStop();
    _run.cancelToIdle();
    await _music.stop();
    await _sfx.stop();
    if (mounted) {
      setState(() {
        _currentFrame = null;
        _bottleDetected = false;
        _sessionError = null;
      });
    }
  }

  Future<void> _stopSession() async {
    if (_run.isPreparingCamera || _run.isCountdown || _run.isError) {
      await _cancelPreActive();
      return;
    }

    _ws.sendStop();
    _run.cancelToIdle();
    await _music.stop();
    await _sfx.stop();
    if (mounted) {
      setState(() {
        _currentFrame = null;
        _bottleDetected = false;
        _sessionError = null;
      });
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    final router = GoRouter.of(context);
    await _feedbackSub?.cancel();
    _feedbackSub = null;
    _ws.removeListener(_onWsStateChanged);
    _run.removeListener(_onRunChanged);
    _ws.sendStop();
    _run.cancelToIdle();
    await _music.stop();
    await _sfx.stop();
    router.go('/dashboard');
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
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
    final actionKind = _actionKind();

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
                onBack: _leave,
                title: 'Free Practice',
                statusPill: 'NO SCORING',
                statusPillColor: AppColors.primarySoft,
                instruction:
                    'Practice freely with live bottle detection. '
                    'Results are not scored or saved.',
                connectionState: _ws.connectionState,
                connecting: _connecting,
                wideLayout: wide,
              );
              final camera = TrainingCameraWorkspace(
                frameBytes: _currentFrame,
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
                statusItems: [
                  if (isTrainingActive)
                    TrainingCameraStatusItem(
                      label: _bottleDetected
                          ? 'Bottle detected'
                          : 'Searching for bottle',
                      color: _bottleDetected
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                ],
              );

              final panel = TrainingSessionPanel(
                phase: _panelPhase(),
                metrics: Column(
                  children: [
                    Text(
                      'ELAPSED',
                      style: AppTheme.caption.copyWith(
                        color: AppColors.primarySoft,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _formatDuration(_run.elapsedSeconds),
                      style: AppTheme.headingMedium.copyWith(
                        fontSize: 40,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w900,
                        color: context.elixTextPrimary,
                      ),
                    ),
                  ],
                ),
                statusContent: TrainingStatusRow(
                  detection: resolveDetectionStatus(
                    sessionActive: isTrainingActive,
                    bottleDetected: isTrainingActive ? _bottleDetected : null,
                  ),
                ),
                notice: Text(
                  'No score or session history will be saved.',
                  style: AppTheme.bodySecondary.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
                compactStatusNote: (_sessionError ?? _run.errorMessage) != null
                    ? Text(
                        _sessionError ?? _run.errorMessage!,
                        style: AppTheme.bodySecondary.copyWith(
                          color: AppColors.error,
                        ),
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
                  startLabel: 'Start Free Practice',
                  onPressed: switch (actionKind) {
                    TrainingActionKind.finish => _stopSession,
                    TrainingActionKind.cancel => _cancelPreActive,
                    TrainingActionKind.retry || TrainingActionKind.start =>
                      _ws.isConnected ? _startSession : _connect,
                  },
                  isLoading: _connecting,
                ),
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
                    SizedBox(height: 320, child: panel),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
