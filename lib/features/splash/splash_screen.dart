import 'dart:math' as math;

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
/// atmosphere and the small status treatment continue so the screen settles
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
  static const _entryDuration = Duration(milliseconds: 1320);
  static const _exitDuration = Duration(milliseconds: 220);
  static const _ambientDuration = Duration(seconds: 8);

  late final AnimationController _entryController;
  late final AnimationController _ambientController;
  late final AnimationController _exitController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _haloOpacity;
  late final Animation<double> _haloScale;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _loaderOpacity;
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
    _ambientController = AnimationController(
      vsync: this,
      duration: _ambientDuration,
    );
    _exitController = AnimationController(vsync: this, duration: _exitDuration);

    _logoScale =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 0.9,
              end: 1.018,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 84,
          ),
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 1.018,
              end: 1,
            ).chain(CurveTween(curve: Curves.easeOut)),
            weight: 16,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.08, 0.56),
          ),
        );
    _logoOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.06, 0.28, curve: Curves.easeOut),
    );
    _haloOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.12, 0.48, curve: Curves.easeOutCubic),
    );
    _haloScale = Tween<double>(begin: 0.84, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.1, 0.52, curve: Curves.easeOutCubic),
      ),
    );
    _titleOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.44, 0.7, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.42, 0.72, curve: Curves.easeOutCubic),
          ),
        );
    _taglineOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.62, 0.84, curve: Curves.easeOut),
    );
    _taglineSlide =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.6, 0.86, curve: Curves.easeOutCubic),
          ),
        );
    _loaderOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.72, 1, curve: Curves.easeOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;

    if (reduceMotion) {
      _ambientController.stop();
      _entryController.stop();
      _entryController.value = 1;
      _entryComplete = true;
      _tryFinish();
      return;
    }

    if (!_ambientController.isAnimating) {
      _ambientController.repeat(reverse: true);
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
    if ((!oldWidget.authReady && widget.authReady) ||
        (oldWidget.startupError != null && widget.startupError == null)) {
      _tryFinish();
    }
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
    _exitController.forward(from: 0).then((_) => _completeFinish(generation));
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
    _ambientController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final compact = MediaQuery.sizeOf(context).height < 560;

    return AnimatedBuilder(
      animation: _exitController,
      child: _buildContent(
        context,
        highContrast: highContrast,
        reducedMotion: reducedMotion,
        compact: compact,
      ),
      builder: (context, child) => Opacity(
        opacity: 1 - _exitController.value,
        child: Transform.scale(
          scale: 1 - (_exitController.value * 0.012),
          child: child,
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required bool highContrast,
    required bool reducedMotion,
    required bool compact,
  }) {
    final colors = context.elixColors;
    return ColoredBox(
      color: colors.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!highContrast)
            const RepaintBoundary(
              child: CustomPaint(painter: _SplashTexturePainter()),
            ),
          if (!highContrast)
            RepaintBoundary(
              child: _AmbientBackdrop(
                animation: reducedMotion
                    ? const AlwaysStoppedAnimation(0.5)
                    : _ambientController,
              ),
            ),
          Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: compact ? 104 : 126,
            ),
            child: Center(child: _buildBrandLockup(context, compact: compact)),
          ),
          _buildStatus(context, highContrast: highContrast),
        ],
      ),
    );
  }

  Widget _buildBrandLockup(BuildContext context, {required bool compact}) {
    return AnimatedBuilder(
      animation: _entryController,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLogoMark(context, compact: compact),
          SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
          SlideTransition(
            position: _titleSlide,
            child: FadeTransition(
              opacity: _titleOpacity,
              child: _buildWordmark(context),
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
                style: AppTheme.bodySecondary.copyWith(
                  color: context.elixTextSecondary,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoMark(BuildContext context, {required bool compact}) {
    final highContrast = context.isHighContrast;
    final height = MediaQuery.sizeOf(context).height;
    final markSize = height < 480 ? 144.0 : (compact ? 166.0 : 204.0);
    final logoSize = markSize * 0.55;

    return FadeTransition(
      opacity: _logoOpacity,
      child: Transform.scale(
        scale: _logoScale.value,
        child: SizedBox(
          width: markSize,
          height: markSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (!highContrast)
                FadeTransition(
                  opacity: _haloOpacity,
                  child: Transform.scale(
                    scale: _haloScale.value,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size.square(markSize),
                        painter: _SplashHaloPainter(
                          primary: AppColors.primary,
                          secondary: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              if (!highContrast)
                Container(
                  width: markSize * 0.78,
                  height: markSize * 0.78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.18),
                        AppColors.accent.withValues(alpha: 0.07),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.48, 1],
                    ),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(logoSize * 0.23),
                  boxShadow: highContrast
                      ? const []
                      : [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.24),
                            blurRadius: 32,
                            spreadRadius: -3,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.12),
                            blurRadius: 52,
                            spreadRadius: -10,
                          ),
                        ],
                ),
                child: ElixAppLogo(
                  size: logoSize,
                  borderRadius: logoSize * 0.23,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWordmark(BuildContext context) {
    final highContrast = context.isHighContrast;
    final style =
        AppTheme.brandTitle(
          fontSize: ElixTypography.isCompact(context) ? 40 : 52,
          color: highContrast ? context.elixTextPrimary : AppColors.textPrimary,
        ).copyWith(
          letterSpacing: ElixTypography.isCompact(context) ? 6.5 : 8,
          shadows: highContrast
              ? null
              : [
                  Shadow(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    blurRadius: 18,
                  ),
                ],
        );
    return Text(AppConstants.appName, style: style);
  }

  Widget _buildStatus(BuildContext context, {required bool highContrast}) {
    final error = widget.startupError;
    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      bottom: AppSpacing.xl,
      child: SafeArea(
        top: false,
        child: Center(
          child: error == null
              ? FadeTransition(
                  opacity: _loaderOpacity,
                  child: _PreparingStatus(
                    authReady: widget.authReady,
                    highContrast: highContrast,
                    animation: _ambientController,
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

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final breath = 0.88 + (animation.value * 0.12);
        return IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.08),
                radius: 0.72,
                colors: [
                  AppColors.primary.withValues(alpha: 0.14 * breath),
                  AppColors.accent.withValues(alpha: 0.065 * breath),
                  Colors.transparent,
                ],
                stops: const [0, 0.46, 1],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _PreparingStatus extends StatelessWidget {
  const _PreparingStatus({
    required this.authReady,
    required this.highContrast,
    required this.animation,
  });

  final bool authReady;
  final bool highContrast;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: highContrast ? colors.textPrimary : AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              authReady ? 'READY TO TRAIN' : 'PREPARING YOUR SESSION',
              style: AppTheme.eyebrow(
                color: context.elixTextSecondary,
              ).copyWith(fontSize: 10, letterSpacing: 1.6),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        RepaintBoundary(
          child: SizedBox(
            width: 188,
            height: 3,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) => CustomPaint(
                painter: _SplashProgressPainter(
                  progress: animation.value,
                  trackColor: colors.borderSubtle.withValues(
                    alpha: highContrast ? 1 : 0.62,
                  ),
                  primary: highContrast
                      ? colors.textPrimary
                      : AppColors.primary,
                  secondary: highContrast
                      ? colors.textPrimary
                      : AppColors.primarySoft,
                ),
              ),
            ),
          ),
        ),
        if (!authReady) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Preparing your session…',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
      ],
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
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.status_circle_error_x,
                color: highContrast ? colors.textPrimary : colors.error,
                size: 15,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'SESSION PREPARATION FAILED',
                style: AppTheme.eyebrow(
                  color: context.elixTextSecondary,
                ).copyWith(fontSize: 10, letterSpacing: 1.6),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ElixPrimaryButton(
              key: const Key('splash_retry_button'),
              label: 'Retry',
              icon: FluentIcons.refresh,
              expanded: false,
              dense: true,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}

/// A static fine texture keeps the large desktop canvas from feeling empty.
class _SplashTexturePainter extends CustomPainter {
  const _SplashTexturePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.primary.withValues(alpha: 0.025);
    const spacing = 32.0;
    for (var x = spacing / 2; x < size.width; x += spacing) {
      for (var y = spacing / 2; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.7, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SplashTexturePainter oldDelegate) => false;
}

/// The halo forms once with the logo; it is intentionally not an orbiting UI
/// control or an indefinitely rotating decoration.
class _SplashHaloPainter extends CustomPainter {
  const _SplashHaloPainter({required this.primary, required this.secondary});

  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.36;
    final subtleRing = Paint()
      ..color = secondary.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, radius, subtleRing);

    final brightArc = Paint()
      ..color = primary.withValues(alpha: 0.76)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -2.28,
      1.18,
      false,
      brightArc,
    );
    final quietArc = Paint()
      ..color = secondary.withValues(alpha: 0.48)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 1.24),
      0.72,
      0.86,
      false,
      quietArc,
    );
  }

  @override
  bool shouldRepaint(covariant _SplashHaloPainter oldDelegate) =>
      oldDelegate.primary != primary || oldDelegate.secondary != secondary;
}

class _SplashProgressPainter extends CustomPainter {
  const _SplashProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.primary,
    required this.secondary,
  });

  final double progress;
  final Color trackColor;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas.drawRRect(track, Paint()..color = trackColor);

    final segmentWidth = size.width * 0.3;
    final left = (progress * (size.width + segmentWidth)) - segmentWidth;
    final segment = Rect.fromLTWH(
      left,
      0,
      segmentWidth,
      size.height,
    ).intersect(Offset.zero & size);
    if (segment.isEmpty) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(segment, const Radius.circular(3)),
      Paint()
        ..shader = LinearGradient(
          colors: [primary.withValues(alpha: 0), primary, secondary],
        ).createShader(segment),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary;
}
