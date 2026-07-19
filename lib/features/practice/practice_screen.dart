import 'dart:async';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../data/models/practice_feedback.dart';
import '../../services/auth_service.dart';
import '../../services/practice_music_service.dart';
import '../../services/session_service.dart';
import '../../services/settings_service.dart';
import '../../services/websocket_service.dart';
import 'practice_game_widgets.dart';
import 'session_summary_sheet.dart';

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    required this.movement,
    required this.difficulty,
    this.freeMode = false,
  });

  final String movement;
  final String difficulty;

  /// When true the user can freely pick/switch the movement in-session.
  final bool freeMode;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen>
    with SingleTickerProviderStateMixin {
  // Active movement/difficulty. In free mode these can change via the picker.
  late String _movement = widget.movement;
  late String _difficulty = widget.difficulty;

  void _selectMovement(String name) {
    final match = movementCatalog.firstWhere(
      (m) => m.name == name,
      orElse: () => movementCatalog.first,
    );
    setState(() {
      _movement = match.name;
      _difficulty = match.difficulty;
    });
  }

  final _ws = WebSocketService();
  final _music = PracticeMusicService();
  final _feedbackHistory = <PracticeFeedback>[];
  final _scrollController = ScrollController();

  StreamSubscription<PracticeFeedback>? _feedbackSub;
  Timer? _timer;
  int _elapsedSeconds = 0;
  Uint8List? _currentFrame;
  PracticeFeedback? _latestFeedback;
  bool _connecting = false;
  String? _sessionError;
  bool _isShowingSummary = false;

  // Hold-to-confirm: the correct movement must be held steady for this long.
  static const _holdDuration = Duration(milliseconds: 2500);
  Timer? _holdTimer;
  DateTime? _holdStartAt;
  double _holdProgress = 0;
  bool _movementConfirmedShowing = false;

  late final AnimationController _scorePulseController;
  late final Animation<double> _scorePulse;
  int? _lastPulsedScore;

  // Game-style state.
  bool _countdownActive = false;
  int _combo = 0;
  int _bestCombo = 0;
  int _scorePopupTrigger = 0;
  int _scorePopupDelta = 0;

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
  }

  @override
  void dispose() {
    _timer?.cancel();
    _holdTimer?.cancel();
    _feedbackSub?.cancel();
    _scorePulseController.dispose();
    _music.dispose();
    _ws.removeListener(_onWsStateChanged);
    _ws.dispose();
    _scrollController.dispose();
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
      setState(() {
        _sessionError = feedback.feedback;
        _latestFeedback = feedback;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// A movement counts as "correct and held" while it stays positive/stable.
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

    // Pause detection while the user decides.
    _ws.sendStop();
    _timer?.cancel();
    _timer = null;
    await _music.stop();
    if (mounted) setState(() {});

    final tryAgain = await _showMovementConfirmedDialog();
    _movementConfirmedShowing = false;
    if (!mounted) return;

    if (tryAgain == true) {
      _startSession();
    } else {
      await _stopSession();
    }
  }

  Future<bool?> _showMovementConfirmedDialog() {
    return showVictoryDialog(
      context,
      movement: _movement,
      score: _latestFeedback?.score,
      durationSeconds: _elapsedSeconds,
      bestCombo: _bestCombo,
    );
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    await _ws.connect();
    if (mounted) setState(() => _connecting = false);
  }

  void _startSession() {
    if (!_ws.isConnected) {
      _connect();
      return;
    }
    setState(() => _countdownActive = true);
  }

  void _beginSessionAfterCountdown() {
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
    final settings = context.read<SettingsService>();
    _ws.sendStart(
      movement: _movement,
      difficulty: _difficulty,
      bottleDetectionEnabled: settings.bottleDetectionEnabled,
    );
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
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

  Future<void> _stopSession() async {
    if (_isShowingSummary) return;

    // Capture context-dependent objects up front so we never look up ancestors
    // through `context` after an async gap or during teardown.
    final router = GoRouter.of(context);
    final sessionService = context.read<SessionService>();
    final userId = context.read<AuthService>().currentUser?.id;

    final wasActive = _ws.sessionActive;
    _ws.sendStop();
    _timer?.cancel();
    _timer = null;
    await _music.stop();

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
      final saved = await SessionSummarySheet.show(
        context,
        movement: _movement,
        score: summaryScore,
        durationSeconds: summaryDuration,
        feedbacks: summaryFeedbacks,
        onSave: () => sessionService.saveCompletedSession(
          userId: userId,
          movementName: _movement,
          difficulty: _difficulty,
          score: summaryScore,
          durationSeconds: summaryDuration,
          feedbackHistory: summaryFeedbacks.reversed.toList(),
        ),
      );

      if (!mounted) return;

      _clearSessionState();
      setState(() {});

      router.go(saved == true ? '/dashboard' : '/movements');
    } finally {
      _isShowingSummary = false;
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isSessionActive = _ws.sessionActive;
    final hasConnectionError =
        _ws.connectionState == WebSocketConnectionState.error;
    final isDisconnected = !_ws.isConnected && !hasConnectionError;

    return ScaffoldPage(
      header: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xl,
          0,
        ),
        child: PageHeader(
          title: Row(
            children: [
              if (widget.freeMode) ...[
                const Flexible(
                  child: Text(
                    'Free Practice',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primarySoft,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _MovementPicker(
                  value: _movement,
                  enabled: !isSessionActive,
                  onChanged: _selectMovement,
                ),
              ] else ...[
                Flexible(
                  child: Text(
                    _movement,
                    style: AppTheme.headingLarge.copyWith(fontSize: 24),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _DifficultyPill(difficulty: _difficulty),
              ],
            ],
          ),
          leading: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: IconButton(
              icon: const Icon(
                FluentIcons.chrome_back,
                color: AppColors.primary,
              ),
              onPressed: () {
                if (_isShowingSummary) return;
                if (_hasSessionData) {
                  _stopSession();
                } else {
                  context.go('/movements');
                }
              },
            ),
          ),
        ),
      ),
      content: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: PulsingGlow(
                  active: isSessionActive,
                  child: _CameraPanel(
                    frameBytes: _currentFrame,
                    mirrored: context.watch<SettingsService>().cameraMirrored,
                    overlayFeedback: isSessionActive ? _latestFeedback : null,
                    holdProgress: isSessionActive ? _holdProgress : 0,
                    isSessionActive: isSessionActive,
                    connectionState: _ws.connectionState,
                    errorMessage: _ws.errorMessage,
                    sessionError: _sessionError,
                    connecting: _connecting,
                    onRetry: _connect,
                    combo: isSessionActive ? _combo : 0,
                    scorePopupTrigger: _scorePopupTrigger,
                    scorePopupDelta: _scorePopupDelta,
                    countdownActive: _countdownActive,
                    onCountdownComplete: _beginSessionAfterCountdown,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(
                width: 380,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ConnectionStatusBadge(
                      state: _ws.connectionState,
                      connecting: _connecting,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ElixCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  FluentIcons.play_solid,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text('Session', style: AppTheme.headingMedium),
                              const Spacer(),
                              RankBadge(score: _latestFeedback?.score),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            children: [
                              Expanded(
                                child: _StatTile(
                                  icon: FluentIcons.clock,
                                  label: 'Timer',
                                  value: _formatDuration(_elapsedSeconds),
                                  valueStyle: AppTheme.headingMedium.copyWith(
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _PulsingScoreTile(
                                  score: _latestFeedback?.score,
                                  pulseAnimation: _scorePulse,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.md),
                          XpBar(score: _latestFeedback?.score),
                          const SizedBox(height: AppSpacing.md),
                          Container(
                            height: 1,
                            color: AppColors.border.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _InfoRow(label: 'Movement', value: _movement),
                          const SizedBox(height: AppSpacing.sm),
                          _InfoRow(label: 'Difficulty', value: _difficulty),
                          if (_bestCombo > 1) ...[
                            const SizedBox(height: AppSpacing.sm),
                            _InfoRow(
                              label: 'Best Combo',
                              value: 'x$_bestCombo',
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (context
                        .watch<SettingsService>()
                        .bottleDetectionEnabled) ...[
                      const SizedBox(height: AppSpacing.md),
                      _BottleStatusIndicator(
                        detected: _latestFeedback?.bottleDetected,
                        isActive: isSessionActive,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    if (_sessionError != null)
                      ElixCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              FluentIcons.warning,
                              color: AppColors.error,
                              size: 28,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(_sessionError!, style: AppTheme.bodySecondary),
                            const SizedBox(height: AppSpacing.md),
                            ElixPrimaryButton(
                              label: 'Retry Session',
                              onPressed: _connecting ? null : _startSession,
                              isLoading: _connecting,
                            ),
                          ],
                        ),
                      )
                    else if (hasConnectionError || isDisconnected)
                      ElixCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              FluentIcons.wifi,
                              color: AppColors.error,
                              size: 28,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              _ws.errorMessage ??
                                  'Backend offline. Start the Python server first.',
                              style: AppTheme.bodySecondary,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            ElixPrimaryButton(
                              label: 'Retry Connection',
                              onPressed: _connecting ? null : _connect,
                              isLoading: _connecting,
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    const SizedBox(height: AppSpacing.md),
                    if (isSessionActive)
                      GameActionButton(
                        label: 'Stop',
                        icon: FluentIcons.stop_solid,
                        danger: true,
                        onPressed: () => _stopSession(),
                      )
                    else
                      GameActionButton(
                        label: _countdownActive ? 'Get Ready…' : 'Start',
                        icon: FluentIcons.play_solid,
                        onPressed: _countdownActive
                            ? null
                            : (_ws.isConnected ? _startSession : _connect),
                        isLoading: _connecting,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.frameBytes,
    required this.mirrored,
    this.overlayFeedback,
    this.holdProgress = 0,
    required this.isSessionActive,
    required this.connectionState,
    required this.onRetry,
    this.errorMessage,
    this.sessionError,
    this.connecting = false,
    this.combo = 0,
    this.scorePopupTrigger = 0,
    this.scorePopupDelta = 0,
    this.countdownActive = false,
    required this.onCountdownComplete,
  });

  final Uint8List? frameBytes;
  final bool mirrored;
  final PracticeFeedback? overlayFeedback;
  final double holdProgress;
  final bool isSessionActive;
  final WebSocketConnectionState connectionState;
  final String? errorMessage;
  final String? sessionError;
  final bool connecting;
  final VoidCallback onRetry;
  final int combo;
  final int scorePopupTrigger;
  final int scorePopupDelta;
  final bool countdownActive;
  final VoidCallback onCountdownComplete;

  @override
  Widget build(BuildContext context) {
    return ElixCard(
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: isSessionActive
              ? Border.all(
                  color: AppColors.primary.withValues(alpha: 0.45),
                  width: 1.5,
                )
              : null,
          boxShadow: isSessionActive
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 24,
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ColoredBox(
            color: const Color(0xFF0A0A0C),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (frameBytes != null)
                  _MirroredCameraFeed(
                    frameBytes: frameBytes!,
                    mirrored: mirrored,
                    overlayFeedback: overlayFeedback,
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.cardSurface.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSessionActive
                                ? FluentIcons.video
                                : FluentIcons.video_solid,
                            size: 40,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          isSessionActive
                              ? 'Waiting for frames...'
                              : 'Camera feed will appear here',
                          style: AppTheme.bodySecondary,
                        ),
                      ],
                    ),
                  ),
                if (connectionState == WebSocketConnectionState.error ||
                    sessionError != null)
                  Container(
                    color: AppColors.background.withValues(alpha: 0.85),
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          sessionError != null
                              ? FluentIcons.error
                              : FluentIcons.warning,
                          color: AppColors.error,
                          size: 40,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          sessionError ?? errorMessage ?? 'Connection error',
                          style: AppTheme.body,
                          textAlign: TextAlign.center,
                        ),
                        if (connectionState ==
                            WebSocketConnectionState.error) ...[
                          const SizedBox(height: AppSpacing.lg),
                          ElixPrimaryButton(
                            label: 'Retry',
                            onPressed: connecting ? null : onRetry,
                            isLoading: connecting,
                            expanded: false,
                          ),
                        ],
                      ],
                    ),
                  ),
                if (holdProgress > 0 && holdProgress < 1)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: AppSpacing.lg,
                    child: Center(
                      child: _HoldIndicator(progress: holdProgress),
                    ),
                  ),
                Positioned(
                  right: AppSpacing.lg,
                  bottom: AppSpacing.lg,
                  child: ComboBadge(combo: combo),
                ),
                Positioned.fill(
                  child: Center(
                    child: ScorePopup(
                      trigger: scorePopupTrigger,
                      delta: scorePopupDelta,
                    ),
                  ),
                ),
                if (countdownActive)
                  Positioned.fill(
                    child: GameCountdownOverlay(
                      onComplete: onCountdownComplete,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
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

class _MirroredCameraFeed extends StatelessWidget {
  const _MirroredCameraFeed({
    required this.frameBytes,
    required this.mirrored,
    this.overlayFeedback,
  });

  final Uint8List frameBytes;
  final bool mirrored;
  final PracticeFeedback? overlayFeedback;

  static const _frameAspectRatio = 640 / 480;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: _frameAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Transform.flip(
              flipX: mirrored,
              child: Image.memory(
                frameBytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
            if (overlayFeedback != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _FrameHudOverlay(feedback: overlayFeedback!),
              ),
          ],
        ),
      ),
    );
  }
}

class _FrameHudOverlay extends StatelessWidget {
  const _FrameHudOverlay({required this.feedback});

  final PracticeFeedback feedback;

  Color _feedbackColor() {
    switch (feedback.feedbackType) {
      case 'positive':
        return AppColors.success;
      case 'warning':
        return AppColors.warning;
      case 'error':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedbackText = feedback.feedback.length > 80
        ? '${feedback.feedback.substring(0, 80)}…'
        : feedback.feedback;
    final accent = _feedbackColor();

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xE6101018), const Color(0xCC0A0A0F)],
        ),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 56,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        feedback.movement,
                        style: AppTheme.body.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Score ${feedback.score}',
                          style: AppTheme.body.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    feedbackText,
                    style: AppTheme.body.copyWith(
                      fontSize: 17,
                      height: 1.35,
                      color: accent,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MovementPicker extends StatelessWidget {
  const _MovementPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ComboBox<String>(
      value: value,
      isExpanded: false,
      placeholder: const Text('Pick a movement'),
      items: [
        for (final m in movementCatalog)
          ComboBoxItem<String>(
            value: m.name,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.name),
                const SizedBox(width: AppSpacing.sm),
                _DifficultyPill(difficulty: m.difficulty),
              ],
            ),
          ),
      ],
      onChanged: enabled
          ? (v) {
              if (v != null) onChanged(v);
            }
          : null,
    );
  }
}

class _DifficultyPill extends StatelessWidget {
  const _DifficultyPill({required this.difficulty});

  final String difficulty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        difficulty,
        style: AppTheme.caption.copyWith(
          color: AppColors.primarySoft,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ConnectionStatusBadge extends StatelessWidget {
  const _ConnectionStatusBadge({required this.state, required this.connecting});

  final WebSocketConnectionState state;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      WebSocketConnectionState.connected => ('Connected', AppColors.success),
      WebSocketConnectionState.connecting => (
        'Connecting...',
        AppColors.warning,
      ),
      WebSocketConnectionState.error => ('Error', AppColors.error),
      WebSocketConnectionState.disconnected => (
        'Disconnected',
        AppColors.textSecondary,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          if (connecting || state == WebSocketConnectionState.connecting)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: SizedBox(
                width: 14,
                height: 14,
                child: const ProgressRing(strokeWidth: 2),
              ),
            )
          else
            Container(
              width: 9,
              height: 9,
              margin: const EdgeInsets.only(right: AppSpacing.sm),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6),
                ],
              ),
            ),
          Text(
            label,
            style: AppTheme.body.copyWith(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottleStatusIndicator extends StatelessWidget {
  const _BottleStatusIndicator({
    required this.detected,
    required this.isActive,
  });

  final bool? detected;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (detected) {
      true => (
        'Bottle detected',
        AppColors.success,
        FluentIcons.status_circle_checkmark,
      ),
      false => (
        'Bottle not detected',
        AppColors.error,
        FluentIcons.status_circle_error_x,
      ),
      null => (
        'Bottle status',
        AppColors.textSecondary,
        FluentIcons.circle_ring,
      ),
    };

    return ElixCard(
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              isActive ? label : 'Start session to detect bottle',
              style: AppTheme.body.copyWith(
                color: isActive ? color : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final IconData icon;
  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: valueStyle ?? AppTheme.headingMedium.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.caption),
        ],
      ),
    );
  }
}

class _PulsingScoreTile extends StatelessWidget {
  const _PulsingScoreTile({required this.score, required this.pulseAnimation});

  final int? score;
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            FluentIcons.favorite_star,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(height: AppSpacing.sm),
          ScaleTransition(
            scale: pulseAnimation,
            child: Text(
              score != null ? '$score' : '—',
              style: AppTheme.headingMedium.copyWith(
                fontSize: 22,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Score',
            style: AppTheme.caption.copyWith(color: AppColors.primarySoft),
          ),
        ],
      ),
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
        Text(label, style: AppTheme.bodySecondary),
        Text(value, style: AppTheme.body.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
