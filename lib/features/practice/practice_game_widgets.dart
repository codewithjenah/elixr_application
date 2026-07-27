import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';

/// Falling confetti rendered with a custom painter (no extra dependencies).
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key, this.particleCount = 120});

  final int particleCount;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiParticle {
  _ConfettiParticle(math.Random rng)
    : x = rng.nextDouble(),
      delay = rng.nextDouble() * 0.5,
      speed = 0.6 + rng.nextDouble() * 0.8,
      size = 6 + rng.nextDouble() * 7,
      sway = (rng.nextDouble() - 0.5) * 0.25,
      swayFreq = 2 + rng.nextDouble() * 3,
      spin = (rng.nextDouble() - 0.5) * 12,
      color = _palette[rng.nextInt(_palette.length)];

  static const _palette = [
    AppColors.primary,
    AppColors.primarySoft,
    AppColors.success,
    AppColors.warning,
    AppColors.accent,
    AppColors.accentSoft,
    Colors.white,
  ];

  final double x; // horizontal start (0..1)
  final double delay; // fraction of animation before it appears
  final double speed; // fall speed multiplier
  final double size;
  final double sway; // horizontal drift amplitude
  final double swayFreq;
  final double spin; // radians of rotation over the full fall
  final Color color;
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _particles = List.generate(
      widget.particleCount,
      (_) => _ConfettiParticle(rng),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ConfettiPainter(
            particles: _particles,
            progress: _controller.value,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.progress});

  final List<_ConfettiParticle> particles;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      // Each particle loops on its own offset timeline.
      final t = ((progress * p.speed + p.delay) % 1.0);
      final y = t * (size.height + 40) - 20;
      final x =
          (p.x + p.sway * math.sin(t * p.swayFreq * math.pi * 2)) * size.width;
      // Fade in at the top, fade out near the bottom.
      final alpha = t < 0.05 ? t / 0.05 : (t > 0.85 ? (1 - t) / 0.15 : 1.0);
      paint.color = p.color.withValues(alpha: alpha.clamp(0.0, 1.0) * 0.9);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * p.spin);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.6,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Game-style "Movement Complete" victory dialog with confetti.
/// Returns `true` for "Try Again", `false` for "Quit".
Future<bool?> showVictoryDialog(
  BuildContext context, {
  required String movement,
  required int? score,
  required int durationSeconds,
  required int bestCombo,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0xD90A0A0F),
    useRootNavigator: true,
    builder: (ctx) => _VictoryDialog(
      movement: movement,
      score: score,
      durationSeconds: durationSeconds,
      bestCombo: bestCombo,
    ),
  );
}

class _VictoryDialog extends StatefulWidget {
  const _VictoryDialog({
    required this.movement,
    required this.score,
    required this.durationSeconds,
    required this.bestCombo,
  });

  final String movement;
  final int? score;
  final int durationSeconds;
  final int bestCombo;

  @override
  State<_VictoryDialog> createState() => _VictoryDialogState();
}

