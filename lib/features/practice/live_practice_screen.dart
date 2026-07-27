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
import '../../data/models/practice_feedback.dart';
import '../../services/practice_music_service.dart';
import '../../services/practice_sfx_service.dart';
import '../../services/settings_service.dart';
import '../../services/websocket_service.dart';
import 'practice_game_widgets.dart';

/// Free-form live practice: the camera streams with detection overlays but the
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

  StreamSubscription<PracticeFeedback>? _feedbackSub;
  Timer? _timer;
  int _elapsedSeconds = 0;
  Uint8List? _currentFrame;
  bool _bottleDetected = false;
  bool _connecting = false;
  String? _sessionError;
  bool _leaving = false;
  bool _countdownActive = false;

  @override
  void initState() {
    super.initState();
    _ws.addListener(_onWsStateChanged);
    _feedbackSub = _ws.feedbackStream.listen(_onFeedback);
    _connect();
    _sfx.preload();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _feedbackSub?.cancel();
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
      setState(() => _sessionError = feedback.feedback);
      return;
    }

    setState(() {
      _sessionError = null;
      _bottleDetected = feedback.bottleDetected;
      if (feedback.frameJpegBytes != null) {
        _currentFrame = feedback.frameJpegBytes;
      }
    });
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
    // Await so "3" appears with the first audible beat (after lead-in seek).
    await _sfx.playCountdown();
    if (!mounted || _countdownActive) return;
    setState(() => _countdownActive = true);
  }

  void _beginSessionAfterCountdown() {
    if (!mounted) return;
    setState(() => _countdownActive = false);
    if (!_ws.isConnected) {
      _connect();
      return;
    }
    _elapsedSeconds = 0;
    _sessionError = null;
    _currentFrame = null;
    // A generic movement keeps the vision pipeline (camera + detection
    // overlays) running; the user practices freely and nothing is scored.
    _ws.sendStart(movement: 'Normal Grip', difficulty: 'Easy');
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
    _sfx.stop();
    _music.start();
  }

  Future<void> _stopSession() async {
    _ws.sendStop();
    _timer?.cancel();
    _timer = null;
    await _music.stop();
    await _sfx.stop();
    if (mounted) {
      setState(() {
        _elapsedSeconds = 0;
        _currentFrame = null;
        _bottleDetected = false;
        _countdownActive = false;
      });
    }
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    // Capture the router before any async gap so we never touch `context`
    // after the widget starts deactivating.
    final router = GoRouter.of(context);
    // Silence incoming frames/state so no setState runs during the exit
    // transition, and fully stop audio before navigating (disposing the
    // AudioPlayer mid-teardown corrupts the frame on Windows).
    await _feedbackSub?.cancel();
    _feedbackSub = null;
    _ws.removeListener(_onWsStateChanged);
    _ws.sendStop();
    _timer?.cancel();
    _timer = null;
    await _music.stop();
    await _sfx.stop();
    router.go('/dashboard');
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
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'No scoring — do whatever you want',
                  style: AppTheme.caption.copyWith(
                    color: AppColors.primarySoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          leading: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: IconButton(
              icon: const Icon(
                FluentIcons.chrome_back,
                color: AppColors.primary,
              ),
              onPressed: _leave,
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
                    isSessionActive: isSessionActive,
                    connectionState: _ws.connectionState,
                    errorMessage: _ws.errorMessage,
                    sessionError: _sessionError,
                    connecting: _connecting,
                    onRetry: _connect,
                    countdownActive: _countdownActive,
                    onCountdownComplete: _beginSessionAfterCountdown,
                  ),
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
                                  FluentIcons.timer,
                                  color: AppColors.primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text('Session', style: AppTheme.headingMedium),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.lg,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppColors.primary.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      FluentIcons.clock,
                                      size: 14,
                                      color: AppColors.primarySoft,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'ELAPSED',
                                      style: AppTheme.caption.copyWith(
                                        color: AppColors.primarySoft,
                                        letterSpacing: 1.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  _formatDuration(_elapsedSeconds),
                                  style: AppTheme.headingMedium.copyWith(
                                    fontSize: 40,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Warm up, freestyle, or drill any move you like. '
                            'This mode just mirrors your camera with live '
                            'detection — nothing is scored or saved.',
                            style: AppTheme.bodySecondary,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _BottleStatusIndicator(
                      detected: isSessionActive ? _bottleDetected : null,
                      isActive: isSessionActive,
                    ),
                    if (_sessionError != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      ElixCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              FluentIcons.warning,
                              color: AppColors.error,
                              size: 28,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(_sessionError!, style: AppTheme.bodySecondary),
                            const SizedBox(height: AppSpacing.md),
                            ElixPrimaryButton(
                              label: 'Retry',
                              onPressed: _connecting ? null : _startSession,
                              isLoading: _connecting,
                            ),
                          ],
                        ),
                      ),
                    ] else if (hasConnectionError || isDisconnected) ...[
                      const SizedBox(height: AppSpacing.md),
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
                    ],
                    const Spacer(),
                    const SizedBox(height: AppSpacing.md),
                    if (isSessionActive)
                      GameActionButton(
                        label: 'Stop',
                        icon: FluentIcons.stop_solid,
                        danger: true,
                        onPressed: _stopSession,
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
    required this.isSessionActive,
    required this.connectionState,
    required this.onRetry,
    this.errorMessage,
    this.sessionError,
    this.connecting = false,
    this.countdownActive = false,
    required this.onCountdownComplete,
  });

  final Uint8List? frameBytes;
  final bool mirrored;
  final bool isSessionActive;
  final WebSocketConnectionState connectionState;
  final String? errorMessage;
  final String? sessionError;
  final bool connecting;
  final VoidCallback onRetry;
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
                  Center(
                    child: AspectRatio(
                      aspectRatio: 640 / 480,
                      child: Transform.flip(
                        flipX: mirrored,
                        child: Image.memory(
                          frameBytes!,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
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
                              : 'Press Start for a free camera session',
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
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.sm),
              child: SizedBox(
                width: 14,
                height: 14,
                child: ProgressRing(strokeWidth: 2),
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
