import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/websocket_service.dart';
import 'training_connection_badge.dart';

Color trainingDifficultyColor(String difficulty) {
  switch (difficulty.toLowerCase()) {
    case 'easy':
      return AppColors.success;
    case 'medium':
      return AppColors.warning;
    case 'hard':
      return AppColors.error;
    default:
      return AppColors.primarySoft;
  }
}

class TrainingSessionHeader extends StatelessWidget {
  const TrainingSessionHeader({
    super.key,
    required this.onBack,
    required this.title,
    required this.statusPill,
    required this.instruction,
    required this.connectionState,
    this.connecting = false,
    this.wideLayout = true,
    this.statusPillColor,
  });

  final VoidCallback onBack;
  final String title;
  final String statusPill;
  final String instruction;
  final WebSocketConnectionState connectionState;
  final bool connecting;
  final bool wideLayout;
  final Color? statusPillColor;

  @override
  Widget build(BuildContext context) {
    final pillColor = statusPillColor ?? AppColors.primarySoft;
    final badge = TrainingConnectionBadge(
      state: connectionState,
      connecting: connecting,
    );

    final titleRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(FluentIcons.chrome_back, color: AppColors.primary),
          onPressed: onBack,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  style: AppTheme.headingLarge.copyWith(
                    fontSize: 22,
                    color: context.elixTextPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusPill(label: statusPill, color: pillColor),
            ],
          ),
        ),
        if (wideLayout) ...[const SizedBox(width: AppSpacing.md), badge],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleRow,
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Text(
              instruction,
              style: AppTheme.bodySecondary.copyWith(
                color: context.elixTextSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!wideLayout) ...[
            const SizedBox(height: AppSpacing.sm),
            Padding(padding: const EdgeInsets.only(left: 44), child: badge),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: AppTheme.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
