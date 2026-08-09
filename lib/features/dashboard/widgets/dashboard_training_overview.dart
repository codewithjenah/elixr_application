import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/progress_repository.dart';
import 'dashboard_panel_card.dart';

/// Single cohesive training metrics strip (replaces four separate neon cards).
class DashboardTrainingOverview extends StatelessWidget {
  const DashboardTrainingOverview({
    super.key,
    required this.stats,
    required this.sessionsThisWeek,
    required this.weeklyTrendPercent,
  });

  final ProgressStats? stats;
  final int sessionsThisWeek;
  final int? weeklyTrendPercent;

  @override
  Widget build(BuildContext context) {
    final avg = stats?.averageScore;
    final metrics = <_MetricData>[
      _MetricData(
        label: 'Total Sessions',
        value: '${stats?.totalSessions ?? 0}',
        subLabel: sessionsThisWeek > 0
            ? '$sessionsThisWeek this week'
            : 'Start practicing',
        icon: FluentIcons.timer,
        accent: AppColors.accent,
      ),
      _MetricData(
        label: 'Average Score',
        value: avg != null ? avg.toStringAsFixed(0) : '—',
        valueSuffix: avg != null ? ' /100' : null,
        subLabel: weeklyTrendPercent != null
            ? '${weeklyTrendPercent! >= 0 ? '+' : '−'}${weeklyTrendPercent!.abs()}% vs last week'
            : 'All time',
        icon: FluentIcons.favorite_star,
        accent: AppColors.accentSoft,
      ),
      _MetricData(
        label: 'Best Score',
        value: stats?.bestScore?.toString() ?? '—',
        subLabel: 'Personal record',
        icon: FluentIcons.trophy2,
        accent: AppColors.warning,
      ),
      _MetricData(
        label: 'Top Move',
        value: stats?.mostPracticedMovement ?? '—',
        subLabel: 'Most practiced',
        icon: FluentIcons.diamond,
        accent: AppColors.primarySoft,
        flexibleValue: true,
      ),
    ];

    return DashboardPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Training Overview',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              if (wide) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < metrics.length; i++) ...[
                        if (i > 0) const _MetricDivider(vertical: true),
                        Expanded(
                          flex: metrics[i].flexibleValue ? 14 : 10,
                          child: _MetricZone(data: metrics[i]),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _MetricZone(data: metrics[0])),
                        const _MetricDivider(vertical: true),
                        Expanded(child: _MetricZone(data: metrics[1])),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _MetricDivider(vertical: false),
                  const SizedBox(height: AppSpacing.sm),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _MetricZone(data: metrics[2])),
                        const _MetricDivider(vertical: true),
                        Expanded(child: _MetricZone(data: metrics[3])),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    required this.subLabel,
    required this.icon,
    required this.accent,
    this.valueSuffix,
    this.flexibleValue = false,
  });

  final String label;
  final String value;
  final String subLabel;
  final IconData icon;
  final Color accent;
  final String? valueSuffix;
  final bool flexibleValue;
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider({required this.vertical});

  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final color = context.elixBorder.withValues(
      alpha: context.isDarkTheme ? 0.45 : 0.7,
    );
    if (vertical) {
      return Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: color,
      );
    }
    return Container(height: 1, color: color);
  }
}

class _MetricZone extends StatelessWidget {
  const _MetricZone({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: data.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(data.icon, size: 13, color: data.accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: context.elixTextSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          RichText(
            maxLines: data.flexibleValue ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: data.value,
                  style: TextStyle(
                    fontSize: data.flexibleValue ? 18 : 26,
                    fontWeight: FontWeight.w800,
                    color: context.elixTextPrimary,
                    height: 1.15,
                  ),
                ),
                if (data.valueSuffix != null)
                  TextSpan(
                    text: data.valueSuffix,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.elixTextSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.subLabel,
            style: TextStyle(fontSize: 11, color: context.elixTextSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
