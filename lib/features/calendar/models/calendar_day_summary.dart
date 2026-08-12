import '../../../data/models/session.dart';

/// One normalized local calendar date and its completed practice sessions.
class CalendarDaySummary {
  CalendarDaySummary({required this.date, required List<Session> sessions})
    : sessions = List<Session>.unmodifiable(sessions);

  final DateTime date;
  final List<Session> sessions;

  int get sessionCount => sessions.length;

  /// Assessment V2 rubric totals (0..12) recorded on this date.
  List<int> get _rubricTotals => [
    for (final s in sessions)
      if (s.isRubricAssessed) s.rubricTotal!,
  ];

  /// Legacy Assessment V1 percentages (0..100) recorded on this date.
  List<int> get _legacyScores => [
    for (final s in sessions)
      if (!s.isRubricAssessed && s.legacyScore != null) s.legacyScore!,
  ];

  int get rubricSessionCount => _rubricTotals.length;

  double? get averageRubricTotal => _average(_rubricTotals);

  int? get bestRubricTotal => _best(_rubricTotals);

  int get legacySessionCount => _legacyScores.length;

  double? get averageLegacyScore => _average(_legacyScores);

  int? get bestLegacyScore => _best(_legacyScores);

  bool get hasRubricData => rubricSessionCount > 0;

  /// Preferred average for UI: rubric when any V2 session exists.
  ///
  /// Callers must pair this with [hasRubricData] to label the scale; a 0..12
  /// rubric total and a 0..100 legacy score are never averaged together.
  double? get preferredAverage =>
      hasRubricData ? averageRubricTotal : averageLegacyScore;

  int? get preferredBest => hasRubricData ? bestRubricTotal : bestLegacyScore;

  static double? _average(List<int> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static int? _best(List<int> values) {
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a > b ? a : b);
  }

  int get totalDurationSeconds =>
      sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);

  Set<String> get difficulties => sessions.map((s) => s.difficulty).toSet();
}
