import 'package:elixr_core/utils/comparable_rubric_progress.dart';

import '../../core/utils/manila_day.dart';
import '../../data/models/session.dart';
import '../calendar/utils/calendar_metrics.dart' as calendar;

/// Dashboard values derived from the trainee's loaded session list.
///
/// These calculations match the previous inline [DashboardScreen] getters.
class DashboardSessionMetrics {
  const DashboardSessionMetrics({
    required this.sessionsThisWeek,
    required this.practicedDays,
    required this.currentStreak,
    required this.weeklyComparison,
    required this.bestSession,
  });

  final int sessionsThisWeek;
  final Set<DateTime> practicedDays;
  final int currentStreak;
  final ComparableRubricComparison weeklyComparison;
  final Session? bestSession;

  factory DashboardSessionMetrics.fromSessions(
    List<Session> sessions, {
    DateTime? nowUtc,
  }) {
    final now = (nowUtc ?? DateTime.now()).toUtc();
    final today = ManilaDay.civilDateFor(now);
    final practiced = calendar.practicedDates(sessions);
    return DashboardSessionMetrics(
      sessionsThisWeek: countSessionsThisWeek(sessions, today: today),
      practicedDays: practiced,
      currentStreak: calendar.currentStreak(practiced, referenceDate: today),
      weeklyComparison: weeklyRubricComparison(sessions, today: today),
      bestSession: bestSessionFor(sessions),
    );
  }
}

int countSessionsThisWeek(List<Session> sessions, {required DateTime today}) {
  final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
  return sessions.where((session) {
    final date = calendar.parseSessionLocalDate(session);
    return date != null && !date.isBefore(startOfWeek);
  }).length;
}

/// Week-over-week change in average rubric total (Assessment V2 only).
///
/// Legacy percentage sessions are excluded so the two scales never mix.
ComparableRubricComparison weeklyRubricComparison(
  List<Session> sessions, {
  required DateTime today,
}) {
  List<int> scoresBetween(int fromDaysAgo, int toDaysAgo) {
    final scores = <int>[];
    for (final session in sessions) {
      if (!_isWithin(session, today, fromDaysAgo, toDaysAgo)) continue;
      final score = ComparableRubricProgress.scoreFor(
        assessmentVersion: session.assessmentVersion,
        rubricTotal: session.rubricTotal,
      );
      if (score != null) scores.add(score);
    }
    return scores;
  }

  return ComparableRubricProgress.compare(
    currentScores: scoresBetween(6, 0),
    comparisonScores: scoresBetween(13, 7),
  );
}

bool _isWithin(
  Session session,
  DateTime today,
  int fromDaysAgo,
  int toDaysAgo,
) {
  final date = calendar.parseSessionLocalDate(session);
  if (date == null) return false;
  final diff = today.difference(date).inDays;
  return diff >= toDaysAgo && diff <= fromDaysAgo;
}

/// Personal best, preferring the Assessment V2 cohort.
///
/// A rubric total (0..12) is never compared against a legacy score (0..100),
/// so legacy sessions are only considered when no V2 session exists.
Session? bestSessionFor(List<Session> sessions) {
  Session? bestRubric;
  Session? bestLegacy;
  for (final session in sessions) {
    if (session.isRubricAssessed) {
      if (bestRubric == null ||
          session.rubricTotal! > bestRubric.rubricTotal!) {
        bestRubric = session;
      }
    } else if (session.legacyScore != null) {
      if (bestLegacy == null ||
          session.legacyScore! > bestLegacy.legacyScore!) {
        bestLegacy = session;
      }
    }
  }
  return bestRubric ?? bestLegacy;
}
