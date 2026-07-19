import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';

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
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineSlide;

  bool _animationDone = false;

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
    _taglineSlide =
        Tween<Offset>(begin: const Offset(0, 0.4), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _logoController,
            curve: const Interval(0.45, 0.85, curve: Curves.easeOutCubic),
          ),
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
    if (_animationDone && widget.authReady) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FluentTheme(
      data: AppTheme.dark,
      child: ScaffoldPage(
        padding: EdgeInsets.zero,
        content: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0A0A0C),
                    AppColors.background,
                    Color(0xFF17101B),
                  ],
                ),
              ),
            ),
            // Floating ambient orbs.
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
                      size: 240,
                      color: const Color(0xFF7B5CFF).withValues(alpha: 0.12),
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
                ]),
                builder: (context, _) {
                  return Opacity(
                    opacity: _logoOpacity.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLogoMark(),
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
            _buildLoader(),
          ],
        ),
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
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primarySoft],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: glow.clamp(0.0, 1.0)),
            blurRadius: 40,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(
        FluentIcons.brightness,
        size: 48,
        color: Colors.white,
      ),
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

  Widget _buildLoader() {
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
              child: SizedBox(
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
            ),
          );
        },
      ),
    );
  }
}
