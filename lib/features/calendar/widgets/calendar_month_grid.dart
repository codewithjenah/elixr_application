import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../models/training_day_snapshot.dart';
import 'calendar_chrome.dart';
import 'calendar_day_cell.dart';
import 'calendar_status_legend.dart';

class CalendarMonthGrid extends StatelessWidget {
  const CalendarMonthGrid({
    super.key,
    required this.dates,
    required this.visibleMonth,
    required this.selectedDate,
    required this.todayDate,
    required this.snapshotsByDate,
    this.classroomCountsByDate = const {},
    this.classroomOverdueByDate = const {},
    required this.onDateSelected,
  });

  final List<DateTime> dates;
  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime todayDate;
  final Map<DateTime, TrainingDaySnapshot> snapshotsByDate;
  final Map<DateTime, int> classroomCountsByDate;
  final Map<DateTime, int> classroomOverdueByDate;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    return CalendarSurface(
      child: Column(
        children: [
          const CalendarWeekdayHeader(),
          const SizedBox(height: AppSpacing.sm),
          for (var week = 0; week < dates.length ~/ 7; week++) ...[
            if (week > 0) const SizedBox(height: 6),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var dow = 0; dow < 7; dow++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: dow == 6 ? 0 : 6),
                        child: CalendarDayCell(
                          date: dates[week * 7 + dow],
                          snapshot: snapshotsByDate[dates[week * 7 + dow]],
                          classroomCount:
                              classroomCountsByDate[dates[week * 7 + dow]] ?? 0,
                          classroomOverdueCount:
                              classroomOverdueByDate[dates[week * 7 + dow]] ??
                              0,
                          isOutsideMonth:
                              dates[week * 7 + dow].month != visibleMonth.month,
                          isSelected: dates[week * 7 + dow] == selectedDate,
                          isToday: dates[week * 7 + dow] == todayDate,
                          onTap: () => onDateSelected(dates[week * 7 + dow]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const CalendarStatusLegend(),
        ],
      ),
    );
  }
}
