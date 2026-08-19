import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../models/training_day_status.dart';
import '../utils/training_day_status_style.dart';

class CalendarStatusLegend extends StatelessWidget {
  const CalendarStatusLegend({super.key});

  static const _items = [
    TrainingDayStatus.planned,
    TrainingDayStatus.inProgress,
    TrainingDayStatus.completed,
    TrainingDayStatus.missed,
    TrainingDayStatus.rest,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          for (final status in _items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: trainingDayStatusColor(status),
                    shape: BoxShape.circle,
                    border: status == TrainingDayStatus.rest
                        ? Border.all(color: context.elixBorder)
                        : null,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.elixTextSecondary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
