import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/movements.dart';

/// Per-movement aggregates.
///
/// [count] is every completed session; [rubricSessionCount] and
/// [averageRubricTotal] cover only Assessment V2 sessions on the 0..12 scale.
typedef MovementStats = ({
  int count,
  int rubricSessionCount,
  double? averageRubricTotal,
});

class MovementsSummary {
  const MovementsSummary({
    required this.practicedCount,
    required this.totalMovements,
    required this.totalSessions,
    required this.rubricSessionCount,
    required this.overallAverageRubric,
  });

  final int practicedCount;
  final int totalMovements;
  final int totalSessions;

  /// Sessions contributing to [overallAverageRubric].
  final int rubricSessionCount;

  /// Weighted rubric average (0..12), or null without Assessment V2 sessions.
  final double? overallAverageRubric;
}

/// Builds page-level summary values from per-movement session aggregates.
MovementsSummary computeMovementsSummary(Map<String, MovementStats> stats) {
  var practiced = 0;
  var totalSessions = 0;
  var rubricSessions = 0;
  var weightedRubricSum = 0.0;

  for (final movement in movementCatalog) {
    final entry = stats[movement.name];
    if (entry == null || entry.count <= 0) continue;
    practiced++;
    totalSessions += entry.count;

    final average = entry.averageRubricTotal;
    if (entry.rubricSessionCount > 0 && average != null) {
      rubricSessions += entry.rubricSessionCount;
      weightedRubricSum += average * entry.rubricSessionCount;
    }
  }

  return MovementsSummary(
    practicedCount: practiced,
    totalMovements: movementCatalog.length,
    totalSessions: totalSessions,
    rubricSessionCount: rubricSessions,
    overallAverageRubric: rubricSessions > 0
        ? weightedRubricSum / rubricSessions
        : null,
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
