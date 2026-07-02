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
  late final AnimationController _pulseController;
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
      duration: const Duration(milliseconds: 1400),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
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
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
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
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) widget.onFinished();
      });
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _pulseController.dispose();
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
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0A0A0C),
                    AppColors.background,
                    Color(0xFF151018),
                  ],
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final pulse = 0.85 + _pulseController.value * 0.15;
                return Center(
                  child: Container(
                    width: 200 * pulse,
                    height: 200 * pulse,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withValues(alpha: 0.06),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary
                              .withValues(alpha: 0.15 * _pulseController.value),
                          blurRadius: 80,
                          spreadRadius: 30,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            Center(
              child: AnimatedBuilder(
                animation: _logoController,
                builder: (context, _) {
                  return Opacity(
                    opacity: _logoOpacity.value,
                    child: Transform.scale(
                      scale: _logoScale.value,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.primary,
                                  AppColors.primarySoft,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              FluentIcons.brightness,
                              size: 44,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                const LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primarySoft,
                                Colors.white,
                              ],
                            ).createShader(bounds),
                            child: Text(
                              AppConstants.appName,
                              style: AppTheme.headingLarge.copyWith(
                                fontSize: 42,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 6,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          SlideTransition(
                            position: _taglineSlide,
                            child: FadeTransition(
                              opacity: _taglineOpacity,
                              child: Text(
                                'Bottle flair training, reimagined',
                                style: AppTheme.bodySecondary.copyWith(
                                  letterSpacing: 0.5,
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
            Positioned(
              bottom: AppSpacing.xxl,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _logoController,
                builder: (context, _) {
                  return Opacity(
                    opacity: _taglineOpacity.value,
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Transform.rotate(
                          angle: _logoController.value * 2 * math.pi,
                          child: const ProgressRing(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
