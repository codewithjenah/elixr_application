import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/recognition_event.dart';
import '../freestyle/freestyle_models.dart';
import '../freestyle/freestyle_session_controller.dart';

class FreestyleOverlay extends StatelessWidget {
  const FreestyleOverlay({
    super.key,
    required this.controller,
    required this.onPause,
    required this.onResume,
    required this.onQuit,
    this.elapsedSeconds = 0,
    this.connectionLost = false,
  });

  final FreestyleSessionController controller;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onQuit;
  final int elapsedSeconds;
  final bool connectionLost;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (controller.phase == FreestyleSessionPhase.idle ||
          controller.isComplete) {
        return const SizedBox.shrink();
      }
      final target = controller.currentTarget;
      final stats = controller.stats;
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 600 || constraints.maxHeight < 440;
          return Stack(
            children: [
              if (controller.isPaused || connectionLost)
                ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: Text(
                      connectionLost ? 'CONNECTION LOST' : 'PAUSED',
                      style: AppTheme.headingLarge.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: AppSpacing.md,
                top: AppSpacing.md,
                width: compact ? constraints.maxWidth - 32 : 330,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: const Color(0xE5151D2C),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primarySoft),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ENDLESS MODE',
                        style: AppTheme.caption.copyWith(
                          color: AppColors.primarySoft,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'RUN ${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}',
                        style: AppTheme.caption.copyWith(
                          color: const Color(0xB3FFFFFF),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'CURRENT',
                        style: AppTheme.caption.copyWith(
                          color: const Color(0xB3FFFFFF),
                        ),
                      ),
                      Text(
                        target?.movement ?? 'Preparing sequence',
                        style: AppTheme.headingLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 27 : 35,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${target?.prop.displayLabel ?? ''}  ·  '
                        '${controller.targetReady ? '${controller.remainingSeconds}s left' : 'Getting ready'}',
                        style: AppTheme.body.copyWith(color: Colors.white),
                      ),
                      if (compact)
                        Text(
                          'SCORE ${stats.runScore}  ·  COMBO ${stats.combo}  ·  SUCCESS ${stats.movementsRecognized + stats.flips}  ·  MISSED ${stats.missed}',
                          style: AppTheme.caption.copyWith(color: Colors.white),
                        ),
                      if (controller.successQuality != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          controller.successQuality!.label.toUpperCase(),
                          style: AppTheme.headingMedium.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'NEXT',
                        style: AppTheme.caption.copyWith(
                          color: const Color(0xB3FFFFFF),
                        ),
                      ),
                      for (final upcoming in controller.upcomingTargets)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            upcoming.movement,
                            style: AppTheme.body.copyWith(color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!compact)
                Positioned(
                  right: AppSpacing.md,
                  top: AppSpacing.md,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xE5151D2C),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'SCORE ${stats.runScore}  ·  COMBO ${stats.combo}',
                          style: AppTheme.body.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'SUCCESS ${stats.movementsRecognized + stats.flips}  ·  MISSED ${stats.missed}',
                          style: AppTheme.caption.copyWith(
                            color: const Color(0xB3FFFFFF),
                          ),
                        ),
                        Text(
                          controller.detectedProp != target?.prop
                              ? 'Searching for prop'
                              : 'Prop detected',
                          style: AppTheme.caption.copyWith(
                            color: controller.detectedProp != target?.prop
                                ? AppColors.warning
                                : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Button(
                      onPressed: controller.isPaused
                          ? onResume
                          : controller.phase == FreestyleSessionPhase.active
                          ? onPause
                          : null,
                      child: Text(controller.isPaused ? 'Resume' : 'Pause'),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Button(onPressed: onQuit, child: const Text('End Session')),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
