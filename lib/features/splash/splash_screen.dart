import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/widgets/elix_app_logo.dart';
import '../../core/widgets/elix_primary_button.dart';

/// The branded hand-off shown while Firebase establishes the first auth state.
///
/// The entrance is deliberately one-shot. When startup takes longer, only the
/// atmosphere, orbit, and indeterminate rail continue so the screen settles
/// rather than replaying the brand reveal.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onFinished,
    required this.authReady,
    this.startupError,
    this.onRetry,
  });

  final VoidCallback onFinished;
  final bool authReady;
  final String? startupError;
  final VoidCallback? onRetry;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _entryDuration = Duration(milliseconds: 1400);
  static const _readyDuration = Duration(milliseconds: 180);
  static const _exitDuration = Duration(milliseconds: 240);
  static const _idleDuration = Duration(seconds: 16);

  late final AnimationController _entryController;
  late final AnimationController _idleController;
  late final AnimationController _readyController;
  late final AnimationController _exitController;
  late final Animation<double> _atmosphereReveal;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _bloomOpacity;
  late final Animation<double> _bloomScale;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _statusOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<Offset> _taglineSlide;

  bool _entryComplete = false;
  bool _completionScheduled = false;
  bool _didFinish = false;
  bool? _reduceMotion;
  int _finishGeneration = 0;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: _entryDuration,
    );
    _idleController = AnimationController(vsync: this, duration: _idleDuration);
    _readyController = AnimationController(
      vsync: this,
      duration: _readyDuration,
    );
    _exitController = AnimationController(vsync: this, duration: _exitDuration);

    _atmosphereReveal = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0, 0.22, curve: Curves.easeOut),
    );
    _logoScale =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 0.94,
              end: 1.008,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 82,
          ),
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 1.008,
              end: 1,
            ).chain(CurveTween(curve: Curves.easeOut)),
            weight: 18,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.1, 0.5),
          ),
        );
    _logoOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.08, 0.3, curve: Curves.easeOut),
    );
    _bloomOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.12, 0.46, curve: Curves.easeOutCubic),
    );
    _bloomScale = Tween<double>(begin: 0.78, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.1, 0.5, curve: Curves.easeOutCubic),
      ),
    );
    _titleOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.48, 0.72, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.46, 0.74, curve: Curves.easeOutCubic),
          ),
        );
    _taglineOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.64, 0.86, curve: Curves.easeOut),
    );
    _taglineSlide =
        Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.62, 0.88, curve: Curves.easeOutCubic),
          ),
        );
    _statusOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.74, 1, curve: Curves.easeOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;

    if (reduceMotion) {
      _idleController.stop();
      _entryController.stop();
      _entryController.value = 1;
      _readyController.value = widget.authReady ? 1 : 0;
      _entryComplete = true;
      _tryFinish();
      return;
    }

    if (!_idleController.isAnimating) {
      _idleController.repeat();
    }
    if (widget.authReady) {
      _presentReady();
    }
    if (!_entryComplete) {
      _entryController.forward().then((_) {
        if (!mounted) return;
        setState(() => _entryComplete = true);
        _tryFinish();
      });
    }
  }

  @override
  void didUpdateWidget(SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startupError == null && widget.startupError != null) {
      _cancelScheduledFinish();
      return;
    }
    if (oldWidget.startupError != null && widget.startupError == null) {
      if (!widget.authReady) {
        _readyController.reset();
      }
    }
    if (!oldWidget.authReady && widget.authReady) {
      _presentReady();
    }
    _tryFinish();
  }

  void _presentReady() {
    if (_readyController.isCompleted || _readyController.isAnimating) return;
    if (_reduceMotion ?? MediaQuery.disableAnimationsOf(context)) {
      _readyController.value = 1;
      return;
    }
    _readyController.forward();
  }

  void _cancelScheduledFinish() {
    if (!_completionScheduled || _didFinish) return;
    _finishGeneration++;
    _completionScheduled = false;
    _exitController.reset();
  }

  void _tryFinish() {
    if (_didFinish ||
        _completionScheduled ||
        !_entryComplete ||
        !widget.authReady ||
        widget.startupError != null) {
      return;
    }

    _completionScheduled = true;
    final generation = ++_finishGeneration;
    if (MediaQuery.disableAnimationsOf(context)) {
      _completeFinish(generation);
      return;
    }
    _presentReady();
    _readyController.forward().then((_) {
      if (!mounted ||
          generation != _finishGeneration ||
          !widget.authReady ||
          widget.startupError != null) {
        return;
      }
      _exitController.forward(from: 0).then((_) => _completeFinish(generation));
    });
  }

  void _completeFinish(int generation) {
    if (!mounted ||
        _didFinish ||
        generation != _finishGeneration ||
        !widget.authReady ||
        widget.startupError != null) {
      return;
    }
    _didFinish = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    _entryController.dispose();
    _idleController.dispose();
    _readyController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final metrics = _SplashMetrics.of(MediaQuery.sizeOf(context));

    return AnimatedBuilder(
      animation: _exitController,
      child: _buildStage(
        context,
        highContrast: highContrast,
        reducedMotion: reducedMotion,
        metrics: metrics,
      ),
      builder: (context, child) {
        final t = Curves.easeInCubic.transform(_exitController.value);
        return Opacity(
          opacity: 1 - t,
          child: Transform.scale(scale: 1 - (t * 0.016), child: child),
        );
      },
    );
  }

  Widget _buildStage(
    BuildContext context, {
    required bool highContrast,
    required bool reducedMotion,
    required _SplashMetrics metrics,
  }) {
    final colors = context.elixColors;
    final canvas = highContrast ? colors.canvas : AppColors.background;

    return ColoredBox(
      color: canvas,
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          if (!highContrast)
            const RepaintBoundary(
              child: CustomPaint(painter: _StaticFieldPainter()),
            ),
          if (!highContrast)
            RepaintBoundary(
              child: CustomPaint(
                painter: _AtmospherePainter(
                  idle: reducedMotion
                      ? const AlwaysStoppedAnimation(0.42)
                      : _idleController,
                  reveal: _atmosphereReveal,
                  primary: AppColors.primary,
                  secondary: AppColors.accent,
                ),
              ),
            ),
          Align(
            alignment: Alignment(0, metrics.stageBias),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                metrics.statusReserve,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _buildBrandLockup(
                  context,
                  highContrast: highContrast,
                  reducedMotion: reducedMotion,
                  metrics: metrics,
                ),
              ),
            ),
          ),
          _buildStatus(
            context,
            highContrast: highContrast,
            reducedMotion: reducedMotion,
            metrics: metrics,
          ),
        ],
      ),
    );
  }

  Widget _buildBrandLockup(
    BuildContext context, {
    required bool highContrast,
    required bool reducedMotion,
    required _SplashMetrics metrics,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLogoMark(
            context,
            highContrast: highContrast,
            reducedMotion: reducedMotion,
            metrics: metrics,
          ),
          SizedBox(height: metrics.lockupGap),
          SlideTransition(
            position: _titleSlide,
            child: FadeTransition(
              opacity: _titleOpacity,
              child: _buildWordmark(context, metrics: metrics),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SlideTransition(
            position: _taglineSlide,
            child: FadeTransition(
              opacity: _taglineOpacity,
              child: Text(
                AppConstants.appTagline,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.bodySecondary.copyWith(
                  color: highContrast
                      ? context.elixTextSecondary
                      : context.elixColors.textMuted,
                  fontSize: metrics.taglineSize,
                  height: 1.35,
                  letterSpacing: 0.2,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoMark(
    BuildContext context, {
    required bool highContrast,
    required bool reducedMotion,
    required _SplashMetrics metrics,
  }) {
    final markSize = metrics.markSize;
    final logoSize = metrics.logoSize;
    final idle = reducedMotion
        ? const AlwaysStoppedAnimation(0.18)
        : _idleController;

    return FadeTransition(
      opacity: _logoOpacity,
      child: AnimatedBuilder(
        animation: _logoScale,
        child: SizedBox(
          width: markSize,
          height: markSize,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (!highContrast)
                FadeTransition(
                  opacity: _bloomOpacity,
                  child: AnimatedBuilder(
                    animation: _bloomScale,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size.square(markSize),
                        painter: const _HeroBloomPainter(
                          primary: AppColors.primary,
                          secondary: AppColors.accent,
                        ),
                      ),
                    ),
                    builder: (context, child) =>
                        Transform.scale(scale: _bloomScale.value, child: child),
                  ),
                ),
              RepaintBoundary(
                child: CustomPaint(
                  size: Size.square(markSize),
                  painter: _OrbitPainter(
                    idle: idle,
                    reveal: _bloomOpacity,
                    primary: highContrast
                        ? context.elixColors.textPrimary
                        : AppColors.primary,
                    secondary: highContrast
                        ? context.elixColors.borderStrong
                        : AppColors.accent,
                    highContrast: highContrast,
                    reducedMotion: reducedMotion,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(logoSize * 0.23),
                  border: highContrast
                      ? Border.all(
                          color: context.elixColors.borderStrong,
                          width: 2,
                        )
                      : null,
                  boxShadow: highContrast
                      ? const []
                      : [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.28),
                            blurRadius: 28,
                            spreadRadius: -4,
                            offset: const Offset(0, 12),
                          ),
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.14),
                            blurRadius: 48,
                            spreadRadius: -8,
                          ),
                        ],
                ),
                child: _SplashLogoSweep(
                  size: logoSize,
                  radius: logoSize * 0.23,
                  animation: reducedMotion
                      ? const AlwaysStoppedAnimation(1)
                      : _entryController,
                  enabled:
                      !highContrast &&
                      !reducedMotion &&
                      !_entryController.isCompleted,
                ),
              ),
            ],
          ),
        ),
        builder: (context, child) =>
            Transform.scale(scale: _logoScale.value, child: child),
      ),
    );
  }

  Widget _buildWordmark(
    BuildContext context, {
    required _SplashMetrics metrics,
  }) {
    final highContrast = context.isHighContrast;
    final style =
        AppTheme.brandTitle(
          fontSize: metrics.wordmarkSize,
          color: highContrast ? context.elixTextPrimary : AppColors.textPrimary,
        ).copyWith(
          letterSpacing: metrics.wordmarkTracking,
          shadows: highContrast
              ? null
              : [
                  Shadow(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    blurRadius: 14,
                  ),
                ],
        );
    return AnimatedBuilder(
      animation: _titleOpacity,
      builder: (context, _) {
        final settle = Curves.easeOutCubic.transform(_titleOpacity.value);
        return Text(
          AppConstants.appName,
          style: style.copyWith(
            letterSpacing:
                ui.lerpDouble(
                  metrics.wordmarkTracking + 1.2,
                  metrics.wordmarkTracking,
                  settle,
                ) ??
                metrics.wordmarkTracking,
          ),
        );
      },
    );
  }

  Widget _buildStatus(
    BuildContext context, {
    required bool highContrast,
    required bool reducedMotion,
    required _SplashMetrics metrics,
  }) {
    final error = widget.startupError;
    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      bottom: AppSpacing.lg,
      child: SafeArea(
        top: false,
        child: Center(
          child: error == null
              ? FadeTransition(
                  opacity: _statusOpacity,
                  child: _PreparingStatus(
                    authReady: widget.authReady,
                    highContrast: highContrast,
                    reducedMotion: reducedMotion,
                    railWidth: metrics.railWidth,
                    idle: reducedMotion
                        ? const AlwaysStoppedAnimation(0.38)
                        : _idleController,
                    ready: reducedMotion && widget.authReady
                        ? const AlwaysStoppedAnimation(1)
                        : _readyController,
                  ),
                )
              : _FailureStatus(
                  message: error,
                  onRetry: widget.onRetry,
                  highContrast: highContrast,
                ),
        ),
      ),
    );
  }
}