class _VictoryDialogState extends State<_VictoryDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _cardScale;
  late final Animation<double> _cardFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _cardScale = Tween(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _cardFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.3, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ConfettiOverlay()),
        Center(
          child: FadeTransition(
            opacity: _cardFade,
            child: ScaleTransition(
              scale: _cardScale,
              child: Container(
                width: 440,
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.25),
                      blurRadius: 48,
                      spreadRadius: -8,
                    ),
                    const BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 32,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.success.withValues(alpha: 0.15),
                        border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.5),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.success.withValues(alpha: 0.4),
                            blurRadius: 24,
                          ),
                        ],
                      ),
                      child: const Icon(
                        FluentIcons.trophy2_solid,
                        color: AppColors.success,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'MOVEMENT COMPLETE!',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: AppColors.textPrimary,
                        shadows: [
                          Shadow(
                            color: AppColors.success.withValues(alpha: 0.5),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'You held "${widget.movement}" steady. Well done!',
                      style: AppTheme.bodySecondary,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: _VictoryStat(
                            icon: FluentIcons.favorite_star,
                            label: 'Score',
                            value: widget.score != null
                                ? '${widget.score}'
                                : '—',
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _VictoryStat(
                            icon: FluentIcons.clock,
                            label: 'Time',
                            value: _formatDuration(widget.durationSeconds),
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: _VictoryStat(
                            icon: FluentIcons.lightning_bolt,
                            label: 'Best Combo',
                            value: widget.bestCombo > 0
                                ? 'x${widget.bestCombo}'
                                : '—',
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: _VictoryQuitButton(
                            onPressed: () => Navigator.of(
                              context,
                              rootNavigator: true,
                            ).pop(false),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 2,
                          child: GameActionButton(
                            label: 'Try Again',
                            icon: FluentIcons.refresh,
                            onPressed: () => Navigator.of(
                              context,
                              rootNavigator: true,
                            ).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VictoryStat extends StatelessWidget {
  const _VictoryStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTheme.caption),
        ],
      ),
    );
  }
}

class _VictoryQuitButton extends StatefulWidget {
  const _VictoryQuitButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_VictoryQuitButton> createState() => _VictoryQuitButtonState();
}

class _VictoryQuitButtonState extends State<_VictoryQuitButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          decoration: BoxDecoration(
            color: _hovering
                ? AppColors.border.withValues(alpha: 0.6)
                : AppColors.background.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.border.withValues(alpha: _hovering ? 1 : 0.8),
            ),
          ),
          child: const Center(
            child: Text(
              'QUIT',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen "3.. 2.. 1.. GO!" overlay shown before a session starts.
class GameCountdownOverlay extends StatefulWidget {
  const GameCountdownOverlay({
    super.key,
    required this.onComplete,
  });

  final VoidCallback onComplete;

  @override
  State<GameCountdownOverlay> createState() => _GameCountdownOverlayState();
}

class _GameCountdownOverlayState extends State<GameCountdownOverlay>
    with SingleTickerProviderStateMixin {
  static const _steps = ['3', '2', '1', 'GO!'];
  int _index = 0;
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Match countdown.mp3 beat spacing (~1.0s after lead-in silence).
      duration: const Duration(milliseconds: 1000),
    );
    _scale = Tween(
      begin: 2.2,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.25, curve: Curves.easeOut),
    );
    _controller.addStatusListener((status) {
      if (status != AnimationStatus.completed || !mounted) return;
      if (_index >= _steps.length - 1) {
        widget.onComplete();
      } else {
        setState(() => _index++);
        _controller.forward(from: 0);
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isGo = _steps[_index] == 'GO!';
    final color = isGo ? AppColors.success : AppColors.primary;
    return ColoredBox(
      color: const Color(0xB30A0A0F),
      child: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Text(
              _steps[_index],
              style: TextStyle(
                fontSize: isGo ? 96 : 120,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
                color: color,
                shadows: [
                  Shadow(color: color.withValues(alpha: 0.8), blurRadius: 40),
                  const Shadow(color: Color(0x66000000), blurRadius: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated "x N COMBO" badge that bounces every time the combo grows.
class ComboBadge extends StatefulWidget {
  const ComboBadge({super.key, required this.combo});

  final int combo;

  @override
  State<ComboBadge> createState() => _ComboBadgeState();
}

class _ComboBadgeState extends State<ComboBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(ComboBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.combo > oldWidget.combo && widget.combo > 1) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _color {
    if (widget.combo >= 10) return AppColors.warning;
    if (widget.combo >= 5) return AppColors.primary;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.combo < 2) return const SizedBox.shrink();
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: const Color(0xE6101018),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _color.withValues(alpha: 0.7), width: 1.5),
          boxShadow: [
            BoxShadow(color: _color.withValues(alpha: 0.35), blurRadius: 16),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(FluentIcons.lightning_bolt, size: 18, color: _color),
            const SizedBox(width: 6),
            Text(
              'x${widget.combo} COMBO',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: _color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A "+N" popup that floats upward and fades out whenever [trigger] changes.
class ScorePopup extends StatefulWidget {
  const ScorePopup({super.key, required this.trigger, required this.delta});

  /// Increment this to replay the animation.
  final int trigger;
  final int delta;

  @override
  State<ScorePopup> createState() => _ScorePopupState();
}

class _ScorePopupState extends State<ScorePopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didUpdateWidget(ScorePopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.delta > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isDismissed || _controller.isCompleted) {
          return const SizedBox.shrink();
        }
        final t = _controller.value;
        return IgnorePointer(
          child: Opacity(
            opacity: (1 - t).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -60 * Curves.easeOut.transform(t)),
              child: Text(
                '+${widget.delta}',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: AppColors.success,
                  shadows: [
                    Shadow(
                      color: AppColors.success.withValues(alpha: 0.7),
                      blurRadius: 24,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Letter rank (S/A/B/C/D) derived from the current score.
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.score});

  final int? score;

  static (String, Color) rankFor(int? score) {
    if (score == null) return ('—', AppColors.textSecondary);
    if (score >= 90) return ('S', AppColors.warning);
    if (score >= 75) return ('A', AppColors.success);
    if (score >= 60) return ('B', AppColors.primary);
    if (score >= 40) return ('C', AppColors.primarySoft);
    return ('D', AppColors.textSecondary);
  }

  @override
  Widget build(BuildContext context) {
    final (rank, color) = rankFor(score);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 14),
        ],
      ),
      child: Center(
        child: Text(
          rank,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// XP-style animated progress bar toward a perfect score of 100.
class XpBar extends StatelessWidget {
  const XpBar({super.key, required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) {
    final value = ((score ?? 0) / 100).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PROGRESS',
              style: AppTheme.caption.copyWith(
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${score ?? 0} / 100',
              style: AppTheme.caption.copyWith(
                color: AppColors.primarySoft,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 10,
            color: AppColors.background,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: value),
              builder: (context, v, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: v == 0 ? 0.001 : v,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primarySoft],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Wraps a child with a soft breathing glow while [active] is true.
class PulsingGlow extends StatefulWidget {
  const PulsingGlow({
    super.key,
    required this.active,
    required this.child,
    this.color = AppColors.primary,
    this.borderRadius = 16,
  });

  final bool active;
  final Widget child;
  final Color color;
  final double borderRadius;

  @override
  State<PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PulsingGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = 0.12 + 0.18 * _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: glow),
                blurRadius: 28 + 10 * _controller.value,
                spreadRadius: -2,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Gradient game-style call-to-action button with a glow.
class GameActionButton extends StatefulWidget {
  const GameActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.isLoading = false,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool danger;

  @override
  State<GameActionButton> createState() => _GameActionButtonState();
}

class _GameActionButtonState extends State<GameActionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final colors = widget.danger
        ? const [Color(0xFFFF6B6B), Color(0xFFFF8E53)]
        : const [AppColors.primary, AppColors.accent];
    final glowColor = widget.danger ? AppColors.error : AppColors.primary;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          transform: Matrix4.identity()
            ..scaleByDouble(
              _hovering && enabled ? 1.02 : 1.0,
              _hovering && enabled ? 1.02 : 1.0,
              1,
              1,
            ),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: enabled
                  ? colors
                  : colors
                        .map((c) => c.withValues(alpha: 0.4))
                        .toList(growable: false),
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: glowColor.withValues(
                        alpha: _hovering ? 0.55 : 0.35,
                      ),
                      blurRadius: _hovering ? 26 : 18,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: ProgressRing(
                      strokeWidth: 3,
                      activeColor: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 18, color: Colors.white),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        widget.label.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: Colors.white,
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
