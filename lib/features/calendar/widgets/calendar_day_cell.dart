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
    final status = snapshot?.status ?? TrainingDayStatus.unplanned;
    final hasPlan = status != TrainingDayStatus.unplanned;
    final unplannedActivity =
        status == TrainingDayStatus.unplanned &&
        (snapshot?.hasUnplannedActivity ?? false);
    final hasClassroom = classroomCount > 0;
    final hasOverdueClassroom = classroomOverdueCount > 0;
    final statusColor = trainingDayStatusColor(status);

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
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (hasPlan)
                  Tooltip(
                    message: status.label,
                    child: Icon(
                      trainingDayStatusIcon(status),
                      size: 11,
                      color: statusColor.withValues(
                        alpha: isOutsideMonth ? 0.5 : 1,
                      ),
                    ),
                  )
                else if (unplannedActivity)
                  Tooltip(
                    message: 'Practice recorded',
                    child: Icon(
                      FluentIcons.circle_fill,
                      size: 8,
                      color: context.elixColors.brandSecondary.withValues(
                        alpha: isOutsideMonth ? 0.5 : 1,
                      ),
                    ),
                  ),
                if (hasClassroom)
                  Semantics(
                    label:
                        '$classroomCount classroom assignment${classroomCount == 1 ? '' : 's'} due${hasOverdueClassroom ? ', overdue' : ''}',
                    child: Tooltip(
                      message: hasOverdueClassroom
                          ? 'Overdue classroom work'
                          : 'Classroom assignment',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasOverdueClassroom
                                ? FluentIcons.warning
                                : FluentIcons.education,
                            size: 11,
                            color: hasOverdueClassroom
                                ? context.elixColors.error
                                : context.elixColors.brandSecondary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '$classroomCount',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: context.elixTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
