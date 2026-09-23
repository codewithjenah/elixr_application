import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/rubric_assessment.dart';
import 'widgets/training_performance.dart';

/// Full-screen "3.. 2.. 1.. GO!" overlay shown before a session starts.
class GameCountdownOverlay extends StatefulWidget {
  const GameCountdownOverlay({super.key, required this.onComplete});

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
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.15,
          colors: [
            color.withValues(alpha: isGo ? 0.10 : 0.07),
            const Color(0x660A0A0F),
            const Color(0x9907060C),
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
      ),
      child: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Text(
              _steps[_index],
              style: TextStyle(
                fontSize: isGo ? 88 : 108,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: color,
                shadows: [
                  Shadow(color: color.withValues(alpha: 0.7), blurRadius: 28),
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
            BoxShadow(color: _color.withValues(alpha: 0.28), blurRadius: 18),
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
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: AppColors.success,
                  shadows: [
                    Shadow(
                      color: AppColors.success.withValues(alpha: 0.55),
                      blurRadius: 20,
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

/// Transient PERFECT / GREAT / GOOD callout driven by [PerformanceCalloutState].
class PerformanceCallout extends StatefulWidget {
  const PerformanceCallout({
    super.key,
    required this.trigger,
    required this.level,
    this.total,
  });

  final int trigger;
  final PerformanceLevel? level;
  final int? total;

  @override
  State<PerformanceCallout> createState() => _PerformanceCalloutState();
}

class _PerformanceCalloutState extends State<PerformanceCallout>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
    _scale = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 0.82, end: 1.08), weight: 28),
        TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 22),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.96), weight: 20),
      ],
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 18),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 52),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);
    if (widget.trigger > 0 && widget.level != null) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(PerformanceCallout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.level != null) {
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
    final copy = performanceCalloutCopy(widget.level);
    if (copy == null) return const SizedBox.shrink();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = context.isHighContrast;
    final color = performanceLevelColor(widget.level);
    final detail = widget.total == null
        ? copy.detail
        : '${copy.detail} · ${widget.total} / ${RubricScale.maxTotal}';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isDismissed || _controller.isCompleted) {
          return const SizedBox.shrink();
        }
        final opacity = reduceMotion ? 1.0 : _fade.value;
        final scale = reduceMotion || copy.restrained ? 1.0 : _scale.value;
        return IgnorePointer(
          child: Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: Column(
                key: const ValueKey('training-performance-callout'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    copy.headline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: copy.restrained ? 28 : 46,
                      fontWeight: FontWeight.w900,
                      letterSpacing: copy.restrained ? 2 : 3.4,
                      color: color,
                      shadows: highContrast || copy.restrained
                          ? const []
                          : [
                              Shadow(
                                color: color.withValues(alpha: 0.55),
                                blurRadius: 28,
                              ),
                            ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: AppTheme.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Compact performance-level badge (Beg/Dev/Cmp/Pro/Mst).
class RankBadge extends StatelessWidget {
  const RankBadge({super.key, required this.level});

  final PerformanceLevel? level;

  static (String, Color) rankFor(
    PerformanceLevel? level, {
    required Color milestone,
  }) => switch (level) {
    null => ('—', AppColors.textSecondary),
    PerformanceLevel.mastered => (level.shortLabel, milestone),
    PerformanceLevel.proficient => (level.shortLabel, AppColors.success),
    PerformanceLevel.competent => (level.shortLabel, AppColors.primary),
    PerformanceLevel.developing => (level.shortLabel, AppColors.primarySoft),
    PerformanceLevel.beginning => (level.shortLabel, AppColors.textSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final (rank, color) = rankFor(
      level,
      milestone: context.elixColors.milestone,
    );
    final highContrast = context.isHighContrast;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
        border: Border.all(
          color: color.withValues(alpha: highContrast ? 1 : 0.6),
          width: 2,
        ),
        boxShadow: highContrast
            ? const <BoxShadow>[]
            : [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 14)],
      ),
      child: Center(
        child: Text(
          rank,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Visual hierarchy for game-style call-to-action buttons.
enum GameActionButtonVariant { primary, secondary }

/// Gradient game-style call-to-action button with restrained elevation.
class GameActionButton extends StatefulWidget {
  const GameActionButton({
    super.key,
    required this.label,
    required this.icon,
    this.onPressed,
    this.isLoading = false,
    this.danger = false,
    this.variant = GameActionButtonVariant.primary,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool danger;
  final GameActionButtonVariant variant;

  @override
  State<GameActionButton> createState() => _GameActionButtonState();
}

class _GameActionButtonState extends State<GameActionButton> {
  static const _kIconSize = 18.0;
  static const _kIconLaneWidth = AppSpacing.md + _kIconSize + AppSpacing.sm;
  static const _kBorderRadius = 16.0;

  bool _hovering = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    final isSecondary =
        !widget.danger && widget.variant == GameActionButtonVariant.secondary;

    final labelColor = widget.danger
        ? (enabled ? AppColors.error : AppColors.error.withValues(alpha: 0.45))
        : Colors.white.withValues(alpha: enabled ? 1 : 0.55);

    final iconColor = widget.danger
        ? labelColor
        : isSecondary
        ? AppColors.primarySoft.withValues(alpha: enabled ? 1 : 0.45)
        : Colors.white.withValues(alpha: enabled ? 1 : 0.55);

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: enabled,
        onShowFocusHighlight: (focused) => setState(() => _focused = focused),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (!enabled) return null;
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() {
            _hovering = false;
            _pressed = false;
          }),
          child: GestureDetector(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: enabled ? widget.onPressed : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: 54,
              transform: Matrix4.translationValues(
                0,
                _hovering && enabled && !_pressed
                    ? -2
                    : (_pressed && enabled ? 1 : 0),
                0,
              ),
              decoration: _buildDecoration(
                enabled: enabled,
                focused: _focused,
                isDark: isDark,
              ),
              child: widget.isLoading
                  ? Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: ProgressRing(
                          strokeWidth: 3,
                          activeColor: widget.danger
                              ? AppColors.error
                              : Colors.white,
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        SizedBox(
                          width: _kIconLaneWidth,
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: 30,
                              height: 30,
                              transform: Matrix4.translationValues(
                                _hovering &&
                                        enabled &&
                                        !_pressed &&
                                        !MediaQuery.disableAnimationsOf(context)
                                    ? 2
                                    : 0,
                                0,
                                0,
                              ),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.danger
                                    ? AppColors.error.withValues(
                                        alpha: enabled ? 0.12 : 0.06,
                                      )
                                    : isSecondary
                                    ? AppColors.primary.withValues(
                                        alpha: enabled ? 0.14 : 0.07,
                                      )
                                    : Colors.white.withValues(
                                        alpha: enabled ? 0.16 : 0.08,
                                      ),
                              ),
                              child: Icon(
                                widget.icon,
                                size: _kIconSize,
                                color: iconColor,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: labelColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: _kIconLaneWidth),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration _buildDecoration({
    required bool enabled,
    required bool focused,
    required bool isDark,
  }) {
    if (widget.danger) {
      return BoxDecoration(
        color: enabled
            ? AppColors.error.withValues(alpha: isDark ? 0.14 : 0.1)
            : AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(_kBorderRadius),
        border: Border.all(
          color: focused
              ? AppColors.error
              : AppColors.error.withValues(alpha: enabled ? 0.45 : 0.22),
          width: focused ? 1.5 : 1,
        ),
      );
    }

    if (widget.variant == GameActionButtonVariant.secondary) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: enabled
              ? const [AppColors.interactiveSurface, AppColors.panelSurface]
              : [
                  AppColors.interactiveSurface.withValues(alpha: 0.45),
                  AppColors.panelSurface.withValues(alpha: 0.45),
                ],
        ),
        borderRadius: BorderRadius.circular(_kBorderRadius),
        border: Border.all(
          color: focused
              ? AppColors.primarySoft
              : AppColors.primary.withValues(alpha: enabled ? 0.38 : 0.16),
          width: focused ? 1.5 : 1,
        ),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      );
    }

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: enabled
            ? const [AppColors.primarySoft, AppColors.primary, AppColors.accent]
            : [
                AppColors.primary.withValues(alpha: 0.35),
                AppColors.accent.withValues(alpha: 0.35),
              ],
      ),
      borderRadius: BorderRadius.circular(_kBorderRadius),
      border: Border.all(
        color: focused
            ? Colors.white.withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: enabled ? 0.22 : 0.1),
        width: focused ? 1.5 : 1,
      ),
      boxShadow: enabled
          ? [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: _hovering && !_pressed ? 0.28 : 0.18,
                ),
                blurRadius: _hovering && !_pressed ? 24 : 18,
                offset: Offset(0, _hovering && !_pressed ? 10 : 7),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 2,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );
  }
}
