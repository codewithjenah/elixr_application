import 'package:elixr_core/utils/comparable_rubric_progress.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/utils/date_time_format.dart';
import '../../../data/models/session.dart';
import '../../training/training_view.dart';
import 'dashboard_panel_card.dart';

/// Personal dashboard analytics derived from the dashboard's loaded sessions.
///
/// Assessment V1 percentage scores are deliberately never plotted with the
/// Assessment V2 0..12 rubric series.
class DashboardTrainingInsights extends StatelessWidget {
  const DashboardTrainingInsights({
    super.key,
    required this.sessions,
    required this.sessionsThisWeek,
    required this.currentStreak,
    required this.weeklyComparison,
  });

  final List<Session> sessions;
  final int sessionsThisWeek;
  final int currentStreak;
  final ComparableRubricComparison weeklyComparison;

  /// The latest valid V2 sessions, plotted oldest-first.
  static List<Session> rubricTrendSessions(List<Session> sessions) {
    final valid =
        sessions
            .where(
              (session) =>
                  session.createdAt != null &&
                  ComparableRubricProgress.scoreFor(
                        assessmentVersion: session.assessmentVersion,
                        rubricTotal: session.rubricTotal,
                      ) !=
                      null,
            )
            .toList()
          ..sort((a, b) => a.createdAt!.compareTo(b.createdAt!));
    return valid.length <= 12 ? valid : valid.sublist(valid.length - 12);
  }

  /// The latest session snapshot entries, shown newest-first regardless of
  /// assessment version. Invalid dates remain after dated sessions.
  static List<Session> recentSessions(List<Session> sessions) {
    final ordered = List<Session>.of(sessions)
      ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    return ordered.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    final rubricSessions = rubricTrendSessions(sessions);
    final recent = recentSessions(sessions);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InsightsHeader(onProgress: () => context.go(AppRoutePaths.progress)),
        const SizedBox(height: AppSpacing.sm),
        _SummaryStrip(
          sessionsThisWeek: sessionsThisWeek,
          currentStreak: currentStreak,
          weeklyComparison: weeklyComparison,
        ),
        const SizedBox(height: AppSpacing.sm),
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 760;
            final trend = _PerformanceTrend(
              sessions: rubricSessions,
              hasLegacySessions: sessions.any(
                (session) =>
                    !session.isRubricAssessed && session.legacyScore != null,
              ),
            );
            final recentPanel = _RecentSessions(sessions: recent);
            if (stacked) {
              return Column(
                children: [
                  trend,
                  const SizedBox(height: AppSpacing.sm),
                  recentPanel,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 13, child: trend),
                const SizedBox(width: AppSpacing.sm),
                Expanded(flex: 7, child: recentPanel),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InsightsHeader extends StatelessWidget {
  const _InsightsHeader({required this.onProgress});
  final VoidCallback onProgress;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRAINING INSIGHTS',
            style: AppTheme.eyebrow(color: context.elixColors.brandPrimary),
          ),
          const SizedBox(height: 2),
          Text('Your recent practice', style: AppTheme.headingMedium),
        ],
      );
      final action = HyperlinkButton(
        onPressed: onProgress,
        child: const Text('View Progress'),
      );
      return constraints.maxWidth < 380
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, action],
            )
          : Row(
              children: [
                Expanded(child: title),
                action,
              ],
            );
    },
  );
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.sessionsThisWeek,
    required this.currentStreak,
    required this.weeklyComparison,
  });

  final int sessionsThisWeek;
  final int currentStreak;
  final ComparableRubricComparison weeklyComparison;

  @override
  Widget build(BuildContext context) {
    final percentageChange = weeklyComparison.percentageChange;
    final trend = percentageChange != null
        ? '${percentageChange >= 0 ? '+' : ''}'
              '${percentageChange.round()}%'
        : 'Not enough data';
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _SummaryValue(label: 'THIS WEEK', value: '$sessionsThisWeek sessions'),
        _SummaryValue(
          label: 'STREAK',
          value: '$currentStreak ${currentStreak == 1 ? 'day' : 'days'}',
        ),
        _SummaryValue(label: 'PROGRESS TREND', value: trend),
      ],
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: context.elixColors.surfaceTinted.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(ElixRadius.control),
      border: Border.all(color: context.elixBorder.withValues(alpha: 0.55)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTheme.eyebrow(color: context.elixTextSecondary)),
        const SizedBox(height: 2),
        Text(value, style: AppTheme.label(color: context.elixTextPrimary)),
      ],
    ),
  );
}

class _PerformanceTrend extends StatelessWidget {
  const _PerformanceTrend({
    required this.sessions,
    required this.hasLegacySessions,
  });
  final List<Session> sessions;
  final bool hasLegacySessions;

