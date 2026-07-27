import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../history_format.dart';

class HistorySummarySection extends StatelessWidget {
  const HistorySummarySection({
    super.key,
    required this.totalSessions,
    required this.averageScore,
    required this.bestScore,
    required this.totalDurationSeconds,
    this.matchingCount,
  });

  final int totalSessions;
  final int averageScore;
  final int bestScore;
  final int totalDurationSeconds;

  /// When non-null, a filter/search is active and this is the result size.
  final int? matchingCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = width >= 1200
                ? 4
                : width >= 500
                ? 2
                : 1;
            final gap = AppSpacing.sm;
            final cardWidth = columns == 1
                ? width
                : (width - gap * (columns - 1)) / columns;

            final cards = [
              _SummaryCard(
                icon: FluentIcons.history,
                label: 'Total Sessions',
                value: '$totalSessions',
                accent: AppColors.accentSoft,
                width: cardWidth,
              ),
              _SummaryCard(
                icon: FluentIcons.chart_template,
                label: 'Average Score',
                value: '$averageScore',
                accent: AppColors.primary,
                width: cardWidth,
              ),
              _SummaryCard(
                icon: FluentIcons.trophy2_solid,
                label: 'Best Score',
                value: '$bestScore',
                accent: AppColors.warning,
                width: cardWidth,
              ),
              _SummaryCard(
                icon: FluentIcons.clock,
                label: 'Total Training Time',
                value: formatTrainingDuration(totalDurationSeconds),
                accent: AppColors.success,
                width: cardWidth,
              ),
            ];

            return Wrap(spacing: gap, runSpacing: gap, children: cards);
          },
        ),
        if (matchingCount != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$matchingCount matching sessions',
            style: AppTheme.caption.copyWith(
              color: context.elixTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.width,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: AppTheme.cardDecoration(context),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(
                  alpha: context.isDarkTheme ? 0.16 : 0.12,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 14, color: accent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: context.elixTextPrimary,
                      height: 1.1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
