import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/utils/manila_day.dart';

import '../../../data/models/group_assignment.dart';

enum TeacherDeadlineState { upcoming, dueToday, overdue }

enum TeacherDeadlineFilter { all, dueToday, upcoming, overdue }

extension TeacherDeadlineStateLabel on TeacherDeadlineState {
  String get label => switch (this) {
    TeacherDeadlineState.upcoming => 'Upcoming',
    TeacherDeadlineState.dueToday => 'Due today',
    TeacherDeadlineState.overdue => 'Overdue',
  };
}

extension TeacherDeadlineFilterLabel on TeacherDeadlineFilter {
  String get label => switch (this) {
    TeacherDeadlineFilter.all => 'All',
    TeacherDeadlineFilter.dueToday => 'Due today',
    TeacherDeadlineFilter.upcoming => 'Upcoming',
    TeacherDeadlineFilter.overdue => 'Overdue',
  };

  bool matches(TeacherDeadlineState state) => switch (this) {
    TeacherDeadlineFilter.all => true,
    TeacherDeadlineFilter.dueToday => state == TeacherDeadlineState.dueToday,
    TeacherDeadlineFilter.upcoming => state == TeacherDeadlineState.upcoming,
    TeacherDeadlineFilter.overdue => state == TeacherDeadlineState.overdue,
  };
}

class TeacherCalendarClassroomOption {
  const TeacherCalendarClassroomOption({required this.id, required this.name});

  final String id;
  final String name;
}

class TeacherCalendarOverview {
  const TeacherCalendarOverview({
    required this.dueTodayCount,
    required this.overdueCount,
    required this.upcomingThisMonthCount,
    required this.upcomingThisWeekCount,
    required this.visibleClassroomCount,
  });

  final int dueTodayCount;
  final int overdueCount;
  final int upcomingThisMonthCount;
  final int upcomingThisWeekCount;
  final int visibleClassroomCount;
}

class TeacherCalendarEvent {
  const TeacherCalendarEvent({
    required this.assignment,
    required this.classroomName,
    required this.civilDate,
    required this.state,
  });

  final GroupAssignment assignment;
  final String classroomName;
  final DateTime civilDate;
  final TeacherDeadlineState state;
}

/// Builds calendar events only for the teacher's currently authorized groups.
/// The repositories enforce ownership at query time; this guards against a
/// stale assignment snapshot after a classroom is no longer available.
List<TeacherCalendarEvent> teacherCalendarEvents({
  required Iterable<GroupAssignment> assignments,
  required Iterable<ElixrGroup> authorizedGroups,
  required DateTime now,
}) {
  final namesByGroupId = {
    for (final group in authorizedGroups)
      if (group.isActive) group.id: group.name,
  };
  final todayKey = ManilaDay.dayKeyFor(now.toUtc());
  final events = <TeacherCalendarEvent>[];
  for (final assignment in assignments) {
    final dueAt = assignment.dueAt;
    final classroomName = namesByGroupId[assignment.groupId];
    if (!assignment.isActive || dueAt == null || classroomName == null) {
      continue;
    }
    final dayKey = ManilaDay.dayKeyFor(dueAt.toUtc());
    events.add(
      TeacherCalendarEvent(
        assignment: assignment,
        classroomName: classroomName,
        civilDate: ManilaDay.civilDateFromDayKey(dayKey),
        state: dayKey.compareTo(todayKey) < 0
            ? TeacherDeadlineState.overdue
            : dayKey == todayKey
            ? TeacherDeadlineState.dueToday
            : TeacherDeadlineState.upcoming,
      ),
    );
  }
  events.sort((a, b) => a.assignment.dueAt!.compareTo(b.assignment.dueAt!));
  return List.unmodifiable(events);
}

List<TeacherCalendarEvent> teacherCalendarEventsForDay(
  Iterable<TeacherCalendarEvent> events,
  DateTime date,
) {
  final dayKey = ManilaDay.dayKeyFromCivil(
    year: date.year,
    month: date.month,
    day: date.day,
  );
  return List.unmodifiable([
    for (final event in events)
      if (ManilaDay.dayKeyFromCivil(
            year: event.civilDate.year,
            month: event.civilDate.month,
            day: event.civilDate.day,
          ) ==
          dayKey)
        event,
  ]);
}

/// Active authorized classrooms the teacher can filter by.
List<TeacherCalendarClassroomOption> teacherCalendarClassroomOptions(
  Iterable<ElixrGroup> authorizedGroups,
) {
  final options = [
    for (final group in authorizedGroups)
      if (group.isActive)
        TeacherCalendarClassroomOption(id: group.id, name: group.name),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return List.unmodifiable(options);
}

List<TeacherCalendarEvent> filterTeacherCalendarEvents(
  Iterable<TeacherCalendarEvent> events, {
  String? classroomId,
  TeacherDeadlineFilter deadlineFilter = TeacherDeadlineFilter.all,
}) {
  final groupId = classroomId?.trim();
  return List.unmodifiable([
    for (final event in events)
      if ((groupId == null ||
              groupId.isEmpty ||
              event.assignment.groupId == groupId) &&
          deadlineFilter.matches(event.state))
        event,
  ]);
}

/// Attention counts from already-loaded events.
///
/// Due today and overdue are global (they need attention regardless of the
/// visible month). Upcoming and classroom counts are scoped to [visibleMonth].
/// Callers should pass classroom-filtered events and leave deadline-state
/// filtering to the grid and selected-day panel.
TeacherCalendarOverview teacherCalendarOverview({
  required Iterable<TeacherCalendarEvent> events,
  required DateTime visibleMonth,
  required DateTime today,
}) {
  final weekStart = _weekStartMonday(today);
  final weekEnd = weekStart.add(const Duration(days: 6));
  var dueToday = 0;
  var overdue = 0;
  var upcomingMonth = 0;
  var upcomingWeek = 0;
  final classrooms = <String>{};
  for (final event in events) {
    if (event.state == TeacherDeadlineState.dueToday) dueToday++;
    if (event.state == TeacherDeadlineState.overdue) overdue++;
    if (_inMonth(event.civilDate, visibleMonth)) {
      classrooms.add(event.assignment.groupId);
      if (event.state == TeacherDeadlineState.upcoming) upcomingMonth++;
    }
    if (event.state == TeacherDeadlineState.upcoming &&
        !event.civilDate.isBefore(weekStart) &&
        !event.civilDate.isAfter(weekEnd)) {
      upcomingWeek++;
    }
  }
  return TeacherCalendarOverview(
    dueTodayCount: dueToday,
    overdueCount: overdue,
    upcomingThisMonthCount: upcomingMonth,
    upcomingThisWeekCount: upcomingWeek,
    visibleClassroomCount: classrooms.length,
  );
}

Map<DateTime, List<TeacherCalendarEvent>> teacherCalendarEventsByDay(
  Iterable<TeacherCalendarEvent> events,
) {
  final grouped = <DateTime, List<TeacherCalendarEvent>>{};
  for (final event in events) {
    (grouped[event.civilDate] ??= <TeacherCalendarEvent>[]).add(event);
  }
  return grouped;
}

bool _inMonth(DateTime date, DateTime visibleMonth) =>
    date.year == visibleMonth.year && date.month == visibleMonth.month;

DateTime _weekStartMonday(DateTime today) {
  final civil = DateTime(today.year, today.month, today.day);
  return civil.subtract(Duration(days: civil.weekday - DateTime.monday));
}
