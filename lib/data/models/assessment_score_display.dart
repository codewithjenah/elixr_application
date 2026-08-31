/// Presentation-only score normalization. Persisted Official ELIXR rubric
/// totals remain 0..12; Teacher Activity grades remain earned/max.
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

  static String official(int rawScore) => format(earned: rawScore, maximum: 12);

  static String teacherActivity({required int earned, required int maximum}) =>
      format(earned: earned, maximum: maximum);

  static String _number(num value) => value == value.roundToDouble()
      ? value.round().toString()
      : value.toStringAsFixed(1);
}