class _SplashMetrics {
  const _SplashMetrics({
    required this.markSize,
    required this.wordmarkSize,
    required this.wordmarkTracking,
    required this.taglineSize,
    required this.lockupGap,
    required this.statusReserve,
    required this.railWidth,
    required this.stageBias,
  });

  factory _SplashMetrics.of(Size size) {
    final height = size.height;
    final width = size.width;
    final short = height < 460;
    final compact = height < 560;
    final narrow = width < ElixTypography.compactBreakpoint;
    return _SplashMetrics(
      markSize: short
          ? 128
          : compact
          ? 168
          : height < 720
          ? 208
          : 236,
      wordmarkSize: short || narrow ? 32 : 42,
      wordmarkTracking: narrow ? 2.2 : 2.8,
      taglineSize: compact ? 12 : 13,
      lockupGap: short ? 10 : (compact ? 12 : 16),
      statusReserve: compact ? 100 : 132,
      railWidth: narrow ? 200 : 248,
      stageBias: short ? -0.02 : -0.06,
    );
  }

  final double markSize;
  final double wordmarkSize;
  final double wordmarkTracking;
  final double taglineSize;
  final double lockupGap;
  final double statusReserve;
  final double railWidth;
  final double stageBias;

  double get logoSize => markSize * 0.52;
}

