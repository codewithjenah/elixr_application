import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_editorial_header.dart';
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
    final gold = context.elixColors.milestone;

    return DashboardPanelCard(
      accent: gold,
      showAccentBar: bestSession != null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ElixSectionHeader(heading: 'Top Performance'),
          const SizedBox(height: AppSpacing.md),
          if (session == null)
            Text(
              'Complete a session to set your first record.',
              style: AppTheme.supporting(color: context.elixTextSecondary),
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
                          style: AppTheme.metric(context, color: gold),
                          children: [
                            TextSpan(text: recordValue),
                            TextSpan(
                              text: recordScale,
                              style: AppTheme.label(
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
                        style: AppTheme.supporting(
                          color: context.elixTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        session.movementName,
                        style: AppTheme.cardTitle(
                          color: context.elixTextPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _RecordBadge(
                  isPerfect: isRubric && rubricTotal == 12,
                  color: gold,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RecordBadge extends StatelessWidget {
  const _RecordBadge({required this.isPerfect, required this.color});

  /// True for a full 12/12 rubric result.
  final bool isPerfect;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: highContrast
            ? context.elixCardSurface
            : color.withValues(alpha: 0.08),
        border: Border.all(
          color: highContrast ? color : color.withValues(alpha: 0.35),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(FluentIcons.medal, size: 18, color: color),
          const SizedBox(height: 2),
          Text(
            isPerfect ? 'PR' : 'Best',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
