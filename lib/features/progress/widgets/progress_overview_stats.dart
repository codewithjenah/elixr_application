import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_stat_card.dart';

/// Progress page metric grid. Presentation-only; values are supplied by
/// [ProgressScreen] after repository load.
class ProgressOverviewStats extends StatelessWidget {
  const ProgressOverviewStats({
    super.key,
    required this.overallPerformanceLabel,
    required this.averageLabel,
    required this.averageValue,
    required this.bestLabel,
    required this.bestValue,
    required this.totalSessions,
    required this.mostPracticed,
  });

  final String overallPerformanceLabel;
  final String averageLabel;
  final String averageValue;
  final String bestLabel;
  final String bestValue;
  final int totalSessions;
  final String mostPracticed;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ElixStatCard(
                  label: 'Overall Performance',
                  value: overallPerformanceLabel,
                  icon: FluentIcons.favorite_star_fill,
                  smallValue: true,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ElixStatCard(
                  label: averageLabel,
                  value: averageValue,
                  icon: FluentIcons.chart_template,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ElixStatCard(
                  label: bestLabel,
                  value: bestValue,
                  icon: FluentIcons.trophy2_solid,
                  valueColor: context.elixColors.milestone,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ElixStatCard(
                  label: 'Total Sessions',
                  value: '$totalSessions',
                  icon: FluentIcons.timer,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ElixStatCard(
          label: 'Most Practiced',
          value: mostPracticed,
          icon: FluentIcons.crown_solid,
          smallValue: true,
        ),
      ],
    );
  }
}
