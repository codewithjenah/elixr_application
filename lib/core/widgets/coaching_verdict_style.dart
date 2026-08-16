import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';
import '../../data/models/coaching_verdict.dart';

Color coachingVerdictColor(
  CoachingVerdict verdict, {
  String feedbackType = 'warning',
}) {
  switch (verdict) {
    case CoachingVerdict.correct:
      return AppColors.success;
    case CoachingVerdict.uncertain:
      return AppColors.textSecondary;
    case CoachingVerdict.wrong:
      switch (feedbackType) {
        case 'error':
          return AppColors.error;
        default:
          return AppColors.warning;
      }
  }
}

IconData coachingVerdictIcon(CoachingVerdict verdict) {
  switch (verdict) {
    case CoachingVerdict.correct:
      return FluentIcons.status_circle_checkmark;
    case CoachingVerdict.uncertain:
      return FluentIcons.info_solid;
    case CoachingVerdict.wrong:
      return FluentIcons.warning;
  }
}
