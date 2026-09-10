import 'package:fluent_ui/fluent_ui.dart';

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
    return CalendarMonthShell(
      dates: dates,
      visibleMonth: visibleMonth,
      selectedDate: selectedDate,
      todayDate: todayDate,
      footer: const CalendarStatusLegend(),
      cellBuilder:
          (
            context,
            date, {
            required isOutsideMonth,
            required isSelected,
            required isToday,
          }) {
            return CalendarDayCell(
              date: date,
              snapshot: snapshotsByDate[date],
              classroomCount: classroomCountsByDate[date] ?? 0,
              classroomOverdueCount: classroomOverdueByDate[date] ?? 0,
              isOutsideMonth: isOutsideMonth,
              isSelected: isSelected,
              isToday: isToday,
              onTap: () => onDateSelected(date),
            );
          },
    );
  }
}
