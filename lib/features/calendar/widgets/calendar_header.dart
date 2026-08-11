import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

const _pink = AppColors.primary;
const _purple = AppColors.accent;
const _violet = AppColors.accentSoft;

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
    return Row(
      children: [
        Tooltip(
          message: 'Previous month',
          child: IconButton(
            icon: const Icon(FluentIcons.chevron_left, size: 14),
            onPressed: onPreviousMonth,
          ),
        ),
        Expanded(
          child: Text(
            DateFormat.yMMMM().format(visibleMonth),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: context.elixTextPrimary,
            ),
          ),
        ),
        Tooltip(
          message: 'Next month',
          child: IconButton(
            icon: const Icon(FluentIcons.chevron_right, size: 14),
            onPressed: onNextMonth,
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
              if (states.isHovered) {
                return _purple.withValues(alpha: 0.22);
              }
              return _purple.withValues(alpha: 0.12);
            }),
            foregroundColor: WidgetStateProperty.all(_violet),
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: _pink.withValues(alpha: 0.28)),
              ),
            ),
          ),
          child: const Text('Today'),
        ),
      ],
    );
  }
}
