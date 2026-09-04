import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../models/training_day_snapshot.dart';
import '../models/training_day_status.dart';
import '../utils/training_day_status_style.dart';

const _pink = AppColors.primary;
const _purple = AppColors.accent;

class CalendarDayCell extends StatefulWidget {
  const CalendarDayCell({
    super.key,
    required this.date,
    required this.isOutsideMonth,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
    this.snapshot,
    this.classroomCount = 0,
  });

  final DateTime date;
  final TrainingDaySnapshot? snapshot;
  final int classroomCount;
  final bool isOutsideMonth;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  State<CalendarDayCell> createState() => _CalendarDayCellState();
}

class _CalendarDayCellState extends State<CalendarDayCell> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final status = widget.snapshot?.status ?? TrainingDayStatus.unplanned;
    final hasPlan = status != TrainingDayStatus.unplanned;
    final statusColor = trainingDayStatusColor(status);
    final unplannedActivity =
        status == TrainingDayStatus.unplanned &&
        (widget.snapshot?.hasUnplannedActivity ?? false);
    final hasClassroom = widget.classroomCount > 0;

    final borderColor = widget.isSelected
        ? _pink
        : widget.isToday
        ? _purple.withValues(alpha: 0.7)
        : hasPlan
        ? statusColor.withValues(alpha: widget.isOutsideMonth ? 0.35 : 0.55)
        : _hovered
        ? context.elixBorder.withValues(alpha: 0.9)
        : context.elixBorder.withValues(alpha: 0.55);

    final fill = widget.isSelected
        ? _pink.withValues(alpha: 0.14)
        : hasPlan
        ? statusColor.withValues(
            alpha: context.isDarkTheme
                ? (widget.isOutsideMonth ? 0.08 : 0.16)
                : (widget.isOutsideMonth ? 0.06 : 0.12),
          )
        : unplannedActivity
        ? _purple.withValues(alpha: context.isDarkTheme ? 0.08 : 0.05)
        : Colors.transparent;

    final numberColor = widget.isOutsideMonth
        ? context.elixTextSecondary.withValues(alpha: 0.45)
        : widget.isSelected || widget.isToday
        ? context.elixTextPrimary
        : context.elixTextPrimary.withValues(alpha: 0.92);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: widget.isSelected || widget.isToday ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.date.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: widget.isToday || hasPlan
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: numberColor,
                ),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.bottomLeft,
                child: Wrap(
                  spacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (hasPlan || unplannedActivity)
                      Container(
                        width: hasPlan ? 8 : 6,
                        height: hasPlan ? 8 : 6,
                        decoration: BoxDecoration(
                          color: (hasPlan ? statusColor : _purple).withValues(
                            alpha: widget.isOutsideMonth ? .5 : 1,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (hasClassroom)
                      Semantics(
                        label:
                            '${widget.classroomCount} classroom assignment${widget.classroomCount == 1 ? '' : 's'} due',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              FluentIcons.education,
                              size: 11,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${widget.classroomCount}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: context.elixTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
