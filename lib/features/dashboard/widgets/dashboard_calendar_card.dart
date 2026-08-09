import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../calendar/utils/calendar_metrics.dart';
import 'dashboard_panel_card.dart';

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

    return DashboardPanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.calendar,
                size: 14,
                color: AppColors.accentSoft.withValues(alpha: 0.95),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Practice Calendar',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.elixTextPrimary,
                  ),
                ),
              ),
              HyperlinkButton(
                onPressed: onViewCalendar,
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  ),
                ),
                child: const Text(
                  'View Calendar',
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          Text(
            DateFormat.yMMMM().format(now),
            style: TextStyle(fontSize: 11, color: context.elixTextSecondary),
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
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: context.elixTextSecondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var week = 0; week < dates.length ~/ 7; week++) ...[
            if (week > 0) const SizedBox(height: 2),
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
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.92),
                )
              : practiced
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.18),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.45),
                  ),
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
                  ? context.elixTextPrimary
                  : context.elixTextSecondary,
            ),
          ),
        ),
      ),
    );

    if (!practiced && !isToday) return content;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: content),
    );
  }
}
