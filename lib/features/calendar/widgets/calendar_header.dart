import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';
import 'calendar_chrome.dart';

class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    super.key,
    required this.visibleMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
    this.trailing,
  });

  final DateTime visibleMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat.yMMMM().format(visibleMonth);
    final monthName = DateFormat.MMMM().format(visibleMonth);
    final month = _MonthTitle(
      monthName: monthName,
      year: visibleMonth.year,
      semanticsLabel: monthLabel,
    );
    final nav = _MonthNavGroup(
      onPreviousMonth: onPreviousMonth,
      onNextMonth: onNextMonth,
      onToday: onToday,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < CalendarLayout.splitBreakpoint;
        final titleAndNav = Row(
          children: [
            Expanded(child: month),
            const SizedBox(width: AppSpacing.sm),
            nav,
          ],
        );

        if (trailing == null) return titleAndNav;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleAndNav,
              const SizedBox(height: AppSpacing.sm),
              trailing!,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: month),
            const SizedBox(width: AppSpacing.md),
            Flexible(child: trailing!),
            const SizedBox(width: AppSpacing.sm),
            nav,
          ],
        );
      },
    );
  }
}

class _MonthTitle extends StatelessWidget {
  const _MonthTitle({
    required this.monthName,
    required this.year,
    required this.semanticsLabel,
  });

  final String monthName;
  final int year;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: monthName,
              style: ElixTypography.sectionTitle(
                context,
                color: context.elixTextPrimary,
              ),
            ),
            TextSpan(
              text: ' $year',
              style: ElixTypography.supporting(color: context.elixTextSecondary)
                  .copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    height: 1.2,
                  ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}

class _MonthNavGroup extends StatelessWidget {
  const _MonthNavGroup({
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
  });

  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: BorderRadius.circular(CalendarLayout.controlRadius),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Previous month',
            child: IconButton(
              icon: Icon(
                FluentIcons.chevron_left,
                size: 12,
                color: context.elixTextPrimary,
              ),
              onPressed: onPreviousMonth,
            ),
          ),
          Container(width: 1, height: 22, color: colors.borderSubtle),
          Tooltip(
            message: 'Next month',
            child: IconButton(
              icon: Icon(
                FluentIcons.chevron_right,
                size: 12,
                color: context.elixTextPrimary,
              ),
              onPressed: onNextMonth,
            ),
          ),
          Container(width: 1, height: 22, color: colors.borderSubtle),
          Button(
            onPressed: onToday,
            style: ButtonStyle(
              padding: WidgetStateProperty.all(
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.isDisabled) return colors.disabledSurface;
                if (states.isPressed) return colors.interactivePressed;
                if (states.isHovered) return colors.interactiveHover;
                return Colors.transparent;
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.isDisabled) return colors.disabledText;
                return context.elixTextPrimary;
              }),
              shape: WidgetStateProperty.resolveWith((states) {
                final focused = states.isFocused;
                return RoundedRectangleBorder(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(CalendarLayout.controlRadius),
                    bottomRight: Radius.circular(CalendarLayout.controlRadius),
                  ),
                  side: BorderSide(
                    color: focused ? colors.focusRing : Colors.transparent,
                    width: focused
                        ? (context.isHighContrast
                              ? ElixFocus.ringWidthHighContrast
                              : ElixFocus.ringWidth)
                        : 0,
                  ),
                );
              }),
            ),
            child: const Text('Today'),
          ),
        ],
      ),
    );
  }
}
