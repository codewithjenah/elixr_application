import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
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
                assignmentCount: 1,
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
    expect(find.text('1 assignment'), findsOneWidget);
    expect(find.text('Open classwork'), findsNothing);
    expect(find.text('No upcoming classwork'), findsNothing);
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

    expect(find.text('No upcoming classwork'), findsOneWidget);

    await tester.tap(find.byKey(const Key('class_card_people_group-2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('class_card_folder_group-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(opened, 2);
  });

  testWidgets('people and classwork callbacks stay independent of open', (
    tester,
  ) async {
    var opened = 0;
    var people = 0;
    var classwork = 0;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: Center(
            child: SizedBox(
              width: 320,
              child: TraineeClassCard(
                groupId: 'group-3',
                className: 'BSHM 4A',
                teacherName: 'Grace Hopper',
                onOpen: () => opened += 1,
                onOpenPeople: () => people += 1,
                onOpenClasswork: () => classwork += 1,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('class_card_people_group-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('class_card_folder_group-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(people, 1);
    expect(classwork, 1);
    expect(opened, 0);
  });

  testWidgets('overflow menu keeps its key and flyout actions', (tester) async {
    var renamed = false;
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: Center(
            child: SizedBox(
              width: 320,
              child: TraineeClassCard(
                groupId: 'group-4',
                className: 'BSIT-4A',
                teacherName: 'Grace Hopper',
                onOpen: () {},
                menuItems: (_) => [
                  MenuFlyoutItem(
                    text: const Text('Rename'),
                    onPressed: () => renamed = true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('class_card_more_group-4')));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(renamed, isTrue);
  });

  testWidgets('avatar falls back to teacher initials', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: Center(
            child: SizedBox(
              width: 320,
              child: TraineeClassCard(
                groupId: 'group-5',
                className: 'BSIT-4A',
                teacherName: 'Grace Hopper',
                ownerInitials: '  ',
                onOpen: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final avatar = tester.widget<ProfileAvatarWidget>(
      find.byKey(const Key('teacher_access_group_teacher_avatar_group-5')),
    );
    expect(avatar.initials, 'GH');
    expect(avatar.networkImageUrl, isNull);
  });

  testWidgets('long copy and empty work stay inside the card', (tester) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: Center(
            child: SizedBox(
              width: 280,
              child: TraineeClassCard(
                groupId: 'group-6',
                className: 'BSIT 4A Advanced Flair Bartending Laboratory',
                teacherName: 'Professor Alexandrina Montgomery-Whitaker',
                sectionLabel: 'MWF 2:30–4:00 PM · Room 1204 East Wing',
                workItems: const [
                  ClassCardWorkItem(
                    dueLabel: 'Due Sep 8, 2026',
                    title:
                        'Behind the Back Stall Sequence with Extended Follow-through',
                  ),
                ],
                onOpen: () {},
                menuItems: (_) => [
                  MenuFlyoutItem(
                    text: const Text('Open class'),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const Key('teacher_access_group_group-6')))
          .height,
      272,
    );
  });

  testWidgets('cards in a row share height, work baseline, and footer', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.dark,
        home: ScaffoldPage(
          content: Center(
            child: SizedBox(
              width: 720,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TraineeClassCard(
                      groupId: 'grid-a',
                      className: 'BSIT-4A',
                      teacherName: 'Ada',
                      sectionLabel: 'Active',
                      workItems: const [
                        ClassCardWorkItem(
                          dueLabel: 'Due today',
                          title: 'Normal Grip',
                        ),
                        ClassCardWorkItem(
                          dueLabel: 'Assigned',
                          title: 'Shoulder Stall',
                        ),
                      ],
                      onOpen: () {},
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TraineeClassCard(
                      groupId: 'grid-b',
                      className: 'BSIT 4A Advanced Flair Bartending Laboratory',
                      teacherName: 'Grace Hopper Hopper Hopper',
                      workItems: const [],
                      onOpen: () {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final a = tester.getRect(
      find.byKey(const Key('teacher_access_group_grid-a')),
    );
    final b = tester.getRect(
      find.byKey(const Key('teacher_access_group_grid-b')),
    );
    expect(a.height, b.height);
    expect(a.bottom, b.bottom);

    final peopleA = tester.getRect(
      find.byKey(const Key('class_card_people_grid-a')),
    );
    final peopleB = tester.getRect(
      find.byKey(const Key('class_card_people_grid-b')),
    );
    expect(peopleA.center.dy, closeTo(peopleB.center.dy, 0.5));

    final firstWork = tester.getRect(find.text('Normal Grip'));
    final emptyWork = tester.getRect(find.text('No upcoming classwork'));
    expect(firstWork.top, closeTo(emptyWork.top, 8));
  });

  testWidgets('high contrast keeps status, actions, and avatar readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.highContrastDark,
        home: ScaffoldPage(
          content: Center(
            child: SizedBox(
              width: 320,
              child: TraineeClassCard(
                groupId: 'group-hc',
                className: 'BSIT-4A',
                teacherName: 'Grace Hopper',
                sectionLabel: 'Archived',
                workItems: const [
                  ClassCardWorkItem(
                    dueLabel: 'Due today',
                    title: 'Normal Grip',
                  ),
                ],
                onOpen: () {},
                menuItems: (_) => [
                  MenuFlyoutItem(
                    text: const Text('Unarchive'),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Archived'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.byKey(const Key('class_card_people_group-hc')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
