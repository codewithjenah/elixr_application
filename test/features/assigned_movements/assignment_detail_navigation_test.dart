import 'package:elixr_application/core/router/app_route_paths.dart';
import 'package:elixr_application/core/theme/app_theme.dart';
import 'package:elixr_application/data/models/assessment_mode.dart';
import 'package:elixr_application/data/models/group_assignment.dart';
import 'package:elixr_application/data/models/movement_origin.dart';
import 'package:elixr_application/data/repositories/in_memory_classroom_assignment_repository.dart';
import 'package:elixr_application/features/assigned_movements/assignment_detail_controller.dart';
import 'package:elixr_application/features/assigned_movements/assignment_detail_screen.dart';
import 'package:elixr_core/repositories/in_memory_group_repository.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('assignment detail back uses the assigned-movements fallback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final groups = InMemoryGroupRepository();
    final assignments = InMemoryClassroomAssignmentRepository();
    addTearDown(groups.dispose);
    addTearDown(assignments.dispose);
    final controller =
        AssignmentDetailController(
            assignmentId: 'asg-a',
            traineeId: 'trainee-1',
            groupRepository: groups,
            assignmentRepository: assignments,
          )
          ..assignment = const GroupAssignment(
            id: 'asg-a',
            teacherId: 'teacher-1',
            groupId: 'group-1',
            movementId: 'official_hand_stall',
            revisionId: 'official_hand_stall_v1',
            origin: MovementOrigin.officialElixr,
            assessmentMode: AssessmentMode.officialGuided,
            status: GroupAssignmentStatus.active,
            displayTitle: 'Hand Stall',
            teacherDisplayName: 'Grace Hopper',
            groupName: 'BSHM 4A',
            officialMovementName: 'Hand Stall',
          )
          ..authorized = true;
    addTearDown(controller.dispose);

    final router = GoRouter(
      initialLocation: AppRoutePaths.assignmentDetail('asg-a'),
      routes: [
        GoRoute(
          path: AppRoutePaths.assignedMovements,
          builder: (context, state) => const Text('assigned movements home'),
          routes: [
            GoRoute(
              path: ':assignmentId',
              builder: (context, state) => AssignmentDetailScreen(
                assignmentId: state.pathParameters['assignmentId']!,
                controller: controller,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      FluentApp.router(theme: AppTheme.dark, routerConfig: router),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('assignment_detail_back')));
    await tester.pumpAndSettle();

    expect(find.text('assigned movements home'), findsOneWidget);
  });
}
