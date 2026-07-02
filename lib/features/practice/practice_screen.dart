import 'dart:async';
import 'dart:typed_data';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/feedback_chip.dart';
import '../../data/models/practice_feedback.dart';
import '../../services/auth_service.dart';
import '../../services/session_service.dart';
import '../../services/settings_service.dart';
import '../../services/websocket_service.dart';
import 'session_summary_sheet.dart';

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
  final _ws = WebSocketService();
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

  late final AnimationController _scorePulseController;
  late final Animation<double> _scorePulse;
  int? _lastPulsedScore;

  @override
  void initState() {
    super.initState();
    _scorePulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scorePulse = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.12), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.12, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _scorePulseController,
      curve: Curves.easeOut,
    ));
    _ws.addListener(_onWsStateChanged);
    _feedbackSub = _ws.feedbackStream.listen(_onFeedback);
    _connect();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _feedbackSub?.cancel();
    _scorePulseController.dispose();
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
      setState(() {
        _sessionError = feedback.feedback;
        _latestFeedback = feedback;
      });
      return;
    }

    final scoreChanged = _latestFeedback?.score != feedback.score;
    setState(() {
      _sessionError = null;
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
    _feedbackHistory.clear();
    _elapsedSeconds = 0;
    _sessionError = null;
    _currentFrame = null;
    _latestFeedback = null;
    final settings = context.read<SettingsService>();
    _ws.sendStart(
      movement: widget.movement,
      difficulty: widget.difficulty,
      bottleDetectionEnabled: settings.bottleDetectionEnabled,
    );
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  bool get _hasSessionData =>
      _ws.sessionActive ||
      _elapsedSeconds > 0 ||
      _feedbackHistory.isNotEmpty;

  void _clearSessionState() {
    _feedbackHistory.clear();
    _elapsedSeconds = 0;
    _sessionError = null;
    _currentFrame = null;
    _latestFeedback = null;
    _lastPulsedScore = null;
  }

  Future<void> _stopSession() async {
    if (_isShowingSummary) return;

    final wasActive = _ws.sessionActive;
    _ws.sendStop();
    _timer?.cancel();
    _timer = null;

    if (!wasActive && _elapsedSeconds == 0 && _feedbackHistory.isEmpty) {
      if (mounted) context.go('/movements');
      return;
    }

    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) {
      _clearSessionState();
      if (mounted) setState(() {});
      if (mounted) context.go('/movements');
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
        movement: widget.movement,
        score: summaryScore,
        durationSeconds: summaryDuration,
        feedbacks: summaryFeedbacks,
        onSave: () => context.read<SessionService>().saveCompletedSession(
              userId: userId,
              movementName: widget.movement,
              difficulty: widget.difficulty,
              score: summaryScore,
              durationSeconds: summaryDuration,
              feedbackHistory: summaryFeedbacks.reversed.toList(),
            ),
      );

      if (!mounted) return;

      _clearSessionState();
      setState(() {});

      if (saved == true) {
        context.go('/dashboard');
      } else {
        context.go('/movements');
      }
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
      header: PageHeader(
        title: Text(widget.movement, style: AppTheme.headingMedium),
        leading: IconButton(
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
      content: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: _CameraPanel(
                  frameBytes: _currentFrame,
                  mirrored: context.watch<SettingsService>().cameraMirrored,
                  overlayFeedback:
                      isSessionActive ? _latestFeedback : null,
                  isSessionActive: isSessionActive,
                  connectionState: _ws.connectionState,
                  errorMessage: _ws.errorMessage,
                  sessionError: _sessionError,
                  connecting: _connecting,
                  onRetry: _connect,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(
                width: 320,
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
                          Text('Session', style: AppTheme.headingMedium),
                          const SizedBox(height: AppSpacing.md),
                          _InfoRow(
                            label: 'Movement',
                            value: widget.movement,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _InfoRow(
                            label: 'Difficulty',
                            value: widget.difficulty,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _InfoRow(
                            label: 'Timer',
                            value: _formatDuration(_elapsedSeconds),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _PulsingScoreRow(
                            score: _latestFeedback?.score,
                            pulseAnimation: _scorePulse,
                          ),
                        ],
                      ),
                    ),
                    if (context.watch<SettingsService>().bottleDetectionEnabled) ...[
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
                    const SizedBox(height: AppSpacing.md),
                    Text('Live Feedback', style: AppTheme.headingMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: _feedbackHistory.isEmpty
                          ? Center(
                              child: Text(
                                isSessionActive
                                    ? 'Waiting for feedback...'
                                    : 'Press Start to begin practice.',
                                style: AppTheme.bodySecondary,
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              itemCount: _feedbackHistory.length,
                              itemBuilder: (context, index) {
                                final item = _feedbackHistory[index];
                                return Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm,
                                  ),
                                  child: FeedbackChip(
                                    message: item.feedback,
                                    feedbackType: item.feedbackType,
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (isSessionActive)
                      ElixPrimaryButton(
                        label: 'Stop',
                        onPressed: () => _stopSession(),
                      )
                    else
                      ElixPrimaryButton(
                        label: 'Start',
                        onPressed: _ws.isConnected ? _startSession : _connect,
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
    required this.isSessionActive,
    required this.connectionState,
    required this.onRetry,
    this.errorMessage,
    this.sessionError,
    this.connecting = false,
  });

  final Uint8List? frameBytes;
  final bool mirrored;
  final PracticeFeedback? overlayFeedback;
  final bool isSessionActive;
  final WebSocketConnectionState connectionState;
  final String? errorMessage;
  final String? sessionError;
  final bool connecting;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ElixCard(
      padding: EdgeInsets.zero,
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
                      Icon(
                        isSessionActive
                            ? FluentIcons.video
                            : FluentIcons.video_solid,
                        size: 48,
                        color: AppColors.textSecondary.withValues(alpha: 0.5),
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
                      if (connectionState == WebSocketConnectionState.error) ...[
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
            ],
          ),
        ),
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
    final feedbackText = feedback.feedback.length > 70
        ? feedback.feedback.substring(0, 70)
        : feedback.feedback;

    return ColoredBox(
      color: const Color(0xFF0F0F14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              feedback.movement,
              style: AppTheme.body.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Score: ${feedback.score}',
              style: AppTheme.body.copyWith(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              feedbackText,
              style: AppTheme.body.copyWith(
                fontSize: 13,
                color: _feedbackColor(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatusBadge extends StatelessWidget {
  const _ConnectionStatusBadge({
    required this.state,
    required this.connecting,
  });

  final WebSocketConnectionState state;
  final bool connecting;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (state) {
      WebSocketConnectionState.connected => ('Connected', AppColors.success),
      WebSocketConnectionState.connecting => ('Connecting...', AppColors.warning),
      WebSocketConnectionState.error => ('Error', AppColors.error),
      WebSocketConnectionState.disconnected => ('Disconnected', AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (connecting || state == WebSocketConnectionState.connecting)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: ProgressRing(strokeWidth: 2),
            )
          else
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: AppSpacing.sm),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          Text(label, style: AppTheme.body.copyWith(color: color, fontSize: 13)),
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
      true => ('Bottle detected', AppColors.success, FluentIcons.status_circle_checkmark),
      false => ('Bottle not detected', AppColors.error, FluentIcons.status_circle_error_x),
      null => ('Bottle status', AppColors.textSecondary, FluentIcons.circle_ring),
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

class _PulsingScoreRow extends StatelessWidget {
  const _PulsingScoreRow({
    required this.score,
    required this.pulseAnimation,
  });

  final int? score;
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Score', style: AppTheme.bodySecondary),
        ScaleTransition(
          scale: pulseAnimation,
          child: Text(
            score != null ? '$score' : '—',
            style: AppTheme.body.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
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
        Text(label, style: AppTheme.bodySecondary),
        Text(value, style: AppTheme.body.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
