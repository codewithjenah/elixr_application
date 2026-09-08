import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_ids.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/assigned_movements/assigned_movement_list.dart';
import 'package:elixr_application/features/assigned_movements/assigned_movements_controller.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GroupAssignment _assignment({
  required String id,
  required String title,
  MovementOrigin origin = MovementOrigin.officialElixr,
  GroupAssignmentStatus status = GroupAssignmentStatus.active,
  String? topic,
}) {
  return GroupAssignment(
    id: id,
    teacherId: 'teacher-1',
    groupId: 'group-1',
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: origin,
    assessmentMode: origin == MovementOrigin.officialElixr
        ? AssessmentMode.officialGuided
        : AssessmentMode.teacherReviewed,
    status: status,
    displayTitle: title,
    teacherDisplayName: 'James Bartender',
    groupName: 'BSHM-4A',
    topic: topic,
    officialMovementName: origin == MovementOrigin.officialElixr
        ? 'Hand Stall'
        : null,
  );
}

AssignmentAttempt _teacherSubmittedAttempt(String assignmentId) {
  return AssignmentAttempt(
    id: assignmentAttemptIdForCanonicalTeacherReviewSubmission(
      assignmentId: assignmentId,
      traineeId: 'trainee-1',
    ),
    traineeId: 'trainee-1',
    teacherId: 'teacher-1',
    groupId: 'group-1',
    assignmentId: assignmentId,
    movementId: 'tm1',
    revisionId: 'rev1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.teacherReviewed,
    attemptKind: AssignmentAttemptKind.teacherReviewSubmission,
    status: AssignmentAttemptStatus.submitted,
  );
}

