import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/constants/movement_visuals.dart';
import '../../../core/theme/app_theme.dart';
import '../../movements/movements_presentation.dart';
import '../just_dance/movement_rotation_controller.dart';

/// Compact "Just Dance"-style rotation prompt shown in a corner of the
/// camera view. Purely visual: no scoring, no pass/fail state, no gating of
/// the underlying freeform session.
class MovementRotationOverlay extends StatelessWidget {
  const MovementRotationOverlay({super.key, required this.controller});

  final MovementRotationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final current = controller.currentMovement;
        if (current == null) return const SizedBox.shrink();
        final next = controller.nextMovement;
        final accent = difficultyAccentColor(current.difficulty);

        return Positioned(
          right: AppSpacing.md,
          bottom: 48,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: const Color(0xCC101018),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.4)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        MovementVisuals.emojiFor(current.name),
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          current.name,
                          style: AppTheme.body.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: controller.progress,
                            child: Container(color: accent),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (next != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Up next: ${next.name}',
                      style: AppTheme.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _RotationIconButton(
                        icon: FluentIcons.previous,
                        tooltip: 'Previous movement',
                        onPressed: controller.skipPrevious,
                      ),
                      _RotationIconButton(
                        icon: controller.isRunning
                            ? FluentIcons.pause
                            : FluentIcons.play,
                        tooltip: controller.isRunning
                            ? 'Pause rotation'
                            : 'Resume rotation',
                        onPressed: controller.isRunning
                            ? controller.pause
                            : controller.resume,
                      ),
                      _RotationIconButton(
                        icon: FluentIcons.next,
                        tooltip: 'Next movement',
                        onPressed: controller.skipNext,
                      ),
                    ],
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

class _RotationIconButton extends StatelessWidget {
  const _RotationIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 14, color: AppColors.textPrimary),
        onPressed: onPressed,
      ),
    );
  }
}
