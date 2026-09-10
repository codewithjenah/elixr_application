import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import '../../../core/widgets/elix_panel_card.dart';

/// Shared calendar geometry so Teacher and Trainee stay one visual system.
abstract final class CalendarLayout {
  static const splitBreakpoint = 900.0;
  static const metricsWideBreakpoint = 1100.0;
  static const metricsPairBreakpoint = 720.0;
  static const calendarFlex = 7;
  static const agendaFlex = 3;
  static const maxContentWidth = 1280.0;
  static const cellGutter = 4.0;
  static const weekGutter = 4.0;
  static const dayMinHeight = 72.0;
  static const cellRadius = 8.0;
  static const controlRadius = 10.0;
  static const tileRadius = 12.0;
}

typedef CalendarDayCellBuilder =
    Widget Function(
      BuildContext context,
      DateTime date, {
      required bool isOutsideMonth,
      required bool isSelected,
      required bool isToday,
    });

/// Shared month-grid surface used by Teacher and Trainee calendars.
class CalendarSurface extends StatelessWidget {
  const CalendarSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ElixPanelCard(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm + 2,
            AppSpacing.md,
            AppSpacing.md,
          ),
      child: child,
    );
  }
}

/// Monday-first weekday labels for the month grid.
class CalendarWeekdayHeader extends StatelessWidget {
  const CalendarWeekdayHeader({super.key});

  static const labels = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colors.borderSubtle.withValues(
              alpha: context.isHighContrast ? 1 : 0.85,
            ),
          ),
        ),
      ),
      child: Row(
        children: [
          for (final label in labels)
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ElixTypography.eyebrow(
                  color: context.elixTextSecondary,
                ).copyWith(letterSpacing: 1.1, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

/// Week grid + weekday band used by both calendars.
class CalendarMonthShell extends StatelessWidget {
  const CalendarMonthShell({
    super.key,
    required this.dates,
    required this.visibleMonth,
    required this.selectedDate,
    required this.todayDate,
    required this.cellBuilder,
    this.footer,
    this.gridKey,
  });

  final List<DateTime> dates;
  final DateTime visibleMonth;
  final DateTime selectedDate;
  final DateTime todayDate;
  final CalendarDayCellBuilder cellBuilder;
  final Widget? footer;
  final Key? gridKey;

  @override
  Widget build(BuildContext context) {
    return CalendarSurface(
      child: Column(
        key: gridKey,
        children: [
          const CalendarWeekdayHeader(),
          const SizedBox(height: AppSpacing.sm),
          for (var week = 0; week < dates.length ~/ 7; week++) ...[
            if (week > 0) const SizedBox(height: CalendarLayout.weekGutter),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var dow = 0; dow < 7; dow++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: dow == 6 ? 0 : CalendarLayout.cellGutter,
                        ),
                        child: cellBuilder(
                          context,
                          dates[week * 7 + dow],
                          isOutsideMonth:
                              dates[week * 7 + dow].month != visibleMonth.month,
                          isSelected: dates[week * 7 + dow] == selectedDate,
                          isToday: dates[week * 7 + dow] == todayDate,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          ?footer,
        ],
      ),
    );
  }
}

/// Two-zone calendar/agenda workspace with a stacked fallback.
class CalendarWorkspaceSplit extends StatelessWidget {
  const CalendarWorkspaceSplit({
    super.key,
    required this.calendar,
    required this.agenda,
  });

  final Widget calendar;
  final Widget agenda;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= CalendarLayout.splitBreakpoint;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: CalendarLayout.calendarFlex, child: calendar),
              const SizedBox(width: AppSpacing.md),
              Expanded(flex: CalendarLayout.agendaFlex, child: agenda),
            ],
          );
        }
        return Column(
          children: [
            calendar,
            const SizedBox(height: AppSpacing.md),
            agenda,
          ],
        );
      },
    );
  }
}

/// Day-of-month numeral with Windows-style today and selected treatments.
class CalendarDayNumber extends StatelessWidget {
  const CalendarDayNumber({
    super.key,
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.isOutsideMonth,
  });

  final int day;
  final bool isToday;
  final bool isSelected;
  final bool isOutsideMonth;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final muted = isOutsideMonth;
    final selectedOnly = isSelected && !isToday;
    final numberColor = selectedOnly
        ? colors.onBrand
        : muted
        ? context.elixTextSecondary.withValues(alpha: 0.45)
        : context.elixTextPrimary;

    final label = Text(
      '$day',
      style: TextStyle(
        fontFamily: ElixTypography.fontFamily,
        fontFamilyFallback: ElixTypography.fontFallbacks,
        fontSize: 13,
        height: 1.1,
        fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
        color: numberColor,
      ),
    );

