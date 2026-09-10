import 'package:fluent_ui/fluent_ui.dart';

import '../../../core/theme/elix_design_tokens.dart';
import '../models/training_day_status.dart';

Color trainingDayStatusColor(
  TrainingDayStatus status,
  ElixSemanticColors colors,
) {
  return switch (status) {
    TrainingDayStatus.planned => colors.brandSecondary,
    TrainingDayStatus.inProgress => colors.warning,
    TrainingDayStatus.completed => colors.success,
    TrainingDayStatus.missed => colors.error,
    TrainingDayStatus.rest => colors.textSecondary,
    TrainingDayStatus.unplanned => colors.borderSubtle,
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
