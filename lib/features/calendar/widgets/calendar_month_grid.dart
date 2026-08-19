import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../models/training_day_snapshot.dart';
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
    required this.onDateSelected,
  });

  final List<DateTime> dates;
  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime todayDate;
  final Map<DateTime, TrainingDaySnapshot> snapshotsByDate;
  final ValueChanged<DateTime> onDateSelected;

  static const _weekdayLabels = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixPanelSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final label in _weekdayLabels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
            ],
          ),
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