Future<GoRouter> _pumpList(
  WidgetTester tester, {
  required List<AssignedMovementItem> items,
  Size viewSize = const Size(1280, 720),
  double? paneWidth,
  bool showGroupName = false,
  bool includePracticeRoute = true,
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => ScaffoldPage(
          content: SizedBox(
            width: paneWidth,
            height: 800,
            child: AssignedMovementList(
              items: items,
              showGroupName: showGroupName,
            ),
          ),
        ),
      ),
      if (includePracticeRoute)
        GoRoute(
          path: '${AppRoutePaths.assignedPracticePrefix}/:assignmentId',
          builder: (context, state) =>
              Text('practice:${state.pathParameters['assignmentId']}'),
        ),
      GoRoute(
        path: '${AppRoutePaths.assignedMovements}/:assignmentId',
        builder: (context, state) =>
            Text('detail:${state.pathParameters['assignmentId']}'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    FluentApp.router(theme: AppTheme.light, routerConfig: router),
  );
  await tester.pump();
  return router;
}

void _expectNoOverflow(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('due and status labels stay short for cards', () {
    final assignment = _assignment(id: 'asg-1', title: 'Hand Stall');
    expect(assignedMovementDueLabel(assignment), 'No due date');
    expect(assignedMovementStatusLabel(assignment, null, null), 'Not started');
    expect(assignedMovementActionLabel(assignment, null), 'Start practice');
    expect(assignedMovementPracticeButtonLabel(null), 'Start practice');
  });

  testWidgets('classwork renders as cards and opens practice', (tester) async {
    await _pumpList(
      tester,
      items: [
        AssignedMovementItem(
          assignment: _assignment(id: 'asg-a', title: 'Hand Stall'),
          attempt: null,
        ),
        AssignedMovementItem(
          assignment: _assignment(
            id: 'asg-b',
            title: 'Basic Bottle Balances',
            origin: MovementOrigin.teacherCreated,
          ),
          attempt: null,
        ),
      ],
    );

    expect(
      find.byKey(const Key('assigned_movement_card_asg-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assigned_movement_card_asg-b')),
      findsOneWidget,
    );
    expect(find.text('Hand Stall'), findsOneWidget);
    expect(find.text('Basic Bottle Balances'), findsOneWidget);
    expect(find.text('James Bartender'), findsNWidgets(2));
    expect(
      find.byKey(const Key('assigned_movements_official_section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assigned_movements_teacher_section')),
      findsOneWidget,
    );
    expect(find.text('Official ELIXR'), findsNWidgets(2));
    expect(find.text('Teacher-created'), findsNWidgets(2));
    expect(find.textContaining('No submission clip'), findsOneWidget);
    expect(find.textContaining('Record a clip'), findsOneWidget);
    expect(find.text('Start practice'), findsNWidgets(2));
    expect(find.text('No due date'), findsNWidgets(2));
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('Not submitted'), findsOneWidget);
    expect(find.byIcon(FluentIcons.education), findsWidgets);
    expect(find.byIcon(FluentIcons.assign), findsWidgets);
    _expectNoOverflow(tester);

    await tester.tap(find.text('Start practice').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('practice:asg-a'), findsOneWidget);
  });

  testWidgets('tapping the card body opens assignment detail', (tester) async {
    await _pumpList(
      tester,
      items: [
        AssignedMovementItem(
          assignment: _assignment(id: 'asg-a', title: 'Hand Stall'),
          attempt: null,
        ),
      ],
      includePracticeRoute: false,
    );

    await tester.tap(find.text('Hand Stall'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('detail:asg-a'), findsOneWidget);
  });

  testWidgets('only Official ELIXR items hide the Teacher-created section', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.light,
        home: ScaffoldPage(
          content: SizedBox(
            height: 600,
            child: AssignedMovementList(
              items: [
                AssignedMovementItem(
                  assignment: _assignment(id: 'asg-a', title: 'Hand Stall'),
                  attempt: null,
                ),
              ],
              showGroupName: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('assigned_movements_official_section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assigned_movements_teacher_section')),
      findsNothing,
    );
  });

  testWidgets('only Teacher-created items hide the Official ELIXR section', (
    tester,
  ) async {
    await tester.pumpWidget(
      FluentApp(
        theme: AppTheme.light,
        home: ScaffoldPage(
          content: SizedBox(
            height: 600,
            child: AssignedMovementList(
              items: [
                AssignedMovementItem(
                  assignment: _assignment(
                    id: 'asg-b',
                    title: 'Basic Bottle Balances',
                    origin: MovementOrigin.teacherCreated,
                  ),
                  attempt: null,
                ),
              ],
              showGroupName: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('assigned_movements_teacher_section')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('assigned_movements_official_section')),
      findsNothing,
    );
  });

  testWidgets(
    'awaiting-check work keeps status text and does not show a play action',
    (tester) async {
      final attempt = _teacherSubmittedAttempt('asg-b');
      await _pumpList(
        tester,
        items: [
          AssignedMovementItem(
            assignment: _assignment(
              id: 'asg-b',
              title: 'Basic Bottle Balances',
              origin: MovementOrigin.teacherCreated,
            ),
            attempt: attempt,
            latestSubmission: attempt,
          ),
        ],
      );

      final card = find.byKey(const Key('assigned_movement_card_asg-b'));
      expect(card, findsOneWidget);
      expect(find.text('Awaiting check'), findsOneWidget);
      expect(find.text('Start practice'), findsNothing);
      expect(find.text('View details'), findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.byIcon(FluentIcons.play)),
        findsNothing,
      );
      expect(
        find.descendant(of: card, matching: find.byIcon(FluentIcons.clock)),
        findsWidgets,
      );

      await tester.tap(find.text('View details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('detail:asg-b'), findsOneWidget);
    },
  );

  testWidgets(
    'null and empty topics stay grouped under General instead of No topic',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        FluentApp(
          theme: AppTheme.light,
          home: ScaffoldPage(
            content: SingleChildScrollView(
              child: ClassroomTopicContent(
                items: [
                  AssignedMovementItem(
                    assignment: _assignment(id: 'asg-a', title: 'Hand Stall'),
                    attempt: null,
                  ),
                  AssignedMovementItem(
                    assignment: _assignment(
                      id: 'asg-b',
                      title: 'Empty topic stall',
                      topic: '   ',
                    ),
                    attempt: null,
                  ),
                  AssignedMovementItem(
                    assignment: _assignment(
                      id: 'asg-c',
                      title: 'Tin Pour',
                      origin: MovementOrigin.teacherCreated,
                      topic: 'Flair basics',
                    ),
                    attempt: null,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(classworkUncategorizedTopicLabel), findsOneWidget);
      expect(find.text('No topic'), findsNothing);
      expect(find.text('Flair basics'), findsOneWidget);
      expect(
        find.byKey(const Key('assigned_movement_card_asg-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assigned_movement_card_asg-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assigned_movement_card_asg-c')),
        findsOneWidget,
      );
    },
  );

  testWidgets('responsive cards render without overflow', (tester) async {
    final items = [
      AssignedMovementItem(
        assignment: _assignment(
          id: 'asg-a',
          title: 'Very Long Official Movement Title For Overflow Checks',
        ),
        attempt: null,
      ),
      AssignedMovementItem(
        assignment: _assignment(
          id: 'asg-b',
          title: 'Very Long Teacher Created Assignment Title For Overflow',
          origin: MovementOrigin.teacherCreated,
        ),
        attempt: null,
      ),
    ];

    for (final size in const [
      Size(400, 900),
      Size(1280, 720),
      Size(1600, 900),
    ]) {
      await _pumpList(
        tester,
        items: items,
        viewSize: size,
        paneWidth: size.width,
      );
      _expectNoOverflow(tester);
      expect(
        find.byKey(const Key('assigned_movement_card_asg-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('assigned_movement_card_asg-b')),
        findsOneWidget,
      );
    }
  });
}
