import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_ui/shadcn_ui.dart' as shad;

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
    if (context.isHighContrast) {
      return _HighContrastMonthNavGroup(
        onPreviousMonth: onPreviousMonth,
        onNextMonth: onNextMonth,
        onToday: onToday,
      );
    }

    final colors = context.elixColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        shad.ShadTooltip(
          builder: (context) => const Text('Previous month'),
          child: Semantics(
            button: true,
            label: 'Previous month',
            child: shad.ShadIconButton.ghost(
              icon: Icon(FluentIcons.chevron_left, color: colors.textPrimary),
              onPressed: onPreviousMonth,
            ),
          ),
        ),
        const SizedBox(width: 4),
        shad.ShadTooltip(
          builder: (context) => const Text('Next month'),
          child: Semantics(
            button: true,
            label: 'Next month',
            child: shad.ShadIconButton.ghost(
              icon: Icon(FluentIcons.chevron_right, color: colors.textPrimary),
              onPressed: onNextMonth,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        shad.ShadButton.outline(
          onPressed: onToday,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const Text('Today'),
        ),
      ],
    );
  }
}

class _HighContrastMonthNavGroup extends StatelessWidget {
  const _HighContrastMonthNavGroup({
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
  });

  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Tooltip(
        message: 'Previous month',
        child: IconButton(
          icon: const Icon(FluentIcons.chevron_left, size: 12),
          onPressed: onPreviousMonth,
        ),
      ),
      Tooltip(
        message: 'Next month',
        child: IconButton(
          icon: const Icon(FluentIcons.chevron_right, size: 12),
          onPressed: onNextMonth,
        ),
      ),
      Button(onPressed: onToday, child: const Text('Today')),
    ],
  );
}
