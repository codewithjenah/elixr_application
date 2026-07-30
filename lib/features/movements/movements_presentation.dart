import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/movements.dart';

typedef MovementStats = ({int count, double avgScore});

class MovementsSummary {
  const MovementsSummary({
    required this.practicedCount,
    required this.totalMovements,
    required this.totalSessions,
    required this.overallAverage,
  });

  final int practicedCount;
  final int totalMovements;
  final int totalSessions;

  /// Weighted average across sessions, or null when there are no sessions.
  final double? overallAverage;
}

/// Builds page-level summary values from per-movement session aggregates.
MovementsSummary computeMovementsSummary(Map<String, MovementStats> stats) {
  var practiced = 0;
  var totalSessions = 0;
  var weightedSum = 0.0;

  for (final movement in movementCatalog) {
    final entry = stats[movement.name];
    if (entry == null || entry.count <= 0) continue;
    practiced++;
    totalSessions += entry.count;
    weightedSum += entry.avgScore * entry.count;
  }

  return MovementsSummary(
    practicedCount: practiced,
    totalMovements: movementCatalog.length,
    totalSessions: totalSessions,
    overallAverage: totalSessions > 0 ? weightedSum / totalSessions : null,
  );
}

Color difficultyAccentColor(String difficulty) {
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

String difficultySectionTitle(String difficulty) {
  switch (difficulty) {
    case 'Easy':
      return 'Easy — Foundations';
    case 'Medium':
      return 'Medium — Balance and control';
    case 'Hard':
      return 'Hard — Advanced stability';
    default:
      return difficulty;
  }
}