  @override
  Widget build(BuildContext context) {
    final message = sessions.isEmpty
        ? 'Complete a scored practice session to start tracking your progress.'
        : 'Complete one more scored practice session to see your progress trend.';
    return DashboardPanelCard(
      accent: context.elixColors.brandPrimary,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.line_chart,
                size: 16,
                color: context.elixColors.brandPrimary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text('Performance Trend', style: AppTheme.cardTitle()),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            sessions.length >= 2
                ? 'Practice Score History · latest ${sessions.length} sessions'
                : message,
            style: ElixTypography.caption(color: context.elixTextSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: sessions.length >= 2 ? 190 : 82,
            child: sessions.length >= 2
                ? _DashboardRubricTrendChart(sessions: sessions)
                : _TrendEmptyState(hasLegacy: hasLegacySessions),
          ),
        ],
      ),
    );
  }
}

class _TrendEmptyState extends StatelessWidget {
  const _TrendEmptyState({required this.hasLegacy});
  final bool hasLegacy;
  @override
  Widget build(BuildContext context) => Center(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          hasLegacy ? FluentIcons.info : FluentIcons.chart,
          size: 17,
          color: context.elixTextSecondary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            hasLegacy
                ? 'Earlier practice scores use a different scale. Complete a new scored session to start your trend.'
                : 'Your next scored session will make this trend more useful.',
            style: ElixTypography.caption(color: context.elixTextSecondary),
          ),
        ),
      ],
    ),
  );
}

class _DashboardRubricTrendChart extends StatelessWidget {
  const _DashboardRubricTrendChart({required this.sessions});
  final List<Session> sessions;

  @override
  Widget build(BuildContext context) => LineChart(
    LineChartData(
      minY: 0,
      maxY: 12,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 3,
        getDrawingHorizontalLine: (_) => FlLine(
          color: context.elixBorder.withValues(alpha: 0.5),
          strokeWidth: 1,
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: 3,
            getTitlesWidget: (value, _) => Text(
              value.toInt().toString(),
              style: ElixTypography.caption(color: context.elixTextSecondary),
            ),
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => context.elixPanelSurface,
          tooltipBorder: BorderSide(color: context.elixColors.brandPrimary),
          getTooltipItems: (spots) => spots.map((spot) {
            final session = sessions[spot.x.toInt()];
            final date = DateTime.tryParse(session.createdAt ?? '');
            final level = session.performanceLevel?.label ?? 'Practice score';
            return LineTooltipItem(
              '${session.rubricTotal ?? 0} / 12\n',
              ElixTypography.label(color: context.elixColors.brandPrimary),
              children: [
                TextSpan(
                  text:
                      '$level\n${session.movementName}\n'
                      '${date == null ? 'Date unavailable' : formatElixrDate(date)}',
                  style: ElixTypography.caption(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: [
            for (var i = 0; i < sessions.length; i++)
              FlSpot(i.toDouble(), sessions[i].rubricTotal!.toDouble()),
          ],
          isCurved: true,
          curveSmoothness: 0.3,
          color: context.elixColors.brandPrimary,
          barWidth: 3,
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(
              radius: 3.5,
              color: context.elixColors.brandPrimary,
              strokeWidth: 1.5,
              strokeColor: context.elixPanelSurface,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            color: context.elixColors.brandPrimary.withValues(alpha: 0.10),
          ),
        ),
      ],
    ),
  );
}

class _RecentSessions extends StatelessWidget {
  const _RecentSessions({required this.sessions});
  final List<Session> sessions;

  @override
  Widget build(BuildContext context) => DashboardPanelCard(
    accent: context.elixColors.brandSecondary,
    padding: const EdgeInsets.all(AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Recent Sessions', style: AppTheme.cardTitle()),
            ),
            HyperlinkButton(
              onPressed: () =>
                  context.go(trainingLocation(view: TrainingView.history)),
              child: const Text('View history'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < sessions.length; i++) ...[
          _RecentSessionRow(session: sessions[i]),
          if (i < sessions.length - 1)
            Divider(
              style: DividerThemeData(
                thickness: 1,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: context.elixBorder.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    ),
  );
}

class _RecentSessionRow extends StatelessWidget {
  const _RecentSessionRow({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(session.createdAt ?? '');
    final v2 = session.isRubricAssessed;
    final score = v2
        ? '${session.rubricTotal ?? 0} / 12'
        : session.legacyScore == null
        ? 'Unscored'
        : '${session.legacyScore} / 100';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.movementName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.label(),
                ),
                const SizedBox(height: 2),
                Text(
                  '${session.difficulty} · ${session.propType.displayLabel} · ${v2 ? 'Practice score' : 'Earlier score'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ElixTypography.caption(
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                score,
                style: ElixTypography.label(
                  color: v2
                      ? context.elixColors.brandPrimary
                      : context.elixTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                date == null ? 'Date unavailable' : formatElixrDate(date),
                style: ElixTypography.caption(color: context.elixTextSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
