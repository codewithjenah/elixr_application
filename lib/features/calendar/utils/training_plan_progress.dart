import 'package:elixr_core/utils/manila_day.dart';

import '../../../data/models/session.dart';
import '../../../data/models/training_plan.dart';
import '../models/training_day_snapshot.dart';
import '../models/training_day_status.dart';

/// Parses [Session.createdAt] onto a Manila `'yyyyMMdd'` day key.
String? parseSessionManilaDayKey(Session session) {
  final raw = session.createdAt;
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return ManilaDay.dayKeyFor(parsed.toUtc());
}

bool sessionMatchesTrainingPlan(Session session, TrainingPlan plan) {
  if (!plan.isTraining) return false;
  return session.movementName == plan.movementName &&
      session.difficulty == plan.difficulty &&
      session.propType == plan.propType;
}

int matchedPlanDurationSeconds({
  required TrainingPlan plan,
  required List<Session> sessionsForDay,
}) {
  if (!plan.isTraining) return 0;
  return sessionsForDay
      .where((session) => sessionMatchesTrainingPlan(session, plan))
      .fold<int>(0, (sum, session) => sum + session.durationSeconds);
}

int? bestMatchingRubricTotal({
  required TrainingPlan plan,
  required List<Session> sessionsForDay,
}) {
  if (!plan.isTraining) return null;
  final totals = [
    for (final session in sessionsForDay)
      if (sessionMatchesTrainingPlan(session, plan) && session.isRubricAssessed)
        session.rubricTotal!,
  ];
  if (totals.isEmpty) return null;
  return totals.reduce((a, b) => a > b ? a : b);
}

TrainingDayStatus deriveTrainingDayStatus({
  required TrainingPlan? plan,
  required int matchedDurationSeconds,
  required String todayKey,
}) {
  if (plan == null) return TrainingDayStatus.unplanned;
  if (plan.isRest) return TrainingDayStatus.rest;

  final reached = matchedDurationSeconds >= plan.targetDurationSeconds;
  if (reached) return TrainingDayStatus.completed;

  if (plan.dayKey.compareTo(todayKey) > 0) {
    return TrainingDayStatus.planned;
  }
  if (plan.dayKey == todayKey) {
    return matchedDurationSeconds > 0
        ? TrainingDayStatus.inProgress
        : TrainingDayStatus.planned;
  }
  return TrainingDayStatus.missed;
}

Map<String, List<Session>> groupSessionsByManilaDayKey(List<Session> sessions) {
  final buckets = <String, List<Session>>{};
  for (final session in sessions) {
    final dayKey = parseSessionManilaDayKey(session);
    if (dayKey == null) continue;
    (buckets[dayKey] ??= <Session>[]).add(session);
  }
  return buckets;
}

TrainingDaySnapshot buildTrainingDaySnapshot({
  required String dayKey,
  required TrainingPlan? plan,
  required List<Session> sessionsForDay,
  required String todayKey,
}) {
  final matchedSeconds = plan == null
      ? 0
      : matchedPlanDurationSeconds(plan: plan, sessionsForDay: sessionsForDay);
  final matching = plan == null
      ? const <Session>[]
      : sessionsForDay
            .where((session) => sessionMatchesTrainingPlan(session, plan))
            .toList(growable: false);
  final status = deriveTrainingDayStatus(
    plan: plan,
    matchedDurationSeconds: matchedSeconds,
    todayKey: todayKey,
  );
  final unplannedActivity =
      sessionsForDay.isNotEmpty &&
      (plan == null || matching.length < sessionsForDay.length);

  return TrainingDaySnapshot(
    dayKey: dayKey,
    civilDate: ManilaDay.civilDateFromDayKey(dayKey),
    status: status,
    plan: plan,
    matchedDurationSeconds: matchedSeconds,
    hasUnplannedActivity: unplannedActivity,
    bestMatchingRubricTotal: plan == null
        ? null
        : bestMatchingRubricTotal(plan: plan, sessionsForDay: sessionsForDay),
    matchingSessions: matching,
  );
}

Map<String, TrainingDaySnapshot> buildTrainingDaySnapshots({
  required Iterable<DateTime> civilDates,
  required List<TrainingPlan> plans,
  required List<Session> sessions,
  required String todayKey,
}) {
  final plansByDay = <String, TrainingPlan>{
    for (final plan in plans) plan.dayKey: plan,
  };
  final sessionsByDay = groupSessionsByManilaDayKey(sessions);
  final result = <String, TrainingDaySnapshot>{};
  for (final date in civilDates) {
    final dayKey = ManilaDay.dayKeyFromCivil(
      year: date.year,
      month: date.month,
      day: date.day,
    );
    result[dayKey] = buildTrainingDaySnapshot(
      dayKey: dayKey,
      plan: plansByDay[dayKey],
      sessionsForDay: sessionsByDay[dayKey] ?? const [],
      todayKey: todayKey,
    );
  }
  return result;
}

