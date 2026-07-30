import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../movements_presentation.dart';

class MovementsHeader extends StatelessWidget {
  const MovementsHeader({super.key, required this.summary});

  final MovementsSummary summary;

  @override
  Widget build(BuildContext context) {
    final averageLabel = summary.overallAverage == null
        ? 'No score yet'
        : '${summary.overallAverage!.round()}% overall average';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(
                  alpha: context.isDarkTheme ? 0.18 : 0.10,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.26),
                ),
              ),
              child: const Icon(
                FluentIcons.more_sports,
                size: 20,
                color: AppColors.accentSoft,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Movements',
                    style: AppTheme.headingLarge.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Build your flair foundation, balance, and advanced control.',
                    style: AppTheme.bodySecondary.copyWith(
                      color: context.elixTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            _SummaryChip(
              label:
                  '${summary.practicedCount} of ${summary.totalMovements} practiced',
            ),
            _SummaryChip(
              label:
                  '${summary.totalSessions} session${summary.totalSessions == 1 ? '' : 's'} completed',
            ),
            _SummaryChip(label: averageLabel),
          ],
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.elixBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.elixTextSecondary,
        ),
      ),
    );
  }
}
