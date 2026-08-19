import 'dart:ui';

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