class _SplashLogoSweep extends StatelessWidget {
  const _SplashLogoSweep({
    required this.size,
    required this.radius,
    required this.animation,
    required this.enabled,
  });

  final double size;
  final double radius;
  final Animation<double> animation;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final logo = ElixAppLogo(size: size, borderRadius: radius);
    if (!enabled) return logo;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        alignment: Alignment.center,
        children: [
          logo,
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SpecularSweepPainter(animation: animation),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreparingStatus extends StatelessWidget {
  const _PreparingStatus({
    required this.authReady,
    required this.highContrast,
    required this.reducedMotion,
    required this.railWidth,
    required this.idle,
    required this.ready,
  });

  final bool authReady;
  final bool highContrast;
  final bool reducedMotion;
  final double railWidth;
  final Animation<double> idle;
  final Animation<double> ready;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final label = authReady ? 'READY' : 'PREPARING YOUR SESSION';
    return Semantics(
      liveRegion: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: SizedBox(
              key: const Key('splash_startup_rail'),
              width: railWidth,
              height: 28,
              child: CustomPaint(
                painter: _CometRailPainter(
                  idle: idle,
                  ready: ready,
                  trackFill: highContrast
                      ? colors.canvas
                      : AppColors.backgroundDeep.withValues(alpha: 0.72),
                  borderColor: highContrast
                      ? colors.borderStrong
                      : AppColors.primary.withValues(alpha: 0.28),
                  comet: highContrast ? colors.textPrimary : AppColors.primary,
                  trail: highContrast
                      ? colors.textPrimary
                      : AppColors.primarySoft,
                  glow: highContrast
                      ? const Color(0x00000000)
                      : AppColors.accent,
                  highContrast: highContrast,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedSwitcher(
            duration: reducedMotion ? Duration.zero : ElixMotion.standard,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: Text(
              label,
              key: ValueKey(label),
              textAlign: TextAlign.center,
              style: AppTheme.eyebrow(
                color: authReady
                    ? (highContrast
                          ? colors.textPrimary
                          : AppColors.textPrimary)
                    : context.elixTextSecondary,
              ).copyWith(fontSize: 10, letterSpacing: 1.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureStatus extends StatelessWidget {
  const _FailureStatus({
    required this.message,
    required this.onRetry,
    required this.highContrast,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool highContrast;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: DecoratedBox(
        key: const Key('splash_failure_panel'),
        decoration: BoxDecoration(
          color: highContrast
              ? colors.surfaceRaised
              : AppColors.cardSurface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highContrast
                ? colors.borderStrong
                : AppColors.border.withValues(alpha: 0.9),
            width: highContrast ? 2 : 1,
          ),
          boxShadow: highContrast
              ? const []
              : [
                  BoxShadow(
                    color: AppColors.background.withValues(alpha: 0.46),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    ElixToneCues.icon(ElixTone.error),
                    color: highContrast ? colors.textPrimary : colors.error,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'SESSION PREPARATION FAILED',
                      style: AppTheme.eyebrow(
                        color: context.elixTextSecondary,
                      ).copyWith(fontSize: 10, letterSpacing: 1.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                  height: 1.35,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElixPrimaryButton(
                    key: const Key('splash_retry_button'),
                    label: 'Retry',
                    icon: FluentIcons.refresh,
                    expanded: false,
                    dense: true,
                    onPressed: onRetry,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

double _unitInterval(double t, double begin, double end, Curve curve) {
  if (t <= begin) return 0;
  if (t >= end) return 1;
  return curve.transform((t - begin) / (end - begin));
}

/// Static grain and vignette so the desktop canvas has depth without ticking.
class _StaticFieldPainter extends CustomPainter {
  const _StaticFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grain = Paint()..color = const Color(0x14F7F5FC);
    const step = 13.0;
    for (var x = 0.0; x < size.width; x += step) {
      for (var y = 0.0; y < size.height; y += step) {
        final hashed = _hash2(x.toInt(), y.toInt());
        if (hashed % 13 != 0) continue;
        canvas.drawCircle(
          Offset(x + (hashed % 5) * 0.35, y + (hashed % 3) * 0.4),
          0.55,
          grain,
        );
      }
    }

    final vignette = Paint()
      ..shader = ui.Gradient.radial(
        size.center(Offset.zero),
        size.longestSide * 0.72,
        [
          const Color(0x00000000),
          AppColors.background.withValues(alpha: 0.22),
          AppColors.background.withValues(alpha: 0.58),
        ],
        const [0.46, 0.78, 1],
      );
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(covariant _StaticFieldPainter oldDelegate) => false;
}

int _hash2(int x, int y) {
  var n = (x * 374761393 + y * 668265263) & 0x7fffffff;
  n = (n ^ (n >> 13)) * 1274126177;
  return n & 0x7fffffff;
}

/// Layered magenta/plum illumination that drifts very slowly.
class _AtmospherePainter extends CustomPainter {
  _AtmospherePainter({
    required this.idle,
    required this.reveal,
    required this.primary,
    required this.secondary,
  }) : super(repaint: idle);

  final Animation<double> idle;
  final Animation<double> reveal;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = reveal.value.clamp(0.0, 1.0);
    if (visible <= 0) return;
    final t = idle.value;
    final breath = 0.88 + (0.12 * (0.5 + 0.5 * math.sin(t * math.pi * 2)));
    final drift = Offset(
      math.sin(t * math.pi * 2) * size.width * 0.018,
      math.cos(t * math.pi * 2) * size.height * 0.012,
    );

    _blob(
      canvas,
      Offset(size.width * 0.5, size.height * 0.34) + drift * 0.35,
      size.shortestSide * 0.44,
      primary.withValues(alpha: 0.09 * visible * breath),
    );
    _blob(
      canvas,
      Offset(size.width * 0.22, size.height * 0.62) + drift * 0.7,
      size.shortestSide * 0.56,
      secondary.withValues(alpha: 0.12 * visible * breath),
    );
    _blob(
      canvas,
      Offset(size.width * 0.82, size.height * 0.28) - drift * 0.5,
      size.shortestSide * 0.38,
      primary.withValues(alpha: 0.07 * visible * breath),
    );
    _blob(
      canvas,
      Offset(size.width * 0.68, size.height * 0.78) +
          Offset(drift.dy, -drift.dx),
      size.shortestSide * 0.34,
      secondary.withValues(alpha: 0.05 * visible * breath),
    );
  }

  void _blob(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          color,
          color.withValues(alpha: color.a * 0.35),
          color.withValues(alpha: 0),
        ],
        const [0, 0.42, 1],
      );
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _AtmospherePainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.idle != idle ||
      oldDelegate.reveal != reveal;
}

/// Soft bloom and concentric rings that resolve once behind the mark.
class _HeroBloomPainter extends CustomPainter {
  const _HeroBloomPainter({required this.primary, required this.secondary});

  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.38;

    canvas.drawCircle(
      center,
      radius * 1.18,
      Paint()
        ..color = primary.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.drawCircle(
      center,
      radius * 0.82,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius * 0.82,
          [
            primary.withValues(alpha: 0.2),
            secondary.withValues(alpha: 0.08),
            const Color(0x00000000),
          ],
          const [0, 0.46, 1],
        ),
    );
    canvas.drawCircle(
      center,
      radius * 1.32,
      Paint()
        ..color = secondary.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _HeroBloomPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.secondary != secondary;
}

/// Slow orbiting arcs. Rotation is idle-only and never a spinner.
class _OrbitPainter extends CustomPainter {
  _OrbitPainter({
    required this.idle,
    required this.reveal,
    required this.primary,
    required this.secondary,
    required this.highContrast,
    required this.reducedMotion,
  }) : super(repaint: reducedMotion ? reveal : idle);

  final Animation<double> idle;
  final Animation<double> reveal;
  final Color primary;
  final Color secondary;
  final bool highContrast;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = reveal.value.clamp(0.0, 1.0);
    if (visible <= 0) return;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.36;
    final turn = reducedMotion ? -2.05 : (idle.value * math.pi * 2);

    final ring = Paint()
      ..color = (highContrast ? primary : secondary).withValues(
        alpha: highContrast ? 1 : 0.22 * visible,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = highContrast ? 2 : 1;
    canvas.drawCircle(center, radius, ring);

    if (highContrast) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -2.05,
        1.05,
        false,
        Paint()
          ..color = primary
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2,
      );
      return;
    }

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      turn - 2.28,
      1.12,
      false,
      Paint()
        ..color = primary.withValues(alpha: 0.78 * visible)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.5,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 1.22),
      (-turn * 0.35) + 0.7,
      0.82,
      false,
      Paint()
        ..color = secondary.withValues(alpha: 0.42 * visible)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.1,
    );
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) =>
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.highContrast != highContrast ||
      oldDelegate.reducedMotion != reducedMotion ||
      oldDelegate.idle != idle ||
      oldDelegate.reveal != reveal;
}

class _SpecularSweepPainter extends CustomPainter {
  _SpecularSweepPainter({required this.animation}) : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final t = _unitInterval(animation.value, 0.3, 0.58, Curves.easeInOutCubic);
    if (t <= 0 || t >= 1) return;
    final x = size.width * (t * 1.55 - 0.28);
    final band = Path()
      ..moveTo(x, -2)
      ..lineTo(x + 34, -2)
      ..lineTo(x + 8, size.height + 2)
      ..lineTo(x - 26, size.height + 2)
      ..close();
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = LinearGradient(
        colors: [
          const Color(0x00FFFFFF),
          Colors.white.withValues(alpha: 0.2 * math.sin(t * math.pi)),
          AppColors.primary.withValues(alpha: 0.1 * math.sin(t * math.pi)),
          const Color(0x00FFFFFF),
        ],
      ).createShader(band.getBounds());
    canvas.drawPath(band, paint);
  }

  @override
  bool shouldRepaint(covariant _SpecularSweepPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

/// Indeterminate capsule rail. [ready] fills the track; never a percentage.
class _CometRailPainter extends CustomPainter {
  _CometRailPainter({
    required this.idle,
    required this.ready,
    required this.trackFill,
    required this.borderColor,
    required this.comet,
    required this.trail,
    required this.glow,
    required this.highContrast,
  }) : super(repaint: idle);

  final Animation<double> idle;
  final Animation<double> ready;
  final Color trackFill;
  final Color borderColor;
  final Color comet;
  final Color trail;
  final Color glow;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final plate = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 4, size.width, size.height - 8),
      const Radius.circular(99),
    );
    canvas.drawRRect(
      plate,
      Paint()
        ..color = trackFill
        ..style = PaintingStyle.fill,
    );
    if (!highContrast) {
      canvas.drawRRect(
        plate,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.08),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(plate.outerRect),
      );
    }
    canvas.drawRRect(
      plate,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = highContrast ? 2 : 1,
    );

    final readyT = Curves.easeOutCubic.transform(
      ready.value.clamp(0.0, 1.0).toDouble(),
    );
    final inner = plate.deflate(highContrast ? 5 : 4);
    final innerRect = inner.outerRect;

    if (readyT > 0) {
      final filled = Rect.fromLTWH(
        innerRect.left,
        innerRect.top,
        innerRect.width * readyT.clamp(0.08, 1.0),
        innerRect.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(filled, const Radius.circular(99)),
        Paint()
          ..shader = LinearGradient(
            colors: [comet.withValues(alpha: 0.45), comet, trail],
          ).createShader(filled),
      );
      return;
    }

    final cycle = idle.isAnimating ? (idle.value * 8) % 1.0 : 0.42;
    final segmentWidth = innerRect.width * 0.28;
    final left =
        innerRect.left +
        (cycle * (innerRect.width + segmentWidth)) -
        segmentWidth;
    final segment = Rect.fromLTWH(
      left,
      innerRect.top,
      segmentWidth,
      innerRect.height,
    ).intersect(innerRect);
    if (segment.isEmpty) return;

    if (!highContrast) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(segment.inflate(4), const Radius.circular(99)),
        Paint()
          ..color = glow.withValues(alpha: 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(segment, const Radius.circular(99)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            comet.withValues(alpha: 0),
            comet,
            trail,
            comet.withValues(alpha: 0.12),
          ],
        ).createShader(segment),
    );
  }

  @override
  bool shouldRepaint(covariant _CometRailPainter oldDelegate) =>
      oldDelegate.trackFill != trackFill ||
      oldDelegate.borderColor != borderColor ||
      oldDelegate.comet != comet ||
      oldDelegate.trail != trail ||
      oldDelegate.glow != glow ||
      oldDelegate.highContrast != highContrast ||
      oldDelegate.idle != idle ||
      oldDelegate.ready != ready;
}
