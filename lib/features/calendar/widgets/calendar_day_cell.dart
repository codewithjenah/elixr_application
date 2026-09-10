import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../models/training_day_snapshot.dart';
import '../models/training_day_status.dart';
import '../utils/training_day_status_style.dart';
import 'calendar_chrome.dart';

class CalendarDayCell extends StatelessWidget {
  const CalendarDayCell({
    super.key,
    required this.date,
    required this.isOutsideMonth,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
    this.snapshot,
    this.classroomCount = 0,
    this.classroomOverdueCount = 0,
  });

  final DateTime date;
  final TrainingDaySnapshot? snapshot;
  final int classroomCount;
  final int classroomOverdueCount;
  final bool isOutsideMonth;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final status = snapshot?.status ?? TrainingDayStatus.unplanned;
    final hasPlan = status != TrainingDayStatus.unplanned;
    final unplannedActivity =
        status == TrainingDayStatus.unplanned &&
        (snapshot?.hasUnplannedActivity ?? false);
    final hasClassroom = classroomCount > 0;
    final hasOverdueClassroom = classroomOverdueCount > 0;
    final statusColor = trainingDayStatusColor(status, colors);

    final label = StringBuffer('${date.day}');
    if (isToday) label.write(', today');
    if (isSelected) label.write(', selected');
    if (hasPlan) label.write(', ${status.label.toLowerCase()}');
    if (unplannedActivity) label.write(', practice recorded');
    if (hasClassroom) {
      label.write(
        ', $classroomCount classroom assignment${classroomCount == 1 ? '' : 's'} due',
      );
    }
    if (hasOverdueClassroom) label.write(', overdue classroom work');

    return CalendarDayFrame(
      onTap: onTap,
      semanticLabel: label.toString(),
      isSelected: isSelected,
      isToday: isToday,
      isOutsideMonth: isOutsideMonth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CalendarDayNumber(
            day: date.day,
            isToday: isToday,
            isSelected: isSelected,
            isOutsideMonth: isOutsideMonth,
          ),
          if (hasPlan || unplannedActivity || hasClassroom)
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: [
                if (hasPlan)
                  CalendarMarkerChip(
                    icon: trainingDayStatusIcon(status),
                    tooltip: status.label,
                    color: statusColor,
                    label: _compactStatusLabel(status),
                    dimmed: isOutsideMonth,
                  )
                else if (unplannedActivity)
                  CalendarMarkerChip(
                    icon: FluentIcons.circle_fill,
                    tooltip: 'Practice recorded',
                    color: colors.brandSecondary,
                    dimmed: isOutsideMonth,
                  ),
                if (hasClassroom)
                  Semantics(
                    label:
                        '$classroomCount classroom assignment${classroomCount == 1 ? '' : 's'} due${hasOverdueClassroom ? ', overdue' : ''}',
                    child: CalendarMarkerChip(
                      icon: hasOverdueClassroom
                          ? FluentIcons.warning
                          : FluentIcons.education,
                      tooltip: hasOverdueClassroom
                          ? 'Overdue classroom work'
                          : 'Classroom assignment',
                      color: hasOverdueClassroom
                          ? colors.error
                          : colors.brandSecondary,
                      count: classroomCount,
                      dimmed: isOutsideMonth,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static String _compactStatusLabel(TrainingDayStatus status) =>
      switch (status) {
        TrainingDayStatus.planned => 'Plan',
        TrainingDayStatus.inProgress => 'Active',
        TrainingDayStatus.completed => 'Done',
        TrainingDayStatus.missed => 'Missed',
        TrainingDayStatus.rest => 'Rest',
        TrainingDayStatus.unplanned => '',
      };
}
