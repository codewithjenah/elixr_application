import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_app_logo.dart';
import '../../core/widgets/elix_scaffold_page.dart';

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
  late final AnimationController _logoController;
  late final AnimationController _ambientController;
  late final AnimationController _shimmerController;
  late final AnimationController _pulseController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineSlide;
  late final Animation<double> _pulseScale;

  bool _animationDone = false;
  bool _completionScheduled = false;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
      ),
    );
    _taglineSlide = Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _logoController,
            curve: const Interval(0.45, 0.85, curve: Curves.easeOutCubic),
          ),
        );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _logoController.forward().then((_) {
      if (mounted) setState(() => _animationDone = true);
      _tryFinish();
    });
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
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) widget.onFinished();
      });
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _ambientController.dispose();
    _shimmerController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final isDark = context.isDarkTheme;
    return ElixScaffoldPage(
      padding: EdgeInsets.zero,
      content: Stack(
        fit: StackFit.expand,
        children: [
          // Dot-grid background — matches AuthScaffold density for visual continuity.
          if (!highContrast)
            CustomPaint(
              painter: _SplashDotGridPainter(
                color: AppColors.primary.withValues(
                  alpha: isDark ? 0.035 : 0.05,
                ),
              ),
            ),
          // Floating ambient orbs — dual pink+purple identity.
          if (!highContrast)
            AnimatedBuilder(
              animation: _ambientController,
              builder: (context, _) {
                final t = _ambientController.value * 2 * math.pi;
                return Stack(
                  children: [
                    _orb(
                      dx: math.sin(t) * 40,
                      dy: math.cos(t) * 60,
                      alignment: const Alignment(-0.8, -0.7),
                      size: 320,
                      color: AppColors.primary.withValues(alpha: 0.18),
                    ),
                    _orb(
                      dx: math.cos(t) * 50,
                      dy: math.sin(t) * 40,
                      alignment: const Alignment(0.9, 0.8),
                      size: 380,
                      color: AppColors.primarySoft.withValues(alpha: 0.14),
                    ),
                    _orb(
                      dx: math.sin(t + 1.5) * 30,
                      dy: math.cos(t + 1.5) * 30,
                      alignment: const Alignment(0.8, -0.9),
                      size: 280,
                      color: AppColors.accent.withValues(alpha: 0.18),
                    ),
                  ],
                );
              },
            ),
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _logoController,
                _shimmerController,
                _pulseController,
              ]),
              builder: (context, _) {
                return Opacity(
                  opacity: _logoOpacity.value,
                  child: Transform.scale(
                    scale: _logoScale.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Transform.scale(
                          scale: _pulseScale.value,
                          child: _buildLogoMark(),
                        ),
                        const SizedBox(height: AppSpacing.lg + AppSpacing.sm),
                        _buildTitle(),
                        const SizedBox(height: AppSpacing.sm),
                        SlideTransition(
                          position: _taglineSlide,
                          child: FadeTransition(
                            opacity: _taglineOpacity,
                            child: Text(
                              'Bottle flair training, reimagined',
                              style: AppTheme.bodySecondary.copyWith(
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          _buildLoader(context),
        ],
      ),
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

  Widget _buildLogoMark() {
    final glow = 0.5 + math.sin(_shimmerController.value * 2 * math.pi) * 0.25;
    return Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(
              alpha: (glow * 0.7).clamp(0.0, 1.0),
            ),
            blurRadius: 40,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const ElixAppLogo(size: 128, borderRadius: 28),
    );
  }

  Widget _buildTitle() {
    final shimmer = _shimmerController.value;
    final pulse = (1 - (shimmer - 0.5).abs() * 2).clamp(0.0, 1.0);
    final color = Color.lerp(AppColors.primary, AppColors.primarySoft, pulse)!;
    return Text(
      AppConstants.appName,
      style: AppTheme.headingLarge.copyWith(
        fontSize: 46,
        fontWeight: FontWeight.w800,
        letterSpacing: 8,
        color: color,
        shadows: [
          Shadow(
            color: AppColors.primary.withValues(alpha: 0.4 + pulse * 0.3),
            blurRadius: 24,
          ),
        ],
      ),
    );
  }

  Widget _buildLoader(BuildContext context) {
    return Positioned(
      bottom: AppSpacing.xxl,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: Listenable.merge([_logoController, _shimmerController]),
        builder: (context, _) {
          return Opacity(
            opacity: _taglineOpacity.value,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 160,
                    height: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Stack(
                        children: [
                          Container(
                            color: AppColors.border.withValues(alpha: 0.5),
                          ),
                          Align(
                            alignment: Alignment(
                              -1 + _shimmerController.value * 2,
                              0,
                            ),
                            child: FractionallySizedBox(
                              widthFactor: 0.4,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary.withValues(alpha: 0),
                                      AppColors.primary,
                                      AppColors.primarySoft,
                                      AppColors.primary.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (!widget.authReady) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Preparing your session\u2026',
                      style: AppTheme.caption.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Dot-grid background painter matching [AuthScaffold]'s visual density.
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
