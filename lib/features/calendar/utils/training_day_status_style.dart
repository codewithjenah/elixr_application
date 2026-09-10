import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/constants/app_colors.dart';
import '../models/training_day_status.dart';

Color trainingDayStatusColor(TrainingDayStatus status) {
  return switch (status) {
    TrainingDayStatus.planned => AppColors.accent,
    TrainingDayStatus.inProgress => AppColors.warning,
    TrainingDayStatus.completed => AppColors.success,
    TrainingDayStatus.missed => AppColors.error,
    TrainingDayStatus.rest => AppColors.textSecondary,
    TrainingDayStatus.unplanned => AppColors.border,
  };
}

/// Non-colour status cue for calendar cells and legends.
IconData trainingDayStatusIcon(TrainingDayStatus status) {
  return switch (status) {
    TrainingDayStatus.planned => FluentIcons.calendar,
    TrainingDayStatus.inProgress => FluentIcons.progress_ring_dots,
    TrainingDayStatus.completed => FluentIcons.completed_solid,
    TrainingDayStatus.missed => FluentIcons.error_badge,
    TrainingDayStatus.rest => FluentIcons.more,
    TrainingDayStatus.unplanned => FluentIcons.circle_ring,
  };
}
