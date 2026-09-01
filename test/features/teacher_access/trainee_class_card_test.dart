import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/teacher_access/trainee_class_card.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

GroupAssignment _assignment({
  required String id,
  required String title,
  DateTime? dueAt,
  GroupAssignmentStatus status = GroupAssignmentStatus.active,
}) {
  return GroupAssignment(
    id: id,
    teacherId: 'teacher-1',
    groupId: 'group-1',
    movementId: 'movement-1',
    revisionId: 'revision-1',
    origin: MovementOrigin.officialElixr,
    assessmentMode: AssessmentMode.officialGuided,
    status: status,
    displayTitle: title,
    teacherDisplayName: 'Grace Hopper',
    groupName: 'BSIT-4A',
    officialMovementName: title,
    dueAt: dueAt,
  );
}

void main() {
  test('class header colors stay in the classroom header palette', () {
    const ids = [
      'group-1',
      'group-2',
      'a',
      'b',
      'c',
      'd',
      'BSIT-4A',
      'BSHM-4A',
      'long-classroom-identifier',
    ];
    for (final id in ids) {
      expect(
        classHeaderColors,
        contains(traineeClassHeaderColor(id)),
        reason: id,
      );
      final accent = traineeClassAccent(id);
      expect(accent.start, traineeClassHeaderColor(id), reason: id);
    }
  });

  test('due labels follow classroom-style wording', () {
    final now = DateTime(2026, 8, 27, 10);
    expect(classCardDueLabel(null, now: now), 'Assigned');
    expect(classCardDueLabel(DateTime(2026, 8, 27, 23), now: now), 'Due today');
    expect(classCardDueLabel(DateTime(2026, 8, 28), now: now), 'Due tomorrow');
    expect(classCardDueLabel(DateTime(2026, 8, 31), now: now), 'Due Monday');
    expect(
      classCardDueLabel(DateTime(2026, 9, 8), now: now),
      'Due Sep 8, 2026',
    );
  });

  test('preview items keep two soonest active assignments', () {
    final items = classCardWorkItemsFromAssignments([
      _assignment(
        id: 'late',
        title: 'Shoulder Stall',
        dueAt: DateTime(2026, 9, 10),
      ),
      _assignment(
        id: 'soon',
        title: 'Normal Grip',
        dueAt: DateTime(2026, 8, 31),
      ),
      _assignment(
        id: 'archived',
        title: 'Claw Grip',
        dueAt: DateTime(2026, 8, 28),
        status: GroupAssignmentStatus.archived,
      ),
      _assignment(id: 'undated', title: 'Hand Stall'),
    ], now: DateTime(2026, 8, 27));
    expect(items, hasLength(2));
    expect(items.first.title, 'Normal Grip');
    expect(items.first.dueLabel, 'Due Monday');
    expect(items.last.title, 'Shoulder Stall');
  });

  testWidgets('class card keeps the group key and opens on tap', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.light,
        home: ScaffoldPage(
          content: Center(
            child: SizedBox(
              width: 320,
              child: TraineeClassCard(
                groupId: 'group-1',
                className: 'BSIT-4A',
                teacherName: 'Jiro Lapuz',
                sectionLabel: 'Active',
                workItems: const [
                  ClassCardWorkItem(
                    dueLabel: 'Due Monday',
                    title: 'Normal Grip',
                  ),
                ],
                onOpen: () => opened = true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('teacher_access_group_group-1')),
      findsOneWidget,
    );
    expect(find.text('BSIT-4A'), findsOneWidget);
    expect(find.text('Jiro Lapuz'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Due Monday'), findsOneWidget);
    expect(find.text('Normal Grip'), findsOneWidget);
    expect(find.text('Open classwork'), findsNothing);
    expect(find.byKey(const Key('class_card_people_group-1')), findsOneWidget);
    expect(find.byKey(const Key('class_card_folder_group-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('teacher_access_group_group-1')));
    expect(opened, isTrue);
  });

  testWidgets('footer icons open the class', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: Center(
            child: SizedBox(
              width: 320,
              child: TraineeClassCard(
                groupId: 'group-2',
                className: 'BSHM 4A',
                teacherName: 'Grace Hopper',
                onOpen: () => opened += 1,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('class_card_people_group-2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('class_card_folder_group-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(opened, 2);
  });
}
