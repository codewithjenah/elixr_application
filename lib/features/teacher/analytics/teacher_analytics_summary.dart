import 'package:fluent_ui/fluent_ui.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_panel_card.dart';
import 'teacher_analytics_controller.dart';
import 'teacher_analytics_models.dart';

/// Compact, best-effort current-week summary for the Teacher dashboard.
///
/// It intentionally owns no dashboard state and never replaces the existing
/// roster content when analytics reads fail.
class TeacherAnalyticsSummary extends StatelessWidget {
  const TeacherAnalyticsSummary({super.key, required this.controller});

  final TeacherAnalyticsController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        return ElixPanelCard(
          accent: context.elixColors.brandSecondary,
          showAccentBar: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SummaryHeader(),
              const SizedBox(height: AppSpacing.md),
              if ((controller.loading || controller.sessionLoading) &&
                  snapshot == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: ProgressBar(),
                )
              else if (controller.errorMessage != null && snapshot == null)
                Text(
                  'Analytics is temporarily unavailable. Your class data is still shown below.',
                  style: AppTheme.body.copyWith(
                    color: context.elixTextSecondary,
                  ),
                )
              else ...[
                _SummaryMetrics(snapshot: snapshot),
                if (snapshot != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  _DashboardCharts(snapshot: snapshot),
                ],
              ],
              if (controller.partialDataWarning != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Some practice history could not be loaded, so some numbers may be incomplete.',
                  style: AppTheme.caption.copyWith(
                    color: context.elixColors.warning,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _SummaryFooter(controller: controller),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: context.elixColors.brandSecondary.withValues(
                  alpha: context.isHighContrast ? 0 : 0.16,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                FluentIcons.chart,
                size: 16,
                color: context.elixColors.brandSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'This Week',
              style: AppTheme.headingMedium.copyWith(
                color: context.elixTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'A quick look at your classes this week.',
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
      ],
    );
  }
}

class _DashboardCharts extends StatelessWidget {
  const _DashboardCharts({required this.snapshot});

  final AnalyticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final charts = [
      _AnalyticsChartPanel(
        title: 'Score progress',
        description: 'Average practice score over time.',
        child: _ScoreProgressChart(buckets: snapshot.trendBuckets),
      ),
      _AnalyticsChartPanel(
        title: 'Practice by classroom',
        description: 'Practice sessions recorded this week.',
        child: _PracticeByClassroomChart(
          comparisons: snapshot.groupComparisons,
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: charts[0]),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: charts[1]),
            ],
          );
        }
        return Column(
          children: [
            charts[0],
            const SizedBox(height: AppSpacing.md),
            charts[1],
          ],
        );
      },
    );
  }
}

class _AnalyticsChartPanel extends StatelessWidget {
  const _AnalyticsChartPanel({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: context.isHighContrast
          ? context.elixCardSurface
          : context.elixCardSurface.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.elixBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.cardTitle(color: context.elixTextPrimary)),
        const SizedBox(height: 2),
        Text(
          description,
          style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(height: 190, child: child),
      ],
    ),
  );
}

class _ScoreProgressChart extends StatelessWidget {
  const _ScoreProgressChart({required this.buckets});

