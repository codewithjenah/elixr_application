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

ElixrGroup _group(String id, String name) => ElixrGroup(
  id: id,
  teacherId: 'teacher-1',
  name: name,
  status: ElixrGroupStatus.active,
);

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

  test('does not expose deadlines outside the authorized classrooms', () {
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
      ],
      authorizedGroups: [_group('allowed', 'Owned classroom')],
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
}
