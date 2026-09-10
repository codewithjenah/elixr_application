import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/teacher/calendar/teacher_calendar_models.dart';
import 'package:elixr_core/models/elixr_group.dart';
import 'package:flutter_test/flutter_test.dart';

GroupAssignment _assignment({
  required String id,
  required String groupId,
  required DateTime dueAt,
}) => GroupAssignment(
  id: id,
  teacherId: 'teacher-1',
  groupId: groupId,
  movementId: 'movement-$id',
  revisionId: 'revision-$id',
  origin: MovementOrigin.officialElixr,
  assessmentMode: AssessmentMode.officialGuided,
  status: GroupAssignmentStatus.active,
  displayTitle: 'Assignment $id',
  teacherDisplayName: 'Teacher',
  groupName: 'Stored group name',
  officialMovementName: 'Hand Stall',
  dueAt: dueAt,
);

ElixrGroup _group(
  String id,
  String name, {
  ElixrGroupStatus status = ElixrGroupStatus.active,
}) => ElixrGroup(id: id, teacherId: 'teacher-1', name: name, status: status);

void main() {
  test('aggregates deadlines from authorized classrooms and filters a day', () {
    final events = teacherCalendarEvents(
      assignments: [
        _assignment(id: 'one', groupId: 'g1', dueAt: DateTime.utc(2026, 9, 5)),
        _assignment(
          id: 'two',
          groupId: 'g2',
          dueAt: DateTime.utc(2026, 9, 5, 3),
        ),
      ],
      authorizedGroups: [_group('g1', 'BSHM 4A'), _group('g2', 'BSHM 4B')],
      now: DateTime.utc(2026, 9, 1),
    );

    expect(events, hasLength(2));
    expect(
      events.map((event) => event.classroomName),
      containsAll(['BSHM 4A', 'BSHM 4B']),
    );
    expect(
      teacherCalendarEventsForDay(events, DateTime(2026, 9, 5)),
      hasLength(2),
    );
  });

  test('only active authorized classrooms contribute deadlines', () {
    final events = teacherCalendarEvents(
      assignments: [
        _assignment(
          id: 'allowed',
          groupId: 'allowed',
          dueAt: DateTime.utc(2026, 9, 5),
        ),
        _assignment(
          id: 'hidden',
          groupId: 'hidden',
          dueAt: DateTime.utc(2026, 9, 5),
        ),
        _assignment(
          id: 'archived',
          groupId: 'archived',
          dueAt: DateTime.utc(2026, 9, 5),
        ),
      ],
      authorizedGroups: [
        _group('allowed', 'Owned classroom'),
        _group(
          'archived',
          'Archived classroom',
          status: ElixrGroupStatus.archived,
        ),
      ],
      now: DateTime.utc(2026, 9, 1),
    );

    expect(events.map((event) => event.assignment.id), ['allowed']);
  });

  test('uses Manila civil dates at the UTC date boundary', () {
    final events = teacherCalendarEvents(
      assignments: [
        _assignment(
          id: 'boundary',
          groupId: 'g1',
          dueAt: DateTime.utc(2026, 9, 4, 16, 30),
        ),
      ],
      authorizedGroups: [_group('g1', 'BSHM 4A')],
      now: DateTime.utc(2026, 9, 4, 12),
    );

    expect(events.single.civilDate, DateTime(2026, 9, 5));
    expect(events.single.state, TeacherDeadlineState.upcoming);
  });

  test('classifies upcoming, due today, and overdue by Manila date', () {
    final events = teacherCalendarEvents(
      assignments: [
        _assignment(id: 'past', groupId: 'g1', dueAt: DateTime.utc(2026, 9, 3)),
        _assignment(
          id: 'today',
          groupId: 'g1',
          dueAt: DateTime.utc(2026, 9, 4, 14),
        ),
        _assignment(
          id: 'future',
          groupId: 'g1',
          dueAt: DateTime.utc(2026, 9, 4, 18),
        ),
      ],
      authorizedGroups: [_group('g1', 'BSHM 4A')],
      now: DateTime.utc(2026, 9, 4, 12),
    );

    expect(events.map((event) => event.state), [
      TeacherDeadlineState.overdue,
      TeacherDeadlineState.dueToday,
      TeacherDeadlineState.upcoming,
    ]);
  });

  test('filters by classroom and deadline state', () {
    final events = teacherCalendarEvents(
      assignments: [
        _assignment(id: 'a', groupId: 'g1', dueAt: DateTime.utc(2026, 9, 3)),
        _assignment(
          id: 'b',
          groupId: 'g2',
          dueAt: DateTime.utc(2026, 9, 4, 14),
        ),
        _assignment(
          id: 'c',
          groupId: 'g1',
          dueAt: DateTime.utc(2026, 9, 4, 18),
        ),
      ],
      authorizedGroups: [_group('g1', 'BSHM 4A'), _group('g2', 'BSHM 4B')],
      now: DateTime.utc(2026, 9, 4, 12),
    );

    expect(
      filterTeacherCalendarEvents(
        events,
        classroomId: 'g1',
      ).map((e) => e.assignment.id),
      ['a', 'c'],
    );
    expect(
      filterTeacherCalendarEvents(
        events,
        deadlineFilter: TeacherDeadlineFilter.overdue,
      ).map((e) => e.assignment.id),
      ['a'],
    );
    expect(
      filterTeacherCalendarEvents(
        events,
        classroomId: 'g1',
        deadlineFilter: TeacherDeadlineFilter.upcoming,
      ).map((e) => e.assignment.id),
      ['c'],
    );
  });

  test('overview counts follow classroom scope and visible month', () {
    final events = teacherCalendarEvents(
      assignments: [
        _assignment(id: 'past', groupId: 'g1', dueAt: DateTime.utc(2026, 9, 3)),
        _assignment(
          id: 'today',
          groupId: 'g2',
          dueAt: DateTime.utc(2026, 9, 4, 14),
        ),
        _assignment(
          id: 'week',
          groupId: 'g1',
          dueAt: DateTime.utc(2026, 9, 6, 8),
        ),
        _assignment(
          id: 'later-month',
          groupId: 'g1',
          dueAt: DateTime.utc(2026, 9, 20),
        ),
        _assignment(
          id: 'next-month',
          groupId: 'g2',
          dueAt: DateTime.utc(2026, 10, 2),
        ),
      ],
      authorizedGroups: [_group('g1', 'BSHM 4A'), _group('g2', 'BSHM 4B')],
      now: DateTime.utc(2026, 9, 4, 12),
    );

    final all = teacherCalendarOverview(
      events: events,
      visibleMonth: DateTime(2026, 9),
      today: DateTime(2026, 9, 4),
    );
    expect(all.dueTodayCount, 1);
    expect(all.overdueCount, 1);
    expect(all.upcomingThisMonthCount, 2);
    expect(all.upcomingThisWeekCount, 1);
    expect(all.visibleClassroomCount, 2);

    final classroom = teacherCalendarOverview(
      events: filterTeacherCalendarEvents(events, classroomId: 'g1'),
      visibleMonth: DateTime(2026, 9),
      today: DateTime(2026, 9, 4),
    );
    expect(classroom.dueTodayCount, 0);
    expect(classroom.overdueCount, 1);
    expect(classroom.visibleClassroomCount, 1);
  });

  test('lists active classrooms for filtering', () {
    final options = teacherCalendarClassroomOptions([
      _group('g2', 'BSHM 4B'),
      _group('g1', 'BSHM 4A'),
      _group('g3', 'Archived', status: ElixrGroupStatus.archived),
    ]);
    expect(options.map((option) => option.id), ['g1', 'g2']);
  });
}
