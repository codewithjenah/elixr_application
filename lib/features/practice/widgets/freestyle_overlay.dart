import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/recognition_event.dart';
import '../../../data/models/training_prop.dart';
import '../freestyle/freestyle_models.dart';
import '../freestyle/freestyle_session_controller.dart';

class FreestyleOverlay extends StatelessWidget {
  const FreestyleOverlay({
    super.key,
    required this.controller,
    required this.onPause,
    required this.onResume,
    required this.onQuit,
    this.connectionLost = false,
  });

  final FreestyleSessionController controller;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onQuit;
  final bool connectionLost;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (controller.isComplete) {
          return const SizedBox.shrink();
        }
        if (controller.phase == FreestyleSessionPhase.idle) {
          return const SizedBox.shrink();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < 620 || constraints.maxHeight < 430;
            return Stack(
              children: [
                if (controller.isPaused || connectionLost)
                  _PauseVeil(
                    connectionLost: connectionLost,
                    paused: controller.isPaused,
                  ),
                Positioned(
                  left: AppSpacing.md,
                  top: AppSpacing.md,
                  child: _PropChip(prop: controller.detectedProp),
                ),
                Positioned(
                  right: AppSpacing.md,
                  top: AppSpacing.md,
                  child: _ComboBadge(combo: controller.stats.combo),
                ),
                Align(
                  alignment: compact ? Alignment.center : Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      compact ? 56 : 72,
                      compact ? AppSpacing.lg : constraints.maxWidth * 0.34,
                      88,
                    ),
                    child: _Callout(controller: controller),
                  ),
                ),
                Positioned(
                  left: AppSpacing.md,
                  bottom: AppSpacing.md,
                  right: compact ? AppSpacing.md : constraints.maxWidth * 0.42,
                  child: _RecentFeed(entries: controller.stats.feed),
                ),
                Positioned(
                  right: AppSpacing.md,
                  bottom: AppSpacing.md,
                  child: _Controls(
                    paused: controller.isPaused,
                    canPause: controller.phase == FreestyleSessionPhase.active,
                    onPause: onPause,
                    onResume: onResume,
                    onQuit: onQuit,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PauseVeil extends StatelessWidget {
  const _PauseVeil({required this.connectionLost, required this.paused});

  final bool connectionLost;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final label = connectionLost ? 'Connection lost' : 'Paused';
    return Semantics(
      liveRegion: true,
      label: label,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Text(
            label.toUpperCase(),
            style: AppTheme.headingLarge.copyWith(
              color: Colors.white,
              letterSpacing: 3,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _PropChip extends StatelessWidget {
  const _PropChip({required this.prop});

  final TrainingProp? prop;

  @override
  Widget build(BuildContext context) {
    final label = switch (prop) {
      TrainingProp.bottle => 'Bottle detected',
      TrainingProp.shaker => 'Shaker detected',
      TrainingProp.bottleAndShaker => 'Bottle + Shaker detected',
      null => 'Searching for a prop',
    };
    final color = prop == null ? AppColors.warning : AppColors.success;
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Text(
          label,
          style: AppTheme.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ComboBadge extends StatelessWidget {
  const _ComboBadge({required this.combo});

  final int combo;

  @override
  Widget build(BuildContext context) {
    if (combo <= 0) return const SizedBox.shrink();
    return Semantics(
      label: '$combo times combo',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${combo}x COMBO',
          style: AppTheme.body.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({required this.controller});

  final FreestyleSessionController controller;

  @override
  Widget build(BuildContext context) {
    final label = controller.liveLabel;
    final quality = controller.liveQuality;
    final title = label == null ? 'WATCHING' : label.toUpperCase();
    return Semantics(
      liveRegion: true,
      label: label == null
          ? 'Watching your technique'
          : '$label${quality == null ? '' : ', ${quality.label}'}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTheme.headingLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 0.95,
              fontSize: label == null ? 28 : 42,
              shadows: const [
                Shadow(
                  color: Color(0x8A000000),
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
          if (quality != null) ...[
            const SizedBox(height: 8),
            Text(
              quality.label.toUpperCase(),
              style: AppTheme.headingMedium.copyWith(
                color: switch (quality) {
                  RecognitionQuality.perfect => AppColors.success,
                  RecognitionQuality.great => AppColors.primarySoft,
                  RecognitionQuality.nice => AppColors.warning,
                },
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentFeed extends StatelessWidget {
  const _RecentFeed({required this.entries});

  final List<FreestyleFeedEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Recent',
            style: AppTheme.caption.copyWith(
              color: const Color(0xB3FFFFFF),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in entries.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                entry.quality == null
                    ? entry.displayLabel
                    : '${entry.displayLabel} · ${entry.quality!.label}',
                style: AppTheme.caption.copyWith(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.paused,
    required this.canPause,
    required this.onPause,
    required this.onResume,
    required this.onQuit,
  });

  final bool paused;
  final bool canPause;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Button(
          onPressed: paused ? onResume : (canPause ? onPause : null),
          child: Text(paused ? 'Resume' : 'Pause'),
        ),
        const SizedBox(width: AppSpacing.sm),
        Button(onPressed: onQuit, child: const Text('Quit')),
      ],
    );
  }
}
