import '../../../data/models/session.dart';
import '../models/calendar_day_summary.dart';

/// Parses [Session.createdAt] and returns a local date-only value.
///
/// Null or invalid timestamps return `null` and must be excluded from
/// calendar calculations.
DateTime? parseSessionLocalDate(Session session) {
  final raw = session.createdAt;
  if (raw == null) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  final local = parsed.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Normalizes any timestamp to a local date-only value.
DateTime normalizeDate(DateTime date) =>
    DateTime(date.year, date.month, date.day);

/// Groups sessions by local calendar date. Invalid timestamps are excluded.
Map<DateTime, CalendarDaySummary> groupSessionsByDate(List<Session> sessions) {
  final buckets = <DateTime, List<Session>>{};
  for (final session in sessions) {
    final date = parseSessionLocalDate(session);
    if (date == null) continue;
    (buckets[date] ??= <Session>[]).add(session);
  }

  return {
    for (final entry in buckets.entries)
      entry.key: CalendarDaySummary(date: entry.key, sessions: entry.value),
  };
}

/// Unique practiced local calendar dates derived from valid session timestamps.
Set<DateTime> practicedDates(List<Session> sessions) {
  return groupSessionsByDate(sessions).keys.toSet();
}

/// Current practice streak using unique local calendar dates.
///
/// Rules:
/// - Multiple sessions on one date count as one streak day.
/// - A streak containing [referenceDate] (default: today) is active.
/// - When the user has not practiced today, a streak ending yesterday remains
///   active.
/// - When the latest practice date is earlier than yesterday, streak is zero.
/// - Future dates do not increase the current streak.
int currentStreak(Set<DateTime> dates, {DateTime? referenceDate}) {
  if (dates.isEmpty) return 0;

  final today = normalizeDate(referenceDate ?? DateTime.now());
  final practiced = {
    for (final d in dates)
      if (!d.isAfter(today)) normalizeDate(d),
  };
  if (practiced.isEmpty) return 0;

  var cursor = today;
  if (!practiced.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  if (!practiced.contains(cursor)) return 0;

  var streak = 0;
  while (practiced.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Longest consecutive run of practiced local calendar dates.
int longestStreak(Set<DateTime> dates) {
  if (dates.isEmpty) return 0;

  final sorted = dates.map(normalizeDate).toSet().toList()..sort();
  var longest = 1;
  var run = 1;
  for (var i = 1; i < sorted.length; i++) {
    final gap = sorted[i].difference(sorted[i - 1]).inDays;
    if (gap == 1) {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 1;
    }
  }
  return longest;
}

/// Total completed sessions inside the given local month.
int monthlySessionCount(
  List<Session> sessions, {
  required int year,
  required int month,
}) {
  return sessions.where((session) {
    final date = parseSessionLocalDate(session);
    return date != null && date.year == year && date.month == month;
  }).length;
}

/// Unique practiced dates inside the given local month.
int monthlyActiveDayCount(
  List<Session> sessions, {
  required int year,
  required int month,
}) {
  return practicedDates(
    sessions,
  ).where((date) => date.year == year && date.month == month).length;
}

/// Best training day within the visible month.
///
/// Tie-break order: highest daily average score, then highest individual
/// session score, then highest session count, then most recent date.
CalendarDaySummary? bestTrainingDay(
  Map<DateTime, CalendarDaySummary> byDate, {
  required int year,
  required int month,
}) {
  final candidates = byDate.values
      .where((day) => day.date.year == year && day.date.month == month)
      .where((day) => day.sessionCount > 0)
      .toList();
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) {
    final avgCmp = (b.averageScore ?? 0).compareTo(a.averageScore ?? 0);
    if (avgCmp != 0) return avgCmp;

    final bestCmp = (b.bestScore ?? 0).compareTo(a.bestScore ?? 0);
    if (bestCmp != 0) return bestCmp;

    final countCmp = b.sessionCount.compareTo(a.sessionCount);
    if (countCmp != 0) return countCmp;

    return b.date.compareTo(a.date);
  });

  return candidates.first;
}

/// Monday-first month grid dates, including leading/trailing adjacent days.
List<DateTime> monthGridDates(int year, int month) {
  final firstOfMonth = DateTime(year, month, 1);
  final leading = firstOfMonth.weekday - DateTime.monday; // Mon=0 .. Sun=6
  final gridStart = firstOfMonth.subtract(Duration(days: leading));
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

  return List<DateTime>.generate(
    totalCells,
    (index) => DateTime(gridStart.year, gridStart.month, gridStart.day + index),
  );
}

/// Safely parses a `YYYY-MM-DD` calendar query parameter.
DateTime? parseCalendarQueryDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  final date = DateTime(year, month, day);
  // Reject overflow such as 2026-02-31 → March 3.
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

/// Formats practice duration for calendar details.
///
/// Examples: `42 sec`, `1 min 20 sec`, `8 min 05 sec`, `1 hr 04 min`.
String formatCalendarDuration(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  if (seconds < 60) return '$seconds sec';

  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remSeconds = seconds % 60;

  if (hours > 0) {
    final mm = minutes.toString().padLeft(2, '0');
    return '$hours hr $mm min';
  }

  final ss = remSeconds.toString().padLeft(2, '0');
  return '$minutes min $ss sec';
}

/// Moves [selected] into [year]/[month], clamping the day into range.
DateTime clampSelectedDay(
  DateTime selected, {
  required int year,
  required int month,
}) {
  final lastDay = DateTime(year, month + 1, 0).day;
  final day = selected.day > lastDay ? lastDay : selected.day;
  return DateTime(year, month, day);
}
