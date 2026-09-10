import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_summary_stat_card.dart';

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final cards = [
          ElixSummaryStatCard(
            label: 'Planned Days',
            value: '$plannedDays',
            detail: 'Training days this month',
            icon: FluentIcons.calendar,
            accent: AppColors.primarySoft,
          ),
          ElixSummaryStatCard(
            label: 'Completed',
            value: '$completedDays',
            detail: 'Targets reached',
            icon: FluentIcons.completed_solid,
            accent: AppColors.success,
          ),
          ElixSummaryStatCard(
            label: 'Adherence',
            value: adherenceLabel,
            detail: adherenceSub,
            icon: FluentIcons.chart,
            accent: AppColors.accent,
          ),
          ElixSummaryStatCard(
            label: 'Practice Streak',
            value: '$planStreak',
            detail: planStreak == 1
                ? 'Completed plan day'
                : 'Completed plan days',
            icon: FluentIcons.lightning_bolt,
            accent: context.elixColors.milestone,
          ),
          ElixSummaryStatCard(
            label: classroomOverdue > 0 ? 'Overdue work' : 'Classroom work',
            value: '${classroomOverdue > 0 ? classroomOverdue : classroomDue}',
            detail: classroomOverdue > 0
                ? 'Needs your attention'
                : classroomDue == 1
                ? 'Assignment due this month'
                : 'Assignments due this month',
            icon: FluentIcons.education,
            accent: classroomOverdue > 0
                ? AppColors.error
                : context.elixColors.milestone,
          ),
        ];

        if (wide) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: cards[i]),
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
                  Expanded(child: cards[0]),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: cards[1]),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: cards[3]),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            IntrinsicHeight(
              child: Row(children: [Expanded(child: cards[4])]),
            ),
          ],
        );
      },
    );
  }
}
