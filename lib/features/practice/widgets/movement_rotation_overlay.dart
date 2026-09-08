import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/movement_image.dart';
import '../just_dance/playground_session_controller.dart';

/// Follow-along HUD for Playground. It deliberately derives every value from
/// [PlaygroundSessionController], including timing, position, and outcomes.
class MovementRotationOverlay extends StatelessWidget {
  const MovementRotationOverlay({
    super.key,
    required this.controller,
    required this.onRestart,
    required this.onEditSetlist,
  });

  final PlaygroundSessionController controller;
  final VoidCallback onRestart;
  final VoidCallback onEditSetlist;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.isComplete) {
        return _Complete(
          controller: controller,
          onRestart: onRestart,
          onEditSetlist: onEditSetlist,
        );
      }
      if (controller.phase == PlaygroundSessionPhase.idle ||
          controller.currentMovement == null) {
        return const SizedBox.shrink();
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 620 || constraints.maxHeight < 430;
          return Stack(
            children: [
              _PhaseBurst(phase: controller.phase, paused: controller.isPaused),
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                top: AppSpacing.md,
                child: _Progress(controller: controller),
              ),
              Align(
                alignment: compact ? Alignment.center : Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: AppSpacing.md,
                    right: compact ? AppSpacing.md : constraints.maxWidth * .38,
                    top: 40,
                  ),
                  child: _Prompt(controller: controller, compact: compact),
                ),
              ),
              Positioned(
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: _Controls(controller: controller),
              ),
            ],
          );
        },
      );
    },
  );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.controller});
  final PlaygroundSessionController controller;
  @override
  Widget build(BuildContext context) {
    final position =
        '${controller.currentIndex + 1} of ${controller.movementCount}';
    return Semantics(
      label: 'Routine progress $position',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: _surface(AppColors.primarySoft),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  FluentIcons.music_in_collection,
                  size: 14,
                  color: AppColors.primarySoft,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'PLAYGROUND · $position',
                    style: AppTheme.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .5,
                    ),
                  ),
                ),
                if (controller.isPaused)
                  const _Pill(label: 'PAUSED', color: AppColors.warning),
              ],
            ),
            const SizedBox(height: 7),
            ProgressBar(
              value:
                  (controller.currentIndex + controller.progress) /
                  controller.movementCount,
            ),
          ],
        ),
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.controller, required this.compact});
  final PlaygroundSessionController controller;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final movement = controller.currentMovement!;
    final phase = controller.phase;
    final presentation = switch (phase) {
      PlaygroundSessionPhase.preparingMovement => (
        'Preparing movement',
        'ELIXR is getting the assessment ready.',
        AppColors.warning,
        FluentIcons.processing,
      ),
      PlaygroundSessionPhase.getReady => (
        'Get Ready',
        'Starting in ${_seconds(controller.remainingDuration)}',
        AppColors.primarySoft,
        FluentIcons.clock,
      ),
      PlaygroundSessionPhase.assessing => (
        'Perform',
        '${_seconds(controller.remainingDuration)} remaining',
        AppColors.success,
        FluentIcons.play_solid,
      ),
      PlaygroundSessionPhase.success => (
        'Success',
        'Movement recognized. Loading the next one…',
        AppColors.success,
        FluentIcons.completed_solid,
      ),
      PlaygroundSessionPhase.missed => (
        'Keep going',
        'This movement was missed. Preparing the next one…',
        AppColors.warning,
        FluentIcons.forward,
      ),
      PlaygroundSessionPhase.transitioning => (
        'Next movement',
        'Preparing the next movement…',
        AppColors.accentSoft,
        FluentIcons.forward,
      ),
      _ => (
        'Playground',
        '',
        AppColors.primarySoft,
        FluentIcons.music_in_collection,
      ),
    };
    final (title, subtitle, accent, icon) = presentation;
    final card = Container(
      key: ValueKey('playground-phase-${phase.name}'),
      constraints: BoxConstraints(maxWidth: compact ? 310 : 350),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: _surface(accent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTheme.body.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              MovementImage(
                movementName: movement.name,
                size: compact ? 64 : 88,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movement.name,
                      style: AppTheme.sectionTitle(
                        context,
                        color: AppColors.textPrimary,
                      ).copyWith(fontSize: compact ? 20 : 25),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: AppTheme.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (phase == PlaygroundSessionPhase.getReady ||
              phase == PlaygroundSessionPhase.assessing) ...[
            const SizedBox(height: 12),
            ProgressBar(value: controller.progress),
          ],
          if (controller.nextMovement case final next?) ...[
            const SizedBox(height: 12),
            _Next(name: next.name),
          ],
        ],
      ),
    );
    return AnimatedSwitcher(
      duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      child: card,
    );
  }
}

