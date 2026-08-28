import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/elix_design_tokens.dart';
import '../../core/widgets/elix_app_logo.dart';
import '../../core/widgets/elix_scaffold_page.dart';

/// The short branded hand-off shown while Firebase establishes the first
/// auth state. The animation is intentionally self-contained: it can loop
/// while startup is slow without changing the app's auth or routing state.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onFinished,
    required this.authReady,
  });

  final VoidCallback onFinished;
  final bool authReady;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _ambientController;
  late final AnimationController _shimmerController;
  late final AnimationController _pulseController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _orbitScale;
  late final Animation<double> _orbitOpacity;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _loaderOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _pulseScale;

  bool _animationDone = false;
  bool _completionScheduled = false;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _logoScale =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 0.82,
              end: 1.035,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
            weight: 76,
          ),
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 1.035,
              end: 1,
            ).chain(CurveTween(curve: Curves.easeOut)),
            weight: 24,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0, 0.62),
          ),
        );
    _logoOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0, 0.3, curve: Curves.easeOut),
    );
    _orbitScale = Tween<double>(begin: 0.72, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.02, 0.7, curve: Curves.easeOutCubic),
      ),
    );
    _orbitOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.02, 0.42, curve: Curves.easeOut),
    );
    _titleOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.28, 0.64, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.28, 0.68, curve: Curves.easeOutCubic),
          ),
        );
    _taglineOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.52, 0.86, curve: Curves.easeOut),
    );
    _taglineSlide =
        Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _entryController,
            curve: const Interval(0.52, 0.9, curve: Curves.easeOutCubic),
          ),
        );
    _loaderOpacity = CurvedAnimation(
      parent: _entryController,
      curve: const Interval(0.7, 1, curve: Curves.easeOut),
    );
    _pulseScale = Tween<double>(begin: 1, end: 1.035).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
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
      _shimmerController.stop();
      _pulseController.stop();
      _entryController.stop();
      _entryController.value = 1;
      _animationDone = true;
      _tryFinish();
      return;
    }

    if (!_ambientController.isAnimating) _ambientController.repeat();
    if (!_shimmerController.isAnimating) _shimmerController.repeat();
    if (!_pulseController.isAnimating) _pulseController.repeat(reverse: true);
    if (!_animationDone) {
      _entryController.forward().then((_) {
        if (mounted) setState(() => _animationDone = true);
        _tryFinish();
      });
    }
  }

  @override
  void didUpdateWidget(SplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.authReady && widget.authReady) {
      _tryFinish();
    }
  }

  void _tryFinish() {
    if (_animationDone && widget.authReady && !_completionScheduled) {
      _completionScheduled = true;
      Future.delayed(
        ElixMotion.duration(context, const Duration(milliseconds: 500)),
        () {
          if (mounted) widget.onFinished();
        },
      );
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    _ambientController.dispose();
    _shimmerController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final isDark = context.isDarkTheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final compactSplash = MediaQuery.sizeOf(context).height < 560;

    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: Stack(
        fit: StackFit.expand,
        children: [
          if (!highContrast)
            CustomPaint(
              painter: _SplashDotGridPainter(
                color: AppColors.primary.withValues(
                  alpha: isDark ? 0.035 : 0.05,
                ),
              ),
            ),
          if (!highContrast)
            _buildAmbientBackdrop(context, reducedMotion: reducedMotion),
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _entryController,
                _ambientController,
                _shimmerController,
                _pulseController,
              ]),
              builder: (context, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLogoMark(context),
                    SizedBox(
                      height: compactSplash ? AppSpacing.md : AppSpacing.lg,
                    ),
                    SlideTransition(
                      position: _titleSlide,
                      child: FadeTransition(
                        opacity: _titleOpacity,
                        child: _buildTitle(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SlideTransition(
                      position: _taglineSlide,
                      child: FadeTransition(
                        opacity: _taglineOpacity,
                        child: Text(
                          AppConstants.appTagline,
                          style: AppTheme.bodySecondary.copyWith(
                            color: context.elixTextSecondary,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _buildLoader(context),
        ],
      ),
    );
  }

  Widget _buildAmbientBackdrop(
    BuildContext context, {
    required bool reducedMotion,
  }) {
    return AnimatedBuilder(
      animation: reducedMotion
          ? const AlwaysStoppedAnimation(0)
          : _ambientController,
      builder: (context, _) {
        final t = _ambientController.value * 2 * math.pi;
        return Stack(
          children: [
            _orb(
              dx: math.sin(t) * 40,
              dy: math.cos(t) * 60,
              alignment: const Alignment(-0.86, -0.72),
              size: 360,
              color: AppColors.primary.withValues(alpha: 0.14),
            ),
            _orb(
              dx: math.cos(t) * 52,
              dy: math.sin(t) * 42,
              alignment: const Alignment(0.9, 0.82),
              size: 400,
              color: AppColors.primarySoft.withValues(alpha: 0.11),
            ),
            _orb(
              dx: math.sin(t + 1.5) * 34,
              dy: math.cos(t + 1.5) * 34,
              alignment: const Alignment(0.82, -0.9),
              size: 300,
              color: AppColors.accent.withValues(alpha: 0.14),
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.9,
                    colors: [
                      Colors.transparent,
                      (context.isDarkTheme ? Colors.black : Colors.white)
                          .withValues(alpha: 0.16),
                    ],
                    stops: const [0.46, 1],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _orb({
    required double dx,
    required double dy,
    required Alignment alignment,
    required double size,
    required Color color,
  }) {
    return Align(
      alignment: alignment,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoMark(BuildContext context) {
    final highContrast = context.isHighContrast;
    final height = MediaQuery.sizeOf(context).height;
    final markSize = height < 480
        ? 150.0
        : height < 560
        ? 174.0
        : 210.0;
    final logoSize = markSize * 0.6;
    final shimmer = _shimmerController.value;
    final glowPhase = (math.sin(shimmer * 2 * math.pi) + 1) / 2;
    final glowColor = Color.lerp(
      AppColors.primary,
      AppColors.accent,
      glowPhase * 0.55,
    )!;

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
                Opacity(
                  opacity: _orbitOpacity.value,
                  child: Transform.scale(
                    scale: _orbitScale.value,
                    child: CustomPaint(
                      size: Size.square(markSize),
                      painter: _SplashOrbitPainter(
                        rotation: _ambientController.value,
                        shimmer: shimmer,
                        primary: AppColors.primary,
                        secondary: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              if (!highContrast)
                Container(
                  width: markSize * 0.705,
                  height: markSize * 0.705,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        glowColor.withValues(alpha: 0.16),
                        glowColor.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              Container(
                width: logoSize,
                height: logoSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(logoSize * 0.23),
                  boxShadow: highContrast
                      ? const []
                      : [
                          BoxShadow(
                            color: glowColor.withValues(
                              alpha: 0.18 + glowPhase * 0.14,
                            ),
                            blurRadius: 34,
                            spreadRadius: -2,
                            offset: const Offset(0, 10),
                          ),
                        ],
                ),
                child: Transform.scale(
                  scale: _pulseScale.value,
                  child: ElixAppLogo(
                    size: logoSize,
                    borderRadius: logoSize * 0.23,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final shimmer = _shimmerController.value;
    final highlight = (1 - (shimmer - 0.5).abs() * 2).clamp(0.0, 1.0);
    final color = context.isHighContrast
        ? context.elixColors.brandPrimary
        : Color.lerp(AppColors.primary, AppColors.primarySoft, highlight)!;

    return Text(
      AppConstants.appName,
      style:
          AppTheme.brandTitle(
            fontSize: ElixTypography.isCompact(context) ? 40 : 52,
            color: color,
          ).copyWith(
            letterSpacing: 8,
            shadows: context.isHighContrast
                ? null
                : [
                    Shadow(
                      color: AppColors.primary.withValues(
                        alpha: 0.16 + highlight * 0.14,
                      ),
                      blurRadius: 18,
                    ),
                  ],
          ),
    );
  }

  Widget _buildLoader(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Positioned(
      bottom: AppSpacing.xxl,
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      child: SafeArea(
        top: false,
        child: FadeTransition(
          opacity: _loaderOpacity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: highContrast
                          ? context.elixTextPrimary
                          : AppColors.primary,
                      boxShadow: highContrast
                          ? const []
                          : [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.7),
                                blurRadius: 10,
                              ),
                            ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    widget.authReady
                        ? 'READY TO TRAIN'
                        : 'PREPARING YOUR SESSION',
                    style: AppTheme.eyebrow(
                      color: context.elixTextSecondary,
                    ).copyWith(fontSize: 10, letterSpacing: 1.8),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: 224,
                height: 4,
                child: AnimatedBuilder(
                  animation: _shimmerController,
                  builder: (context, _) => CustomPaint(
                    painter: _SplashProgressPainter(
                      progress: _shimmerController.value,
                      trackColor: context.elixBorder.withValues(
                        alpha: highContrast ? 1 : 0.55,
                      ),
                      primary: highContrast
                          ? context.elixTextPrimary
                          : AppColors.primary,
                      secondary: highContrast
                          ? context.elixTextPrimary
                          : AppColors.primarySoft,
                      highContrast: highContrast,
                    ),
                  ),
                ),
              ),
              if (!widget.authReady) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Preparing your session…',
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
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

/// A thin orbit system turns the logo into a focal point without competing
/// with it. The rotation is ambient and never affects startup state.
class _SplashOrbitPainter extends CustomPainter {
  const _SplashOrbitPainter({
    required this.rotation,
    required this.shimmer,
    required this.primary,
    required this.secondary,
  });

  final double rotation;
  final double shimmer;
  final Color primary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final baseRadius = math.min(size.width, size.height) * 0.31;
    final rotationAngle = rotation * math.pi * 2;
    final shimmerAngle = shimmer * math.pi * 2;

    final innerRing = Paint()
      ..color = primary.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, baseRadius, innerRing);

    final outerRing = Paint()
      ..color = secondary.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(center, baseRadius * 1.34, outerRing);

    final brightArc = Paint()
      ..color = Color.lerp(primary, secondary, 0.35)!.withValues(alpha: 0.86)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: baseRadius * 1.34),
      rotationAngle - 0.75,
      1.05,
      false,
      brightArc,
    );

    final quietArc = Paint()
      ..color = primary.withValues(alpha: 0.44)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: baseRadius),
      -rotationAngle + shimmerAngle + 1.9,
      0.62,
      false,
      quietArc,
    );

    final particlePaint = Paint()..style = PaintingStyle.fill;
    for (var index = 0; index < 3; index++) {
      final angle = rotationAngle + shimmerAngle * 0.3 + index * 2.1;
      final radius = baseRadius * (index.isEven ? 1.34 : 1);
      particlePaint.color = (index == 0 ? primary : secondary).withValues(
        alpha: index == 0 ? 0.9 : 0.42,
      );
      canvas.drawCircle(
        Offset(
          center.dx + math.cos(angle) * radius,
          center.dy + math.sin(angle) * radius,
        ),
        index == 0 ? 2.5 : 1.6,
        particlePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashOrbitPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.shimmer != shimmer ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary;
}

class _SplashProgressPainter extends CustomPainter {
  const _SplashProgressPainter({
    required this.progress,
    required this.trackColor,
    required this.primary,
    required this.secondary,
    required this.highContrast,
  });

  final double progress;
  final Color trackColor;
  final Color primary;
  final Color secondary;
  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(3),
    );
    canvas.drawRRect(track, Paint()..color = trackColor);

    final segmentWidth = size.width * 0.42;
    final segmentLeft = (progress * (size.width + segmentWidth)) - segmentWidth;
    final segment = Rect.fromLTWH(
      segmentLeft,
      0,
      segmentWidth,
      size.height,
    ).intersect(Offset.zero & size);
    if (segment.isEmpty) return;

    final segmentRRect = RRect.fromRectAndRadius(
      segment,
      const Radius.circular(3),
    );
    final segmentPaint = Paint()
      ..shader = LinearGradient(
        colors: [primary.withValues(alpha: 0), primary, secondary, primary],
      ).createShader(segment);
    canvas.drawRRect(segmentRRect, segmentPaint);

    if (!highContrast) {
      canvas.drawRRect(
        segmentRRect,
        Paint()
          ..color = primary.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplashProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.highContrast != highContrast;
}

/// Dot-grid background matching [AuthScaffold]'s visual density.
class _SplashDotGridPainter extends CustomPainter {
  const _SplashDotGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 28.0;
    const radius = 1.0;

    for (var x = 0.0; x < size.width; x += spacing) {
      for (var y = 0.0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SplashDotGridPainter oldDelegate) =>
      oldDelegate.color != color;
}
