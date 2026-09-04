import 'package:elixr_core/models/elixr_group.dart';
import 'package:elixr_core/utils/manila_day.dart';

import '../../../data/models/group_assignment.dart';

enum TeacherDeadlineState { upcoming, dueToday, overdue }

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
    for (final group in authorizedGroups) group.id: group.name,
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
