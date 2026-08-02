import '../../../data/models/session.dart';

/// One normalized local calendar date and its completed practice sessions.
class CalendarDaySummary {
  CalendarDaySummary({required this.date, required List<Session> sessions})
    : sessions = List<Session>.unmodifiable(sessions);

  final DateTime date;
  final List<Session> sessions;

  int get sessionCount => sessions.length;

  double? get averageScore {
    if (sessions.isEmpty) return null;
    final total = sessions.fold<int>(0, (sum, s) => sum + s.score);
    return total / sessions.length;
  }

  int? get bestScore {
    if (sessions.isEmpty) return null;
    return sessions.map((s) => s.score).reduce((a, b) => a > b ? a : b);
  }

  int get totalDurationSeconds =>
      sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);

  Set<String> get difficulties => sessions.map((s) => s.difficulty).toSet();
}