class _Next extends StatelessWidget {
  const _Next({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        MovementImage(movementName: name, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Up next · $name',
            style: AppTheme.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});
  final PlaygroundSessionController controller;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(5),
    decoration: _surface(AppColors.border),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: controller.isPaused ? 'Resume routine' : 'Pause routine',
          child: Button(
            onPressed: controller.isPaused
                ? controller.resume
                : controller.pause,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  controller.isPaused ? FluentIcons.play : FluentIcons.pause,
                  size: 14,
                ),
                const SizedBox(width: 6),
                Text(controller.isPaused ? 'Resume' : 'Pause'),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: 'Skip movement',
          child: Button(
            onPressed: controller.isPaused || !controller.isAssessing
                ? null
                : controller.requestNext,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.forward, size: 14),
                SizedBox(width: 6),
                Text('Skip'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _Complete extends StatelessWidget {
  const _Complete({
    required this.controller,
    required this.onRestart,
    required this.onEditSetlist,
  });
  final PlaygroundSessionController controller;
  final VoidCallback onRestart;
  final VoidCallback onEditSetlist;
  @override
  Widget build(BuildContext context) {
    final total = controller.outcomes.length;
    final successes = controller.outcomes
        .where((item) => item.status == PlaygroundMovementStatus.success)
        .length;
    final misses = total - successes;
    final percentage = total == 0 ? 0 : (successes * 100 / total).round();
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xE80D0D0F),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Container(
              key: const ValueKey('playground-routine-complete'),
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: _surface(AppColors.success),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    FluentIcons.completed_solid,
                    color: AppColors.success,
                    size: 34,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Routine complete',
                    style: AppTheme.sectionTitle(
                      context,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$percentage% completed successfully',
                    style: AppTheme.bodySecondary.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _Stat('TOTAL', '$total'),
                      _Stat('SUCCESS', '$successes', AppColors.success),
                      _Stat('MISSED', '$misses', AppColors.warning),
                    ],
                  ),
                  if (controller.outcomes.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final item in controller.outcomes)
                          _Pill(
                            label:
                                '${item.movement.name} · ${item.status == PlaygroundMovementStatus.success ? 'Success' : 'Missed'}',
                            color:
                                item.status == PlaygroundMovementStatus.success
                                ? AppColors.success
                                : AppColors.warning,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    alignment: WrapAlignment.center,
                    children: [
                      Tooltip(
                        message: 'Restart this routine',
                        child: FilledButton(
                          onPressed: onRestart,
                          child: const Text('Restart routine'),
                        ),
                      ),
                      Tooltip(
                        message: 'Edit the setlist',
                        child: Button(
                          onPressed: onEditSetlist,
                          child: const Text('Edit setlist'),
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
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, [this.color]);
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          value,
          style: AppTheme.sectionTitle(
            context,
            color: color ?? AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: AppTheme.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .15),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: .4)),
    ),
    child: Text(
      label,
      style: AppTheme.caption.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

BoxDecoration _surface(Color accent) => BoxDecoration(
  color: const Color(0xE817171D),
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: accent.withValues(alpha: .5)),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: .3),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ],
);
String _seconds(Duration value) => '${(value.inMilliseconds / 1000).ceil()}s';

class _PhaseBurst extends StatefulWidget {
  const _PhaseBurst({required this.phase, required this.paused});

  final PlaygroundSessionPhase phase;
  final bool paused;

  @override
  State<_PhaseBurst> createState() => _PhaseBurstState();
}

class _PhaseBurstState extends State<_PhaseBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  String? _headline;
  Color _color = AppColors.primary;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    );
    _scale = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 0.86, end: 1.06), weight: 35),
        TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0), weight: 25),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 40),
      ],
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 18),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 32),
    ]).animate(_controller);
    _syncFromPhase(null);
  }

  @override
  void didUpdateWidget(_PhaseBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      _syncFromPhase(oldWidget.phase);
    }
  }

  void _syncFromPhase(PlaygroundSessionPhase? previous) {
    if (widget.paused) return;
    final burst = _burstFor(widget.phase);
    if (burst == null) return;
    _headline = burst.headline;
    _color = burst.color;
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_headline == null ||
              _controller.isDismissed ||
              _controller.isCompleted) {
            return const SizedBox.shrink();
          }
          return Center(
            child: Opacity(
              opacity: reduceMotion ? 1 : _fade.value,
              child: Transform.scale(
                scale: reduceMotion ? 1 : _scale.value,
                child: Text(
                  _headline!,
                  key: const ValueKey('playground-phase-callout'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 3,
                    color: _color,
                    shadows: [
                      Shadow(
                        color: _color.withValues(alpha: 0.5),
                        blurRadius: 24,
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

({String headline, Color color})? _burstFor(PlaygroundSessionPhase phase) {
  return switch (phase) {
    PlaygroundSessionPhase.getReady => (
      headline: 'GET READY',
      color: AppColors.primary,
    ),
    PlaygroundSessionPhase.success => (
      headline: 'CLEARED!',
      color: AppColors.success,
    ),
    PlaygroundSessionPhase.missed => (
      headline: 'MISSED',
      color: AppColors.warning,
    ),
    PlaygroundSessionPhase.transitioning => (
      headline: 'NEXT UP',
      color: AppColors.accent,
    ),
    PlaygroundSessionPhase.idle ||
    PlaygroundSessionPhase.preparingMovement ||
    PlaygroundSessionPhase.assessing ||
    PlaygroundSessionPhase.completed => null,
  };
}
