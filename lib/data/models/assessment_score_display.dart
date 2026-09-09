import 'rubric_assessment.dart';

/// Presentation-only Official ELIXR wording and score formatting.
///
/// Persisted Official ELIXR rubric totals remain 0..12. Teacher Activity
/// grades remain earned/max. Performance thresholds stay on
/// [PerformanceLevel.fromTotal]; this type never duplicates them.
abstract final class AssessmentScoreDisplay {
  static double normalizedPercentage({
    required num earned,
    required num maximum,
  }) {
    if (maximum <= 0) return 0;
    return (earned / maximum * 100).clamp(0, 100).toDouble();
  }

  static String format({required num earned, required num maximum}) {
    final percentage = normalizedPercentage(earned: earned, maximum: maximum);
    final earnedText = _number(earned);
    final maximumText = _number(maximum);
    final percentageText = percentage == percentage.roundToDouble()
        ? percentage.round().toString()
        : percentage.toStringAsFixed(1);
    return '$earnedText/$maximumText • $percentageText%';
  }

  static String official(int rawScore) => '${_number(rawScore)}/12';

  static String officialAverage(num average) => '${_number(average)}/12';

  static String points(num value) => _number(value);

  static String teacherActivity({required int earned, required int maximum}) =>
      format(earned: earned, maximum: maximum);

  static String performanceLabel(PerformanceLevel level) => switch (level) {
    PerformanceLevel.beginning => 'Getting Started',
    PerformanceLevel.developing => 'Learning',
    PerformanceLevel.competent => 'Good',
    PerformanceLevel.proficient => 'Great',
    PerformanceLevel.mastered => 'Mastered',
  };

  /// Badge-only shortening of [performanceLabel]. Do not use for full readouts.
  static String performanceCompactLabel(PerformanceLevel level) =>
      switch (level) {
        PerformanceLevel.beginning => 'Start',
        PerformanceLevel.developing => 'Learn',
        PerformanceLevel.competent => 'Good',
        PerformanceLevel.proficient => 'Great',
        PerformanceLevel.mastered => 'Mastered',
      };

  static String performanceLabelForTotal(int total) => performanceLabel(
    PerformanceLevel.fromTotal(
      total.clamp(0, RubricAssessment.maxTotalScore).toInt(),
    ),
  );

  static String criterionLabel(RubricCriterion criterion) =>
      switch (criterion) {
        RubricCriterion.technique => 'Form',
        RubricCriterion.stability => 'Control',
        RubricCriterion.completion => 'Finish',
        RubricCriterion.propPositioning => 'Position',
      };

  static String officialWithPerformance(int total) {
    final clamped = total.clamp(0, RubricAssessment.maxTotalScore).toInt();
    return '${official(clamped)} · ${performanceLabel(PerformanceLevel.fromTotal(clamped))}';
  }

  static String criterionScore(
    RubricCriterion criterion,
    int score, {
    bool colon = false,
  }) {
    final name = criterionLabel(criterion);
    return colon ? '$name: $score/3' : '$name $score/3';
  }

  static String officialSemantics(int total, {PerformanceLevel? level}) {
    final clamped = total.clamp(0, RubricAssessment.maxTotalScore).toInt();
    final resolved = level ?? PerformanceLevel.fromTotal(clamped);
    return 'ELIXR Score $clamped out of 12, ${performanceLabel(resolved)}';
  }

  static String _number(num value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}
