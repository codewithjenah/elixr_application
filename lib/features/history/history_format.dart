import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';

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

String scoreQualityLabel(int score) {
  if (score >= 80) return 'Excellent';
  if (score >= 50) return 'Developing';
  return 'Needs Practice';
}

Color scoreQualityColor(int score) {
  if (score >= 80) return AppColors.success;
  if (score >= 50) return AppColors.warning;
  return AppColors.error;
}

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
