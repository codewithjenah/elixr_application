import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/elix_design_tokens.dart';

class CalendarHeader extends StatelessWidget {
  const CalendarHeader({
    super.key,
    required this.visibleMonth,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onToday,
  });

  final DateTime visibleMonth;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    final monthLabel = DateFormat.yMMMM().format(visibleMonth);
    final monthName = DateFormat.MMMM().format(visibleMonth);

    return Row(
      children: [
        Expanded(
          child: Align(
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
                    text: ' ${visibleMonth.year}',
                    style: ElixTypography.sectionTitle(
                      context,
                      color: context.elixTextSecondary,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              semanticsLabel: monthLabel,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.elixCardSurface,
            borderRadius: BorderRadius.circular(10),
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
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Button(
          onPressed: onToday,
          style: ButtonStyle(
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.isDisabled) return colors.disabledSurface;
              if (states.isPressed) return colors.interactivePressed;
              if (states.isHovered) {
                return colors.brandSecondary.withValues(alpha: 0.16);
              }
              return colors.surfaceInteractive;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.isDisabled) return colors.disabledText;
              return context.elixTextPrimary;
            }),
            shape: WidgetStateProperty.resolveWith((states) {
              final focused = states.isFocused;
              return RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: focused ? colors.focusRing : colors.borderSubtle,
                  width: focused
                      ? (context.isHighContrast
                            ? ElixFocus.ringWidthHighContrast
                            : ElixFocus.ringWidth)
                      : 1,
                ),
              );
            }),
          ),
          child: const Text('Today'),
        ),
      ],
    );
  }
}