    if (!isSelected && !isToday) return label;

    final todayAndSelected = isToday && isSelected;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selectedOnly ? colors.brandPrimary : Colors.transparent,
        borderRadius: BorderRadius.circular(selectedOnly ? 8 : 13),
        border: selectedOnly
            ? null
            : Border.all(
                color: highContrast
                    ? colors.borderStrong
                    : (todayAndSelected
                          ? colors.brandPrimary
                          : colors.brandSecondary),
                width: highContrast ? 2 : (todayAndSelected ? 1.8 : 1.4),
              ),
      ),
      child: label,
    );
  }
}

/// Compact in-cell status/event marker. Never color-only: always has an icon.
class CalendarMarkerChip extends StatelessWidget {
  const CalendarMarkerChip({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    this.label,
    this.count,
    this.dimmed = false,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final String? label;
  final int? count;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final foreground = color.withValues(alpha: dimmed ? 0.5 : 1);
    final text = label ?? (count != null ? '$count' : null);
    return Tooltip(
      message: tooltip,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 72),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: highContrast
              ? colors.surfaceBase
              : color.withValues(alpha: dimmed ? 0.08 : 0.14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: highContrast
                ? colors.borderStrong
                : color.withValues(alpha: dimmed ? 0.28 : 0.42),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: foreground),
            if (text != null) ...[
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: ElixTypography.fontFamily,
                    fontFamilyFallback: ElixTypography.fontFallbacks,
                    fontSize: 9,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: highContrast
                        ? context.elixTextPrimary.withValues(
                            alpha: dimmed ? 0.55 : 1,
                          )
                        : foreground,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Keyboard-accessible day cell chrome with hover, selected, today, and focus.
class CalendarDayFrame extends StatefulWidget {
  const CalendarDayFrame({
    super.key,
    required this.onTap,
    required this.semanticLabel,
    required this.isSelected,
    required this.isToday,
    required this.isOutsideMonth,
    required this.child,
    this.height,
  });

  final VoidCallback onTap;
  final String semanticLabel;
  final bool isSelected;
  final bool isToday;
  final bool isOutsideMonth;
  final Widget child;
  final double? height;

  @override
  State<CalendarDayFrame> createState() => _CalendarDayFrameState();
}

class _CalendarDayFrameState extends State<CalendarDayFrame> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final highContrast = context.isHighContrast;
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1).clamp(1.0, 1.35);
    final minHeight =
        (widget.height ?? CalendarLayout.dayMinHeight) * textScale;

    Color fill;
    Color border;
    var borderWidth = 1.0;

    if (widget.isSelected) {
      fill = highContrast
          ? colors.surfaceBase
          : colors.surfaceSelected.withValues(
              alpha: context.isDarkTheme ? 0.72 : 0.55,
            );
      border = colors.brandPrimary;
      borderWidth = highContrast ? 2.5 : 1.5;
    } else if (widget.isToday) {
      fill = _hovered && !highContrast
          ? colors.interactiveHover
          : Colors.transparent;
      border = colors.brandSecondary;
      borderWidth = highContrast ? 2.5 : 1.3;
    } else {
      fill = _hovered && !highContrast
          ? colors.interactiveHover
          : Colors.transparent;
      border = widget.isOutsideMonth
          ? colors.borderSubtle.withValues(alpha: highContrast ? 1 : 0.28)
          : colors.borderSubtle.withValues(alpha: highContrast ? 1 : 0.62);
    }

    if (_focused) {
      border = colors.focusRing;
      borderWidth = highContrast
          ? ElixFocus.ringWidthHighContrast
          : ElixFocus.ringWidth;
    }

    return Semantics(
      button: true,
      selected: widget.isSelected,
      enabled: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: ElixMotion.duration(context, ElixMotion.micro),
            curve: ElixMotion.microCurve,
            width: double.infinity,
            constraints: BoxConstraints(minHeight: minHeight),
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(CalendarLayout.cellRadius),
              border: Border.all(color: border, width: borderWidth),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Footer legend strip that stays attached to the month grid.
class CalendarLegendBar extends StatelessWidget {
  const CalendarLegendBar({super.key, required this.items});

  final List<(IconData icon, Color color, String label)> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: context.elixColors.borderSubtle.withValues(
                alpha: context.isHighContrast ? 1 : 0.8,
              ),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm + 2),
          child: Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              for (final item in items)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(item.$1, size: 11, color: item.$2),
                    const SizedBox(width: 6),
                    Text(
                      item.$3,
                      style: ElixTypography.label(
                        color: context.elixTextSecondary,
                      ).copyWith(fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
