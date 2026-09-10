/// Shared contract for progress math that compares Assessment V2 results.
///
/// Only valid 0..12 rubric totals from Assessment V2 belong in these metrics.
/// Legacy 0..100 scores remain available for raw session displays, but never
/// enter a rubric average, trend, or comparison.
abstract final class ComparableRubricProgress {
  static const maximumScore = 12;

  static bool isEligible({
    required int assessmentVersion,
    required int? rubricTotal,
  }) =>
      assessmentVersion == 2 &&
      rubricTotal != null &&
      rubricTotal >= 0 &&
      rubricTotal <= maximumScore;

  /// Returns a comparable 0..12 V2 total, or null when this record is not
  /// eligible for rubric math. A valid zero is deliberately retained.
  static int? scoreFor({
    required int assessmentVersion,
    required int? rubricTotal,
  }) =>
      isEligible(assessmentVersion: assessmentVersion, rubricTotal: rubricTotal)
      ? rubricTotal
      : null;

  static double? average(Iterable<int> scores) {
    final values = scores.toList(growable: false);
    if (values.isEmpty) return null;
    return values.reduce((sum, score) => sum + score) / values.length;
  }

  /// Compares two V2-only score cohorts without substituting missing values
  /// with zero. Percentage change is unavailable when its denominator is 0.
  static ComparableRubricComparison compare({
    required Iterable<int> currentScores,
    required Iterable<int> comparisonScores,
  }) => ComparableRubricComparison(
    currentAverage: average(currentScores),
    comparisonAverage: average(comparisonScores),
  );
}

class ComparableRubricComparison {
  const ComparableRubricComparison({
    required this.currentAverage,
    required this.comparisonAverage,
  });

  final double? currentAverage;
  final double? comparisonAverage;

  /// Difference on the native 0..12 scale when both cohorts have data.
  double? get pointChange => currentAverage == null || comparisonAverage == null
      ? null
      : currentAverage! - comparisonAverage!;

  /// Percentage change when both cohorts have data and the comparison average
  /// is a usable non-zero denominator. This is distinct from a real 0% change.
  double? get percentageChange {
    final change = pointChange;
    final baseline = comparisonAverage;
    if (change == null || baseline == null || baseline == 0) return null;
    return change / baseline * 100;
  }
}
