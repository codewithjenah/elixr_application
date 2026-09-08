import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/core/widgets/movement_image.dart';
import 'package:elixr_application/core/widgets/profile_avatar.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/assignment_attempt.dart';
import 'package:elixr_application/data/models/assignment_attempt_ids.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/features/assigned_movements/assigned_movement_list.dart';
import 'package:elixr_application/features/assigned_movements/assigned_movements_controller.dart';
import 'package:elixr_core/models/rubric_assessment.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GroupAssignment _assignment({
  required String id,
  required String title,
  MovementOrigin origin = MovementOrigin.officialElixr,
  GroupAssignmentStatus status = GroupAssignmentStatus.active,
  AssessmentMode? assessmentMode,
  String teacherId = 'teacher-1',
  String teacherDisplayName = 'James Bartender',
  String? topic,
  DateTime? dueAt,
  String? officialMovementName,
}) {
  return GroupAssignment(
    id: id,
    teacherId: teacherId,
    groupId: 'group-1',
    movementId: 'official_hand_stall',
    revisionId: 'official_hand_stall_v1',
    origin: origin,
    assessmentMode:
        assessmentMode ??
        (origin == MovementOrigin.officialElixr
            ? AssessmentMode.officialGuided
            : AssessmentMode.teacherReviewed),
    status: status,
    displayTitle: title,
    teacherDisplayName: teacherDisplayName,
    groupName: 'BSHM-4A',
    topic: topic,
    dueAt: dueAt,
    officialMovementName:
        officialMovementName ??
        (origin == MovementOrigin.officialElixr ? title : null),
  );
}

