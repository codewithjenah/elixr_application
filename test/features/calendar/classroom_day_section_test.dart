import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/calendar/models/calendar_classroom_assignment.dart';
import 'package:elixr_application/features/calendar/widgets/classroom_day_section.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final assignments = [
    _item('a', 'Hand Stall drill'),
    _item('b', 'Bottle control'),
  ];

  testWidgets('shows multiple classroom items and opens the selected item', (
    tester,
  ) async {
    CalendarClassroomAssignment? opened;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: ClassroomDaySection(
            items: assignments,
            onOpen: (item) => opened = item,
          ),
        ),
      ),
    );

    expect(find.text('CLASSROOM WORK'), findsOneWidget);
    expect(find.text('Hand Stall drill'), findsOneWidget);
    expect(find.text('Bottle control'), findsOneWidget);
    expect(find.text('Due'), findsNWidgets(2));

    await tester.tap(find.text('Bottle control'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opened?.assignment.id, 'b');
  });
}

CalendarClassroomAssignment _item(String id, String title) =>
    CalendarClassroomAssignment(
      assignment: GroupAssignment(
        id: id,
        teacherId: 'teacher',
        groupId: 'group',
        movementId: 'movement',
        revisionId: 'revision',
        origin: MovementOrigin.teacherCreated,
        assessmentMode: AssessmentMode.teacherReviewed,
        status: GroupAssignmentStatus.active,
        displayTitle: title,
        teacherDisplayName: 'Grace Hopper',
        groupName: 'BSHM 4A',
        dueAt: DateTime.utc(2026, 9, 10, 16),
      ),
      submission: null,
      now: DateTime.utc(2026, 9, 10, 12),
    );
