import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/session.dart';
import 'dashboard_panel_card.dart';

/// Personal-best summary for the dashboard right rail.
class DashboardTopPerformance extends StatelessWidget {
  const DashboardTopPerformance({super.key, required this.bestSession});

  final Session? bestSession;

  @override
  Widget build(BuildContext context) {
    final session = bestSession;
    final rubricTotal = session?.rubricTotal;
    final isRubric = session != null && session.isRubricAssessed;
    final recordValue = isRubric
        ? '$rubricTotal'
        : (session?.legacyScore?.toString() ?? '—');
    final recordLabel = isRubric ? 'Best Rubric' : 'Best Legacy Score';
    final recordScale = isRubric ? ' / 12' : ' / 100';
    final levelLabel = session?.performanceLevel?.label;

    return DashboardPanelCard(
      accent: AppColors.warning,
      showAccentBar: bestSession != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.trophy2,
                size: 14,
                color: AppColors.warning.withValues(alpha: 0.95),
              ),
              const SizedBox(width: 6),
              Text(
                'Top Performance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.elixTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (session == null)
            Text(
              'Complete a session to set your first record.',
              style: TextStyle(fontSize: 12, color: context.elixTextSecondary),
            )
          else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: recordValue,
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: AppColors.warning,
                                height: 1,
                              ),
                            ),
                            TextSpan(
                              text: recordScale,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: context.elixTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        levelLabel == null
                            ? recordLabel
                            : '$recordLabel · $levelLabel',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.elixTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        session.movementName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.elixTextPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _RecordBadge(isPerfect: isRubric && rubricTotal == 12),
              ],
            ),
        ],
      ),
    );
  }
}

class _RecordBadge extends StatelessWidget {
  const _RecordBadge({required this.isPerfect});

  /// True for a full 12/12 rubric result.
  final bool isPerfect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.warning.withValues(alpha: 0.08),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: 0.35),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.medal,
            size: 18,
            color: AppColors.warning.withValues(alpha: 0.95),
          ),
          const SizedBox(height: 2),
          Text(
            isPerfect ? 'PR' : 'Best',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: AppColors.warning.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}
