import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/elix_design_tokens.dart';
import 'calendar_chrome.dart';
import 'calendar_metric_tile.dart';

class CalendarSummaryCards extends StatelessWidget {
  const CalendarSummaryCards({
    super.key,
    required this.plannedDays,
    required this.completedDays,
    required this.adherencePercent,
    required this.planStreak,
    this.classroomDue = 0,
    this.classroomOverdue = 0,
  });

  final int plannedDays;
  final int completedDays;
  final int? adherencePercent;
  final int planStreak;
  final int classroomDue;
  final int classroomOverdue;

  @override
  Widget build(BuildContext context) {
    final adherenceLabel = adherencePercent == null
        ? '—'
        : '$adherencePercent%';
    final adherenceSub = adherencePercent == null
        ? 'No actionable plans yet'
        : 'Completed of due training days';
    final classroomOverdueActive = classroomOverdue > 0;

    final cards = [
      CalendarMetricTile(
        label: 'Planned Days',
        value: '$plannedDays',
        detail: 'Training days this month',
        icon: FluentIcons.calendar,
        tone: ElixTone.selected,
      ),
      CalendarMetricTile(
        label: 'Completed',
        value: '$completedDays',
        detail: 'Targets reached',
        icon: FluentIcons.completed_solid,
        tone: ElixTone.success,
      ),
      CalendarMetricTile(
        label: 'Adherence',
        value: adherenceLabel,
        detail: adherenceSub,
        icon: FluentIcons.chart,
        tone: ElixTone.milestone,
      ),
      CalendarMetricTile(
        label: 'Practice Streak',
        value: '$planStreak',
        detail: planStreak == 1 ? 'Completed plan day' : 'Completed plan days',
        icon: FluentIcons.lightning_bolt,
        tone: ElixTone.milestone,
      ),
      CalendarMetricTile(
        label: classroomOverdueActive ? 'Overdue work' : 'Classroom work',
        value: '${classroomOverdueActive ? classroomOverdue : classroomDue}',
        detail: classroomOverdueActive
            ? 'Needs your attention'
            : classroomDue == 1
            ? 'Assignment due this month'
            : 'Assignments due this month',
        icon: classroomOverdueActive
            ? FluentIcons.warning
            : FluentIcons.education,
        tone: classroomOverdueActive ? ElixTone.error : ElixTone.milestone,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= CalendarLayout.metricsWideBreakpoint) {
          return _MetricRow(tiles: cards);
        }
        if (constraints.maxWidth >= CalendarLayout.metricsPairBreakpoint) {
          return Column(
            children: [
              _MetricRow(tiles: cards.sublist(0, 3)),
              const SizedBox(height: AppSpacing.sm),
              _MetricRow(tiles: cards.sublist(3)),
            ],
          );
        }
        return Column(
          children: [
            _MetricRow(tiles: cards.sublist(0, 2)),
            const SizedBox(height: AppSpacing.sm),
            _MetricRow(tiles: cards.sublist(2, 4)),
            const SizedBox(height: AppSpacing.sm),
            _MetricRow(tiles: cards.sublist(4)),
          ],
        );
      },
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}
