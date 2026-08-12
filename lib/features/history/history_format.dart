import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../data/models/rubric_assessment.dart';

/// Formats a duration for summary cards and session rows.
///
/// Examples: `34s`, `8m 12s`, `1h 15m`.
String formatTrainingDuration(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  if (seconds < 60) return '${seconds}s';

  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remSeconds = seconds % 60;

  if (hours > 0) {
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  if (remSeconds == 0) return '${minutes}m';
  return '${minutes}m ${remSeconds}s';
}

/// Quality label for a legacy Assessment V1 percentage (0..100).
///
/// Never pass a rubric total to this function; the two scales are unrelated.
String scoreQualityLabel(int legacyScore) {
  if (legacyScore >= 80) return 'Excellent';
  if (legacyScore >= 50) return 'Developing';
  return 'Needs Practice';
}

/// Quality color for a legacy Assessment V1 percentage (0..100).
Color scoreQualityColor(int legacyScore) {
  if (legacyScore >= 80) return AppColors.success;
  if (legacyScore >= 50) return AppColors.warning;
  return AppColors.error;
}

/// Explicit legacy read-out so a 0..100 value is never mistaken for a rubric.
String legacyScoreLabel(int legacyScore) => 'Legacy Score: $legacyScore/100';

/// Assessment V2 rubric total read-out (0..12).
String rubricTotalLabel(int rubricTotal) => '$rubricTotal / 12';

/// Assessment V2 rubric average read-out (0..12).
String rubricAverageLabel(double averageRubricTotal) =>
    '${averageRubricTotal.toStringAsFixed(1)} / 12';

/// Performance level for a rubric total, using the model's thresholds.
PerformanceLevel rubricPerformanceLevel(int rubricTotal) =>
    PerformanceLevel.fromTotal(rubricTotal);

Color performanceLevelColor(PerformanceLevel level) => switch (level) {
  PerformanceLevel.mastered || PerformanceLevel.proficient => AppColors.success,
  PerformanceLevel.competent => AppColors.warning,
  PerformanceLevel.developing || PerformanceLevel.beginning => AppColors.error,
};

Color difficultyColor(String difficulty) {
  switch (difficulty) {
    case 'Easy':
      return AppColors.success;
    case 'Medium':
      return AppColors.warning;
    case 'Hard':
      return AppColors.error;
    default:
      return AppColors.textSecondary;
  }
}

enum HistorySortMode {
  mostRecent,
  oldest,
  highestScore,
  lowestScore,
  longestSession,
}

extension HistorySortModeLabel on HistorySortMode {
  String get label {
    switch (this) {
      case HistorySortMode.mostRecent:
        return 'Most Recent';
      case HistorySortMode.oldest:
        return 'Oldest';
      case HistorySortMode.highestScore:
        return 'Highest Score';
      case HistorySortMode.lowestScore:
        return 'Lowest Score';
      case HistorySortMode.longestSession:
        return 'Longest Session';
    }
  }
}