AssignmentAttempt _officialSubmittedAttempt(String assignmentId) {
  return AssignmentAttempt(
    id: 'ptr-$assignmentId',
    traineeId: 'trainee-1',
    teacherId: 'teacher-1',
    groupId: 'group-1',
    assignmentId: assignmentId,
    movementId: 'official_elbow_stall',
    revisionId: 'official_elbow_stall_v1',
    origin: MovementOrigin.officialElixr,
    assessmentMode: AssessmentMode.officialGuided,
    attemptKind: AssignmentAttemptKind.practicePointer,
    status: AssignmentAttemptStatus.submitted,
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

Finder _card(String assignmentId) =>
    find.byKey(Key('assigned_movement_card_$assignmentId'));

Finder _movementImage(String movementName) => find.byWidgetPredicate(
  (widget) => widget is MovementImage && widget.movementName == movementName,
);

Finder _cardAvatar(String assignmentId) =>
    find.byKey(Key('assigned_movement_teacher_avatar_$assignmentId'));

Size _cardSize(WidgetTester tester, String assignmentId) =>
    tester.getSize(_card(assignmentId));

double _actionBottom(WidgetTester tester, String assignmentId) {
  return tester
      .getRect(find.byKey(Key('assigned_movement_action_$assignmentId')))
      .bottom;
}

AssignedMovementItem _teacherItem({
  required String id,
  required String title,
  AssessmentMode assessmentMode = AssessmentMode.teacherReviewed,
  AssignmentAttempt? attempt,
  String? teacherProfilePictureUrl,
}) {
  return AssignedMovementItem(
    assignment: _assignment(
      id: id,
      title: title,
      origin: MovementOrigin.teacherCreated,
      assessmentMode: assessmentMode,
    ),
    attempt: attempt,
    latestSubmission: attempt,
    teacherProfilePictureUrl: teacherProfilePictureUrl,
  );
}

AssignmentAttempt _approvedAttempt(String assignmentId) {
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
    status: AssignmentAttemptStatus.approved,
  );
}

AssignmentAttempt _historicalAttempt(String assignmentId) {
  return AssignmentAttempt(
    id: 'hist-$assignmentId',
    traineeId: 'trainee-1',
    teacherId: 'teacher-1',
    groupId: 'group-1',
    assignmentId: assignmentId,
    movementId: 'tm1',
    revisionId: 'rev1',
    origin: MovementOrigin.teacherCreated,
    assessmentMode: AssessmentMode.templateScored,
    attemptKind: AssignmentAttemptKind.templateScore,
    status: AssignmentAttemptStatus.checked,
    rubric: const RubricAssessment(
      technique: 2,
      stability: 2,
      completion: 3,
      propPositioning: 2,
    ),
  );
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
    expect(_movementImage('Hand Stall'), findsOneWidget);
    expect(_movementImage('Basic Bottle Balances'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('assigned_movement_card_asg-a')),
        matching: find.byIcon(FluentIcons.education),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('assigned_movement_card_asg-b')),
        matching: find.byIcon(FluentIcons.assign),
      ),
      findsNothing,
    );
    expect(find.byIcon(FluentIcons.education), findsWidgets);
    expect(find.byIcon(FluentIcons.assign), findsWidgets);
    _expectNoOverflow(tester);

    await tester.tap(find.text('Start practice').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('practice:asg-a'), findsOneWidget);
  });

  testWidgets(
    'official assignment cards resolve MovementImage from each movement name',
    (tester) async {
      await _pumpList(
        tester,
        items: [
          AssignedMovementItem(
            assignment: _assignment(id: 'asg-ng', title: 'Normal Grip'),
            attempt: null,
          ),
          AssignedMovementItem(
            assignment: _assignment(id: 'asg-es', title: 'Elbow Stall'),
            attempt: _officialSubmittedAttempt('asg-es'),
          ),
        ],
      );

      expect(_movementImage('Normal Grip'), findsOneWidget);
      expect(_movementImage('Elbow Stall'), findsOneWidget);
      expect(
        find.descendant(
          of: _card('asg-ng'),
          matching: find.text('Official ELIXR'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _card('asg-es'),
          matching: find.text('Official ELIXR'),
        ),
        findsOneWidget,
      );
      expect(find.text('Not started'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(
        find.descendant(
          of: _card('asg-ng'),
          matching: find.byIcon(FluentIcons.education),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _card('asg-es'),
          matching: find.byIcon(FluentIcons.education),
        ),
        findsNothing,
      );
      _expectNoOverflow(tester);
    },
  );

  testWidgets('teacher-created cards pass the display title to MovementImage', (
    tester,
  ) async {
    await _pumpList(
      tester,
      paneWidth: 800,
      viewSize: const Size(800, 900),
      items: [
        _teacherItem(id: 'asg-custom', title: 'Custom Flair Sequence XYZ'),
        _teacherItem(
          id: 'asg-sub',
          title: 'Tin Pour',
          attempt: _teacherSubmittedAttempt('asg-sub'),
        ),
        AssignedMovementItem(
          assignment: _assignment(
            id: 'asg-due',
            title: 'Hand Stall',
            dueAt: DateTime.now().toUtc().add(const Duration(days: 14)),
          ),
          attempt: null,
        ),
      ],
    );

    expect(_movementImage('Custom Flair Sequence XYZ'), findsOneWidget);
    expect(_movementImage('Tin Pour'), findsOneWidget);
    expect(_movementImage('Hand Stall'), findsOneWidget);
    expect(
      find.descendant(
        of: _card('asg-custom'),
        matching: find.text('Teacher-created'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _card('asg-sub'),
        matching: find.text('Teacher-created'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _card('asg-due'),
        matching: find.text('Official ELIXR'),
      ),
      findsOneWidget,
    );
    expect(find.text('Not submitted'), findsOneWidget);
    expect(find.text('Awaiting check'), findsOneWidget);
    expect(find.text('No due date'), findsNWidgets(2));
    expect(find.text('Not started'), findsOneWidget);
    expect(
      find.descendant(
        of: _card('asg-custom'),
        matching: find.byIcon(FluentIcons.assign),
      ),
      findsNothing,
    );
    expect(
      _cardSize(tester, 'asg-custom').height,
      _cardSize(tester, 'asg-sub').height,
    );
    _expectNoOverflow(tester);
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

  testWidgets(
    '2-column Teacher-created cards share height despite different text lengths',
    (tester) async {
      await _pumpList(
        tester,
        paneWidth: 800,
        viewSize: const Size(800, 900),
        items: [
          _teacherItem(id: 'short', title: 'Stall'),
          _teacherItem(
            id: 'long',
            title:
                'Very Long Teacher Created Assignment Title That Wraps Onto A Second Line',
          ),
        ],
      );

      expect(
        _cardSize(tester, 'short').height,
        _cardSize(tester, 'long').height,
      );
      expect(
        _actionBottom(tester, 'short'),
        closeTo(_actionBottom(tester, 'long'), 0.5),
      );
      _expectNoOverflow(tester);
    },
  );

  testWidgets(
    'Historical metadata does not make a Teacher-created card taller than Approved',
    (tester) async {
      await _pumpList(
        tester,
        paneWidth: 800,
        viewSize: const Size(800, 900),
        items: [
          _teacherItem(
            id: 'hist',
            title: 'Retired template stall',
            assessmentMode: AssessmentMode.templateScored,
            attempt: _historicalAttempt('hist'),
          ),
          _teacherItem(
            id: 'appr',
            title: 'Approved stall',
            attempt: _approvedAttempt('appr'),
          ),
        ],
      );

      expect(find.text('Historical'), findsOneWidget);
      expect(find.text('Approved'), findsOneWidget);
      expect(
        find.textContaining('Automatic template assessment retired'),
        findsOneWidget,
      );
      expect(
        _cardSize(tester, 'hist').height,
        _cardSize(tester, 'appr').height,
      );
      expect(
        _actionBottom(tester, 'hist'),
        closeTo(_actionBottom(tester, 'appr'), 0.5),
      );
      _expectNoOverflow(tester);
    },
  );

  testWidgets('3-column teacher cards stay equal height and aligned', (
    tester,
  ) async {
    await _pumpList(
      tester,
      paneWidth: 1200,
      viewSize: const Size(1200, 900),
      items: [
        _teacherItem(id: 'a', title: 'Short'),
        _teacherItem(
          id: 'b',
          title: 'A much longer teacher assignment title for the middle card',
          attempt: _approvedAttempt('b'),
        ),
        _teacherItem(
          id: 'c',
          title: 'Historical wrap check',
          assessmentMode: AssessmentMode.templateScored,
          attempt: _historicalAttempt('c'),
        ),
      ],
    );

    final heightA = _cardSize(tester, 'a').height;
    expect(_cardSize(tester, 'b').height, heightA);
    expect(_cardSize(tester, 'c').height, heightA);
    expect(
      _actionBottom(tester, 'a'),
      closeTo(_actionBottom(tester, 'c'), 0.5),
    );
    _expectNoOverflow(tester);
  });

  testWidgets('narrow 1-column classwork does not clip assignment cards', (
    tester,
  ) async {
    await _pumpList(
      tester,
      paneWidth: 400,
      viewSize: const Size(400, 1200),
      items: [
        _teacherItem(
          id: 'hist',
          title:
              'Very Long Teacher Created Assignment Title For Overflow Checks',
          assessmentMode: AssessmentMode.templateScored,
          attempt: _historicalAttempt('hist'),
        ),
        _teacherItem(
          id: 'appr',
          title: 'Approved stall',
          attempt: _approvedAttempt('appr'),
        ),
      ],
    );

    expect(_card('hist'), findsOneWidget);
    expect(_card('appr'), findsOneWidget);
    expect(find.text('James Bartender'), findsNWidgets(2));
    _expectNoOverflow(tester);
  });

  testWidgets('teacher avatar uses public profile URL beside the name', (
    tester,
  ) async {
    await _pumpList(
      tester,
      items: [
        _teacherItem(
          id: 'asg-b',
          title: 'Basic Bottle Balances',
          teacherProfilePictureUrl: 'https://example.test/grace.png',
        ),
      ],
    );

    final avatar = tester.widget<ProfileAvatarWidget>(_cardAvatar('asg-b'));
    expect(avatar.networkImageUrl, 'https://example.test/grace.png');
    expect(avatar.initials, 'JB');
    expect(find.text('James Bartender'), findsOneWidget);
    expect(_movementImage('Basic Bottle Balances'), findsOneWidget);
    expect(
      find.descendant(
        of: _card('asg-b'),
        matching: find.byIcon(FluentIcons.assign),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: _card('asg-b'),
        matching: find.byIcon(FluentIcons.contact),
      ),
      findsNothing,
    );
    _expectNoOverflow(tester);
  });

  testWidgets('teacher avatar falls back to initials without a photo', (
    tester,
  ) async {
    await _pumpList(
      tester,
      items: [_teacherItem(id: 'asg-b', title: 'Basic Bottle Balances')],
    );

    final avatar = tester.widget<ProfileAvatarWidget>(_cardAvatar('asg-b'));
    expect(avatar.networkImageUrl, isNull);
    expect(avatar.initials, 'JB');
    expect(find.text('James Bartender'), findsOneWidget);
    _expectNoOverflow(tester);
  });

  testWidgets('broken teacher photo URL still renders the assignment card', (
    tester,
  ) async {
    await _pumpList(
      tester,
      items: [
        _teacherItem(
          id: 'asg-b',
          title: 'Basic Bottle Balances',
          teacherProfilePictureUrl: 'https://example.test/missing.png',
        ),
      ],
    );

    expect(_card('asg-b'), findsOneWidget);
    final avatar = tester.widget<ProfileAvatarWidget>(_cardAvatar('asg-b'));
    expect(avatar.networkImageUrl, 'https://example.test/missing.png');
    expect(find.text('James Bartender'), findsOneWidget);
    expect(find.text('Start practice'), findsOneWidget);
    _expectNoOverflow(tester);
  });

  testWidgets('card keyboard Enter and Space still open assignment details', (
    tester,
  ) async {
    for (final entry in {
      'asg-enter': LogicalKeyboardKey.enter,
      'asg-space': LogicalKeyboardKey.space,
    }.entries) {
      await _pumpList(
        tester,
        items: [_teacherItem(id: entry.key, title: 'Basic Bottle Balances')],
        includePracticeRoute: false,
      );

      final title = find.descendant(
        of: _card(entry.key),
        matching: find.text('Basic Bottle Balances'),
      );
      Focus.of(tester.element(title)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(entry.value);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('detail:${entry.key}'), findsOneWidget);
    }
  });

  testWidgets('card hover does not throw or clip neighboring layout', (
    tester,
  ) async {
    await _pumpList(
      tester,
      paneWidth: 800,
      viewSize: const Size(800, 900),
      items: [
        _teacherItem(id: 'a', title: 'Short'),
        _teacherItem(
          id: 'b',
          title: 'Approved stall',
          attempt: _approvedAttempt('b'),
        ),
      ],
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(_card('a')));
    addTearDown(gesture.removePointer);
    await tester.pump();
    expect(_cardSize(tester, 'a').height, _cardSize(tester, 'b').height);
    _expectNoOverflow(tester);
  });
}
