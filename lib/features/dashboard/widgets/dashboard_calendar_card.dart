import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../calendar/utils/calendar_metrics.dart';

const _purple = AppColors.accent;
const _violet = AppColors.accentSoft;
const _pink = AppColors.primary;
const _panelColor = AppColors.panelSurface;

/// Compact Monday-first practice calendar used on the Dashboard.
class DashboardCalendarCard extends StatelessWidget {
  const DashboardCalendarCard({
    super.key,
    required this.practicedDays,
    required this.onViewCalendar,
    required this.onDateSelected,
  });

  final Set<DateTime> practicedDays;
  final VoidCallback onViewCalendar;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final visibleMonth = DateTime(now.year, now.month);
    final today = normalizeDate(now);
    final dates = monthGridDates(visibleMonth.year, visibleMonth.month);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _panelColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _purple.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: _purple.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(FluentIcons.calendar, size: 14, color: _violet),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Practice Calendar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              HyperlinkButton(
                onPressed: onViewCalendar,
                child: const Text('View Calendar'),
              ),
            ],
          ),
          Text(
            DateFormat.yMMMM().format(now),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final d in const [
                'Mon',
                'Tue',
                'Wed',
                'Thu',
                'Fri',
                'Sat',
                'Sun',
              ])
                Expanded(
                  child: Text(
                    d,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var week = 0; week < dates.length ~/ 7; week++) ...[
            Row(
              children: [
                for (var dow = 0; dow < 7; dow++)
                  Expanded(
                    child: _CompactDayCell(
                      date: dates[week * 7 + dow],
                      inMonth:
                          dates[week * 7 + dow].month == visibleMonth.month,
                      practiced: practicedDays.contains(dates[week * 7 + dow]),
                      isToday: dates[week * 7 + dow] == today,
                      onTap: () => onDateSelected(dates[week * 7 + dow]),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactDayCell extends StatelessWidget {
  const _CompactDayCell({
    required this.date,
    required this.inMonth,
    required this.practiced,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final bool inMonth;
  final bool practiced;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!inMonth) {
      return const SizedBox(height: 30);
    }

    final content = SizedBox(
      height: 30,
      child: Center(
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: isToday
              ? const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [_pink, _purple]),
                )
              : practiced
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: _purple.withValues(alpha: 0.28),
                  border: Border.all(color: _purple.withValues(alpha: 0.55)),
                )
              : null,
          child: Text(
            '${date.day}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: isToday || practiced
                  ? FontWeight.w700
                  : FontWeight.w400,
              color: isToday
                  ? Colors.white
                  : practiced
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );

    // Active practiced dates (and today) are navigable into the full calendar.
    if (!practiced && !isToday) return content;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: content),
    );
  }
}
