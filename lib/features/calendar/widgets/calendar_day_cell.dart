import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../models/calendar_day_summary.dart';

const _pink = AppColors.primary;
const _purple = AppColors.accent;
const _cyan = AppColors.primarySoft;

class CalendarDayCell extends StatefulWidget {
  const CalendarDayCell({
    super.key,
    required this.date,
    required this.isOutsideMonth,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
    this.summary,
  });

  final DateTime date;
  final CalendarDaySummary? summary;
  final bool isOutsideMonth;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  State<CalendarDayCell> createState() => _CalendarDayCellState();
}

class _CalendarDayCellState extends State<CalendarDayCell> {
  bool _hovered = false;

  Color _activityTint(int count) {
    if (count <= 0) return Colors.transparent;
    if (count == 1) return _purple.withValues(alpha: 0.10);
    if (count <= 3) return _purple.withValues(alpha: 0.18);
    return _purple.withValues(alpha: 0.28);
  }

  Color _difficultyColor(String difficulty) {
    switch (difficulty) {
      case 'Easy':
        return _cyan;
      case 'Medium':
        return _purple;
      case 'Hard':
        return _pink;
      default:
        return context.elixTextSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = widget.summary;
    final count = summary?.sessionCount ?? 0;
    final average = summary?.averageScore;
    final difficulties = summary?.difficulties ?? const <String>{};

    final borderColor = widget.isSelected
        ? _pink
        : widget.isToday
        ? _purple.withValues(alpha: 0.7)
        : _hovered
        ? context.elixBorder.withValues(alpha: 0.9)
        : context.elixBorder.withValues(alpha: 0.55);

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
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? _pink.withValues(alpha: 0.14)
                : _activityTint(count),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: widget.isSelected || widget.isToday ? 1.4 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${widget.date.day}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: widget.isToday || count > 0
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: numberColor,
                    ),
                  ),
                  const Spacer(),
                  if (count > 0)
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: widget.isOutsideMonth
                            ? context.elixTextSecondary.withValues(alpha: 0.55)
                            : _violetSafe,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (average != null)
                Text(
                  average.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: widget.isOutsideMonth
                        ? context.elixTextSecondary.withValues(alpha: 0.5)
                        : context.elixTextSecondary,
                  ),
                )
              else
                const SizedBox(height: 14),
              const Spacer(),
              if (difficulties.isNotEmpty)
                Row(
                  children: [
                    for (final difficulty in _orderedDifficulties(difficulties))
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: _difficultyColor(difficulty).withValues(
                            alpha: widget.isOutsideMonth ? 0.45 : 0.9,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _orderedDifficulties(Set<String> difficulties) {
    const order = ['Easy', 'Medium', 'Hard'];
    final ordered = order.where(difficulties.contains).toList();
    for (final difficulty in difficulties) {
      if (!ordered.contains(difficulty)) ordered.add(difficulty);
    }
    return ordered;
  }
}

const _violetSafe = AppColors.accentSoft;