class TrainingAdherenceMetrics {
  const TrainingAdherenceMetrics({
    required this.plannedDays,
    required this.completedDays,
    required this.eligiblePlannedDays,
    required this.adherencePercent,
    required this.planStreak,
  });

  /// Training plans in the visible month, excluding rest days.
  final int plannedDays;
  final int completedDays;

  /// Training plans on or before today. Future plans are excluded.
  final int eligiblePlannedDays;

  /// `completed eligible / eligible`, or null when nothing is eligible yet.
  final int? adherencePercent;
  final int planStreak;
}

TrainingAdherenceMetrics computeTrainingAdherenceMetrics({
  required List<TrainingPlan> plans,
  required List<Session> sessions,
  required String todayKey,
  required String monthKey,
}) {
  final monthPlans = plans
      .where((plan) => ManilaDay.monthKeyFromDayKey(plan.dayKey) == monthKey)
      .toList(growable: false);
  final sessionsByDay = groupSessionsByManilaDayKey(sessions);

  final trainingPlans = monthPlans.where((plan) => plan.isTraining).toList();
  var completed = 0;
  var eligible = 0;
  var eligibleCompleted = 0;

  for (final plan in trainingPlans) {
    final matched = matchedPlanDurationSeconds(
      plan: plan,
      sessionsForDay: sessionsByDay[plan.dayKey] ?? const [],
    );
    final status = deriveTrainingDayStatus(
      plan: plan,
      matchedDurationSeconds: matched,
      todayKey: todayKey,
    );
    if (status == TrainingDayStatus.completed) completed++;
    if (plan.dayKey.compareTo(todayKey) <= 0) {
      eligible++;
      if (status == TrainingDayStatus.completed) eligibleCompleted++;
    }
  }

  final percent = eligible == 0
      ? null
      : ((eligibleCompleted / eligible) * 100).round();

  return TrainingAdherenceMetrics(
    plannedDays: trainingPlans.length,
    completedDays: completed,
    eligiblePlannedDays: eligible,
    adherencePercent: percent,
    planStreak: computePlanStreak(
      plans: plans,
      sessions: sessions,
      todayKey: todayKey,
    ),
  );
}

/// Consecutive Manila days the user followed the plan, working backward.
///
/// Rest days are skipped. Today is ignored while it is still actionable
/// (unplanned, planned, or in progress). Unplanned past days break the streak.
int computePlanStreak({
  required List<TrainingPlan> plans,
  required List<Session> sessions,
  required String todayKey,
}) {
  final plansByDay = <String, TrainingPlan>{
    for (final plan in plans) plan.dayKey: plan,
  };
  final sessionsByDay = groupSessionsByManilaDayKey(sessions);

  TrainingDayStatus statusFor(String dayKey) {
    final plan = plansByDay[dayKey];
    final matched = plan == null
        ? 0
        : matchedPlanDurationSeconds(
            plan: plan,
            sessionsForDay: sessionsByDay[dayKey] ?? const [],
          );
    return deriveTrainingDayStatus(
      plan: plan,
      matchedDurationSeconds: matched,
      todayKey: todayKey,
    );
  }

  var cursor = todayKey;
  final todayStatus = statusFor(cursor);
  if (todayStatus == TrainingDayStatus.unplanned ||
      todayStatus == TrainingDayStatus.planned ||
      todayStatus == TrainingDayStatus.inProgress) {
    cursor = ManilaDay.addCalendarDays(cursor, -1);
  }

  var streak = 0;
  // Bound the walk so a missing-plan history cannot loop forever.
  for (var i = 0; i < 366; i++) {
    final status = statusFor(cursor);
    if (status == TrainingDayStatus.rest) {
      cursor = ManilaDay.addCalendarDays(cursor, -1);
      continue;
    }
    if (status == TrainingDayStatus.completed) {
      streak++;
      cursor = ManilaDay.addCalendarDays(cursor, -1);
      continue;
    }
    break;
  }
  return streak;
}

String trainingPracticeLocation({
  required String movement,
  required String difficulty,
  required String propProtocolValue,
}) {
  return Uri(
    path: '/practice',
    queryParameters: {
      'movement': movement,
      'difficulty': difficulty,
      'prop': propProtocolValue,
    },
  ).toString();
}

String formatPlanMinutes(int minutes) => '$minutes min';

int practicedMinutesFromSeconds(int seconds) => seconds < 0 ? 0 : seconds ~/ 60;