  final List<AnalyticsTrendBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var index = 0; index < buckets.length; index++)
        if (buckets[index].averageScore case final score?)
          FlSpot(index.toDouble(), score),
    ];
    if (spots.isEmpty) {
      return _ChartEmptyState(message: 'No scored practice yet.');
    }
    final labelInterval = buckets.length > 6
        ? (buckets.length / 4).ceilToDouble()
        : 1.0;
    return Semantics(
      label: 'Score progress chart on a 0 to 12 scale',
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 12,
          minX: 0,
          maxX: buckets.length <= 1 ? 1 : (buckets.length - 1).toDouble(),
          gridData: _horizontalGrid(context),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => context.elixPanelSurface,
              getTooltipItems: (touched) => [
                for (final spot in touched)
                  LineTooltipItem(
                    '${buckets[spot.x.toInt()].label}\n${spot.y.toStringAsFixed(1)} / 12',
                    TextStyle(
                      color: context.elixTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          titlesData: _scoreTitles(
            context,
            buckets: buckets,
            interval: labelInterval,
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: context.elixColors.brandSecondary,
              barWidth: 3,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 3,
                  color: context.elixColors.brandSecondary,
                  strokeColor: context.elixCardSurface,
                  strokeWidth: 1,
                ),
              ),
              belowBarData: BarAreaData(
                show: !context.isHighContrast,
                color: context.elixColors.brandSecondary.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}

class _PracticeByClassroomChart extends StatelessWidget {
  const _PracticeByClassroomChart({required this.comparisons});

  final List<GroupComparison> comparisons;

  @override
  Widget build(BuildContext context) {
    final active = comparisons
        .where((comparison) => comparison.sessionCount > 0)
        .toList(growable: false);
    if (active.isEmpty) {
      return _ChartEmptyState(message: 'No practice activity yet.');
    }
    final highest = active.fold<int>(
      0,
      (current, comparison) =>
          current > comparison.sessionCount ? current : comparison.sessionCount,
    );
    final maxY = ((highest + 3) ~/ 4 * 4).toDouble();
    return Semantics(
      label: 'Practice by classroom chart',
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: _horizontalGrid(context),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => context.elixPanelSurface,
              getTooltipItem: (group, _, rod, _) {
                final comparison = active[group.x];
                return BarTooltipItem(
                  '${comparison.group.name}\n${comparison.sessionCount} sessions',
                  TextStyle(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxY <= 8 ? 2 : (maxY / 4).ceilToDouble(),
                getTitlesWidget: (value, _) =>
                    _AxisLabel(value.toInt().toString()),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, _) {
                  final index = value.toInt();
                  if (index < 0 || index >= active.length) {
                    return const SizedBox.shrink();
                  }
                  return _AxisLabel(_shortLabel(active[index].group.name));
                },
              ),
            ),
          ),
          barGroups: [
            for (var index = 0; index < active.length; index++)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: active[index].sessionCount.toDouble(),
                    color: context.elixColors.brandSecondary,
                    width: active.length > 8 ? 12 : 20,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}

FlGridData _horizontalGrid(BuildContext context) => FlGridData(
  drawVerticalLine: false,
  getDrawingHorizontalLine: (_) =>
      FlLine(color: context.elixBorder.withValues(alpha: 0.45), strokeWidth: 1),
);

FlTitlesData _scoreTitles(
  BuildContext context, {
  required List<AnalyticsTrendBucket> buckets,
  required double interval,
}) => FlTitlesData(
  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  leftTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 28,
      interval: 3,
      getTitlesWidget: (value, _) => _AxisLabel(value.toInt().toString()),
    ),
  ),
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 30,
      interval: interval,
      getTitlesWidget: (value, _) {
        final index = value.toInt();
        if (index < 0 || index >= buckets.length) {
          return const SizedBox.shrink();
        }
        return _AxisLabel(_shortLabel(buckets[index].label));
      },
    ),
  ),
);

class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, color: context.elixTextSecondary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

String _shortLabel(String value) =>
    value.length > 10 ? '${value.substring(0, 9)}…' : value;

class _ChartEmptyState extends StatelessWidget {
  const _ChartEmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      message,
      style: AppTheme.body.copyWith(color: context.elixTextSecondary),
      textAlign: TextAlign.center,
    ),
  );
}

class _SummaryFooter extends StatelessWidget {
  const _SummaryFooter({required this.controller});

  final TeacherAnalyticsController controller;

  @override
  Widget build(BuildContext context) {
    final actions = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Tooltip(
          message: 'Refresh analytics',
          child: Semantics(
            label: 'Refresh analytics',
            button: true,
            child: IconButton(
              key: const Key('teacher_analytics_refresh'),
              icon: const Icon(FluentIcons.refresh),
              onPressed: controller.sessionLoading ? null : controller.refresh,
            ),
          ),
        ),
        FilledButton(
          key: const Key('teacher_analytics_view_analytics'),
          onPressed: () => context.go(AppRoutePaths.teacherAnalytics),
          child: const Text('View Analytics'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Align(alignment: Alignment.centerLeft, child: actions);
        }
        return Align(alignment: Alignment.centerRight, child: actions);
      },
    );
  }
}

class _SummaryMetrics extends StatelessWidget {
  const _SummaryMetrics({required this.snapshot});

  final AnalyticsSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final values = [
      _SummaryMetricData(
        label: 'Class average score',
        value: _score(snapshot?.averageScore),
        icon: FluentIcons.favorite_star,
        color: context.elixColors.milestone,
      ),
      _SummaryMetricData(
        label: 'Practice per student',
        value: snapshot?.averagePracticeSessions?.toStringAsFixed(1) ?? '—',
        icon: FluentIcons.repeat_all,
        color: context.elixColors.brandSecondary,
      ),
      _SummaryMetricData(
        label: 'Assignments completed',
        value: snapshot?.completionRate == null
            ? '—'
            : '${(snapshot!.completionRate! * 100).toStringAsFixed(0)}%',
        icon: FluentIcons.completed,
        color: context.elixColors.success,
      ),
      _SummaryMetricData(
        label: 'Change from last week',
        value: snapshot?.improvement == null
            ? '—'
            : _signed(snapshot!.improvement!),
        icon: FluentIcons.trending12,
        color: _changeColor(context, snapshot?.improvement),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final children = [
          for (final value in values) _SummaryMetric(data: value),
        ];
        if (wide) {
          return Row(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) const SizedBox(width: AppSpacing.lg),
                Expanded(child: children[index]),
              ],
            ],
          );
        }
        return Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.md,
          children: [
            for (final child in children)
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
                child: child,
              ),
          ],
        );
      },
    );
  }

  static String _score(double? value) =>
      value == null ? '—' : '${value.toStringAsFixed(1)} / 12';
  static String _signed(double value) =>
      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)}';

  static Color _changeColor(BuildContext context, double? value) {
    if (value == null) return context.elixTextSecondary;
    return value >= 0 ? context.elixColors.success : context.elixColors.error;
  }
}

class _SummaryMetricData {
  const _SummaryMetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.data});

  final _SummaryMetricData data;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Container(
      constraints: const BoxConstraints(minHeight: 102),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : context.elixCardSurface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.elixBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, size: 16, color: data.color),
          const SizedBox(height: AppSpacing.md),
          Text(
            data.value,
            style: AppTheme.cardTitle(color: context.elixTextPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
