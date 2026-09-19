import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_spacing.dart';
import '../theme/app_theme.dart';
import '../theme/elix_design_tokens.dart';

/// A compact, non-blocking acknowledgement for a confirmed Daily Quest award.
///
/// The parent creates a new [eventId] only after the repository confirms an
/// award. This deliberately keeps watch-stream updates from replaying it.
class QuestRewardEffect extends StatefulWidget {
  const QuestRewardEffect({
    super.key,
    required this.eventId,
    required this.xp,
    required this.questTitle,
  });

  final String eventId;
  final int xp;
  final String questTitle;

  @override
  State<QuestRewardEffect> createState() => _QuestRewardEffectState();
}

class _QuestRewardEffectState extends State<QuestRewardEffect>
    with SingleTickerProviderStateMixin {
  static final _lifetime = ElixMotion.intro + ElixMotion.standard;

  late final AnimationController _controller;
  Timer? _reducedMotionDismissTimer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _lifetime)
      ..addStatusListener(_handleAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restart();
  }

  @override
  void didUpdateWidget(covariant QuestRewardEffect oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventId != widget.eventId) _restart();
  }

  void _restart() {
    _reducedMotionDismissTimer?.cancel();
    _visible = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 1;
      _reducedMotionDismissTimer = Timer(_lifetime, () {
        if (mounted) setState(() => _visible = false);
      });
      return;
    }
    _controller.duration = ElixMotion.duration(context, _lifetime);
    _controller.forward(from: 0);
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        !MediaQuery.disableAnimationsOf(context) &&
        mounted) {
      setState(() => _visible = false);
    }
  }

  @override
  void dispose() {
    _reducedMotionDismissTimer?.cancel();
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final highContrast = context.isHighContrast;
    final fade = reducedMotion
        ? const AlwaysStoppedAnimation<double>(1)
        : TweenSequence<double>([
            TweenSequenceItem(
              tween: Tween<double>(
                begin: 0,
                end: 1,
              ).chain(CurveTween(curve: Curves.easeOutCubic)),
              weight: 22,
            ),
            TweenSequenceItem(tween: ConstantTween<double>(1), weight: 46),
            TweenSequenceItem(
              tween: Tween<double>(
                begin: 1,
                end: 0,
              ).chain(CurveTween(curve: Curves.easeInCubic)),
              weight: 32,
            ),
          ]).animate(_controller);
    final scale = reducedMotion
        ? const AlwaysStoppedAnimation<double>(1)
        : Tween<double>(begin: 0.96, end: 1).animate(
            CurvedAnimation(
              parent: _controller,
              curve: const Interval(0, 0.32, curve: Curves.easeOutCubic),
            ),
          );
    final verticalOffset = reducedMotion
        ? const AlwaysStoppedAnimation<double>(0)
        : Tween<double>(begin: 6, end: -3).animate(
            CurvedAnimation(
              parent: _controller,
              curve: const Interval(0, 1, curve: Curves.easeOutCubic),
            ),
          );

    return IgnorePointer(
      child: Semantics(
        container: true,
        liveRegion: true,
        label: '+${widget.xp} XP claimed for ${widget.questTitle}',
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Opacity(
            opacity: fade.value,
            child: Transform.translate(
              offset: Offset(0, verticalOffset.value),
              child: Transform.scale(scale: scale.value, child: child),
            ),
          ),
          child: Container(
            key: const Key('quest_reward_effect'),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: highContrast
                  ? context.elixCardSurface
                  : context.elixColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: context.elixColors.success.withValues(
                  alpha: highContrast ? 1 : 0.42,
                ),
                width: highContrast ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.completed_solid,
                  size: 15,
                  color: context.elixColors.success,
                ),
                const SizedBox(width: 7),
                Text(
                  '+${widget.xp} XP',
                  style: TextStyle(
                    color: context.elixColors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Quest claimed',
                  style: TextStyle(
                    color: context.elixTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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
