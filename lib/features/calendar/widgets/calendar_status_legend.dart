import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/theme/app_theme.dart';
import '../models/training_day_status.dart';
import '../utils/training_day_status_style.dart';
import 'calendar_chrome.dart';

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
    final colors = context.elixColors;
    return CalendarLegendBar(
      items: [
        for (final status in _items)
          (
            trainingDayStatusIcon(status),
            trainingDayStatusColor(status, colors),
            status.label,
          ),
        (FluentIcons.education, colors.brandSecondary, 'Classroom'),
        (FluentIcons.warning, colors.error, 'Overdue'),
      ],
    );
  }
}
