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
import '../../services/auth_service.dart';
import '../../services/practice_music_service.dart';
import '../../services/practice_sfx_service.dart';
import '../../services/session_service.dart';
import '../../services/settings_service.dart';
import '../../services/websocket_service.dart';
import 'practice_game_widgets.dart';
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
  });

  final String movement;
  final String difficulty;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen>
    with SingleTickerProviderStateMixin {
  late final String _movement = widget.movement;
  late final String _difficulty = widget.difficulty;

  final _ws = WebSocketService();
  final _music = PracticeMusicService();
  final _sfx = PracticeSfxService();
  final _feedbackHistory = <PracticeFeedback>[];

  StreamSubscription<PracticeFeedback>? _feedbackSub;
  Timer? _timer;
  int _elapsedSeconds = 0;
  Uint8List? _currentFrame;
  PracticeFeedback? _latestFeedback;
  bool _connecting = false;
  String? _sessionError;
  bool _isShowingSummary = false;

  static const _holdDuration = Duration(milliseconds: 2500);
  Timer? _holdTimer;
  DateTime? _holdStartAt;
  double _holdProgress = 0;
  bool _movementConfirmedShowing = false;

  late final AnimationController _scorePulseController;
  late final Animation<double> _scorePulse;
  int? _lastPulsedScore;

  bool _countdownActive = false;
  int _combo = 0;
  int _bestCombo = 0;
  int _scorePopupTrigger = 0;
  int _scorePopupDelta = 0;

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
    _feedbackSub = _ws.feedbackStream.listen(_onFeedback);
    _connect();
    _sfx.preload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _holdTimer?.cancel();
    _feedbackSub?.cancel();
    _scorePulseController.dispose();
    _music.dispose();
    _sfx.dispose();
    _ws.removeListener(_onWsStateChanged);
    _ws.dispose();
    super.dispose();
  }

  void _onWsStateChanged() {
    if (mounted) setState(() {});
  }

  void _onFeedback(PracticeFeedback feedback) {
    if (!mounted) return;

    if (feedback.isSessionFatal) {
      _timer?.cancel();
      _music.stop();
      _sfx.stop();
      setState(() {
        _sessionError = feedback.feedback;
        _latestFeedback = feedback;
        _currentFrame = null;
      });
      return;
    }

    final previousScore = _latestFeedback?.score;
    final scoreChanged = previousScore != feedback.score;
    setState(() {
      _sessionError = null;
      if (feedback.feedbackType == 'positive') {
        _combo++;
        if (_combo > _bestCombo) _bestCombo = _combo;
      } else if (feedback.feedbackType == 'error' ||
          feedback.feedbackType == 'warning') {
        _combo = 0;
      }
      if (previousScore != null && feedback.score > previousScore) {
        _scorePopupDelta = feedback.score - previousScore;
        _scorePopupTrigger++;
      }
      _latestFeedback = feedback;
      if (feedback.frameJpegBytes != null) {
        _currentFrame = feedback.frameJpegBytes;
      }
      if (_feedbackHistory.isEmpty ||
          _feedbackHistory.last.feedback != feedback.feedback) {
        _feedbackHistory.insert(0, feedback);
        if (_feedbackHistory.length > 50) {
          _feedbackHistory.removeLast();
        }
      }
    });

    _trackHold(feedback);

    if (scoreChanged && _lastPulsedScore != feedback.score) {
      _lastPulsedScore = feedback.score;
      _scorePulseController.forward(from: 0);
    }
  }

  void _trackHold(PracticeFeedback feedback) {
    if (_movementConfirmedShowing || !_ws.sessionActive) {
      _resetHold();
      return;
    }

    final isCorrect =
        feedback.feedbackType == 'positive' &&
        feedback.postureStatus == 'stable';

    if (!isCorrect) {
      _resetHold();
      return;
    }

    _holdStartAt ??= DateTime.now();
    _holdTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _holdStartAt == null) return;
      final elapsed = DateTime.now().difference(_holdStartAt!);
      final progress = (elapsed.inMilliseconds / _holdDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      setState(() => _holdProgress = progress);
      if (progress >= 1.0) _onMovementConfirmed();
    });
  }

  void _resetHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdStartAt = null;
    if (_holdProgress != 0 && mounted) {
      setState(() => _holdProgress = 0);
    } else {
      _holdProgress = 0;
    }
  }

  Future<void> _onMovementConfirmed() async {
    if (_movementConfirmedShowing) return;
    _movementConfirmedShowing = true;
    _resetHold();

    _ws.sendStop();
    _timer?.cancel();
    _timer = null;
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
    if (_countdownActive) return;
    await _sfx.playCountdown();
    if (!mounted || _countdownActive) return;
    setState(() => _countdownActive = true);
  }

  Future<void> _beginSessionAfterCountdown() async {
    if (!mounted) return;
    setState(() => _countdownActive = false);
    if (!_ws.isConnected) {
      _connect();
      return;
    }
    _feedbackHistory.clear();
    _elapsedSeconds = 0;
    _sessionError = null;
    _currentFrame = null;
    _latestFeedback = null;
    _combo = 0;
    _bestCombo = 0;
    _resetHold();
    final cameraIndex =
        await context.read<SettingsService>().loadSelectedCameraIndex();
    if (!mounted) return;
    _ws.sendStart(
      movement: _movement,
      difficulty: _difficulty,
      cameraIndex: cameraIndex,
    );
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    _sfx.stop();
    _music.start();
  }

  bool get _hasSessionData =>
      _ws.sessionActive || _elapsedSeconds > 0 || _feedbackHistory.isNotEmpty;

  void _clearSessionState() {
    _feedbackHistory.clear();
    _elapsedSeconds = 0;
    _sessionError = null;
    _currentFrame = null;
    _latestFeedback = null;
    _lastPulsedScore = null;
    _combo = 0;
    _bestCombo = 0;
    _resetHold();
  }

  Future<void> _stopSession({bool heldSteady = false}) async {
    if (_isShowingSummary) return;

    final router = GoRouter.of(context);
    final sessionService = context.read<SessionService>();
    final authUser = context.read<AuthService>().currentUser;
    final userId = authUser?.id;
    final displayName = authUser?.fullName ?? 'Trainee';

    final wasActive = _ws.sessionActive;
    _ws.sendStop();
    _timer?.cancel();
    _timer = null;
    await _music.stop();
    await _sfx.stop();

    if (!wasActive && _elapsedSeconds == 0 && _feedbackHistory.isEmpty) {
      if (mounted) router.go('/movements');
      return;
    }

    if (userId == null) {
      _clearSessionState();
      if (mounted) setState(() {});
      if (mounted) router.go('/movements');
      return;
    }

    final summaryScore = _latestFeedback?.score ?? 0;
    final summaryDuration = _elapsedSeconds;
    final summaryFeedbacks = List<PracticeFeedback>.unmodifiable(
      _feedbackHistory.reversed.toList(),
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
          movementName: _movement,
          difficulty: _difficulty,
          score: summaryScore,
          durationSeconds: summaryDuration,
          feedbackHistory: summaryFeedbacks.reversed.toList(),
        ),
      );

      if (!mounted) return;

      // End congrats before the next action. Do NOT stop again in finally —
      // Try Again starts countdown on the same player and a finally stop
      // would silence it immediately.
      await _sfx.stop();

      if (result == SessionSummaryResult.tryAgain) {
        _clearSessionState();
        setState(() {});
        await _startSession();
        return;
      }

      _clearSessionState();
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
    if (_hasSessionData) {
      _stopSession();
    } else {
      context.go('/movements');
    }
  }

  TrainingActionKind _actionKind({required bool isSessionActive}) {
    if (isSessionActive) return TrainingActionKind.finish;
    if (_countdownActive) return TrainingActionKind.getReady;
    return TrainingActionKind.start;
  }

  @override
  Widget build(BuildContext context) {
    final isSessionActive = _ws.sessionActive;
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
              final camera = _buildCamera(isSessionActive: isSessionActive);
              final panel = _buildPanel(
                isSessionActive: isSessionActive,
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

  Widget _buildCamera({required bool isSessionActive}) {
    return TrainingCameraWorkspace(
      frameBytes: _currentFrame,
      mirrored: context.watch<SettingsService>().cameraMirrored,
      connectionState: _ws.connectionState,
      connecting: _connecting,
      isSessionActive: isSessionActive,
      errorMessage: _ws.errorMessage,
      sessionError: _sessionError,
      onRetry: _connect,
      countdownActive: _countdownActive,
      onCountdownComplete: _beginSessionAfterCountdown,
      overlayFeedback: isSessionActive ? _latestFeedback : null,
      overlays: Stack(
        fit: StackFit.expand,
        children: [
          if (_holdProgress > 0 && _holdProgress < 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: AppSpacing.lg,
              child: Center(child: _HoldIndicator(progress: _holdProgress)),
            ),
          Positioned(
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: ComboBadge(combo: isSessionActive ? _combo : 0),
          ),
          Positioned.fill(
            child: Center(
              child: ScorePopup(
                trigger: _scorePopupTrigger,
                delta: _scorePopupDelta,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel({
    required bool isSessionActive,
    required bool hasConnectionError,
  }) {
    final score = _latestFeedback?.score;
    final actionKind = _actionKind(isSessionActive: isSessionActive);

    return TrainingSessionPanel(
      phase: isSessionActive
          ? TrainingSessionPhase.inProgress
          : TrainingSessionPhase.ready,
      rankBadge: score != null ? RankBadge(score: score) : null,
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
                    _formatDuration(_elapsedSeconds),
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
                  child: ScaleTransition(
                    scale: _scorePulse,
                    child: Text(
                      score != null ? '$score' : '—',
                      style: AppTheme.headingMedium.copyWith(
                        fontSize: 28,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TrainingPerformanceBar(score: score),
        ],
      ),
      statusContent: TrainingStatusRow(
        detection: resolveDetectionStatus(
          sessionActive: isSessionActive,
          bottleDetected: _latestFeedback?.bottleDetected,
        ),
        postureLabel: postureDisplayLabel(_latestFeedback?.postureStatus),
      ),
      supportingContent: Column(
        children: [
          _InfoRow(label: 'Movement', value: _movement),
          const SizedBox(height: AppSpacing.sm),
          _InfoRow(label: 'Difficulty', value: _difficulty),
          if (_bestCombo > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            _InfoRow(label: 'Best Combo', value: 'x$_bestCombo'),
          ],
        ],
      ),
      compactStatusNote: _sessionError != null
          ? Text(
              _sessionError!,
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
        onPressed: actionKind == TrainingActionKind.finish
            ? () => _stopSession()
            : actionKind == TrainingActionKind.start
            ? (_ws.isConnected ? _startSession : _connect)
            : null,
        isLoading: _connecting,
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
