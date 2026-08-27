import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
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
    officialMovementName: origin == MovementOrigin.officialElixr
        ? 'Hand Stall'
        : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('due and status labels stay short for cards', () {
    final assignment = _assignment(id: 'asg-1', title: 'Hand Stall');
    expect(assignedMovementDueLabel(assignment), 'No due date');
    expect(assignedMovementStatusLabel(assignment, null, null), 'Not started');
    expect(assignedMovementActionLabel(assignment, null), 'Start practice');
  });

  testWidgets('classwork renders as cards and opens practice', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
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
              height: 600,
              child: AssignedMovementList(
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
                showGroupName: false,
              ),
            ),
          ),
        ),
        GoRoute(
          path: '${AppRoutePaths.assignedPracticePrefix}/:assignmentId',
          builder: (context, state) =>
              Text('practice:${state.pathParameters['assignmentId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      FluentApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();

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
    expect(find.text('Official ELIXR'), findsOneWidget);
    expect(find.text('Teacher-created'), findsOneWidget);
    expect(find.text('Start practice'), findsNWidgets(2));
    expect(find.text('No due date'), findsNWidgets(2));
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('Not submitted'), findsOneWidget);

    await tester.tap(find.text('Start practice').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('practice:asg-a'), findsOneWidget);
  });
}
